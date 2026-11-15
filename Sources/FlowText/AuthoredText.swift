import Foundation

/// Splits a reply body into the part the user wrote and the quoted original below it
/// ("On … wrote:", "-----Original Message-----", or "> " lines). Edits touch only the
/// authored part; the quote, and with it the thread, is preserved byte for byte.
public enum AuthoredText {
    public static func split(_ body: String) -> (authored: String, quoted: String) {
        let ns = body as NSString
        let patterns = [#"(?m)^[ \t]*On .{1,300}wrote:[ \t]*$"#, #"(?m)^-{2,}\s*Original Message\s*-{2,}"#, #"(?m)^>"#]
        var cut = ns.length
        for p in patterns {
            if let r = body.range(of: p, options: .regularExpression) {
                cut = min(cut, NSRange(r, in: body).location)
            }
        }
        guard cut < ns.length else { return (body, "") }
        // Keep the blank line(s) before the quote with the quote.
        var start = cut
        while start > 0, let c = Unicode.Scalar(ns.character(at: start - 1)), CharacterSet.whitespacesAndNewlines.contains(c) { start -= 1 }
        return (ns.substring(to: start), ns.substring(from: start))
    }

    public static func join(authored: String, quoted: String) -> String { authored + quoted }
}
