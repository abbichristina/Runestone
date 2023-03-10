import Combine
import Foundation
#if os(iOS)
import UIKit
#endif

protocol IndentControllerDelegate: AnyObject {
    func indentController(_ controller: IndentController, shouldInsert text: String, in range: NSRange)
    func indentController(_ controller: IndentController, shouldSelect range: NSRange)
    func indentControllerDidUpdateTabWidth(_ controller: IndentController)
}

final class IndentController {
    #if os(macOS)
    private typealias NSStringDrawingOptions = NSString.DrawingOptions
    #endif

    weak var delegate: IndentControllerDelegate?

    let indentStrategy = CurrentValueSubject<IndentStrategy, Never>(.tab(length: 2))
//    var indentFont: MultiPlatformFont {
//        didSet {
//            if indentFont != oldValue {
//                _tabWidth = nil
//            }
//        }
//    }
//
//
//    var indentStrategy: IndentStrategy {
//        didSet {
//            if indentStrategy != oldValue {
//                _tabWidth = nil
//            }
//        }
//    }
    var tabWidth: CGFloat {
        if let tabWidth = _tabWidth {
            return tabWidth
        } else {
            let str = String(repeating: " ", count: indentStrategy.value.tabLength)
            let maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            let options: NSStringDrawingOptions = [.usesFontLeading, .usesLineFragmentOrigin]
            let attributes: [NSAttributedString.Key: Any] = [.font: font.value]
            let bounds = str.boundingRect(with: maxSize, options: options, attributes: attributes, context: nil)
            let tabWidth = round(bounds.size.width)
            if tabWidth != _tabWidth {
                _tabWidth = tabWidth
                delegate?.indentControllerDidUpdateTabWidth(self)
            }
            return tabWidth
        }
    }

    private let stringView: CurrentValueSubject<StringView, Never>
    private let lineManager: CurrentValueSubject<LineManager, Never>
    private let languageMode: CurrentValueSubject<InternalLanguageMode, Never>
    private let font: CurrentValueSubject<MultiPlatformFont, Never>
    private var _tabWidth: CGFloat?

    init(
        stringView: CurrentValueSubject<StringView, Never>,
        lineManager: CurrentValueSubject<LineManager, Never>,
        languageMode: CurrentValueSubject<InternalLanguageMode, Never>,
        font: CurrentValueSubject<MultiPlatformFont, Never>
    ) {
        self.stringView = stringView
        self.lineManager = lineManager
        self.languageMode = languageMode
        self.font = font
    }

    func shiftLeft(in selectedRange: NSRange) {
        let lines = lineManager.value.lines(in: selectedRange)
        let originalRange = range(surrounding: lines)
        var newSelectedRange = selectedRange
        var replacementString: String?
        let indentString = indentStrategy.value.string(indentLevel: 1)
        let utf8IndentLength = indentString.count
        let utf16IndentLength = indentString.utf16.count
        for (lineIndex, line) in lines.enumerated() {
            let lineRange = NSRange(location: line.location, length: line.data.totalLength)
            let lineString = stringView.value.substring(in: lineRange) ?? ""
            guard lineString.hasPrefix(indentString) else {
                replacementString = (replacementString ?? "") + lineString
                continue
            }
            let startIndex = lineString.index(lineString.startIndex, offsetBy: utf8IndentLength)
            let endIndex = lineString.endIndex
            replacementString = (replacementString ?? "") + lineString[startIndex ..< endIndex]
            if lineIndex == 0 {
                // We don't want the selection to move to the previous line when we can't shift left anymore.
                // Therefore we keep it to the minimum location, which is the location the line starts on.
                // If we try to exceed that, we need to adjust the length of the selected range.
                let preferredLocation = newSelectedRange.location - utf16IndentLength
                let newLocation = max(preferredLocation, originalRange.location)
                newSelectedRange.location = newLocation
                if newLocation > preferredLocation {
                    let preferredLength = newSelectedRange.length - (newLocation - preferredLocation)
                    newSelectedRange.length = max(preferredLength, 0)
                }
            } else {
                newSelectedRange.length -= utf16IndentLength
            }
        }
        if let replacementString = replacementString {
            delegate?.indentController(self, shouldInsert: replacementString, in: originalRange)
            delegate?.indentController(self, shouldSelect: newSelectedRange)
        }
    }

