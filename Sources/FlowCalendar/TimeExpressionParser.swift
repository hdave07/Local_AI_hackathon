import Foundation

/// A spoken time expression resolved to an exact interval in the local time zone.
public struct TimeQuery: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// "at 4": a short slot starting at that time.
        case moment
        /// "Friday afternoon", "between 2 and 4".
        case range
        /// "tomorrow", "Monday": the whole day.
        case day
    }

    public let kind: Kind
    public let interval: DateInterval
    /// Human description used in answers: "tomorrow (Sun 15 Nov) at 4:00 PM".
    public let description: String
    /// Defaults Flow applied, stated in the answer ("I took 4 as 4 PM").
    public let assumptions: [String]
    /// Start of the day the query is about (for "show the day").
    public let day: Date
}

public enum TimeParseError: Error, Sendable, Equatable {
    case unrecognized(String)
}

/// Deterministic parser for the time expressions the router passes in `query_calendar`
/// ("at four tomorrow", "Friday afternoon", "at 10 am on Tuesday", "November 20 at noon").
/// All arithmetic goes through `Calendar`, so daylight-saving transitions are handled by
/// Foundation, never by adding fixed seconds.
public enum TimeExpressionParser {
    /// Length of a "moment" query: "anything at 4" checks 4:00 to 4:30.
    public static let momentLength: TimeInterval = 30 * 60

