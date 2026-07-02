import Foundation

/// The plaintext content that gets sealed into `Envelope.ciphertext`.
/// The server never sees this; only peers can decrypt it.
public struct MessagePayload: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case text
        case photo
        case youtube
        case gameInvite
        case chessMove
        case typing
        case receipt
    }

    public var id: UUID
    public var kind: Kind
    public var text: String?
    /// Base64-encoded image bytes for photos (still E2EE; server never sees it).
    public var imageBase64: String?
    public var linkURL: String?
    public var chessMove: ChessMove?
    public var receiptState: DeliveryState?
    /// For edit/delete this references the target message id.
    public var targetMessageID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        text: String? = nil,
        imageBase64: String? = nil,
        linkURL: String? = nil,
        chessMove: ChessMove? = nil,
        receiptState: DeliveryState? = nil,
        targetMessageID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageBase64 = imageBase64
        self.linkURL = linkURL
        self.chessMove = chessMove
        self.receiptState = receiptState
        self.targetMessageID = targetMessageID
        self.createdAt = createdAt
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> MessagePayload {
        try JSONDecoder().decode(MessagePayload.self, from: data)
    }
}

/// Delivery lifecycle used by both receipts and persisted messages.
public enum DeliveryState: String, Codable, Sendable {
    case sending
    case sent
    case delivered
    case read
}
