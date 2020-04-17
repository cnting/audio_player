//
//  AudioDownloadUtil.swift
//  audio_player
//
//  Created by 牛新怀 on 2020/4/16.
//

import Foundation
import CommonCrypto

class AudioDownloadUtil: NSObject {
    
    //单例
    static let session = AudioDownloadUtil.init()
    private lazy var urlSession: URLSession = {
       // 创建会话相关配置
        let config = URLSessionConfiguration.background(withIdentifier: "KDownLoadURLSession_audio_player")
        // 在应用进入后台时，让系统决定决定是否在后台继续下载。如果是false，进入后台将暂停下载
        config.isDiscretionary = true
        config.timeoutIntervalForRequest = 15
        // 创建一个可以在后台下载的session (其实会话的类型有四种形式)
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        return session
    }()
    
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var urls: [String] = [String]()
    private var isDownloading: Bool = false
    private var designatedDownloadUrl: String = ""
    
    public func startDownloadTask(with url: String) {
        let downloadUrl = URL.init(string: url)
        guard downloadUrl != nil else {
            return
        }
        if !urls.contains(url) {
            urls.append(url)
        }
        guard !isDownloading else {
            return
        }
        designatedDownloadUrl = url
        let request = URLRequest.init(url: downloadUrl!)
        if resumeData == nil {
            task = urlSession.downloadTask(with: request)
        } else {
            task = urlSession.downloadTask(withResumeData: resumeData!)
        }
        task?.resume()
        resumeData = nil
        
    }
    
    public func cancleTask() {
        task?.cancel(byProducingResumeData: { (data) in
            self.resumeData = data
        })
    }
    
    public func getDesignatedUrlfileCachePath(with url: String) -> String? {
        
        guard url.hasPrefix("http") || url.hasPrefix("https") else {
            return url
        }
        
        let haveCache = haveDesignatedUrlCache(with: url)
        guard haveCache else {
            return url
        }
        
        return fileCachePath(url)
    }
    
    private func haveDesignatedUrlCache(with url: String) -> Bool {
        
        let path = fileCachePath(url)
        guard path != nil else {
            return false
        }
        
        if FileManager.default.fileExists(atPath: path!) {
            return true
        }
        return false
    }
    
    private func fileCachePath(_ url: String) -> String? {
        let downloadUrl = URL.init(string: url)
        guard downloadUrl != nil else {
            return nil
        }
        
        if !FileManager.default.fileExists(atPath: AudioPath.filePath) {
            do {
                try FileManager.default.createDirectory(atPath: AudioPath.filePath, withIntermediateDirectories: true, attributes: nil)
            } catch  {
                print(">>>>>>>>>创建audio_player文件夹失败error:\(error.localizedDescription)")
            }
        }
        
        let path = AudioPath.filePath + "\(url.MD5())"
        return path
    }
    
    public func clearAudioCaches() {
        if FileManager.default.fileExists(atPath: AudioPath.filePath) {
            
            do {
                let cacheArray = try FileManager.default.contentsOfDirectory(atPath: AudioPath.filePath)
                
                guard cacheArray.count != 0 else {
                    return
                }
                cacheArray.forEach { (cachePath) in
                    let path = AudioPath.filePath + cachePath
                    try? FileManager.default.removeItem(atPath: path)
                }
            } catch {
            
            }
        }
    }
    
}

// urlSession delegate
extension AudioDownloadUtil: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        isDownloading = false
        guard downloadTask.response != nil else {
            return
        }
        
        let destination =  AudioPath.filePath + "\(self.designatedDownloadUrl.MD5())"
        do {
            try FileManager.default.moveItem(atPath: location.path, toPath: destination)
            ///md5
            if urls.count != 0 {
                for idx in 0..<urls.count {
                    let fileName = urls[idx]
                    if fileName == self.designatedDownloadUrl {
                        urls.remove(at: idx)
                        break
                    }
                }
                if urls.count != 0 {
                    resumeData = nil
                    startDownloadTask(with: urls[0])
                }
            }
        }
        catch {
            print("audio_player download failed error:\(error.localizedDescription)")
        }
        
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        ///进度
        isDownloading = true
//        print(">>>>>下载进度:\(Float(totalBytesWritten)/Float(totalBytesExpectedToWrite))")
    }
    
    // 任务完成时调用，但是不一定下载完成；用户点击暂停后，也会调用这个方法
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 如果下载任务可以恢复，那么NSError的userInfo包含了NSURLSessionDownloadTaskResumeData键对应的数据，保存起来，继续下载要用到
        guard error != nil, let data = (error! as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data else {
            return
        }
        
        resumeData = data
    }
    
}

struct AudioPath {
    static let lastPathComponent = "/audio_voice/"
    static let designatedPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).last! + "/Caches" + "/flutter_cache"
    static let filePath = AudioPath.designatedPath + AudioPath.lastPathComponent
}

//MD5
extension Int {
    func hexedString() -> String
    {
        return NSString(format:"%02x", self) as String
    }
}

extension NSData {
    
    func hexedString() -> String {
        var string = String()
        let unsafePointer = bytes.assumingMemoryBound(to: UInt8.self)
        for i in UnsafeBufferPointer<UInt8>(start:unsafePointer, count: length){
            string += Int(i).hexedString()
        }
        return string
    }
    
    func MD5() -> NSData {
        let result = NSMutableData(length: Int(CC_MD5_DIGEST_LENGTH))!
        let unsafePointer = result.mutableBytes.assumingMemoryBound(to: UInt8.self)
        CC_MD5(bytes, CC_LONG(length), UnsafeMutablePointer<UInt8>(unsafePointer))
        return NSData(data: result as Data)
    }
}

extension String {
    public func MD5() -> String {
        let data = (self as NSString).data(using: String.Encoding.utf8.rawValue)! as NSData
        return data.MD5().hexedString()
    }
}
