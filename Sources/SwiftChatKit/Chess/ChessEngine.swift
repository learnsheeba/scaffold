import Foundation

public enum PieceColor: String, Codable, Sendable {
    case white = "w"
    case black = "b"

    public var opposite: PieceColor { self == .white ? .black : .white }
}

public enum PieceType: String, Codable, Sendable {
    case pawn, knight, bishop, rook, queen, king

    /// Unicode glyph for procedural rendering (no image assets).
    public func glyph(_ color: PieceColor) -> String {
        switch (color, self) {
        case (.white, .king):   return "\u{2654}"
        case (.white, .queen):  return "\u{2655}"
        case (.white, .rook):   return "\u{2656}"
        case (.white, .bishop): return "\u{2657}"
        case (.white, .knight): return "\u{2658}"
        case (.white, .pawn):   return "\u{2659}"
        case (.black, .king):   return "\u{265A}"
        case (.black, .queen):  return "\u{265B}"
        case (.black, .rook):   return "\u{265C}"
        case (.black, .bishop): return "\u{265D}"
        case (.black, .knight): return "\u{265E}"
        case (.black, .pawn):   return "\u{265F}"
        }
    }
}

public struct Piece: Codable, Sendable, Equatable {
    public var type: PieceType
    public var color: PieceColor
    public init(_ type: PieceType, _ color: PieceColor) {
        self.type = type
        self.color = color
    }
}

/// 0...7 file/rank coordinate.
public struct Square: Codable, Sendable, Equatable, Hashable {
    public var file: Int  // 0 = a
    public var rank: Int  // 0 = rank 1
    public init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }
    public var isOnBoard: Bool { (0..<8).contains(file) && (0..<8).contains(rank) }

    /// Algebraic like "e4".
    public var algebraic: String {
        let files = "abcdefgh"
        return "\(files[files.index(files.startIndex, offsetBy: file)])\(rank + 1)"
    }
}

public struct ChessMove: Codable, Sendable, Equatable {
    public var from: Square
    public var to: Square
    public var promotion: PieceType?
    public init(from: Square, to: Square, promotion: PieceType? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }
}

/// Pure-Swift chess rules engine: movement, turn validation, check & checkmate.
/// Intentionally standard-but-simplified (no en passant / castling) per spec's
/// "basic chess rules" requirement.
public final class ChessEngine {
    public private(set) var board: [[Piece?]]  // board[rank][file]
    public private(set) var turn: PieceColor

    public init() {
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        turn = .white
        setupStandard()
    }

