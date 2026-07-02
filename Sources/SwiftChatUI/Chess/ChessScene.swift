import SpriteKit
import SwiftChatKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Procedurally-drawn 64-square chessboard + Unicode-glyph pieces (no assets).
/// Supports native drag to move; validated moves are reported via `onMove`.
public final class ChessScene: SKScene {
    public let engine: ChessEngine
    public var localColor: PieceColor
    /// Called when the local player completes a legal move (for encryption/sync).
    public var onMove: ((ChessMove) -> Void)?
    /// Called when the game reaches checkmate.
    public var onCheckmate: ((PieceColor) -> Void)?

    private var squareSize: CGFloat = 40
    private var pieceNodes: [Square: SKLabelNode] = [:]
    private var dragging: SKLabelNode?
    private var dragOrigin: Square?

    public init(engine: ChessEngine, localColor: PieceColor, size: CGSize) {
        self.engine = engine
        self.localColor = localColor
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    public override func didMove(to view: SKView) {
        squareSize = min(size.width, size.height) / 8
        drawBoard()
        rebuildPieces()
    }

    private func drawBoard() {
        for r in 0..<8 {
            for f in 0..<8 {
                let node = SKShapeNode(rectOf: CGSize(width: squareSize, height: squareSize))
                node.position = center(of: Square(file: f, rank: r))
                let light = (f + r) % 2 == 0
                node.fillColor = light
                    ? SKColor(white: 0.93, alpha: 1)
                    : SKColor(red: 0.46, green: 0.58, blue: 0.34, alpha: 1)
                node.strokeColor = .clear
                node.zPosition = 0
                addChild(node)
            }
        }
    }

    private func rebuildPieces() {
        pieceNodes.values.forEach { $0.removeFromParent() }
        pieceNodes.removeAll()
        for r in 0..<8 {
            for f in 0..<8 {
                let sq = Square(file: f, rank: r)
                guard let piece = engine.piece(at: sq) else { continue }
                let label = SKLabelNode(text: piece.type.glyph(piece.color))
                label.fontSize = squareSize * 0.72
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = .center
                label.position = center(of: sq)
                label.zPosition = 1
                addChild(label)
                pieceNodes[sq] = label
            }
        }
    }

    private func center(of sq: Square) -> CGPoint {
        // Flip the board so the local player's pieces are at the bottom.
        let f = localColor == .white ? sq.file : 7 - sq.file
        let r = localColor == .white ? sq.rank : 7 - sq.rank
        let origin = CGPoint(
            x: (size.width - squareSize * 8) / 2,
            y: (size.height - squareSize * 8) / 2
        )
        return CGPoint(
            x: origin.x + (CGFloat(f) + 0.5) * squareSize,
            y: origin.y + (CGFloat(r) + 0.5) * squareSize
        )
    }

    private func square(at point: CGPoint) -> Square? {
        let origin = CGPoint(
            x: (size.width - squareSize * 8) / 2,
            y: (size.height - squareSize * 8) / 2
        )
        let f = Int((point.x - origin.x) / squareSize)
        let r = Int((point.y - origin.y) / squareSize)
        guard (0..<8).contains(f), (0..<8).contains(r) else { return nil }
        let file = localColor == .white ? f : 7 - f
        let rank = localColor == .white ? r : 7 - r
        return Square(file: file, rank: rank)
    }

    /// Apply a remote (already-validated on the sender) move and refresh the board.
    public func applyRemoteMove(_ move: ChessMove) {
        engine.apply(move, validateTurn: false)
        rebuildPieces()
        checkForMate()
    }

    private func checkForMate() {
        let side = engine.turn
        if engine.isCheckmate(for: side) {
            onCheckmate?(side)
        }
    }

    // MARK: - Drag handling (shared touch/mouse pipeline)

    func beginDrag(at point: CGPoint) {
        guard let sq = square(at: point), let node = pieceNodes[sq] else { return }
        guard let piece = engine.piece(at: sq), piece.color == localColor, engine.turn == localColor else { return }
        dragging = node
        dragOrigin = sq
        node.zPosition = 5
    }

    func updateDrag(to point: CGPoint) {
        dragging?.position = point
    }

    func endDrag(at point: CGPoint) {
        defer { dragging = nil; dragOrigin = nil }
        guard let node = dragging, let from = dragOrigin else { return }
        node.zPosition = 1
        guard let to = square(at: point) else { rebuildPieces(); return }
        let move = ChessMove(from: from, to: to)
        if engine.apply(move) {
            onMove?(move)
            rebuildPieces()
            checkForMate()
        } else {
            rebuildPieces()  // snap back
        }
    }

    #if os(iOS)
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { beginDrag(at: t.location(in: self)) }
    }
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { updateDrag(to: t.location(in: self)) }
    }
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { endDrag(at: t.location(in: self)) }
    }
    #elseif os(macOS)
    public override func mouseDown(with event: NSEvent) { beginDrag(at: event.location(in: self)) }
    public override func mouseDragged(with event: NSEvent) { updateDrag(to: event.location(in: self)) }
    public override func mouseUp(with event: NSEvent) { endDrag(at: event.location(in: self)) }
    #endif
}
