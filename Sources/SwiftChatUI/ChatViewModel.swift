import SwiftUI
import SwiftData
import Combine
import SwiftChatKit

/// Bridges the encrypted ChatClient with the SwiftData store and the UI.
@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var draft = ""
    @Published public var background: BackgroundStyle = .aurora
    @Published public var summary: String?
    @Published public var isSummarizing = false

    public let client: ChatClient
    public let typing = TypingState()
    private let summarizer = Summarizer()
    private var context: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var typingSendThrottle: Date = .distantPast

    public init(convoID: UUID, selfID: UUID = UUID()) {
        self.client = ChatClient(selfID: selfID, convoID: convoID)
        bind()
    }

    public func attach(context: ModelContext) {
        self.context = context
    }

    public func connect(to url: URL) {
        client.connect(to: url)
    }

    private func bind() {
        client.incoming
            .receive(on: RunLoop.main)
            .sink { [weak self] incoming in
                self?.handle(incoming)
            }
            .store(in: &cancellables)
    }

    // MARK: - Inbound

    private func handle(_ incoming: ChatClient.Incoming) {
        guard let payload = incoming.payload else { return }  // handshake handled internally
        let env = incoming.envelope
        switch env.type {
        case .typing:
            typing.peerDidType()
        case .message:
            persistIncoming(payload, senderID: env.senderID)
            sendReceipt(for: payload.id, state: .delivered)
        case .edit:
            applyEdit(payload)
        case .delete:
            applyDelete(payload)
        case .receipt:
            applyReceipt(payload)
        case .chessMove, .gameInvite, .handshake:
            break  // handled by chess board layer / handshake path
        }
    }

    private func persistIncoming(_ payload: MessagePayload, senderID: UUID) {
        guard let context else { return }
        let kind: MessageKind
        switch payload.kind {
        case .photo: kind = .photo
        case .youtube: kind = .youtube
        case .gameInvite: kind = .gameInvite
        default: kind = .text
        }
        var relPath: String?
        if payload.kind == .photo, let b64 = payload.imageBase64, let data = Data(base64Encoded: b64) {
            relPath = try? MediaStore.shared.writeImage(data)
        }
        let msg = ChatMessage(
            id: payload.id,
            convoID: client.convoID,
            senderID: senderID,
            kind: kind,
            text: payload.text,
            mediaRelativePath: relPath,
            linkURL: payload.linkURL,
            createdAt: payload.createdAt,
            deliveryState: .delivered
        )
        context.insert(msg)
        try? context.save()
    }

    private func applyEdit(_ payload: MessagePayload) {
        guard let target = payload.targetMessageID, let msg = fetch(target) else { return }
        msg.applyEdit(newText: payload.text ?? "")
        try? context?.save()
    }

    private func applyDelete(_ payload: MessagePayload) {
        guard let target = payload.targetMessageID, let msg = fetch(target) else { return }
        if let path = msg.mediaRelativePath { MediaStore.shared.removeImage(relativePath: path) }
        msg.tombstone()
        try? context?.save()
    }

    private func applyReceipt(_ payload: MessagePayload) {
        guard let target = payload.targetMessageID, let msg = fetch(target),
              let state = payload.receiptState else { return }
        msg.deliveryState = state
        msg.receipts.append(DeliveryReceipt(messageID: target, state: state))
        try? context?.save()
    }

    private func fetch(_ id: UUID) -> ChatMessage? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Outbound

    public func sendText() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let context else { return }
        let payload = MessagePayload(kind: .text, text: text)
        let msg = ChatMessage(
            id: payload.id,
            convoID: client.convoID,
            senderID: client.selfID,
            kind: .text,
            text: text,
            deliveryState: .sent
        )
        context.insert(msg)
        try? context.save()
        client.send(payload, as: .message)
        draft = ""
    }

    public func sendPhoto(_ data: Data) {
        guard let context, let relPath = try? MediaStore.shared.writeImage(data) else { return }
        let payload = MessagePayload(kind: .photo, imageBase64: data.base64EncodedString())
        let msg = ChatMessage(
            id: payload.id,
            convoID: client.convoID,
            senderID: client.selfID,
            kind: .photo,
            mediaRelativePath: relPath,
            deliveryState: .sent
        )
        context.insert(msg)
        try? context.save()
        client.send(payload, as: .message)
    }

    public func editMessage(_ msg: ChatMessage, newText: String) {
        msg.applyEdit(newText: newText)
        try? context?.save()
        let payload = MessagePayload(kind: .text, text: newText, targetMessageID: msg.id)
        client.send(payload, as: .edit)
    }

    public func deleteMessage(_ msg: ChatMessage) {
        if let path = msg.mediaRelativePath { MediaStore.shared.removeImage(relativePath: path) }
        msg.tombstone()
        try? context?.save()
        let payload = MessagePayload(kind: .text, targetMessageID: msg.id)
        client.send(payload, as: .delete)
    }

    private func sendReceipt(for id: UUID, state: DeliveryState) {
        let payload = MessagePayload(kind: .receipt, receiptState: state, targetMessageID: id)
        client.send(payload, as: .receipt)
    }

    public func draftChanged() {
        let now = Date()
        if now.timeIntervalSince(typingSendThrottle) > 1 {
            typingSendThrottle = now
            client.sendTyping()
        }
    }

    // MARK: - Summarization

    public func catchMeUp(messages: [ChatMessage]) {
        isSummarizing = true
        Task {
            let result = await summarizer.summarize(messages: messages)
            self.summary = result
            self.isSummarizing = false
        }
    }
}
