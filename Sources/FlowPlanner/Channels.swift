import FlowCore
import FlowRouting
import Foundation

/// What the planner knows about a messaging channel. This table is the only place channel
/// specifics live; the planner and runner reason about capabilities, not apps.
public struct ChannelInfo: Sendable, Equatable {
    public let channel: MessageChannel
    public let displayName: String
    /// Allowlisted app the planner may activate before messaging steps. Nil when the app is
    /// not in FlowCore's `KnownApp` allowlist (e.g. WhatsApp); the channel adapter then
    /// prepares its own app as part of the step.
    public let app: KnownApp?
    /// Words that name the channel when spoken ("email", "text", "whatsapp").
    public let spokenNames: [String]

    public init(channel: MessageChannel, displayName: String, app: KnownApp?, spokenNames: [String]) {
        self.channel = channel
        self.displayName = displayName
        self.app = app
        self.spokenNames = spokenNames
    }
}

public struct ChannelCatalog: Sendable, Equatable {
    public let channels: [ChannelInfo]
    /// Used when a messaging command names no channel and context gives none.
    public let defaultChannel: MessageChannel

    public init(channels: [ChannelInfo], defaultChannel: MessageChannel) {
        self.channels = channels
        self.defaultChannel = defaultChannel
    }

    public static let standard = ChannelCatalog(
        channels: [
            ChannelInfo(channel: .mail, displayName: "Mail", app: .mail, spokenNames: ["email", "e-mail", "mail"]),
            ChannelInfo(channel: .messages, displayName: "Messages", app: nil,
                        spokenNames: ["text", "texts", "text message", "imessage", "sms", "messages app"]),
            ChannelInfo(channel: .whatsapp, displayName: "WhatsApp", app: nil,
                        spokenNames: ["whatsapp", "whatsapp message", "whats app"]),
        ],
        defaultChannel: .mail)

    public func info(_ channel: MessageChannel) -> ChannelInfo? {
        channels.first { $0.channel == channel }
    }

    /// Longest spoken names first, so "whatsapp message" wins over "message".
    var spokenIndex: [(String, MessageChannel)] {
        channels.flatMap { info in info.spokenNames.map { ($0, info.channel) } }.sorted { $0.0.count > $1.0.count }
    }
}

/// Finds an explicitly named channel in a clause and rewrites the clause into the router's
/// channel-neutral vocabulary ("text Lee I'm late" → "message Lee I'm late").
public struct ChannelResolver: Sendable {
    public let catalog: ChannelCatalog

    public init(catalog: ChannelCatalog) {
        self.catalog = catalog
    }

    public struct Resolved: Sendable, Equatable {
        public let clause: String
        public let channel: MessageChannel?
    }

    public func resolve(_ clause: String) -> Resolved {
        var text = clause
        var found: MessageChannel?
        for (name, channel) in catalog.spokenIndex {
            let n = NSRegularExpression.escapedPattern(for: name)
            // "… on WhatsApp", "via text", "over email", "using Messages", "by text"
            if let r = text.range(of: #"\s*,?\s+(?:on|via|over|through|using|in|by)\s+(?:the\s+)?"# + n + #"\b"#, options: [.regularExpression, .caseInsensitive]) {
                text.removeSubrange(r)
                found = found ?? channel
            }
            // Leading verb: "text Lee …", "whatsapp Lee …", "email Dana …"
            if let r = text.range(of: #"^(?:"# + n + #")\s+"#, options: [.regularExpression, .caseInsensitive]),
               ["text", "imessage", "whatsapp", "sms", "whats app"].contains(name) {
                text.replaceSubrange(r, with: "message ")
                found = found ?? channel
            }
            // "send Lee a WhatsApp saying …" → "message Lee saying …"
            if let r = text.range(of: #"^send\s+([a-z][a-z'.-]*)\s+an?\s+"# + n + #"(?:\s+message)?\b"#, options: [.regularExpression, .caseInsensitive]),
               name != "mail" {
                let who = text[r].split(separator: " ")[1]
                text.replaceSubrange(r, with: (["email", "e-mail"].contains(name) ? "email " : "message ") + who)
                found = found ?? channel
            }
            // "send a WhatsApp to …"
            if let r = text.range(of: #"\b(?:an?\s+)"# + n + #"(?:\s+message)?\b"#, options: [.regularExpression, .caseInsensitive]),
               name != "mail" {
                let replacement = ["email", "e-mail"].contains(name) ? "an email" : "a message"
                text.replaceSubrange(r, with: replacement)
                found = found ?? channel
            }
            // Search nouns: "Sarah's WhatsApp message", "the text from Lee", "my latest email"
            if found == nil, ["whatsapp", "whatsapp message", "text", "text message", "imessage", "texts"].contains(name),
               let r = text.range(of: #"\b"# + n + #"(?:\s+message)?\b"#, options: [.regularExpression, .caseInsensitive]),
               text.range(of: #"^(?:find|search|look|show|open|read|check|get|pull)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                text.replaceSubrange(r, with: "message")
                found = channel
            }
            if found == nil, ["email", "e-mail"].contains(name),
               text.range(of: #"\b"# + n + #"\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                found = channel  // "email" stays in the text; the router already understands it
            }
        }
        return Resolved(clause: text.split(whereSeparator: \.isWhitespace).joined(separator: " "), channel: found)
    }
}
