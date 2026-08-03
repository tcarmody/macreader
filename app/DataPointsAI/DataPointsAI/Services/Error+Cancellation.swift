import Foundation

extension Error {
    /// True when this error means "the work was cancelled", not "the work failed".
    ///
    /// Debounced search cancels the in-flight request on every keystroke, so
    /// correcting a typo routinely lands here. Cancellation is the system doing
    /// what we asked and must never reach the user as an error.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError { return urlError.code == .cancelled }

        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
