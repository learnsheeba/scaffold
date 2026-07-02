# SwiftChat — System Design Document

A local-network, end-to-end encrypted chat system built entirely in Swift & SwiftUI.
Three targets: **iOS app**, **macOS app**, and a **Swift backend server**. A shared
Swift package holds all cross-platform logic (crypto, wire protocol, chess engine,
AI summarizer, SwiftData models).

---

## 1. Goals & Non-Goals

### Goals
- Real-time messaging over **WebSockets** on the **local network only** (no internet routing for transport).
- **End-to-end encryption (E2EE)** using Apple **CryptoKit**. The server routes only opaque ciphertext.
- Native, Apple-Messages-style UI with custom `Path`-drawn bubble tails.
- Local persistence with **SwiftData**; photos cached on disk via **FileManager** (only the relative path is stored in the model).
- Rich features: photo sharing, YouTube link previews (`LinkPresentation`), edit/delete with tombstones, inline multiplayer **SpriteKit chess**, typing indicators, 5 animated backgrounds, and on-device **FoundationModels** summarization.

### Non-Goals
- No cloud accounts, no push notifications, no internet message routing.
- No third-party API keys. (Link metadata is fetched by `LPMetadataProvider` directly, which is permitted.)
- No CocoaPods. Dependencies via **Swift Package Manager** only.

---

