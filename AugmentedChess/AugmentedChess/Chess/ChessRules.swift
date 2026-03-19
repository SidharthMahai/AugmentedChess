import Foundation

enum ChessRules {
    static func legalMoves(for color: PieceColor, in board: ChessBoard) -> [ChessMove] {
        var moves: [ChessMove] = []
        for index in 0..<64 {
            guard let piece = board.piece(at: index), piece.color == color else { continue }
            moves.append(contentsOf: pseudoLegalMoves(from: index, piece: piece, in: board))
        }

        return moves.filter { move in
            let applied = board.applying(move)
            return !isKingInCheck(color: color, in: applied)
        }
    }

    static func legalMoves(from square: Int, in board: ChessBoard) -> [ChessMove] {
        guard let piece = board.piece(at: square), piece.color == board.sideToMove else { return [] }

        return pseudoLegalMoves(from: square, piece: piece, in: board).filter { move in
            !isKingInCheck(color: piece.color, in: board.applying(move))
        }
    }

    static func isKingInCheck(color: PieceColor, in board: ChessBoard) -> Bool {
        guard let kingSquare = board.kingSquare(for: color) else { return false }
        return isSquareAttacked(kingSquare, by: color.opposite, in: board)
    }

    static func isCheckmate(for color: PieceColor, in board: ChessBoard) -> Bool {
        isKingInCheck(color: color, in: board) && legalMoves(for: color, in: board).isEmpty
    }

    static func isStalemate(for color: PieceColor, in board: ChessBoard) -> Bool {
        !isKingInCheck(color: color, in: board) && legalMoves(for: color, in: board).isEmpty
    }

    static func isSquareAttacked(_ square: Int, by attacker: PieceColor, in board: ChessBoard) -> Bool {
        for index in 0..<64 {
            guard let piece = board.piece(at: index), piece.color == attacker else { continue }
            let attacks = pseudoLegalMoves(from: index, piece: piece, in: board, attacksOnly: true)
            if attacks.contains(where: { $0.to == square }) {
                return true
            }
        }
        return false
    }

    private static func pseudoLegalMoves(from index: Int, piece: Piece, in board: ChessBoard, attacksOnly: Bool = false) -> [ChessMove] {
        switch piece.type {
        case .pawn:
            return pawnMoves(from: index, piece: piece, in: board, attacksOnly: attacksOnly)
        case .knight:
            return knightMoves(from: index, piece: piece, in: board)
        case .bishop:
            return slidingMoves(from: index, piece: piece, in: board, directions: [(1,1), (-1,1), (1,-1), (-1,-1)])
        case .rook:
            return slidingMoves(from: index, piece: piece, in: board, directions: [(1,0), (-1,0), (0,1), (0,-1)])
        case .queen:
            return slidingMoves(from: index, piece: piece, in: board, directions: [(1,1), (-1,1), (1,-1), (-1,-1), (1,0), (-1,0), (0,1), (0,-1)])
        case .king:
            return kingMoves(from: index, piece: piece, in: board)
        }
    }

    private static func pawnMoves(from index: Int, piece: Piece, in board: ChessBoard, attacksOnly: Bool) -> [ChessMove] {
        let file = ChessSquare.file(index)
        let rank = ChessSquare.rank(index)
        let direction = piece.color == .white ? 1 : -1
        let startRank = piece.color == .white ? 1 : 6
        let promotionRank = piece.color == .white ? 7 : 0

        var moves: [ChessMove] = []

        for df in [-1, 1] {
            let nf = file + df
            let nr = rank + direction
            guard ChessSquare.isValid(file: nf, rank: nr) else { continue }
            let to = ChessSquare.index(file: nf, rank: nr)
            if let target = board.piece(at: to), target.color != piece.color {
                let promotion: PieceType? = nr == promotionRank ? .queen : nil
                moves.append(ChessMove(from: index, to: to, promotion: promotion))
            }
        }

        if attacksOnly {
            return moves
        }

        let oneAheadRank = rank + direction
        if ChessSquare.isValid(file: file, rank: oneAheadRank) {
            let oneAhead = ChessSquare.index(file: file, rank: oneAheadRank)
            if board.piece(at: oneAhead) == nil {
                let promotion: PieceType? = oneAheadRank == promotionRank ? .queen : nil
                moves.append(ChessMove(from: index, to: oneAhead, promotion: promotion))

                if rank == startRank {
                    let twoAheadRank = rank + (2 * direction)
                    let twoAhead = ChessSquare.index(file: file, rank: twoAheadRank)
                    if board.piece(at: twoAhead) == nil {
                        moves.append(ChessMove(from: index, to: twoAhead, promotion: nil))
                    }
                }
            }
        }

        return moves
    }

    private static func knightMoves(from index: Int, piece: Piece, in board: ChessBoard) -> [ChessMove] {
        let file = ChessSquare.file(index)
        let rank = ChessSquare.rank(index)
        let offsets = [
            (1,2), (2,1), (-1,2), (-2,1),
            (1,-2), (2,-1), (-1,-2), (-2,-1)
        ]

        var moves: [ChessMove] = []
        for (df, dr) in offsets {
            let nf = file + df
            let nr = rank + dr
            guard ChessSquare.isValid(file: nf, rank: nr) else { continue }
            let to = ChessSquare.index(file: nf, rank: nr)
            if let target = board.piece(at: to), target.color == piece.color {
                continue
            }
            moves.append(ChessMove(from: index, to: to, promotion: nil))
        }
        return moves
    }

    private static func kingMoves(from index: Int, piece: Piece, in board: ChessBoard) -> [ChessMove] {
        let file = ChessSquare.file(index)
        let rank = ChessSquare.rank(index)
        var moves: [ChessMove] = []

        for df in -1...1 {
            for dr in -1...1 {
                if df == 0 && dr == 0 { continue }
                let nf = file + df
                let nr = rank + dr
                guard ChessSquare.isValid(file: nf, rank: nr) else { continue }
                let to = ChessSquare.index(file: nf, rank: nr)
                if let target = board.piece(at: to), target.color == piece.color {
                    continue
                }
                moves.append(ChessMove(from: index, to: to, promotion: nil))
            }
        }

        return moves
    }

    private static func slidingMoves(from index: Int, piece: Piece, in board: ChessBoard, directions: [(Int, Int)]) -> [ChessMove] {
        let file = ChessSquare.file(index)
        let rank = ChessSquare.rank(index)
        var moves: [ChessMove] = []

        for (df, dr) in directions {
            var nf = file + df
            var nr = rank + dr
            while ChessSquare.isValid(file: nf, rank: nr) {
                let to = ChessSquare.index(file: nf, rank: nr)
                if let target = board.piece(at: to) {
                    if target.color != piece.color {
                        moves.append(ChessMove(from: index, to: to, promotion: nil))
                    }
                    break
                } else {
                    moves.append(ChessMove(from: index, to: to, promotion: nil))
                }
                nf += df
                nr += dr
            }
        }

        return moves
    }
}
