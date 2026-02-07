import Foundation
import os

extension Logger {
    /// Logs a DecodingError with detailed path and type information for debugging.
    func logDecodingError(_ error: DecodingError) {
        switch error {
        case .typeMismatch(let type, let context):
            self.error("Decode TypeMismatch: expected \(String(describing: type)), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .keyNotFound(let key, let context):
            self.error("Decode KeyNotFound: \(key.stringValue), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .valueNotFound(let type, let context):
            self.error("Decode ValueNotFound: \(String(describing: type)), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
        case .dataCorrupted(let context):
            self.error("Decode DataCorrupted: \(context.debugDescription)")
        @unknown default:
            self.error("Decode unknown error: \(error.localizedDescription)")
        }
    }
}
