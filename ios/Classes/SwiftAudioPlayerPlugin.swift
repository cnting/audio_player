import Flutter
import UIKit

class SwiftAudioPlayer: NSObject {
    
    var player: ListenAudioPlayer?
    private var isPlaying: Bool! = false
    private var isInitialized: Bool! = false
    var playerCurrentTime: Int! = 0
    var playerDuration: Int! = 0
    private var playerShortDuration: Double! = 0.0
    private var playerClipRange: [Int]! = []
    private var playerLoops: Int! = 0
    private var loopCount: Int! = 0
    private var displayLink: CADisplayLink!
    fileprivate var eventChannel: FlutterEventChannel?
    fileprivate var eventSink: FlutterEventSink?
    
    public convenience init(on asset: String, _ clipRange: [Int], _ numberOfLoops: Int) throws {
        let path = Bundle.main.path(forResource: asset, ofType: nil) ?? ""
        try self.init(with:path,clipRange,numberOfLoops)
    }
    
    public init(with url: String, _ clipRange: [Int], _ numberOfLoops: Int) throws {
        isInitialized = false
        isPlaying = false
        if url.hasPrefix("http") || url.hasPrefix("https") {
            player = try ListenAudioPlayer.init(contentsOf: URL.init(string: url)!)
        } else {
            
            if url.contains("file://") {
                let filePath = url as NSString;
                let path = filePath.substring(from: url.count - (url.count - 7))
                player = try ListenAudioPlayer.init(contentsOfPath: path)

            } else {
                player = try ListenAudioPlayer.init(contentsOfPath: url)

            }
        }
        super.init()
        
        if clipRange.count != 0 {
            playerClipRange = clipRange
            let firstValue: Int = clipRange[0]
            let lastValue: Int = clipRange[1]
            
            if (firstValue == 0) {
                playerCurrentTime = 0
            } else {
                playerCurrentTime = firstValue/1000
                seekTo(with: playerCurrentTime)
            }
            if (lastValue != -1) {//-1表示播放到音频末尾
                playerDuration = lastValue/1000
                playerShortDuration = Double(lastValue)/1000.0
                createDisplayLink()
            } else {
                player?.delegate = self
                playerDuration = Int(player!.duration);
//                seekTo(with: playerDuration - 10)
            }
            
            playerLoops = numberOfLoops
        } else {
            playerLoops = numberOfLoops
            playerCurrentTime = 0
            playerDuration = Int(player!.duration)
            player?.delegate = self
        }
        
        sendInitialized()
    }
    
    @objc private func fire(with playLink: CADisplayLink) {
        if player!.currentTime >= playerShortDuration {
            loopCount += 1
            seekTo(with: playerCurrentTime)
            if playerLoops == -1 {
                play()
            } else if playerLoops <= loopCount {
                pause()
                sendPlayStateComplate()
            } else if playerLoops > loopCount {
                play()
            }
        }
    }
    
