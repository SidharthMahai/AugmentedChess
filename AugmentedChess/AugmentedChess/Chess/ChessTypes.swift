import Foundation
import UIKit

enum PieceColor: String, Codable, CaseIterable {
    case white
    case black

    var opposite: PieceColor { self == .white ? .black : .white }
}

enum PieceType: String, Codable, CaseIterable {
    case king
    case queen
    case rook
    case bishop
    case knight
    case pawn
}

struct Piece: Codable, Equatable {
    let color: PieceColor
    let type: PieceType
}

struct ChessMove: Codable, Equatable, Hashable {
    let from: Int
    let to: Int
    let promotion: PieceType?
}

enum Difficulty: String, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var searchDepth: Int {
        switch self {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }
}

enum BattleTheme: String, CaseIterable, Identifiable {
    case winterfell
    case dragonstone
    case kingsLanding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winterfell: return "Winterfell"
        case .dragonstone: return "Dragonstone"
        case .kingsLanding: return "King's Landing"
        }
    }

    var subtitle: String {
        switch self {
        case .winterfell: return "Cold steel, frost runes, northern dusk."
        case .dragonstone: return "Volcanic stone, ember glow, storm fire."
        case .kingsLanding: return "Royal obsidian, gold trim, throne glow."
        }
    }

    var boardLight: UIColor {
        switch self {
        case .winterfell: return UIColor(red: 0.30, green: 0.33, blue: 0.36, alpha: 1)
        case .dragonstone: return UIColor(red: 0.35, green: 0.27, blue: 0.24, alpha: 1)
        case .kingsLanding: return UIColor(red: 0.32, green: 0.30, blue: 0.26, alpha: 1)
        }
    }

    var boardDark: UIColor {
        switch self {
        case .winterfell: return UIColor(red: 0.17, green: 0.19, blue: 0.22, alpha: 1)
        case .dragonstone: return UIColor(red: 0.19, green: 0.14, blue: 0.13, alpha: 1)
        case .kingsLanding: return UIColor(red: 0.15, green: 0.14, blue: 0.13, alpha: 1)
        }
    }

    var runeNorth: UIColor {
        switch self {
        case .winterfell: return UIColor(red: 0.36, green: 0.58, blue: 0.76, alpha: 0.65)
        case .dragonstone: return UIColor(red: 0.32, green: 0.52, blue: 0.60, alpha: 0.60)
        case .kingsLanding: return UIColor(red: 0.45, green: 0.60, blue: 0.84, alpha: 0.55)
        }
    }

    var runeSouth: UIColor {
        switch self {
        case .winterfell: return UIColor(red: 0.70, green: 0.48, blue: 0.24, alpha: 0.55)
        case .dragonstone: return UIColor(red: 0.88, green: 0.42, blue: 0.16, alpha: 0.68)
        case .kingsLanding: return UIColor(red: 0.82, green: 0.64, blue: 0.26, alpha: 0.62)
        }
    }

    var whitePiece: UIColor {
        switch self {
        case .winterfell: return UIColor(red: 0.74, green: 0.79, blue: 0.86, alpha: 1)
        case .dragonstone: return UIColor(red: 0.79, green: 0.80, blue: 0.82, alpha: 1)
        case .kingsLanding: return UIColor(red: 0.88, green: 0.83, blue: 0.73, alpha: 1)
        }
    }

    var blackPiece: UIColor {
        switch self {
        case .winterfell: return UIColor(red: 0.54, green: 0.41, blue: 0.27, alpha: 1)
        case .dragonstone: return UIColor(red: 0.64, green: 0.31, blue: 0.18, alpha: 1)
        case .kingsLanding: return UIColor(red: 0.36, green: 0.30, blue: 0.24, alpha: 1)
        }
    }
}

enum PlayerTheme: String {
    case stark
    case lannister
}

enum ChessSquare {
    static func index(file: Int, rank: Int) -> Int {
        rank * 8 + file
    }

    static func file(_ index: Int) -> Int {
        index % 8
    }

    static func rank(_ index: Int) -> Int {
        index / 8
    }

    static func isValid(file: Int, rank: Int) -> Bool {
        (0..<8).contains(file) && (0..<8).contains(rank)
    }
}
