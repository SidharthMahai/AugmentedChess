import Foundation

struct ChessBoard: Codable, Equatable {
    private(set) var squares: [Piece?]
    var sideToMove: PieceColor

    init(squares: [Piece?], sideToMove: PieceColor) {
        self.squares = squares
        self.sideToMove = sideToMove
    }

    static func initial() -> ChessBoard {
        var squares = Array<Piece?>(repeating: nil, count: 64)

        func put(_ type: PieceType, _ color: PieceColor, _ file: Int, _ rank: Int) {
            squares[ChessSquare.index(file: file, rank: rank)] = Piece(color: color, type: type)
        }

        let backRank: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            put(backRank[file], .white, file, 0)
            put(.pawn, .white, file, 1)
            put(.pawn, .black, file, 6)
            put(backRank[file], .black, file, 7)
        }

        return ChessBoard(squares: squares, sideToMove: .white)
    }

    subscript(_ index: Int) -> Piece? {
        get { squares[index] }
        set { squares[index] = newValue }
    }

    func piece(at index: Int) -> Piece? {
        guard squares.indices.contains(index) else { return nil }
        return squares[index]
    }

    func kingSquare(for color: PieceColor) -> Int? {
        squares.firstIndex { piece in
            guard let piece else { return false }
            return piece.color == color && piece.type == .king
        }
    }

    func applying(_ move: ChessMove) -> ChessBoard {
        guard squares.indices.contains(move.from), squares.indices.contains(move.to) else { return self }
        var next = self
        guard var piece = next[move.from] else { return self }

        next[move.from] = nil

        if let promotion = move.promotion {
            piece = Piece(color: piece.color, type: promotion)
        }

        next[move.to] = piece
        next.sideToMove = sideToMove.opposite
        return next
    }
}
