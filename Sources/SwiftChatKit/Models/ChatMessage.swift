import Foundation
import SwiftData

public enum MessageKind: String, Codable, Sendable {
    case text
    case photo
    case youtube
    case gameInvite
    case chess
}

/// Locally cached chat message. Raw image bytes are NEVER stored here; only the
/// relative on-disk path (`mediaRelativePath`) is persisted.
@Model
public final class ChatMessage {
    @Attribute(.unique) public var id: UUID
    public var convoID: UUID
    public var senderID: UUID
    public var kindRaw: String
    public var text: String?
    /// Relative path (into the app-support media dir) — resolved lazily by the UI.
    public var mediaRelativePath: String?
    public var linkURL: String?
    public var createdAt: Date
    /// Non-nil => render an "(Edited)" label.
    public var editedAt: Date?
    /// Tombstone flag. When true the payload is scrubbed but the row is kept.
    public var isDeleted: Bool
    public var deliveryStateRaw: String

    @Relationship(deleteRule: .cascade)
    public var receipts: [DeliveryReceipt]

    public var kind: MessageKind {
        get { MessageKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    public var deliveryState: DeliveryState {
        get { DeliveryState(rawValue: deliveryStateRaw) ?? .sent }
        set { deliveryStateRaw = newValue.rawValue }
    }

    public var isEdited: Bool { editedAt != nil }

    public init(
        id: UUID = UUID(),
        convoID: UUID,
        senderID: UUID,
        kind: MessageKind,
        text: String? = nil,
        mediaRelativePath: String? = nil,
        linkURL: String? = nil,
        createdAt: Date = Date(),
        deliveryState: DeliveryState = .sent
    ) {
        self.id = id
        self.convoID = convoID
        self.senderID = senderID
        self.kindRaw = kind.rawValue
        self.text = text
        self.mediaRelativePath = mediaRelativePath
        self.linkURL = linkURL
        self.createdAt = createdAt
        self.editedAt = nil
        self.isDeleted = false
        self.deliveryStateRaw = deliveryState.rawValue
        self.receipts = []
    }

    /// Apply an edit: replace text and stamp `editedAt`.
    public func applyEdit(newText: String, at date: Date = Date()) {
        guard !isDeleted else { return }
        self.text = newText
        self.editedAt = date
    }

    /// Tombstone the message: keep the row, scrub the payload, set the flag.
    /// The caller is responsible for removing any on-disk media file.
    public func tombstone(at date: Date = Date()) {
        self.text = nil
        self.mediaRelativePath = nil
        self.linkURL = nil
        self.isDeleted = true
        self.editedAt = date
    }

    /// The text the AI summarizer should use: latest edited text, ignoring tombstones.
    public var summarizableText: String? {
        guard !isDeleted else { return nil }
        return text
    }
}

@Model
public final class DeliveryReceipt {
    @Attribute(.unique) public var id: UUID
    public var messageID: UUID
    public var stateRaw: String
    public var at: Date

    public var state: DeliveryState {
        get { DeliveryState(rawValue: stateRaw) ?? .sent }
        set { stateRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), messageID: UUID, state: DeliveryState, at: Date = Date()) {
        self.id = id
        self.messageID = messageID
        self.stateRaw = state.rawValue
        self.at = at
    }
}

@Model
public final class ChessGameState {
    @Attribute(.unique) public var id: UUID
    public var messageID: UUID
    public var fen: String
    public var turn: String
    public var isCheckmate: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        messageID: UUID,
        fen: String,
        turn: String = "w",
        isCheckmate: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.fen = fen
        self.turn = turn
        self.isCheckmate = isCheckmate
        self.updatedAt = updatedAt
    }
}

/// Central schema helper so both apps configure SwiftData identically.
public enum ChatSchema {
    public static let models: [any PersistentModel.Type] = [
        ChatMessage.self,
        DeliveryReceipt.self,
        ChessGameState.self
    ]
}