## 2. High-Level Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│                          Local Wi-Fi / LAN                            │
│                                                                       │
│   ┌────────────┐        WebSocket (ws://)        ┌────────────┐        │
│   │  iOS App   │◀──────────────────────────────▶│  Backend    │        │
│   │ (SwiftUI)  │        opaque ciphertext         │  (Vapor)   │        │
│   └────────────┘                                  │            │        │
│         ▲                                         │  routes    │        │
│         │ shared symmetric key (X25519 ECDH)      │ envelopes  │        │
│         ▼                                         │  only      │        │
│   ┌────────────┐        WebSocket (ws://)         │            │        │
│   │ macOS App  │◀──────────────────────────────▶│            │        │
│   │ (SwiftUI)  │        opaque ciphertext         └────────────┘        │
│   └────────────┘                                                       │
└───────────────────────────────────────────────────────────────────────┘

        Shared Swift Package "SwiftChatKit"
        ├─ Crypto          (CryptoKit: X25519 + HKDF + AES-GCM/ChaChaPoly)
        ├─ Protocol        (Envelope, Frame, MessagePayload, wire codec)
        ├─ Models          (SwiftData: ChatMessage, DeliveryReceipt, ChessGame)
        ├─ Chess           (pure-Swift rules engine, checkmate detection)
        ├─ Summarizer      (FoundationModels wrapper + fallback)
        └─ MediaStore      (FileManager image cache)
```

### Package layout (SwiftPM)

```
SwiftChat/
├─ Package.swift
├─ SYSTEMDESIGN.md
├─ Sources/
│  ├─ SwiftChatKit/          # shared, cross-platform (no UIKit/AppKit)
│  │  ├─ Crypto/
│  │  ├─ Protocol/
│  │  ├─ Models/
│  │  ├─ Chess/
│  │  ├─ Summarizer/
│  │  └─ Media/
│  ├─ SwiftChatServer/       # executable target (Vapor)
│  ├─ SwiftChatUI/           # shared SwiftUI views (bubbles, backgrounds, chess view)
│  ├─ SwiftChatIOS/          # iOS @main App
│  └─ SwiftChatMac/          # macOS @main App
└─ Tests/
   └─ SwiftChatKitTests/     # unit tests + UI/E2E test
```

> Note on Xcode: because iOS/macOS UI targets require app bundles, the two client
> targets are shipped both as SwiftPM library sources *and* wired into an
> `SwiftChat.xcodeproj` (documented in README). The `App` entry points use
> `#if os(iOS)` / `#if os(macOS)` guards so ~95% of view code is shared in
> `SwiftChatUI`.

---

## 3. Networking & Transport

- **Transport:** `URLSessionWebSocketTask` on the clients; **Vapor**'s `webSocket`
  route on the server. Plain `ws://` (no TLS) because traffic never leaves the LAN
  and confidentiality is provided at the application layer by E2EE.
- **Discovery:** The server advertises via **Bonjour** (`NetService/NWListener`,
  `_swiftchat._tcp`). Clients browse for the service so no IP typing is required;
  a manual host field is provided as a fallback.
- **Server role:** A dumb relay. It maintains `clientID -> WebSocket` and forwards
  every inbound `Envelope` to the other participants. It **cannot decrypt** payloads.

### Wire format

Every frame on the wire is a length-agnostic, `Codable` **`Envelope`** encoded as
**binary** (`JSONEncoder` → `Data`, sent as `.binary`). Only routing metadata is
plaintext; the actual content lives in `ciphertext`.

```swift
struct Envelope: Codable {
    let type: FrameType        // .handshake, .message, .edit, .delete,
                               // .typing, .receipt, .chessMove, .gameInvite
    let senderID: UUID
    let convoID: UUID
    var handshake: HandshakePayload?   // plaintext public key (safe to expose)
    var ciphertext: Data?              // AES-GCM/ChaChaPoly sealed box (opaque)
    let nonceHint: UInt64?             // monotonic, replay defense
}
```

- `handshake` frames carry the **X25519 public key** in the clear — that is safe
  and required for key agreement.
- All other frames carry only `ciphertext`. The server sees random-looking bytes.

---

## 4. Security & E2EE Design

### Key exchange
1. On connect, each client generates an ephemeral **Curve25519 (X25519)** key pair
   (`Curve25519.KeyAgreement.PrivateKey`).
2. Clients exchange **public keys** via `.handshake` envelopes (relayed by server).
3. Each side computes the **shared secret** via ECDH, then derives a
   **symmetric key** with **HKDF-SHA256** and a fixed protocol salt/info:
   ```
   sharedSecret = myPriv.sharedSecretFromKeyAgreement(with: theirPub)
   symKey = sharedSecret.hkdfDerivedSymmetricKey(
       using: SHA256.self, salt: "swiftchat-salt", sharedInfo: "swiftchat-v1", outputByteCount: 32)
   ```
4. The resulting `SymmetricKey` is identical on both peers and never transmitted.

### Payload encryption
- Each `MessagePayload` (text, edit, delete, chess move, typing, receipt) is
  `Codable`-encoded then sealed:
  ```
  let sealed = try AES.GCM.seal(plaintextData, using: symKey)
  envelope.ciphertext = sealed.combined   // nonce||ciphertext||tag
  ```
- **ChaChaPoly** is offered as an alternative cipher (config flag) for devices
  favoring it; both are AEAD so integrity + auth are guaranteed.
- **Replay protection:** monotonic `nonceHint` per sender; receiver rejects
  non-increasing values.
- **Server guarantee:** The server code path only ever touches `Envelope.type`,
  `senderID`, `convoID`, and forwards `ciphertext` verbatim. There is no code path
  that decrypts — enforced by the server target not linking the `Crypto` module.

---

## 5. Persistence (SwiftData)

Both clients embed the same `@Model` schema from `SwiftChatKit`.

```swift
@Model final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var convoID: UUID
    var senderID: UUID
    var kind: MessageKind        // .text, .photo, .youtube, .gameInvite, .chess
    var text: String?            // latest (edited) text
    var mediaRelativePath: String?   // relative path into app-support media dir
    var linkURL: String?
    var createdAt: Date
    var editedAt: Date?          // non-nil => render "(Edited)"
    var isDeleted: Bool          // tombstone flag
    var deliveryState: DeliveryState  // .sending, .sent, .delivered, .read
    @Relationship var receipts: [DeliveryReceipt]
}

@Model final class DeliveryReceipt {
    var id: UUID
    var messageID: UUID
    var state: DeliveryState
    var at: Date
}

@Model final class ChessGameState {
    @Attribute(.unique) var id: UUID
    var messageID: UUID
    var fen: String              // board position
    var turn: String             // "w" / "b"
    var isCheckmate: Bool
    var updatedAt: Date
}
```

### Media caching rule (hard requirement)
- Raw image bytes are **never** stored in SwiftData.
- On receiving/sending a photo, `MediaStore` writes bytes to
  `Application Support/SwiftChat/Media/<uuid>.jpg` via **FileManager** and returns
  the **relative** path, which is the only thing persisted in
  `ChatMessage.mediaRelativePath`.
- The UI resolves relative→absolute at render time and **loads asynchronously**
  (`Task`/`AsyncImage`-style `DiskImageLoader`) so the main thread never blocks.

### Tombstones (edit/delete lifecycle)
- **Edit:** update `text`, set `editedAt = now`, persist; UI appends `(Edited)`.
- **Delete:** DO NOT delete the row. Instead:
  - `text = nil`, `mediaRelativePath = nil` (and the on-disk file is removed),
    `linkURL = nil`, `isDeleted = true`.
  - Persist the scrubbed **tombstone**.
  - UI renders a distinct "This message was deleted" bubble.
- Both events are transported as `.edit` / `.delete` envelopes (still encrypted).

---

## 6. UI Design

- **Bubble geometry:** `MessageBubbleShape: Shape` draws the rounded rectangle and
  the **curved tail** using `Path` with `addQuadCurve`/`addCurve`, mirrored for
  inbound vs. outbound.
- **Color/layout:** outbound = blue gradient trailing-aligned; inbound = gray
  leading-aligned — the Apple Messages look.
- **Special bubbles:** tombstone (italic, muted, dashed), edited label, typing
  indicator, photo, YouTube preview card, chess board card, game-invite card.
- **Shared views** live in `SwiftChatUI` and are used verbatim by both apps;
  platform differences (window chrome, photo picker) are `#if os(...)`-guarded.

### Backgrounds (5, toggleable)
1. **Aurora** — `TimelineView` + `Canvas` flowing gradient blobs.
2. **Bokeh** — `Canvas` drifting translucent circles.
3. **Starfield** — `TimelineView` parallax dots.
4. **Waves** — `Canvas` layered sine waves.
5. **Pulse** — `PhaseAnimator` breathing radial gradient.
A `BackgroundStyle` enum + `@AppStorage` selection drives a `ChatBackground` view.

### Typing indicator
- Client sends transient `.typing` envelopes (encrypted, not persisted).
- A `TypingIndicatorView` shows **3 dots** with a staggered custom
  `.easeInOut(...).repeatForever()` bounce.
- A 3-second `Task`-based timeout clears the indicator if no further typing frame
  arrives.

---

## 7. Media & Links

- **Photos:** `PhotosPicker` (PhotosUI) on both platforms → bytes → `MediaStore`
  (FileManager) → `mediaRelativePath` persisted → sent encrypted as base64 inside
  the payload (still E2EE; server never sees the image).
- **YouTube previews:** `LPMetadataProvider().startFetchingMetadata(for:)` fetches
  title + thumbnail (`imageProvider`) asynchronously. This is the one permitted
  public-internet call and needs **no API key**. Rendered inline as an
  `LPLinkView`-style card built in SwiftUI.

---

## 8. Inline Multiplayer Chess (SpriteKit)

- **Rendering:** `ChessScene: SKScene` embedded via `SpriteView` inside a chat
  bubble. The 8×8 board and all pieces are drawn **procedurally** with
  `SKShapeNode`/`SKLabelNode` (Unicode glyphs) — **no asset files**.
- **Interaction:** native drag via `SKNode` touch/`NSResponder` handling; legal
  moves validated by the pure-Swift `ChessEngine`.
- **Rules:** `ChessEngine` enforces per-piece movement, turn validation, capture,
  and **checkmate detection** (king-in-check with no legal escape).
- **Sync:** each accepted move is serialized (`ChessMove{from,to,promotion}`),
  encrypted, and sent as a `.chessMove` envelope; the peer applies it and updates
  `ChessGameState`. Game invites use `.gameInvite`.

---

## 9. Cross-Platform AI Summarization ("Catch me up")

- Shared `Summarizer` in `SwiftChatKit` wraps **FoundationModels**:
  ```
  let session = LanguageModelSession()
  let answer = try await session.respond(to: prompt)
  ```
- Input: the **most recent 20** `ChatMessage`s from SwiftData, **excluding
  tombstones**, using each message's **latest edited text**.
- **Fallback:** guard on `SystemLanguageModel.default.availability`. If the device
  lacks Apple Intelligence hardware/OS support, show a graceful
  "Summaries aren't available on this device" state (and an optional naive
  extractive fallback). A "Catch me up" toolbar button triggers it on **both**
  iOS and macOS.

---

## 10. Message Lifecycle Sequence

```
Send:   compose → encrypt → .message envelope → server relay → peer decrypts →
        persist ChatMessage → render → peer sends .receipt(delivered) → sender
        updates DeliveryReceipt/deliveryState.

Edit:   editedAt=now, text updated → .edit envelope → peer updates + "(Edited)".

Delete: scrub payload, isDeleted=true, remove disk media → .delete envelope →
        peer tombstones → both render "This message was deleted".
```

---

## 11. Testing Strategy

- **Unit (≥4):**
  1. `ChatMessage` tombstone scrub keeps the row but clears payload + sets flag.
  2. `MediaStore` writes bytes to disk and persists only a relative path (no bytes in model).
  3. `Envelope`/`MessagePayload` round-trips through the binary wire codec.
  4. Crypto round-trip: two peers derive the **same** key and AES-GCM
     encrypt→decrypt yields the original plaintext.
  5. (Bonus) `ChessEngine` detects a fool's-mate checkmate.
- **UI/E2E (1):** launch the app, type a message, tap send, assert the bubble and
  its `(Edited)`/tombstone transitions appear (`XCUITest`).

---

## 12. Key Risks & Decisions

| Decision | Rationale |
|---|---|
| Vapor for server | Mature Swift WebSocket + Bonjour-friendly; SPM-installable. |
| `ws://` not `wss://` | LAN-only; confidentiality already at app layer via E2EE. |
| X25519 + HKDF + AES-GCM | Standard, CryptoKit-native, AEAD integrity + forward-ish secrecy. |
| Relative media paths | App-container paths change across launches; relative is stable. |
| Shared `SwiftChatUI` | Maximize code reuse; platform specifics behind `#if os`. |
| FoundationModels + availability guard | Required on-device AI with graceful degradation. |
