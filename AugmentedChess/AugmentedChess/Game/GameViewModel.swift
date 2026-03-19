import Foundation
import SwiftUI
import Combine

struct MoveEvent: Identifiable, Equatable {
    let id = UUID()
    let move: ChessMove
    let wasCapture: Bool
    let moverColor: PieceColor
}

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var board = ChessBoard.initial()
    @Published var hasStarted = false
    @Published var selectedSquare: Int?
    @Published var legalTargets: Set<Int> = []
    @Published var hintMove: ChessMove?
    @Published var selectedTheme: BattleTheme = .winterfell
    @Published var difficulty: Difficulty = .medium
    @Published var statusText = "Place the board on a flat surface."
    @Published var turnSecondsRemaining: Int = 10
    @Published var latestMoveEvent: MoveEvent?
    @Published var isBoardPlaced = false

    let humanColor: PieceColor = .white
    let humanTheme: PlayerTheme = .stark
    let aiTheme: PlayerTheme = .lannister

    private var aiTask: Task<Void, Never>?
    private var turnTimerTask: Task<Void, Never>?

    var canInteract: Bool {
        hasStarted && isBoardPlaced && board.sideToMove == humanColor && !isGameOver
    }

    var sideInfoText: String {
        "You: House Stark (White)  |  Opponent: House Lannister (Black)"
    }

    var turnInfoText: String {
        if ChessRules.isCheckmate(for: humanColor, in: board) || ChessRules.isCheckmate(for: humanColor.opposite, in: board) {
            return "Battle ended"
        }
        let side = board.sideToMove == humanColor ? "House Stark" : "House Lannister"
        return "Turn: \(side) (\(turnSecondsRemaining)s)"
    }

    var isGameOver: Bool {
        ChessRules.isCheckmate(for: .white, in: board) ||
        ChessRules.isCheckmate(for: .black, in: board) ||
        ChessRules.isStalemate(for: .white, in: board) ||
        ChessRules.isStalemate(for: .black, in: board)
    }

    deinit {
        aiTask?.cancel()
        turnTimerTask?.cancel()
    }

    func startExperience() {
        hasStarted = true
        isBoardPlaced = false
        resetGame()
        statusText = "Scan and tap a flat surface to deploy the battlefield."
    }

    func returnToLanding() {
        aiTask?.cancel()
        turnTimerTask?.cancel()
        hasStarted = false
        isBoardPlaced = false
        resetGame()
    }

    func boardPlaced() {
        if !isBoardPlaced {
            isBoardPlaced = true
            statusText = "Your side is nearest you. Your turn. Command House Stark."
            startTurnTimer()
        }
    }

    func startRepositionMode() {
        turnTimerTask?.cancel()
        isBoardPlaced = false
        statusText = "Tap a new flat surface to reposition the battlefield."
    }

    func resetGame() {
        aiTask?.cancel()
        turnTimerTask?.cancel()
        board = ChessBoard.initial()
        selectedSquare = nil
        legalTargets = []
        hintMove = nil
        turnSecondsRemaining = 10
        latestMoveEvent = nil
        statusText = isBoardPlaced ? "Your turn. Command House Stark." : "Place the board on a flat surface."
        if hasStarted && isBoardPlaced {
            startTurnTimer()
        }
    }

    func requestHint() {
        guard canInteract else { return }
        hintMove = ChessHintService.bestHint(for: humanColor, in: board, difficulty: difficulty)
        if let hintMove {
            statusText = "Hint: \(notation(for: hintMove)). Highlighted on board."
        }
    }

    func handleSquareTap(_ square: Int) {
        guard isBoardPlaced else { return }
        guard canInteract else { return }
        guard (0..<64).contains(square) else { return }

        if let selected = selectedSquare,
           legalTargets.contains(square),
           let move = ChessRules.legalMoves(from: selected, in: board).first(where: { $0.to == square }) {
            applyHumanMove(move)
            return
        }

        guard let piece = board.piece(at: square), piece.color == humanColor else {
            selectedSquare = nil
            legalTargets = []
            return
        }

        selectedSquare = square
        let moves = ChessRules.legalMoves(from: square, in: board)
        legalTargets = Set(moves.map(\.to))
        hintMove = nil
        statusText = moves.isEmpty ? "This unit has no legal moves." : "Choose a highlighted destination."
    }

    private func applyHumanMove(_ move: ChessMove) {
        let capture = board.piece(at: move.to) != nil
        board = board.applying(move)
        latestMoveEvent = MoveEvent(move: move, wasCapture: capture, moverColor: humanColor)
        selectedSquare = nil
        legalTargets = []
        hintMove = nil
        statusText = "House Lannister is considering its response..."
        startTurnTimer()
        updateGameStateOrTriggerAI()
    }

    private func updateGameStateOrTriggerAI() {
        if setGameOverStatusIfNeeded() { return }

        if board.sideToMove != humanColor {
            aiTask?.cancel()
            aiTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                let position = self.board
                let level = self.difficulty
                let aiMove = ChessAI.bestMove(for: position.sideToMove, in: position, difficulty: level)

                guard !Task.isCancelled else { return }
                guard let aiMove else {
                    await MainActor.run {
                        _ = self.setGameOverStatusIfNeeded()
                    }
                    return
                }

                await MainActor.run {
                    self.applyAIMove(aiMove)
                }
            }
        }
    }

    private func applyAIMove(_ move: ChessMove) {
        let mover = board.sideToMove
        let capture = board.piece(at: move.to) != nil
        board = board.applying(move)
        latestMoveEvent = MoveEvent(move: move, wasCapture: capture, moverColor: mover)
        statusText = "Your turn. Strike back."
        startTurnTimer()
        _ = setGameOverStatusIfNeeded()
    }

    @discardableResult
    private func setGameOverStatusIfNeeded() -> Bool {
        if ChessRules.isCheckmate(for: humanColor, in: board) {
            turnTimerTask?.cancel()
            statusText = "Checkmate. House Lannister wins this battle."
            return true
        }
        if ChessRules.isCheckmate(for: humanColor.opposite, in: board) {
            turnTimerTask?.cancel()
            statusText = "Checkmate. House Stark is victorious."
            return true
        }
        if ChessRules.isStalemate(for: board.sideToMove, in: board) {
            turnTimerTask?.cancel()
            statusText = "Stalemate. The battlefield falls silent."
            return true
        }
        if ChessRules.isKingInCheck(color: board.sideToMove, in: board) {
            statusText = board.sideToMove == humanColor ? "You are in check." : "Enemy king is in check."
        }
        return false
    }

    private func startTurnTimer() {
        turnTimerTask?.cancel()
        let activeTurn = board.sideToMove
        turnSecondsRemaining = 10

        turnTimerTask = Task { [weak self] in
            guard let self else { return }
            var remaining = 10
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.board.sideToMove == activeTurn, !self.isGameOver else { return }
                    remaining -= 1
                    self.turnSecondsRemaining = max(remaining, 0)
                }
            }
            await MainActor.run {
                guard self.board.sideToMove == activeTurn, !self.isGameOver else { return }
                self.handleTurnTimeout()
            }
        }
    }

    private func handleTurnTimeout() {
        statusText = "Timer expired. Executing forced move."
        let side = board.sideToMove
        guard let move = ChessAI.bestMove(for: side, in: board, difficulty: .easy) ??
                ChessRules.legalMoves(for: side, in: board).first else {
            _ = setGameOverStatusIfNeeded()
            return
        }

        if side == humanColor {
            applyHumanMove(move)
        } else {
            applyAIMove(move)
        }
    }

    private func notation(for move: ChessMove) -> String {
        "\(squareName(move.from)) -> \(squareName(move.to))"
    }

    private func squareName(_ index: Int) -> String {
        guard (0..<64).contains(index) else { return "??" }
        let file = ChessSquare.file(index)
        let rank = ChessSquare.rank(index) + 1
        guard let scalar = UnicodeScalar(97 + file) else { return "??" }
        let fileChar = Character(scalar)
        return "\(fileChar)\(rank)"
    }
}
