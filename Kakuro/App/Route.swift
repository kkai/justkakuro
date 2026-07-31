import Foundation

enum Route: Hashable {
    case game(size: BoardSize, difficulty: Difficulty)
    case resumeGame
    case tutorial(Technique?)
    case practice(Technique)
    case learn
    case practiceMenu
    case stats
    case settings
}
