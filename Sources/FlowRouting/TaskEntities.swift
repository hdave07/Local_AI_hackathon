import CryptoKit
import FlowCore
import Foundation

/// A messaging channel: Mail, Messages, WhatsApp, or any other adapter Track A provides.
/// Open-ended by design (a string identity), so adding a channel needs no planner change.
public struct MessageChannel: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue.lowercased() }

    public static let mail = MessageChannel(rawValue: "mail")
    public static let messages = MessageChannel(rawValue: "messages")
    public static let whatsapp = MessageChannel(rawValue: "whatsapp")

    public var description: String { rawValue }
}

/// A message (email, text, chat) as identified and verified by the executor's channel
/// adapter. `id` is the adapter's stable identity; `epoch` scopes it to one result set.
public struct MessageRef: Sendable, Equatable, Hashable {
    public let channel: MessageChannel
    public let id: String
    /// Display name of the sender ("Sarah Chen").
    public let sender: String
    /// Address or handle, when known ("sarah.chen@example.com", "+1 555…", a chat handle).
    public let senderAddress: String?
    /// Subject for email; first line or conversation name for chats.
    public let subject: String
    /// Human-readable date ("today 9:14", "Nov 13").
    public let date: String?
    /// Snapshot/result-set epoch; a stale epoch is rejected by the executor.
    public let epoch: Int

    public init(
        channel: MessageChannel = .mail, id: String, sender: String, senderAddress: String? = nil, subject: String,
        date: String? = nil, epoch: Int = 0
    ) {
        self.channel = channel
        self.id = id
        self.sender = sender
        self.senderAddress = senderAddress
        self.subject = subject
        self.date = date
        self.epoch = epoch
    }

    /// "Sarah Chen — “Meeting tomorrow” (today 9:14)"
    public var spoken: String {
        "\(sender) — “\(subject)”" + (date.map { " (\($0))" } ?? "")
    }
}

/// The current state of a Flow-authored outgoing message as observed in the channel's
/// real compose UI (plan 03 §3 `DraftSnapshot`). The visible draft is the source of truth.
public struct DraftSnapshot: Sendable, Equatable, Hashable {
    public let channel: MessageChannel
    public let id: String
    public let recipients: [String]
    public let subject: String
    public let body: String
    /// Increases with every change, including changes made by the user outside Flow.
    public let version: Int
    /// The message this draft replies to, if any.
    public let inReplyTo: String?

    public init(
        channel: MessageChannel = .mail, id: String, recipients: [String], subject: String = "", body: String, version: Int,
        inReplyTo: String? = nil
    ) {
        self.channel = channel
        self.id = id
        self.recipients = recipients
        self.subject = subject
        self.body = body
        self.version = version
        self.inReplyTo = inReplyTo
    }

    /// SHA-256 over channel, normalized recipients, subject and body (spec 02 §3: approval
    /// binds body, recipients, subject and version). The channel is included so approving
    /// a WhatsApp message can never authorize the same text over email.
    public var contentHash: String {
        let recipients = self.recipients.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.sorted()
        let normalizedBody = body.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let material = ([channel.rawValue, "\u{1F}"] + recipients + ["\u{1F}", subject.trimmingCharacters(in: .whitespaces), "\u{1F}", normalizedBody])
            .joined(separator: "\u{1E}")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A window the executor verified (subset of Track A's `WindowRef`).
public struct SelectedWindow: Sendable, Equatable {
    public let app: KnownApp?
    public let title: String?
    public let windowID: String

    public init(app: KnownApp?, title: String?, windowID: String) {
        self.app = app
        self.title = title
        self.windowID = windowID
    }
}
