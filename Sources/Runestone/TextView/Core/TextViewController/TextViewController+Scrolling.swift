import Foundation

 extension TextViewController {
    func scrollRangeToVisible(_ range: NSRange) {
        lineFragmentLayouter.layoutLines(toLocation: range.upperBound)
        justScrollRangeToVisible(range)
    }

    func scrollLocationToVisible(_ location: Int) {
        let range = NSRange(location: location, length: 0)
        justScrollRangeToVisible(range)
    }
}

private extension TextViewController {
    private func justScrollRangeToVisible(_ range: NSRange) {
        let lowerBoundRect = caret(at: range.lowerBound)
        let upperBoundRect = range.length == 0 ? lowerBoundRect : caret(at: range.upperBound)
        let rectMinX = min(lowerBoundRect.minX, upperBoundRect.minX)
        let rectMaxX = max(lowerBoundRect.maxX, upperBoundRect.maxX)
        let rectMinY = min(lowerBoundRect.minY, upperBoundRect.minY)
        let rectMaxY = max(lowerBoundRect.maxY, upperBoundRect.maxY)
        let rect = CGRect(x: rectMinX, y: rectMinY, width: rectMaxX - rectMinX, height: rectMaxY - rectMinY)
        scrollView?.contentOffset = contentOffsetForScrollingToVisibleRect(rect)
    }

    private func caret(at location: Int) -> CGRect {
        caret.frame(at: location, allowMovingCaretToNextLineFragment: true)
    }

    /// Computes a content offset to scroll to in order to reveal the specified rectangle.
    ///
    /// The function will return a rectangle that scrolls the text view a minimum amount while revealing as much as possible of the rectangle. It is not guaranteed that the entire rectangle can be revealed.
    /// - Parameter rect: The rectangle to reveal.
    /// - Returns: The content offset to scroll to.
    private func contentOffsetForScrollingToVisibleRect(_ rect: CGRect) -> CGPoint {
        // Create the viewport: a rectangle containing the content that is visible to the user.
        let contentOffset = scrollView?.contentOffset ?? .zero
        let adjustedContentInset = scrollView?.adjustedContentInset ?? .zero
        let textContainerInset = textContainer.inset.value
        var viewport = CGRect(origin: contentOffset, size: textView.frame.size)
        viewport.origin.y += adjustedContentInset.top + textContainerInset.top
        viewport.origin.x += adjustedContentInset.left + textContainerInset.left
        viewport.size.width -= adjustedContentInset.left
        + adjustedContentInset.right
        + textContainerInset.left
        + textContainerInset.right
        viewport.size.height -= adjustedContentInset.top
        + adjustedContentInset.bottom
        + textContainerInset.top
        + textContainerInset.bottom
        // Construct the best possible content offset.
        var newContentOffset = contentOffset
        if rect.minX < viewport.minX {
            newContentOffset.x -= viewport.minX - rect.minX
        } else if rect.maxX > viewport.maxX && rect.width <= viewport.width {
            // The end of the rectangle is not visible and the rect fits within the screen so we'll scroll to reveal the entire rect.
            newContentOffset.x += rect.maxX - viewport.maxX
        } else if rect.maxX > viewport.maxX {
            newContentOffset.x += rect.minX
        }
        if rect.minY < viewport.minY {
            newContentOffset.y -= viewport.minY - rect.minY
        } else if rect.maxY > viewport.maxY && rect.height <= viewport.height {
            // The end of the rectangle is not visible and the rect fits within the screen so we'll scroll to reveal the entire rect.
            newContentOffset.y += rect.maxY - viewport.maxY
        } else if rect.maxY > viewport.maxY {
            newContentOffset.y += rect.minY
        }
        let minimumContentOffset = scrollView?.minimumContentOffset ?? .zero
        let maximumContentOffset = scrollView?.maximumContentOffset ?? .zero
        let cappedXOffset = min(max(newContentOffset.x, minimumContentOffset.x), maximumContentOffset.x)
        let cappedYOffset = min(max(newContentOffset.y, minimumContentOffset.y), maximumContentOffset.y)
        return CGPoint(x: cappedXOffset, y: cappedYOffset)
    }
}
