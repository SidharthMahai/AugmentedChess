import Foundation
import AVFoundation
import AudioToolbox

final class GameAudioManager: NSObject {
    static let shared = GameAudioManager()

    private var ambientPlayer: AVAudioPlayer?
    private var oneShotPlayers: [AVAudioPlayer] = []

    private override init() {}

    func playAmbientLoop() {
        guard ambientPlayer == nil else {
            ambientPlayer?.play()
            return
        }

        guard let url = Bundle.main.url(forResource: "battle_ambient", withExtension: "mp3") else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.22
            player.prepareToPlay()
            player.play()
            ambientPlayer = player
        } catch {
            ambientPlayer = nil
        }
    }

    func stopAmbientLoop() {
        ambientPlayer?.stop()
    }

    func playMove() {
        if let url = Bundle.main.url(forResource: "move", withExtension: "mp3") {
            playOneShot(url: url)
        } else if let url = Bundle.main.url(forResource: "move", withExtension: "wav") {
            playOneShot(url: url)
        } else {
            AudioServicesPlaySystemSound(1104)
        }
    }

    func playCapture() {
        if let url = Bundle.main.url(forResource: "capture", withExtension: "mp3") {
            playOneShot(url: url)
        } else if let url = Bundle.main.url(forResource: "capture", withExtension: "wav") {
            playOneShot(url: url)
        } else {
            AudioServicesPlaySystemSound(1157)
        }
    }

    private func playOneShot(url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.65
            player.delegate = self
            oneShotPlayers.append(player)
            player.play()
        } catch {
            AudioServicesPlaySystemSound(1104)
        }
    }
}

extension GameAudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        oneShotPlayers.removeAll(where: { $0 === player })
    }
}
