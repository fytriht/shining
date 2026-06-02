import Foundation

public enum IdeaTextAppender {
    public static func append(existing: String, capture: String, timestamp: String) -> String {
        let trimmedCapture = capture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCapture.isEmpty else {
            return existing
        }

        let entry = """
        ## \(timestamp)

        \(trimmedCapture)
        """

        guard !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return entry
        }

        return existing.trimmingTrailingNewlines() + "\n\n" + entry
    }
}

private extension String {
    func trimmingTrailingNewlines() -> String {
        var result = self
        while result.last == "\n" || result.last == "\r" {
            result.removeLast()
        }
        return result
    }
}
