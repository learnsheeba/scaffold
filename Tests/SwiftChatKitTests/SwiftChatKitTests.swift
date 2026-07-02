import Testing
import Foundation
import CryptoKit
import SwiftData
@testable import SwiftChatKit

// MARK: - Unit 1: Tombstone scrub keeps the row, clears payload, sets the flag.

@Test func tombstoneScrubsPayloadButKeepsRow() throws {
    let msg = ChatMessage(
        convoID: UUID(),
        senderID: UUID(),
        kind: .photo,
        text: "secret caption",
        mediaRelativePath: "Media/abc.jpg",
        linkURL: "https://youtu.be/x"
    )

    #expect(msg.isDeleted == false)
    msg.tombstone()

    #expect(msg.isDeleted == true)
    #expect(msg.text == nil)
    #expect(msg.mediaRelativePath == nil)
    #expect(msg.linkURL == nil)
    // The row object still exists (not deleted from context).
    #expect(msg.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
}

// MARK: - Unit 2: Edit sets editedAt and summarizableText uses latest text.

@Test func editUpdatesTextAndIsEditedFlag() throws {
    let msg = ChatMessage(convoID: UUID(), senderID: UUID(), kind: .text, text: "hi")
    #expect(msg.isEdited == false)

    msg.applyEdit(newText: "hello there")
    #expect(msg.isEdited == true)
    #expect(msg.text == "hello there")
    #expect(msg.summarizableText == "hello there")

    // Tombstoned messages are never summarizable.
    msg.tombstone()
    #expect(msg.summarizableText == nil)
}

// MARK: - Unit 3: MediaStore stores bytes on disk, returns only a relative path.

@Test func mediaStoreWritesToDiskAndReturnsRelativePath() throws {
    let store = MediaStore()
    let bytes = Data([0x01, 0x02, 0x03, 0x04, 0x05])

    let relPath = try store.writeImage(bytes, fileExtension: "jpg")

    // Only a relative path is returned (never the raw bytes).
    #expect(relPath.hasPrefix("Media/"))
    #expect(relPath.hasSuffix(".jpg"))

    let absURL = try store.absoluteURL(forRelativePath: relPath)
    let loaded = try Data(contentsOf: absURL)
    #expect(loaded == bytes)

    store.removeImage(relativePath: relPath)
    #expect(FileManager.default.fileExists(atPath: absURL.path) == false)
}

// MARK: - Unit 4: Envelope + payload round-trip through the binary wire codec.

@Test func envelopeAndPayloadWireRoundTrip() throws {
    let payload = MessagePayload(kind: .text, text: "round trip", targetMessageID: UUID())
    let payloadData = try payload.encoded()
    let decodedPayload = try MessagePayload.decode(payloadData)
    #expect(decodedPayload.text == "round trip")
    #expect(decodedPayload.kind == .text)

    let env = Envelope(
        type: .message,
        senderID: UUID(),
        convoID: UUID(),
        ciphertext: payloadData,
        nonceHint: 7
    )
    let wire = try WireCodec.encode(env)
    let decodedEnv = try WireCodec.decode(wire)
    #expect(decodedEnv.type == .message)
    #expect(decodedEnv.nonceHint == 7)
    #expect(decodedEnv.ciphertext == payloadData)
}

// MARK: - Unit 5: Two peers derive the SAME key; AES-GCM round-trips E2EE.

@Test func e2eeKeyAgreementAndSealOpenRoundTrip() throws {
    let alice = CryptoEngine(suite: .aesGCM)
    let bob = CryptoEngine(suite: .aesGCM)

    try alice.establishSharedKey(withPeerPublicKey: bob.publicKeyData)
    try bob.establishSharedKey(withPeerPublicKey: alice.publicKeyData)

    #expect(alice.isEstablished)
    #expect(bob.isEstablished)

    let secret = MessagePayload(kind: .text, text: "top secret")
    let sealed = try alice.sealPayload(secret)

    // The sealed bytes must not equal the plaintext.
    #expect(sealed != (try secret.encoded()))

    let opened = try bob.openPayload(sealed)
    #expect(opened.text == "top secret")
}

// MARK: - Unit 6: ChessEngine detects Fool's Mate checkmate.

@Test func chessEngineDetectsFoolsMate() throws {
    let e = ChessEngine()
    func sq(_ f: Int, _ r: Int) -> Square { Square(file: f, rank: r) }

    // 1. f3 e5  2. g4 Qh4#
    #expect(e.apply(ChessMove(from: sq(5, 1), to: sq(5, 2))))   // f2-f3
    #expect(e.apply(ChessMove(from: sq(4, 6), to: sq(4, 4))))   // e7-e5
    #expect(e.apply(ChessMove(from: sq(6, 1), to: sq(6, 3))))   // g2-g4
    #expect(e.apply(ChessMove(from: sq(3, 7), to: sq(7, 3))))   // Qd8-h4#

    #expect(e.isInCheck(.white))
    #expect(e.isCheckmate(for: .white))
}

// MARK: - Unit 7: SwiftData persistence round-trip for ChatMessage.

@Test func swiftDataPersistsAndTombstones() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: ChatMessage.self, DeliveryReceipt.self, ChessGameState.self,
        configurations: config
    )
    let context = ModelContext(container)

    let id = UUID()
    let msg = ChatMessage(id: id, convoID: UUID(), senderID: UUID(), kind: .text, text: "persist me")
    context.insert(msg)
    try context.save()

    let fetched = try context.fetch(
        FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == id })
    ).first
    #expect(fetched?.text == "persist me")

    fetched?.tombstone()
    try context.save()

    // Row remains after tombstoning.
    let stillThere = try context.fetch(
        FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == id })
    ).first
    #expect(stillThere != nil)
    #expect(stillThere?.isDeleted == true)
    #expect(stillThere?.text == nil)
}
