import Foundation

enum DurationEstimator {
    static func estimate(text: String, wordsPerMinute: Int) -> TimeInterval {
        let words = text
            .split { $0.isWhitespace || $0.isNewline }
            .filter { !$0.isEmpty }
            .count
        guard wordsPerMinute > 0 else { return 0 }
        return (Double(words) / Double(wordsPerMinute)) * 60
    }

    static func formatted(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}
