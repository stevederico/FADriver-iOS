import Foundation

/// Splits a user command on explicit chain markers: `" and then "`, `" then "`,
/// `"; "`. Conservative — bare `"and"` (`"text alice and bob"`) does NOT split,
/// only the exact spaced phrases do. Case-insensitive matching; preserves the
/// original casing of each segment.
public enum ChainSplitter {
    public static func split(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let markers = [" and then ", " then ", "; "]
        var segments = [trimmed]
        for marker in markers {
            segments = segments.flatMap { splitPreservingCase($0, marker: marker) }
        }
        return segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitPreservingCase(_ s: String, marker: String) -> [String] {
        let lower = s.lowercased()
        let markerLower = marker.lowercased()
        guard let range = lower.range(of: markerLower) else { return [s] }
        let lhsEnd = s.index(s.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
        let rhsStart = s.index(lhsEnd, offsetBy: marker.count)
        let lhs = String(s[s.startIndex..<lhsEnd])
        let rhs = String(s[rhsStart..<s.endIndex])
        return [lhs] + splitPreservingCase(rhs, marker: marker)
    }
}