    private func createDisplayLink() {
        displayLink = CADisplayLink.init(target: self, selector: #selector(fire(with:)))
        displayLink.add(to: RunLoop.current, forMode: RunLoop.Mode.common)
        displayLink.isPaused = true
        sendInitialized()
    }
    
    public func play() {
        isPlaying = true
        updatePlayingState()
    }
    
    public func pause() {
        isPlaying = false
        updatePlayingState()
    }
    
    public func setIsLooping(with isLooping:Bool) {
        if isLooping {
            playerLoops = -1
        }
    }
    
    public func setVolume(with volume: Double) {
        player?.volume = Float((volume < 0.0) ? 0.0 : (volume > 1.0) ? 1.0 : volume)
    }
    
    public func seekTo(with location: Int) {
        player?.currentTime = TimeInterval(location)
    }
    
    public func currentTime() -> Int {
        return Int(player!.currentTime) - playerCurrentTime
    }
    
    public func setRate(with rate: Double) {
        player?.enableRate = true
        player?.rate = Float(rate)
    }
    
    public func updatePlayingState() {
        guard isInitialized == true else {
            return
        }
        if isPlaying {
            sendPlayStateChanged(with: true)
            player?.play()
        } else {
            sendPlayStateChanged(with: false)
            player?.pause()
        }
        displayLink?.isPaused = !isPlaying
    }
    
    public func sendBufferingUpdate() {
        guard eventSink != nil else {
            return
        }
        eventSink!(["event":"bufferingUpdate","values":[playerCurrentTime * 1000,playerDuration * 1000 - playerCurrentTime * 1000]])
    }
    
    private func sendPlayStateChanged(with isPlaying: Bool) {
        guard eventSink != nil else {
            return
        }
        eventSink!(["event":"playStateChanged","isPlaying":NSNumber.init(value: isPlaying)])
    }
    
    private func sendPlayStateComplate() {
        guard eventSink != nil else {
            return
        }
        eventSink!(["event":"completed"])
    }
    
    private func sendInitialized() {
        if eventSink != nil && !isInitialized {
            let duration = Int(player?.duration ?? 0)
            if duration == 0 {
                return
            }
            isInitialized = true
            let normDuration = (playerClipRange.count == 0 ? (duration * 1000) : (playerDuration - playerCurrentTime)*1000)
            eventSink!(["event":"initialized","duration":normDuration])
        }
    }
    
    public func dispose() {
        if isInitialized {
            player?.stop()
        }
        displayLink?.invalidate()
        eventChannel?.setStreamHandler(nil)
    }
    
}

extension SwiftAudioPlayer:ListenAudioPlayerDelegate {
    func playDidFinishByPlaying() {
        loopCount += 1
//        seekTo(with: self.playerCurrentTime)
        if playerLoops == -1 {
            seekTo(with: self.playerCurrentTime)
            play()
        } else if playerLoops <= loopCount {
            pause()
            sendPlayStateComplate()
        } else if playerLoops > loopCount {
            seekTo(with: self.playerCurrentTime)
            play()
        }
    }
}

extension SwiftAudioPlayer: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        sendInitialized()
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

public class SwiftAudioPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "cnting.com/audio_player", binaryMessenger: registrar.messenger())
    let instance = SwiftAudioPlayerPlugin(with: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
    
    private var registry: FlutterTextureRegistry!
    private var messenger: FlutterBinaryMessenger!
    private var players: NSMutableDictionary!
    private var registrars: FlutterPluginRegistrar!
    
    public init(with registrar:FlutterPluginRegistrar) {
        
        registry = registrar.textures()
        messenger = registrar.messenger()
        registrars = registrar
        super.init()
        players = NSMutableDictionary.init()
    }
    
    private func currentTimeMillis() -> String {
        let now = NSDate()
        let timeInterval:TimeInterval = now.timeIntervalSince1970
        return "\(timeInterval)"
//        return Int(timeInterval)
    }
    
    private func onPlayer(setUp player: SwiftAudioPlayer, on result: FlutterResult) {
        let id = currentTimeMillis()
        
        let eventChannel = FlutterEventChannel.init(name: "cnting.com/audio_player/audioEvents\(id)", binaryMessenger: messenger)
        eventChannel.setStreamHandler(player)
        player.eventChannel = eventChannel
        players[id] = player
        result(["playerId":(id)])
        
    }

    private func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult, _ playerId: String, _ player: SwiftAudioPlayer) {
        let argsMap = call.arguments as? Dictionary<String, Any>
        guard argsMap != nil else {
            result(FlutterError.init(code: "Unknown arguments", message: "No audio player arguments associated with arguments", details: nil))
            return
        }
        if call.method == AudioPlayerMethodCallName.setLooping {
            player.setIsLooping(with: argsMap!["looping"] as! Bool)
            result(nil)
        } else if call.method == AudioPlayerMethodCallName.setVolume {
            player.setVolume(with: argsMap!["volume"] as! Double)
            result(nil)
        } else if call.method == AudioPlayerMethodCallName.play {
            player.play()
            result(nil)
        } else if call.method == AudioPlayerMethodCallName.pause {
            player.pause()
            result(nil)
        } else if call.method == AudioPlayerMethodCallName.seekTo {
            let location: Int = Int(truncating: (argsMap!["location"] as! NSNumber))
            player.seekTo(with: location == 0 ? player.playerCurrentTime : location/1000)
            result(nil)
        } else if call.method == AudioPlayerMethodCallName.position {
            if player.playerDuration == Int(player.player!.duration) {
                result(Int((floor(player.player!.currentTime) - Double(player.playerCurrentTime!)) * Double(1000)))
            } else {
                result(Int((round(player.player!.currentTime) - Double(player.playerCurrentTime!)) * Double(1000)))
            }
            
            player.sendBufferingUpdate()
        } else if call.method == AudioPlayerMethodCallName.dispose {
            player.dispose()
            players.removeObject(forKey: playerId)
            result(nil)
        } else if call.method == AudioPlayerMethodCallName.setSpeed {
            let rate: Double = Double(truncating: argsMap!["speed"] as! NSNumber)
            player.setRate(with: rate)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == AudioPlayerMethodCallName.inited {
        players.forEach { (object) in
            let player = object.value as! SwiftAudioPlayer
            player.dispose()
        }
        players.removeAllObjects()
        result(nil)
    } else if call.method == AudioPlayerMethodCallName.create {
        let argsMap = call.arguments as? Dictionary<String, Any>
        if argsMap != nil {
            let asset = argsMap!["asset"] as? String
            let urlStr = argsMap!["uri"] as? String
            var player: SwiftAudioPlayer!
            var clipRange: [Int] = [Int]()
            var numberOfLoops: Int = 0
            
            let cr = argsMap!["clipRange"]
            let nols = argsMap!["loopingTimes"]
            
            if cr != nil {
                clipRange = cr! as! [Int]
            }
            if nols != nil {
                numberOfLoops = nols! as! Int
            }
            
            if asset != nil {
                var assetPath: String!
                let package = argsMap!["package"] as? String
                if package != nil {
                    assetPath = registrars.lookupKey(forAsset: asset ?? "", fromPackage: package ?? "")
                } else {
                    assetPath = registrars.lookupKey(forAsset: asset ?? "")
                }
                do {
                    player = try SwiftAudioPlayer.init(on: assetPath,clipRange,numberOfLoops)
                    onPlayer(setUp: player, on: result)
                } catch {}
            } else if urlStr != nil {
                do {
                    player = try SwiftAudioPlayer.init(with: urlStr!,clipRange,numberOfLoops)
                    onPlayer(setUp: player, on: result)
                } catch {}
                
            } else {
                result(FlutterMethodNotImplemented)
            }
        } else {result(FlutterMethodNotImplemented)}
        
    } else {
        let argsMap = call.arguments as? Dictionary<String, Any>
        if argsMap != nil {
            let playerId = argsMap!["playerId"] as? String
            if playerId != nil {
                let player = players[(playerId!)] as? SwiftAudioPlayer
                if player == nil {
                    result(FlutterError.init(code: "Unknown playerId", message: "No audio player associated with player id \(playerId!)", details: nil))
                    return
                }
                onMethodCall(call, result: result, playerId!, player!)
            }
        }
    }
  }
}
