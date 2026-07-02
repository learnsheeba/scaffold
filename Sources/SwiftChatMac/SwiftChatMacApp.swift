import SwiftUI
import SwiftData
import SwiftChatKit
import SwiftChatUI

@main
struct SwiftChatMacApp: App {
    let container: ModelContainer
    @StateObject private var viewModel: ChatViewModel

    init() {
        let convoID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        do {
            container = try ModelContainer(
                for: ChatMessage.self, DeliveryReceipt.self, ChessGameState.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        _viewModel = StateObject(wrappedValue: ChatViewModel(convoID: convoID))
    }

    var body: some Scene {
        WindowGroup {
            ChatView(viewModel: viewModel)
                .frame(minWidth: 480, minHeight: 600)
                .onAppear {
                    if let url = URL(string: "ws://localhost:8080/chat?convo=\(viewModel.client.convoID)") {
                        viewModel.connect(to: url)
                    }
                }
        }
        .modelContainer(container)
    }
}
