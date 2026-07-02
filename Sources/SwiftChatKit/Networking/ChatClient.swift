import Foundation
import Combine

/// Client-side WebSocket connection to the local relay server.
/// Handles the E2EE handshake, sealing outbound payloads, and opening inbound ones.
@MainActor
public final class ChatClient: ObservableObject {
    public struct Incoming {
        public let envelope: Envelope
        public let payload: MessagePayload?   // nil for handshake frames
    }

    @Published public private(set) var isConnected = false
    @Published public private(set) var isSecure = false

    public let selfID: UUID
    public let convoID: UUID

    private let crypto: CryptoEngine
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var outboundNonce: UInt64 = 0
    private var lastInboundNonce: [UUID: UInt64] = [:]

    /// Emits decrypted inbound frames for the UI/store to consume.
    public let incoming = PassthroughSubject<Incoming, Never>()

    public init(selfID: UUID = UUID(), convoID: UUID, suite: CipherSuite = .aesGCM) {
        self.selfID = selfID
        self.convoID = convoID
        self.crypto = CryptoEngine(suite: suite)
    }

    public func connect(to url: URL) {
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        isConnected = true
        receiveLoop()
        sendHandshake()
    }

    public func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        isSecure = false
    }

    // MARK: - Handshake

    private func sendHandshake() {
        let env = Envelope(
            type: .handshake,
            senderID: selfID,
            convoID: convoID,
            handshake: HandshakePayload(
                publicKeyData: crypto.publicKeyData,
                cipherSuite: crypto.cipherSuite
            )
        )
        rawSend(env)
    }

    // MARK: - Sending

    /// Seal a payload and send it as the given frame type.
    public func send(_ payload: MessagePayload, as type: FrameType) {
        guard crypto.isEstablished else { return }
        do {
            let sealed = try crypto.sealPayload(payload)
            outboundNonce += 1
            let env = Envelope(
                type: type,
                senderID: selfID,
                convoID: convoID,
                ciphertext: sealed,
                nonceHint: outboundNonce
            )
            rawSend(env)
        } catch {
            // Sealing failed; drop silently (surfaced via delivery state in real app).
        }
    }

    public func sendTyping() {
        send(MessagePayload(kind: .typing), as: .typing)
    }

    private func rawSend(_ env: Envelope) {
        guard let data = try? WireCodec.encode(env) else { return }
        task?.send(.data(data)) { _ in }
    }

    // MARK: - Receiving

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor in self.handle(message) }
                Task { @MainActor in self.receiveLoop() }
            case .failure:
                Task { @MainActor in
                    self.isConnected = false
                    self.isSecure = false
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }

        guard let env = try? WireCodec.decode(data), env.senderID != selfID else { return }

        if env.type == .handshake, let hs = env.handshake {
            try? crypto.establishSharedKey(withPeerPublicKey: hs.publicKeyData)
            isSecure = crypto.isEstablished
            incoming.send(Incoming(envelope: env, payload: nil))
            return
        }

        // Replay defense: reject non-increasing nonces.
        if let n = env.nonceHint {
            let last = lastInboundNonce[env.senderID] ?? 0
            guard n > last else { return }
            lastInboundNonce[env.senderID] = n
        }

        guard let cipher = env.ciphertext,
              let payload = try? crypto.openPayload(cipher) else { return }
        incoming.send(Incoming(envelope: env, payload: payload))
    }
}
