import SwiftUI
import SwiftData
import PhotosUI
import SwiftChatKit

/// The main shared chat screen used by both the iOS and macOS apps.
public struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: ChatViewModel

    @Query(sort: \ChatMessage.createdAt, order: .forward)
    private var messages: [ChatMessage]

    @State private var photoItem: PhotosPickerItem?
    @State private var editing: ChatMessage?
    @State private var editText = ""

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            ChatBackground(style: viewModel.background)

            VStack(spacing: 0) {
                header
                messageList
                inputBar
            }
        }
        .onAppear { viewModel.attach(context: modelContext) }
        .sheet(item: $editing) { msg in editSheet(msg) }
    }

    private var header: some View {
        HStack {
            Button {
                viewModel.catchMeUp(messages: messages)
            } label: {
                Label("Catch me up", systemImage: "sparkles")
            }
            .disabled(viewModel.isSummarizing)

            Spacer()

            Picker("Background", selection: $viewModel.background) {
                ForEach(BackgroundStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .overlay(alignment: .bottom) {
            if let summary = viewModel.summary {
                Text(summary)
                    .font(.footnote)
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .transition(.opacity)
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { msg in
                        MessageBubbleView(
                            message: msg,
                            isOutbound: msg.senderID == viewModel.client.selfID
                        )
                        .id(msg.id)
                        .contextMenu {
                            if msg.senderID == viewModel.client.selfID && !msg.isDeleted {
                                Button("Edit") { editText = msg.text ?? ""; editing = msg }
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteMessage(msg)
                                }
                            }
                        }
                    }
                    if viewModel.typing.isPeerTyping {
                        HStack { TypingIndicatorView(); Spacer() }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo")
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        viewModel.sendPhoto(data)
                    }
                }
            }

            TextField("Message", text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.draft) { _, _ in viewModel.draftChanged() }
                .onSubmit { viewModel.sendText() }

            Button {
                viewModel.sendText()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(.thinMaterial)
    }

    private func editSheet(_ msg: ChatMessage) -> some View {
        VStack(spacing: 16) {
            Text("Edit message").font(.headline)
            TextField("Message", text: $editText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { editing = nil }
                Spacer()
                Button("Save") {
                    viewModel.editMessage(msg, newText: editText)
                    editing = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}
