//
//  AudioPlayer.swift
//  audio_player
//
//  Created by 牛新怀 on 2019/12/12.
//

import Foundation
import AVFoundation

public enum AudioPlayerError: Error {
    case fileExtension, fileNotFound
}

protocol ListenAudioPlayerDelegate:NSObjectProtocol {
    func playDidFinishByPlaying()
    func playerPlayDidError()
    func playerbufferingStart()
    func playerbufferingEnd()
}

public class ListenAudioPlayer: NSObject {
    
    /// Name of the used to initialize the object
    public var name: String?
    
    weak var delegate:ListenAudioPlayerDelegate?
    
    /// URL of the used to initialize the object
    public let url: URL?
    fileprivate var player: AVAudioPlayer?
    
    // MARK: Init
    
    public convenience init(fileName: String) throws {
        let soundFileComponents = fileName.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ".")
        guard soundFileComponents.count == 2 else {
            throw AudioPlayerError.fileExtension
        }
        
        guard let url = Bundle.main.url(forResource: soundFileComponents[0], withExtension: soundFileComponents[1]) else {
            throw AudioPlayerError.fileNotFound
        }
        try self.init(contentsOf: url)
    }
    
    public convenience init(contentsOfPath path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        try self.init(contentsOf: fileURL)
    }
    
    public init(contentsOf url: URL) throws {
        self.url = url
        name = url.lastPathComponent
        super.init()
    }
    
    public func resetPlayer() {
        guard self.url != nil else {
            return
        }
        sendbufferingStart()
        DispatchQueue.global().async {
            do {
                let data = try Data.init(contentsOf: self.url!)
                DispatchQueue.main.async {
                    do {
                        self.player = try AVAudioPlayer.init(data: data, fileTypeHint: AVFileType.mp3.rawValue)
                        try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
                        try AVAudioSession.sharedInstance().setActive(true)
                        self.player?.numberOfLoops = 0
                        self.player?.currentTime = 0
                        self.player?.prepareToPlay()
                        self.player?.delegate = self
                        self.sendbufferingEnd()
                    } catch {
                        self.sendError()
                    }
                }
            } catch {
                self.sendError()
            }
        }
    }
    
    private func sendError() {
        DispatchQueue.main.async {
            self.delegate?.playerPlayDidError()
        }
    }
    
    private func sendbufferingStart() {
        DispatchQueue.main.async {
            self.delegate?.playerbufferingStart()
        }
    }
    
    private func sendbufferingEnd() {
        DispatchQueue.main.async {
            self.delegate?.playerbufferingEnd()
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension ListenAudioPlayer: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.delegate?.playDidFinishByPlaying()
    }
    
    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        sendError()
    }
}

// MARK: - play/pause/...
extension ListenAudioPlayer {
    
    public var isPlaying: Bool {
        guard let nonNilsound = player else {
            return false
        }
        return nonNilsound.isPlaying
    }
    
    /// the duration of the player.
    public var duration: TimeInterval {
        guard let nonNilsound = player else {
            return 0.0
        }
        return nonNilsound.duration
    }
    
    /// currentTime is the offset into the sound of the current playback position.
    public var currentTime: TimeInterval {
        get {
            guard let nonNilsound = player else {
                return 0.0
            }
            return nonNilsound.currentTime
        }
        set {
            player?.currentTime = newValue
        }
    }
    
    /// The volume for the sound. The nominal range is from 0.0 to 1.0.
    public var volume: Float {
        get {
            guard let nonNilsound = player else {
                return 0.0
            }
            return nonNilsound.volume
        }
        set {
            player?.volume = newValue
        }
    }
    
    /* "numberOfLoops" is the number of times that the sound will return to the beginning upon reaching the end.
     A value of zero means to play the sound just once.
     A value of one will result in playing the sound twice, and so on..
     Any negative number will loop indefinitely until stopped.
     */
    public var numberOfLoops: Int {
        get {
            guard let nonNilsound = player else {
                return 0
            }
            return nonNilsound.numberOfLoops
        }
        set {
            player?.numberOfLoops = newValue
        }
    }
    
    /* set panning. -1.0 is left, 0.0 is center, 1.0 is right. */
    public var pan: Float {
        get {
            guard let nonNilsound = player else {
                return 0.0
            }
            return nonNilsound.pan
        }
        set {
            player?.pan = newValue
        }
    }
    
    /* You must set enableRate to YES for the rate property to take effect. You must set this before calling prepareToPlay. */
    public var enableRate: Bool {
        get {
            guard let nonNilsound = player else {
                return false
            }
            return nonNilsound.enableRate
        }
        set {
            player?.enableRate = newValue
        }
    }
    
     /* See enableRate. The playback rate for the sound. 1.0 is normal, 0.5 is half speed, 2.0 is double speed. */
    public var rate: Float {
        get {
            guard let nonNilsound = player else {
                return 0.0
            }
            return nonNilsound.rate
        }
        set {
            player?.rate = newValue
        }
    }
    
    public func play() {
        player?.play()
    }
    
    public func pause() {
        player?.pause()
    }
    
    public func stop() {
        player?.stop()
    }
    
}
