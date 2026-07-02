import SwiftUI
import SpriteKit
import SwiftChatKit

/// Embeds the SpriteKit chess scene inline in the chat timeline.
public struct ChessBoardView: View {
    @StateObject private var model: ChessBoardModel

    public init(localColor: PieceColor, onMove: @escaping (ChessMove) -> Void) {
        _model = StateObject(wrappedValue: ChessBoardModel(localColor: localColor, onMove: onMove))
    }

    public var body: some View {
        VStack(spacing: 6) {
            SpriteView(scene: model.scene, options: [.allowsTransparency])
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(model.isMate ? .red : .secondary)
        }
        .padding(6)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Feed a peer's synced move into the board.
    public func applyRemoteMove(_ move: ChessMove) {
        model.applyRemote(move)
    }
}

@MainActor
final class ChessBoardModel: ObservableObject {
    let engine = ChessEngine()
    let scene: ChessScene
    @Published var statusText = "White to move"
    @Published var isMate = false

    init(localColor: PieceColor, onMove: @escaping (ChessMove) -> Void) {
        scene = ChessScene(engine: engine, localColor: localColor, size: CGSize(width: 280, height: 280))
        scene.onMove = { move in
            onMove(move)
        }
        scene.onCheckmate = { [weak self] loser in
            self?.isMate = true
            self?.statusText = "Checkmate — \(loser == .white ? "Black" : "White") wins"
        }
        refreshStatus()
    }

    func applyRemote(_ move: ChessMove) {
        scene.applyRemoteMove(move)
        refreshStatus()
    }

    private func refreshStatus() {
        guard !isMate else { return }
        statusText = engine.turn == .white ? "White to move" : "Black to move"
    }
}
