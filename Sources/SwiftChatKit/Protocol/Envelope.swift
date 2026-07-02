import Foundation

/// The kind of frame traveling over the WebSocket.
/// Only routing metadata is plaintext; content lives in `ciphertext`.
public enum FrameType: String, Codable, Sendable {
    case handshake     // carries a plaintext X25519 public key (safe)
    case message       // a new chat message
    case edit          // edit mutation for an existing message
    case delete        // delete/tombstone mutation
    case typing        // transient "is typing" signal (never persisted)
    case receipt       // delivery/read receipt
    case gameInvite    // chess game invite
    case chessMove     // a single chess move to sync
}

/// The outermost frame on the wire. The server may read `type`, `senderID`,
/// and `convoID` for routing only. It must treat `ciphertext` as opaque.
public struct Envelope: Codable, Sendable, Equatable {
    public var type: FrameType
    public var senderID: UUID
    public var convoID: UUID
    /// Plaintext public key material — only present on `.handshake` frames.
    public var handshake: HandshakePayload?
    /// AEAD sealed box (nonce || ciphertext || tag). Opaque to the server.
    public var ciphertext: Data?
    /// Monotonic per-sender counter for replay defense.
    public var nonceHint: UInt64?

    public init(
        type: FrameType,
        senderID: UUID,
        convoID: UUID,
        handshake: HandshakePayload? = nil,
        ciphertext: Data? = nil,
        nonceHint: UInt64? = nil
    ) {
        self.type = type
        self.senderID = senderID
        self.convoID = convoID
        self.handshake = handshake
        self.ciphertext = ciphertext
        self.nonceHint = nonceHint
    }
}

/// Plaintext handshake material. A raw X25519 public key is safe to expose.
public struct HandshakePayload: Codable, Sendable, Equatable {
    public var publicKeyData: Data
    public var cipherSuite: CipherSuite

    public init(publicKeyData: Data, cipherSuite: CipherSuite) {
        self.publicKeyData = publicKeyData
        self.cipherSuite = cipherSuite
    }
}

public enum CipherSuite: String, Codable, Sendable {
    case aesGCM
    case chaChaPoly
}

/// Binary wire codec. Envelopes are JSON-encoded to `Data` and sent as `.binary`.
public enum WireCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ envelope: Envelope) throws -> Data {
        try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> Envelope {
        try decoder.decode(Envelope.self, from: data)
    }
}