    public func setupStandard() {
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        let back: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            board[0][file] = Piece(back[file], .white)
            board[1][file] = Piece(.pawn, .white)
            board[6][file] = Piece(.pawn, .black)
            board[7][file] = Piece(back[file], .black)
        }
        turn = .white
    }

    public func piece(at sq: Square) -> Piece? {
        guard sq.isOnBoard else { return nil }
        return board[sq.rank][sq.file]
    }

    private func set(_ piece: Piece?, at sq: Square) {
        board[sq.rank][sq.file] = piece
    }

    /// Validate and apply a move. Returns true on success.
    @discardableResult
    public func apply(_ move: ChessMove, validateTurn: Bool = true) -> Bool {
        guard isLegal(move, forTurn: validateTurn) else { return false }
        performRaw(move)
        turn = turn.opposite
        return true
    }

    /// Raw mutation without validation (used for hypothetical check testing).
    private func performRaw(_ move: ChessMove) {
        guard var moving = piece(at: move.from) else { return }
        if moving.type == .pawn, move.to.rank == (moving.color == .white ? 7 : 0) {
            moving = Piece(move.promotion ?? .queen, moving.color)
        }
        set(nil, at: move.from)
        set(moving, at: move.to)
    }

    public func isLegal(_ move: ChessMove, forTurn: Bool = true) -> Bool {
        guard move.from.isOnBoard, move.to.isOnBoard, move.from != move.to else { return false }
        guard let moving = piece(at: move.from) else { return false }
        if forTurn && moving.color != turn { return false }
        if let target = piece(at: move.to), target.color == moving.color { return false }
        guard pseudoLegal(move, piece: moving) else { return false }
        // Must not leave own king in check.
        return !leavesKingInCheck(move, color: moving.color)
    }

    private func pseudoLegal(_ move: ChessMove, piece: Piece) -> Bool {
        let df = move.to.file - move.from.file
        let dr = move.to.rank - move.from.rank
        switch piece.type {
        case .pawn:
            let dir = piece.color == .white ? 1 : -1
            let startRank = piece.color == .white ? 1 : 6
            // forward
            if df == 0 && dr == dir && self.piece(at: move.to) == nil { return true }
            if df == 0 && dr == 2 * dir && move.from.rank == startRank
                && self.piece(at: move.to) == nil
                && self.piece(at: Square(file: move.from.file, rank: move.from.rank + dir)) == nil {
                return true
            }
            // capture
            if abs(df) == 1 && dr == dir, let t = self.piece(at: move.to), t.color != piece.color {
                return true
            }
            return false
        case .knight:
            return (abs(df) == 1 && abs(dr) == 2) || (abs(df) == 2 && abs(dr) == 1)
        case .bishop:
            return abs(df) == abs(dr) && df != 0 && pathClear(move)
        case .rook:
            return (df == 0 || dr == 0) && pathClear(move)
        case .queen:
            return ((df == 0 || dr == 0) || abs(df) == abs(dr)) && pathClear(move)
        case .king:
            return abs(df) <= 1 && abs(dr) <= 1
        }
    }

    private func pathClear(_ move: ChessMove) -> Bool {
        let df = move.to.file - move.from.file
        let dr = move.to.rank - move.from.rank
        let stepF = df == 0 ? 0 : df / abs(df)
        let stepR = dr == 0 ? 0 : dr / abs(dr)
        var f = move.from.file + stepF
        var r = move.from.rank + stepR
        while f != move.to.file || r != move.to.rank {
            if board[r][f] != nil { return false }
            f += stepF
            r += stepR
        }
        return true
    }

    private func kingSquare(_ color: PieceColor) -> Square? {
        for r in 0..<8 {
            for f in 0..<8 {
                if let p = board[r][f], p.type == .king, p.color == color {
                    return Square(file: f, rank: r)
                }
            }
        }
        return nil
    }

    public func isInCheck(_ color: PieceColor) -> Bool {
        guard let king = kingSquare(color) else { return false }
        for r in 0..<8 {
            for f in 0..<8 {
                guard let p = board[r][f], p.color == color.opposite else { continue }
                let m = ChessMove(from: Square(file: f, rank: r), to: king)
                if pseudoLegal(m, piece: p) { return true }
            }
        }
        return false
    }

    private func leavesKingInCheck(_ move: ChessMove, color: PieceColor) -> Bool {
        let snapshot = board
        performRaw(move)
        let inCheck = isInCheck(color)
        board = snapshot
        return inCheck
    }

    public func allLegalMoves(for color: PieceColor) -> [ChessMove] {
        var moves: [ChessMove] = []
        for r in 0..<8 {
            for f in 0..<8 {
                guard let p = board[r][f], p.color == color else { continue }
                let from = Square(file: f, rank: r)
                for tr in 0..<8 {
                    for tf in 0..<8 {
                        let m = ChessMove(from: from, to: Square(file: tf, rank: tr))
                        if isLegal(m, forTurn: false) && p.color == color {
                            moves.append(m)
                        }
                    }
                }
            }
        }
        return moves
    }

    /// Checkmate: side to move is in check and has no legal escape.
    public func isCheckmate(for color: PieceColor) -> Bool {
        guard isInCheck(color) else { return false }
        return allLegalMoves(for: color).isEmpty
    }

    // MARK: - Simple FEN-ish serialization for sync/persistence

    public func serializePosition() -> String {
        var rows: [String] = []
        for r in (0..<8).reversed() {
            var row = ""
            var empties = 0
            for f in 0..<8 {
                if let p = board[r][f] {
                    if empties > 0 { row += "\(empties)"; empties = 0 }
                    row += fenChar(p)
                } else {
                    empties += 1
                }
            }
            if empties > 0 { row += "\(empties)" }
            rows.append(row)
        }
        return rows.joined(separator: "/") + " " + turn.rawValue
    }

    private func fenChar(_ p: Piece) -> String {
        let c: String
        switch p.type {
        case .pawn: c = "p"
        case .knight: c = "n"
        case .bishop: c = "b"
        case .rook: c = "r"
        case .queen: c = "q"
        case .king: c = "k"
        }
        return p.color == .white ? c.uppercased() : c
    }
}
