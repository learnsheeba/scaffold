import Foundation
import CryptoKit

/// Handles the client-side E2EE: X25519 key agreement, HKDF key derivation,
/// and AEAD (AES-GCM / ChaChaPoly) sealing. Lives ONLY in the clients — the
/// server target does not link this type, so it can never decrypt payloads.
public final class CryptoEngine {
    public enum CryptoError: Error {
        case notEstablished
        case badPublicKey
        case sealFailed
        case openFailed
    }

    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private var symmetricKey: SymmetricKey?
    private let suite: CipherSuite

    private static let salt = Data("swiftchat-salt".utf8)
    private static let info = Data("swiftchat-v1".utf8)

    public init(suite: CipherSuite = .aesGCM) {
        self.privateKey = Curve25519.KeyAgreement.PrivateKey()
        self.suite = suite
    }

    /// The public key to advertise in a `.handshake` envelope.
    public var publicKeyData: Data {
        privateKey.publicKey.rawRepresentation
    }

    public var cipherSuite: CipherSuite { suite }

    public var isEstablished: Bool { symmetricKey != nil }

    /// Complete ECDH with the peer's public key and derive the shared symmetric key.
    public func establishSharedKey(withPeerPublicKey data: Data) throws {
        guard let peerPub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data) else {
            throw CryptoError.badPublicKey
        }
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peerPub)
        symmetricKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Self.salt,
            sharedInfo: Self.info,
            outputByteCount: 32
        )
    }

    /// Test/utility seam: inject a known key (used by unit tests for determinism).
    public func setSymmetricKey(_ key: SymmetricKey) {
        self.symmetricKey = key
    }

    public func seal(_ plaintext: Data) throws -> Data {
        guard let key = symmetricKey else { throw CryptoError.notEstablished }
        switch suite {
        case .aesGCM:
            guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
                throw CryptoError.sealFailed
            }
            return combined
        case .chaChaPoly:
            return try ChaChaPoly.seal(plaintext, using: key).combined
        }
    }

    public func open(_ ciphertext: Data) throws -> Data {
        guard let key = symmetricKey else { throw CryptoError.notEstablished }
        switch suite {
        case .aesGCM:
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        case .chaChaPoly:
            let box = try ChaChaPoly.SealedBox(combined: ciphertext)
            return try ChaChaPoly.open(box, using: key)
        }
    }

    /// Convenience: encrypt a payload straight into a sealed `Data`.
    public func sealPayload(_ payload: MessagePayload) throws -> Data {
        try seal(payload.encoded())
    }

    /// Convenience: decrypt sealed `Data` back into a payload.
    public func openPayload(_ ciphertext: Data) throws -> MessagePayload {
        try MessagePayload.decode(open(ciphertext))
    }
}
