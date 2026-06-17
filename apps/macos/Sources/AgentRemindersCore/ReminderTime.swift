import Foundation

public enum TimeError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self {
        case .invalid(let value): return "Invalid time value: \(value)"
        }
    }
}

/// Relative + absolute time parsing, mirroring src/time.ts and extending it with
/// the v1 word shortcuts (later / today / tonight / tomorrow).
public enum ReminderTime {
    private static let unitSeconds: [String: Double] = [
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
        "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
        "d": 86_400, "day": 86_400, "days": 86_400
    ]

    private static let relativeRegex = try! NSRegularExpression(
        pattern: "^(\\d+)\\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)$",
        options: [.caseInsensitive]
    )

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Format a date as an ISO string with milliseconds + Z, matching JS `toISOString()`.
    public static func iso(from date: Date) -> String {
        isoFractional.string(from: date)
    }

    /// Parse a stored ISO timestamp back into a Date.
    public static func parseStored(_ value: String) -> Date? {
        isoFractional.date(from: value) ?? isoPlain.date(from: value)
    }

    /// Parse a user/agent-supplied value into a stored ISO string.
    /// Returns nil for empty input (clears the time). Throws on unparseable input.
    public static func parse(_ value: String?, now: Date) throws -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = relativeRegex.firstMatch(in: trimmed, options: [], range: range) {
            let nsString = trimmed as NSString
            let amount = Double(nsString.substring(with: match.range(at: 1))) ?? 0
            let unit = nsString.substring(with: match.range(at: 2)).lowercased()
            let seconds = unitSeconds[unit] ?? 0
            return iso(from: now.addingTimeInterval(amount * seconds))
        }

        if let shortcutDate = shortcut(trimmed.lowercased(), now: now) {
            return iso(from: shortcutDate)
        }

        if let absolute = parseStored(trimmed) {
            return iso(from: absolute)
        }

        throw TimeError.invalid(trimmed)
    }

    public static func isDue(_ value: String?, now: Date) -> Bool {
        guard let value, let date = parseStored(value) else { return false }
        return date.timeIntervalSince(now) <= 0
    }

    private static func shortcut(_ value: String, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        switch value {
        case "later":
            return now.addingTimeInterval(3600)
        case "today":
            return atHour(17, from: now, calendar: calendar, bumpToTomorrowIfPast: true)
        case "tonight":
            return atHour(20, from: now, calendar: calendar, bumpToTomorrowIfPast: true)
        case "tomorrow":
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return atHour(9, from: tomorrow, calendar: calendar, bumpToTomorrowIfPast: false)
        default:
            return nil
        }
    }

    private static func atHour(_ hour: Int, from date: Date, calendar: Calendar, bumpToTomorrowIfPast: Bool) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard let candidate = calendar.date(from: components) else { return nil }
        if bumpToTomorrowIfPast, candidate.timeIntervalSince(date) <= 0 {
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return candidate
    }
}