    static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12,
    ]
    static let minuteWords: [String: Int] = ["fifteen": 15, "thirty": 30, "forty-five": 45, "fortyfive": 45, "oh-five": 5]
    static let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    static let months = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
                         "september": 9, "october": 10, "november": 11, "december": 12, "jan": 1, "feb": 2, "mar": 3, "apr": 4,
                         "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12]
    /// Parts of the day (local hours, end exclusive).
    static let parts: [(String, Int, Int)] = [
        ("morning", 8, 12), ("afternoon", 12, 17), ("evening", 17, 21), ("tonight", 18, 24), ("night", 18, 24),
        ("lunchtime", 12, 13), ("lunch", 12, 13),
    ]

    public static func parse(_ raw: String, now: Date, calendar: Calendar = .current) -> Result<TimeQuery, TimeParseError> {
        var text = " " + normalize(raw) + " "
        var assumptions: [String] = []
        let today = calendar.startOfDay(for: now)
        func addDays(_ n: Int, _ d: Date = today) -> Date { calendar.date(byAdding: .day, value: n, to: d)! }

        // ---- Day ----
        var day: Date?
        var dayLabel: String?
        var rangeOverride: DateInterval?
        /// Removes the first match only if `accept` approves its groups.
        func take(_ pattern: String, accept: ([String]) -> Bool = { _ in true }) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let groups = (0..<m.numberOfRanges).map { i -> String in
                    Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
                }
                guard accept(groups) else { continue }
                text.replaceSubrange(Range(m.range, in: text)!, with: " ")
                return groups
            }
            return nil
        }

        if take(#" (?:the )?day after tomorrow "#) != nil { day = addDays(2); dayLabel = "the day after tomorrow" }
        else if take(#" tomorrow "#) != nil { day = addDays(1); dayLabel = "tomorrow" }
        else if take(#" today "#) != nil || text.contains(" tonight ") { day = today; dayLabel = "today" }
        else if take(#" this (?=morning|afternoon|evening|lunch)"#) != nil { day = today; dayLabel = "today" }
        if day == nil, take(#" (?:this )?weekend "#) != nil {
            let wd = calendar.component(.weekday, from: today)
            let toSaturday = (7 - wd + 7) % 7
            let saturday = addDays(toSaturday)
            day = saturday
            dayLabel = "this weekend"
            rangeOverride = DateInterval(start: saturday, end: addDays(2, saturday))
        }
        if day == nil, let g = take(#" (next |this |on )?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)s? "#) {
            text = text.replacingOccurrences(of: " this ", with: " ")
            let target = weekdays[g[2]]!
            let wd = calendar.component(.weekday, from: today)
            var delta = (target - wd + 7) % 7
            if g[1].hasPrefix("next"), delta == 0 { delta = 7 }
            day = addDays(delta)
            dayLabel = delta == 0 ? "today" : (delta == 1 ? "tomorrow" : nil)  // the date already names the weekday
        }
        if day == nil, let g = take(#" (?:on )?(?:the )?(\d{1,2})(?:st|nd|rd|th)? (?:of )?([a-z]+) "#, accept: { months[$0[2]] != nil }),
           let month = months[g[2]] {
            day = monthDay(month: month, day: Int(g[1])!, today: today, calendar: calendar)
            dayLabel = nil
        } else if day == nil, let g = take(#" (?:on )?([a-z]+) (\d{1,2})(?:st|nd|rd|th)? "#, accept: { months[$0[1]] != nil }),
                  let month = months[g[1]] {
            day = monthDay(month: month, day: Int(g[2])!, today: today, calendar: calendar)
            dayLabel = nil
        } else if day == nil, let g = take(#" (?:on )?the (\d{1,2})(?:st|nd|rd|th) "#) {
            let comps = calendar.dateComponents([.year, .month], from: today)
            var d = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: Int(g[1])!))
            if let candidate = d, candidate < today { d = calendar.date(byAdding: .month, value: 1, to: candidate) }
            day = d.map { calendar.startOfDay(for: $0) }
            dayLabel = nil
        }

        // ---- Part of day ----
        var part: (String, Int, Int)?
        for p in parts where text.contains(" \(p.0) ") {
            part = p
            text = text.replacingOccurrences(of: " \(p.0) ", with: " ")
            break
        }

        // ---- Times ----
        func clock(_ hourText: String, _ minuteText: String, _ meridiem: String) -> (Int, Int, Bool)? {
            guard var hour = Int(hourText) ?? numberWords[hourText] else { return nil }
            let minute = Int(minuteText) ?? minuteWords[minuteText] ?? 0
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            var assumed = false
            if meridiem == "pm", hour < 12 { hour += 12 }
            else if meridiem == "am", hour == 12 { hour = 0 }
            else if meridiem.isEmpty, hour >= 1, hour <= 12 {
                if let part {
                    if part.1 >= 12, hour < 12 { hour += 12 }  // "four in the afternoon"
                } else if hour <= 6 {
                    hour += 12
                    assumed = true
                } else if hour <= 11 {
                    assumed = true
                }
            }
            return (hour, minute, assumed)
        }
        let num = #"(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#
        let minutes = #"(?:(?::| )(\d{2}|fifteen|thirty|forty-five|fortyfive))?"#
        let mer = #"(?: ?(am|pm))?"#
        var times: [(Int, Int, Bool)] = []

        if take(#" (?:at )?noon "#) != nil || take(#" (?:at )?midday "#) != nil { times.append((12, 0, false)) }
        else if take(#" (?:at )?midnight "#) != nil { times.append((0, 0, false)) }
        else if let g = take(#" (?:between|from) "# + num + minutes + mer + #" (?:and|to|until|till) "# + num + minutes + mer + " ") {
            if var a = clock(g[1], g[2], g[3].isEmpty ? g[6] : g[3]), let b = clock(g[4], g[5], g[6]) {
                if a.0 > b.0, g[3].isEmpty { a.0 -= 12 }  // "between 11 and 1" stays in order
                times = [a, b]
            }
        } else if let g = take(#" (?:at |around |by )?(\d{1,2})"# + minutes + mer + #"(?: o'?clock)? "#) {
            if let t = clock(g[1], g[2], g[3]) { times = [t] }
        } else if let g = take(#" (at |around |by )?"# + num + minutes + mer + #"( o'?clock)? "#,
                               accept: { !$0[1].isEmpty || !$0[4].isEmpty || !$0[5].isEmpty }) {
            // Number words ("four") only count as times with a cue: "at four", "four pm", "four o'clock".
            if let t = clock(g[2], g[3], g[4]) { times = [t] }
        }

        let leftover = text.split(separator: " ").filter { !["at", "on", "in", "the", "for", "of", "around", "by", "anything", "free", "busy"].contains($0) }
        if day == nil, part == nil, times.isEmpty { return .failure(.unrecognized(raw)) }
        if !leftover.isEmpty, times.isEmpty, part == nil, day == nil { return .failure(.unrecognized(raw)) }

        let theDay = day ?? today
        if day == nil { assumptions.append("I assumed you meant today") }
        let dayText = describeDay(theDay, label: dayLabel, calendar: calendar)
        func at(_ h: Int, _ m: Int, on d: Date) -> Date {
            h >= 24 ? addDays(1, d) : calendar.date(bySettingHour: h, minute: m, second: 0, of: d)!
        }

        if let rangeOverride {
            return .success(TimeQuery(kind: .range, interval: rangeOverride, description: dayText, assumptions: assumptions, day: theDay))
        }
        if times.count == 2 {
            let start = at(times[0].0, times[0].1, on: theDay)
            var end = at(times[1].0, times[1].1, on: theDay)
            if end <= start { end = calendar.date(byAdding: .hour, value: 12, to: end)! }
            return .success(TimeQuery(kind: .range, interval: DateInterval(start: start, end: end),
                                      description: "\(dayText) from \(clockText(start, calendar)) to \(clockText(end, calendar))",
                                      assumptions: assumptions, day: theDay))
        }
        if let t = times.first {
            if t.2 {
                let shown = clockText(at(t.0, t.1, on: theDay), calendar)
                assumptions.append("I took that as \(shown)")
            }
            let start = at(t.0, t.1, on: theDay)
            return .success(TimeQuery(kind: .moment, interval: DateInterval(start: start, duration: momentLength),
                                      description: "\(dayText) at \(clockText(start, calendar))", assumptions: assumptions, day: theDay))
        }
        if let part {
            let start = at(part.1, 0, on: theDay)
            let end = at(part.2, 0, on: theDay)
            return .success(TimeQuery(kind: .range, interval: DateInterval(start: start, end: end),
                                      description: "\(dayText) \(part.0 == "tonight" ? "evening" : "in the \(part.0)") (\(clockText(start, calendar))–\(clockText(end, calendar)))",
                                      assumptions: assumptions, day: theDay))
        }
        return .success(TimeQuery(kind: .day, interval: DateInterval(start: theDay, end: addDays(1, theDay)),
                                  description: dayText, assumptions: assumptions, day: theDay))
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased().replacingOccurrences(of: "’", with: "'")
        s = s.replacingOccurrences(of: #"\b([ap])\.?\s?m\.?(?=\s|$)"#, with: "$1m", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)(am|pm)\b"#, with: "$1 $2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[?!,.;]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\bin the\b"#, with: " ", options: .regularExpression)
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func monthDay(month: Int, day: Int, today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        guard var d = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        if d < today { d = calendar.date(byAdding: .year, value: 1, to: d)! }  // "January 3" in November means next year
        return calendar.startOfDay(for: d)
    }

    public static func describeDay(_ day: Date, label: String?, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"
        let date = f.string(from: day)
        return label.map { "\($0) (\(date))" } ?? date
    }

    public static func clockText(_ date: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
