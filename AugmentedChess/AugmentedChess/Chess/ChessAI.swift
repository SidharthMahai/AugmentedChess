import Foundation

struct ChessAI {
    private static let searchBound = 1_000_000

    static func bestMove(for color: PieceColor, in board: ChessBoard, difficulty: Difficulty) -> ChessMove? {
        let legal = ChessRules.legalMoves(for: color, in: board)
        guard !legal.isEmpty else { return nil }

        if difficulty == .easy {
            return legal.max(by: { moveScore($0, on: board, for: color) < moveScore($1, on: board, for: color) })
        }

        let depth = difficulty.searchDepth
        var best: ChessMove?
        var bestScore = -searchBound
        var alpha = -searchBound
        let beta = searchBound

        for move in legal.shuffled() {
            let next = board.applying(move)
            let score = -negamax(board: next, depth: depth - 1, alpha: -beta, beta: -alpha, perspective: color.opposite)
            if score > bestScore {
                bestScore = score
                best = move
            }
            alpha = max(alpha, score)
        }

        return best
    }

    private static func negamax(board: ChessBoard, depth: Int, alpha: Int, beta: Int, perspective: PieceColor) -> Int {
        var alpha = alpha

        if depth == 0 {
            return evaluate(board: board, for: perspective)
        }

        let legal = ChessRules.legalMoves(for: perspective, in: board)
        if legal.isEmpty {
            if ChessRules.isKingInCheck(color: perspective, in: board) {
                return -searchBound + 1
            }
            return 0
        }

        var best = -searchBound
        for move in legal {
            let next = board.applying(move)
            let score = -negamax(board: next, depth: depth - 1, alpha: -beta, beta: -alpha, perspective: perspective.opposite)
            best = max(best, score)
            alpha = max(alpha, score)
            if alpha >= beta { break }
        }

        return best
    }

    private static func moveScore(_ move: ChessMove, on board: ChessBoard, for color: PieceColor) -> Int {
        let targetValue = board.piece(at: move.to).map(pieceValue) ?? 0
        let mover = board.piece(at: move.from).map(pieceValue) ?? 0
        return targetValue * 10 - mover
    }

    static func evaluate(board: ChessBoard, for color: PieceColor) -> Int {
        var score = 0

        for index in 0..<64 {
            guard let piece = board.piece(at: index) else { continue }
            let material = pieceValue(piece)
            let positional = pieceSquareBonus(piece: piece, index: index)
            let signed = material + positional
            score += piece.color == color ? signed : -signed
        }

        if ChessRules.isCheckmate(for: color.opposite, in: board) {
            score += 50_000
        }
        if ChessRules.isCheckmate(for: color, in: board) {
            score -= 50_000
        }

        return score
    }

    private static func pieceValue(_ piece: Piece) -> Int {
        switch piece.type {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 20_000
        }
    }

    private static func pieceSquareBonus(piece: Piece, index: Int) -> Int {
        let rank = piece.color == .white ? ChessSquare.rank(index) : (7 - ChessSquare.rank(index))
        let file = ChessSquare.file(index)
        let centerDistance = abs(3 - file) + abs(3 - rank)

        switch piece.type {
        case .pawn:
            return rank * 6 - centerDistance
        case .knight:
            return 20 - (centerDistance * 4)
        case .bishop:
            return 12 - (centerDistance * 2)
        case .rook:
            return rank * 2
        case .queen:
            return 8 - centerDistance
        case .king:
            return -(centerDistance * 2)
        }
    }
}
