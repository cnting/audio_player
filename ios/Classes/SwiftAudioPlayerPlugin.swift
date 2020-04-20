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
    private var playerUrl: String! = ""
    private var wasPlayingBeforePause: Bool! = false
    fileprivate var eventChannel: FlutterEventChannel?
    fileprivate var eventSink: FlutterEventSink?
    
    public convenience init(on asset: String, _ clipRange: [Int], _ numberOfLoops: Int, _ autoCache: Bool) throws {
        let path = Bundle.main.path(forResource: asset, ofType: nil) ?? ""
        try self.init(with:path,clipRange,numberOfLoops,autoCache)
    }
    
    public init(with url: String, _ clipRange: [Int], _ numberOfLoops: Int, _ autoCache: Bool) throws {
        super.init()
        isInitialized = false
        isPlaying = false
        
        let audioUrl = AudioDownloadUtil.session.getDesignatedUrlfileCachePath(with: url)
        guard audioUrl != nil else {
            return
        }
        initAudioPlayer(with: audioUrl!, clipRange, numberOfLoops, autoCache)
    }
    
    public func resetPlayer(with url: String?,on asset: String?, _ clipRange: [Int], _ numberOfLoops: Int, _ autoCache: Bool) {
        isInitialized = false
        isPlaying = false
        playerClipRange = clipRange
        playerLoops = numberOfLoops
        var downloadUrl = ""
        if asset != nil {
            downloadUrl = Bundle.main.path(forResource: asset, ofType: nil) ?? ""
        } else if (url != nil) {
            downloadUrl = url!
        }
        guard !downloadUrl.isEmpty else {
            return
        }
        let audioUrl = AudioDownloadUtil.session.getDesignatedUrlfileCachePath(with: downloadUrl)
        guard audioUrl != nil else {
            return
        }
        //链接不同需要重新初始化player
        if self.playerUrl != audioUrl! {
            initAudioPlayer(with: audioUrl!, clipRange, numberOfLoops, autoCache)
            return
        }
        
        self.loopCount = 0
        if clipRange.count != 0 {
            let firstValue: Int = clipRange[0]
            let lastValue: Int = clipRange[1]
            
            if (firstValue == 0) {
                playerCurrentTime = 0
            } else {
                playerCurrentTime = firstValue/1000
            }
            if (lastValue != -1) {//-1表示播放到音频末尾
                playerDuration = lastValue/1000
                playerShortDuration = Double(lastValue)/1000.0
            } else {
                let obj = ceil(player!.duration)
                playerDuration = Int(obj);
            }
        } else {
            playerCurrentTime = 0
            let obj = ceil(player!.duration)
            playerDuration = Int(obj);
        }
        seekTo(with: playerCurrentTime)
        sendInitialized()
        
    }
    
    private func initAudioPlayer(with url: String, _ clipRange: [Int], _ numberOfLoops: Int, _ autoCache: Bool) {
        self.playerUrl = url
        self.loopCount = 0
        playerClipRange = clipRange
        playerLoops = numberOfLoops
        if url.hasPrefix("http") || url.hasPrefix("https") {
            do {
                player = try ListenAudioPlayer.init(contentsOf: URL.init(string: url)!)
                player?.delegate = self
                player?.resetPlayer()
            } catch {}
            
            initDownloadState(autoCache)
        } else {
            var cachePath = url
            
            if url.contains("file://") {
                let filePath = url as NSString;
                let path = filePath.substring(from: url.count - (url.count - 7))
                cachePath = path
            }
            do {
                player = try ListenAudioPlayer.init(contentsOfPath: cachePath)
                player?.delegate = self
                player?.resetPlayer()
            } catch {}
        }
    }
    
    private func config(_ clipRange: [Int], _ numberOfLoops: Int, _ flag: Bool) {
        if clipRange.count != 0 {
            let firstValue: Int = clipRange[0]
            let lastValue: Int = clipRange[1]
            
            if (firstValue == 0) {
                playerCurrentTime = 0
            } else {
                playerCurrentTime = firstValue/1000
            }
            if (lastValue != -1) {//-1表示播放到音频末尾
                playerDuration = lastValue/1000
                playerShortDuration = Double(lastValue)/1000.0
                if flag {
                    createDisplayLink()
                }
            } else {
                player?.delegate = self
                let obj = ceil(player!.duration)
                playerDuration = Int(obj);
            }
            
        } else {
            playerCurrentTime = 0
            let obj = ceil(player!.duration)
            playerDuration = Int(obj);
            player?.delegate = self
        }
        if flag {
            seekTo(with: playerCurrentTime)
            sendInitialized()
            addNotification()
        }
        
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
    
    private func initDownloadState(_ autoCache: Bool) {
        if autoCache {
            AudioDownloadUtil.session.startDownloadTask(with: playerUrl)
        }
    }
    
    private func createDisplayLink() {
        displayLink = CADisplayLink.init(target: self, selector: #selector(fire(with:)))
        displayLink.add(to: RunLoop.current, forMode: RunLoop.Mode.common)
        displayLink.isPaused = true
        sendInitialized()
    }
    
    private func addNotification() {
        NotificationCenter.default.addObserver(self, selector:#selector(becomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector:#selector(becomeDeath), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    private func removeNotification() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    @objc func becomeActive(noti:Notification) {
//        print("进入前台")
        if wasPlayingBeforePause {
            play()
        }
    }
    
    @objc func becomeDeath(noti:Notification) {
        guard player != nil else {
            return
        }
//        print("进入后台")
        wasPlayingBeforePause = player!.isPlaying
        if player!.isPlaying {
            pause()
        }
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
    
    private func sendBufferingStart() {
        guard eventSink != nil else {
            return
        }
        eventSink!(["event":"bufferingStart"])
    }
    
    private func sendBufferingEnd() {
        guard eventSink != nil else {
            return
        }
        eventSink!(["event":"bufferingEnd"])
    }
    
    public func removeAllAudioCache() {
        AudioDownloadUtil.session.clearAudioCaches()
    }
    
    private func sendPlayStateChanged(with isPlaying: Bool) {
        guard eventSink != nil else {
            return
        }
//        print(">>>>>>>>>>>>audio_player当前状态是:\(isPlaying)")
        eventSink!(["event":"playStateChanged","isPlaying":NSNumber.init(value: isPlaying)])
    }
    
    private func sendPlayStateComplate() {
        guard eventSink != nil else {
            return
        }
        eventSink!(["event":"completed"])
    }
    
    private func sendPlayStateError() {
        guard eventSink != nil else {
            return
        }
        eventSink!(FlutterError.init(code: "audio_player_error", message: "throws custom error", details: nil))
    }
    
    private func sendInitialized() {
        if eventSink != nil && !isInitialized {
            let duration = Int(player?.duration ?? 0)
            if duration == 0 && playerDuration == 0 {
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
        removeNotification()
    }
    
}

extension SwiftAudioPlayer:ListenAudioPlayerDelegate {
    
    func playerPlayDidError() {
        pause()
        sendPlayStateError()
    }
    
    func playDidFinishByPlaying() {
        loopCount += 1
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
    
    func playerbufferingStart() {
//        sendBufferingStart()
    }
    
    func playerbufferingEnd() {
//        sendBufferingEnd()
        config(self.playerClipRange, self.playerLoops,true)
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
        } else if call.method == AudioPlayerMethodCallName.removeDownload {
            player.removeAllAudioCache()
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    //1:url 2:assetPath 3:clipRange 4:loopingTimes 5:autoCache
    private func methodCallSource(_ call: FlutterMethodCall) -> (String?,String?,[Int],Int,Bool) {
        let argsMap = call.arguments as? Dictionary<String, Any>
        if argsMap != nil {
            let asset = argsMap!["asset"] as? String
            let urlStr = argsMap!["uri"] as? String
            var autoCache = argsMap!["autoCache"] as? Bool
            if autoCache == nil {
                autoCache = false
            }
            
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
                return (nil,assetPath,clipRange,numberOfLoops,autoCache!)
            } else if urlStr != nil {
                return (urlStr!,nil,clipRange,numberOfLoops,autoCache!)
            }
        }
        return (nil,nil,[],0,false)
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
        var player: SwiftAudioPlayer!
        let object = methodCallSource(call)
        let urlStr = object.0
        let assetPath = object.1
        let clipRange = object.2
        let numberOfLoops = object.3
        let autoCache = object.4
        if urlStr != nil {
            do {
                player = try SwiftAudioPlayer.init(with: urlStr!,clipRange,numberOfLoops,autoCache)
                onPlayer(setUp: player, on: result)
            } catch {result(FlutterMethodNotImplemented)}
        } else if assetPath != nil {
            do {
                player = try SwiftAudioPlayer.init(on: assetPath!,clipRange,numberOfLoops,autoCache)
                onPlayer(setUp: player, on: result)
            } catch {result(FlutterMethodNotImplemented)}
        } else {
            result(FlutterMethodNotImplemented)
        }
        
    } else if call.method == AudioPlayerMethodCallName.reset {
        let argsMap = call.arguments as? Dictionary<String, Any>
        if argsMap != nil {
            let playerId = argsMap!["playerId"] as? String
            if playerId != nil {
                let player = players[(playerId!)] as? SwiftAudioPlayer
                if player == nil {
                    result(FlutterError.init(code: "Unknown playerId", message: "No audio player associated with player id \(playerId!)", details: nil))
                    return
                }
                let object = methodCallSource(call)
                let urlStr = object.0
                let assetPath = object.1
                let clipRange = object.2
                let numberOfLoops = object.3
                let autoCache = object.4
                player?.resetPlayer(with: urlStr, on: assetPath, clipRange, numberOfLoops,autoCache)
                onPlayer(setUp: player!, on: result)
                onMethodCall(call, result: result, playerId!, player!)
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