    func shiftRight(in selectedRange: NSRange) {
        let lines = lineManager.value.lines(in: selectedRange)
        let originalRange = range(surrounding: lines)
        var newSelectedRange = selectedRange
        var replacementString: String?
        let indentString = indentStrategy.value.string(indentLevel: 1)
        let indentLength = indentString.utf16.count
        for (lineIndex, line) in lines.enumerated() {
            let lineRange = NSRange(location: line.location, length: line.data.totalLength)
            let lineString = stringView.value.substring(in: lineRange) ?? ""
            replacementString = (replacementString ?? "") + indentString + lineString
            if lineIndex == 0 {
                newSelectedRange.location += indentLength
            } else {
                newSelectedRange.length += indentLength
            }
        }
        if let replacementString = replacementString {
            delegate?.indentController(self, shouldInsert: replacementString, in: originalRange)
            delegate?.indentController(self, shouldSelect: newSelectedRange)
        }
    }

    func insertLineBreak(in range: NSRange, using symbol: String) {
        guard let startLinePosition = lineManager.value.linePosition(at: range.lowerBound) else {
            delegate?.indentController(self, shouldInsert: symbol, in: range)
            return
        }
        guard let endLinePosition = lineManager.value.linePosition(at: range.upperBound) else {
            delegate?.indentController(self, shouldInsert: symbol, in: range)
            return
        }
        let strategy = languageMode.value.strategyForInsertingLineBreak(from: startLinePosition, to: endLinePosition, using: indentStrategy.value)
        if strategy.insertExtraLineBreak {
            // Inserting a line break enters a new indentation level.
            // We insert an additional line break and place the cursor in the new block.
            let firstLineText = symbol + indentStrategy.value.string(indentLevel: strategy.indentLevel)
            let secondLineText = symbol + indentStrategy.value.string(indentLevel: strategy.indentLevel - 1)
            let indentedText = firstLineText + secondLineText
            delegate?.indentController(self, shouldInsert: indentedText, in: range)
            let newSelectedRange = NSRange(location: range.location + firstLineText.utf16.count, length: 0)
            delegate?.indentController(self, shouldSelect: newSelectedRange)
        } else {
            let indentedText = symbol + indentStrategy.value.string(indentLevel: strategy.indentLevel)
            delegate?.indentController(self, shouldInsert: indentedText, in: range)
        }
    }

    // Returns the range of an indentation text if the cursor is placed after an indentation.
    // This can be used when doing a deleteBackward operation to delete an indent level.
    func indentRangeInFrontOfLocation(_ location: Int) -> NSRange? {
        guard let line = lineManager.value.line(containingCharacterAt: location) else {
            return nil
        }
        let tabLength: Int
        switch indentStrategy.value {
        case .tab:
            tabLength = 1
        case .space(let length):
            tabLength = length
        }
        let localLocation = location - line.location
        guard localLocation >= tabLength else {
            return nil
        }
        let indentLevel = languageMode.value.currentIndentLevel(of: line, using: indentStrategy.value)
        let indentString = indentStrategy.value.string(indentLevel: indentLevel)
        guard localLocation <= indentString.utf16.count else {
            return nil
        }
        guard localLocation % tabLength == 0 else {
            return nil
        }
        return NSRange(location: location - tabLength, length: tabLength)
    }

    func isIndentation(at location: Int) -> Bool {
        guard let line = lineManager.value.line(containingCharacterAt: location) else {
            return false
        }
        let localLocation = location - line.location
        guard localLocation >= 0 else {
            return false
        }
        let indentLevel = languageMode.value.currentIndentLevel(of: line, using: indentStrategy.value)
        let indentString = indentStrategy.value.string(indentLevel: indentLevel)
        return localLocation <= indentString.utf16.count
    }
}

private extension IndentController {
    private func range(surrounding lines: [LineNode]) -> NSRange {
        let firstLine = lines[0]
        let lastLine = lines[lines.count - 1]
        let location = firstLine.location
        let length = (lastLine.location - location) + lastLine.data.totalLength
        return NSRange(location: location, length: length)
    }
}
