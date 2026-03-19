import Foundation

struct ChessHintService {
    static func bestHint(for color: PieceColor, in board: ChessBoard, difficulty: Difficulty) -> ChessMove? {
        // Hint search is one level deeper than the selected AI level to feel more helpful.
        let strongerDifficulty: Difficulty
        switch difficulty {
        case .easy: strongerDifficulty = .medium
        case .medium, .hard: strongerDifficulty = .hard
        }
        return ChessAI.bestMove(for: color, in: board, difficulty: strongerDifficulty)
    }
}
