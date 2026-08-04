import Flutter
import UIKit
import Foundation
import ActivityKit
import UserNotifications

class DownloadManager: NSObject {
    static let shared = DownloadManager()

    private var backgroundSession: URLSession!
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var taskIdMap: [Int: String] = [:]
    private var progressMap: [String: (received: Int64, total: Int64)] = [:]
    private var resumeDataMap: [String: Data] = [:]
    private var saveDirMap: [String: String] = [:]
    private var retryCountMap: [String: Int] = [:]
    private var downloadUrlMap: [String: String] = [:]
    private var fileNameMap: [String: String] = [:]
    private let maxRetries = 3
    private var proxyHost: String = ""
    private var proxyPort: Int = 0
    private var proxyUsername: String = ""
    private var proxyPassword: String = ""
    private var proxyEnabled: Bool = false
    private var proxyProtocol: String = "http"
    var liveActivityEnabled: Bool = true
    var backgroundCompletionHandler: (() -> Void)?
    var liveActivityErrorSink: FlutterEventSink?

    var eventSink: FlutterEventSink? {
        didSet {
            if eventSink != nil {
                replayPendingEvents()
                restorePendingTasks()
            }
        }
    }
    private var pendingEvents: [[String: Any]] = []

    private func replayPendingEvents() {
        guard let sink = eventSink else { return }
        for event in pendingEvents {
            sink(event)
        }
        pendingEvents.removeAll()
    }

    private override init() {
        super.init()
        backgroundSession = createSession()
        resolvePersistentDownloadFolder()
    }

    deinit {
        persistentFolderURL?.stopAccessingSecurityScopedResource()
    }

    var persistentFolderURL: URL?

    private func resolvePersistentDownloadFolder() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "persistentDownloadFolderBookmark") else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return }
        if url.startAccessingSecurityScopedResource() {
            persistentFolderURL = url
        }
    }

    func setProxy(host: String, port: Int, username: String, password: String, enabled: Bool, protocol proto: String = "http") {
        let newProtocol = proto.lowercased()
        // Skip if nothing changed (avoids tearing down session on every init)
        guard proxyHost != host || proxyPort != port || proxyUsername != username ||
              proxyPassword != password || proxyEnabled != enabled || proxyProtocol != newProtocol else {
            return
        }
        proxyHost = host
        proxyPort = port
        proxyUsername = username
        proxyPassword = password
        proxyEnabled = enabled
        proxyProtocol = newProtocol
        // Recreate session with new proxy if no active downloads
        guard activeTasks.isEmpty else { return }
        backgroundSession.invalidateAndCancel()
        backgroundSession = createSession()
    }

    private func createSession() -> URLSession {
        let config = URLSessionConfiguration.background(withIdentifier: "com.dirxplore.background.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.shouldUseExtendedBackgroundIdleMode = true
        config.allowsCellularAccess = true
        if #available(iOS 13.0, *) {
            config.allowsExpensiveNetworkAccess = true
            config.allowsConstrainedNetworkAccess = true
        }
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 604800 // 7 days max for entire resource
        config.timeoutIntervalForRequest = 30 // 30s to establish connection or receive next packet
        if proxyEnabled && !proxyHost.isEmpty && proxyPort > 0 {
            var proxyDict: [String: Any]
            switch proxyProtocol {
            case "socks5", "socks4":
                proxyDict = [
                    "SOCKSEnable": 1,
                    "SOCKSProxy": proxyHost,
                    "SOCKSPort": proxyPort,
                ]
                if !proxyUsername.isEmpty {
                    proxyDict["SOCKSUser"] = proxyUsername
                    proxyDict["SOCKSPassword"] = proxyPassword
                }
            case "https":
                proxyDict = [
                    "HTTPSEnable": 1,
                    "HTTPSProxy": proxyHost,
                    "HTTPSPort": proxyPort,
                ]
                if !proxyUsername.isEmpty {
                    proxyDict["HTTPSUser"] = proxyUsername
                    proxyDict["HTTPSPassword"] = proxyPassword
                }
            default: // http
                proxyDict = [
                    "HTTPEnable": 1,
                    "HTTPProxy": proxyHost,
                    "HTTPPort": proxyPort,
                ]
                if !proxyUsername.isEmpty {
                    proxyDict["HTTPUser"] = proxyUsername
                    proxyDict["HTTPPassword"] = proxyPassword
                }
                // Also set HTTPS to same proxy for HTTPS URLs
                proxyDict["HTTPSEnable"] = 1
                proxyDict["HTTPSProxy"] = proxyHost
                proxyDict["HTTPSPort"] = proxyPort
            }
            config.connectionProxyDictionary = proxyDict
        }
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func startDownload(url: String, fileName: String, downloadId: String, saveDir: String? = nil) {
        if let dir = saveDir {
            saveDirMap[downloadId] = dir
            // Pre-create the download directory so it exists when file arrives
            let dirURL = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        downloadUrlMap[downloadId] = url
        fileNameMap[downloadId] = fileName
        guard let downloadUrl = URL(string: url) else {
            sendEvent(type: "error", downloadId: downloadId, data: ["message": "Invalid URL"])
            return
        }

        if let resumeData = resumeDataMap[downloadId] {
            let task = backgroundSession.downloadTask(withResumeData: resumeData)
            task.taskDescription = "\(downloadId)|\(fileName)"
            activeTasks[downloadId] = task
            taskIdMap[task.taskIdentifier] = downloadId
            resumeDataMap.removeValue(forKey: downloadId)
            task.resume()
            sendEvent(type: "resumed", downloadId: downloadId, data: ["fileName": fileName])
            if #available(iOS 16.2, *), liveActivityEnabled {
                updateLiveActivityStatus(downloadId: downloadId, fileName: fileName, progress: 0, status: "Downloading", isCompleted: false)
            }
        } else {
            var request = URLRequest(url: downloadUrl)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

            let task = backgroundSession.downloadTask(with: request)
            task.taskDescription = "\(downloadId)|\(fileName)"
            activeTasks[downloadId] = task
            taskIdMap[task.taskIdentifier] = downloadId
            progressMap[downloadId] = (0, 0)
            task.resume()
            sendEvent(type: "started", downloadId: downloadId, data: ["fileName": fileName, "url": url])
            if #available(iOS 16.2, *), liveActivityEnabled {
                createLiveActivity(downloadId: downloadId, fileName: fileName)
            }
        }
    }

    func pauseDownload(downloadId: String) {
        guard let task = activeTasks[downloadId] else {
            sendEvent(type: "error", downloadId: downloadId, data: ["message": "No active task to pause"])
            return
        }
        task.cancel { [weak self] possibleResumeData in
            guard let self = self else { return }
            if let resumeData = possibleResumeData {
                self.resumeDataMap[downloadId] = resumeData
            }
            self.activeTasks.removeValue(forKey: downloadId)
            self.taskIdMap.removeValue(forKey: task.taskIdentifier)
            self.sendEvent(type: "paused", downloadId: downloadId, data: [:])
            if #available(iOS 16.2, *), self.liveActivityEnabled {
                let progress = self.progressMap[downloadId].map { Double($0.0) / Double(max($0.1, 1)) } ?? 0
                let fileName = self.fileNameMap[downloadId] ?? "Downloading..."
                self.updateLiveActivityStatus(downloadId: downloadId, fileName: fileName, progress: progress, status: "Paused", isCompleted: false)
            }
        }
    }

    func cancelDownload(downloadId: String) {
        guard let task = activeTasks[downloadId] else {
            sendEvent(type: "cancelled", downloadId: downloadId, data: [:])
            if #available(iOS 16.2, *), liveActivityEnabled {
                endLiveActivity(downloadId: downloadId, finalProgress: 0, status: "Cancelled", isCompleted: false)
            }
            return
        }
        task.cancel()
        activeTasks.removeValue(forKey: downloadId)
        taskIdMap.removeValue(forKey: task.taskIdentifier)
        resumeDataMap.removeValue(forKey: downloadId)
        progressMap.removeValue(forKey: downloadId)
        retryCountMap.removeValue(forKey: downloadId)
        fileNameMap.removeValue(forKey: downloadId)
        sendEvent(type: "cancelled", downloadId: downloadId, data: [:])
        if #available(iOS 16.2, *), liveActivityEnabled {
            endLiveActivity(downloadId: downloadId, finalProgress: 0, status: "Cancelled", isCompleted: false)
        }
    }

    func cancelAll() {
        for (id, task) in activeTasks {
            task.cancel()
            taskIdMap.removeValue(forKey: task.taskIdentifier)
            resumeDataMap.removeValue(forKey: id)
            progressMap.removeValue(forKey: id)
            retryCountMap.removeValue(forKey: id)
            fileNameMap.removeValue(forKey: id)
        }
        activeTasks.removeAll()
    }

    func restorePendingTasks() {
        backgroundSession.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            for task in tasks {
                if let downloadTask = task as? URLSessionDownloadTask,
                   let desc = downloadTask.taskDescription {
                    let parts = desc.split(separator: "|", maxSplits: 1)
                    if parts.count == 2 {
                        let downloadId = String(parts[0])
                        let fileName = String(parts[1])
                        // Skip tasks already tracked from a fresh startDownload call
                        if self.activeTasks[downloadId] != nil { continue }
                        self.activeTasks[downloadId] = downloadTask
                        self.taskIdMap[downloadTask.taskIdentifier] = downloadId
                        self.sendEvent(type: "restored", downloadId: downloadId, data: ["fileName": fileName])
                    }
                }
            }
        }
    }

    private func sendEvent(type: String, downloadId: String, data: [String: Any]) {
        var event: [String: Any] = ["type": type, "downloadId": downloadId]
        event.merge(data) { (_, new) in new }
        if Thread.isMainThread {
            guard let sink = eventSink else {
                pendingEvents.append(event)
                return
            }
            sink(event)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let sink = self?.eventSink else {
                    self?.pendingEvents.append(event)
                    return
                }
                sink(event)
            }
        }
    }

    private func sendProgress(downloadId: String, received: Int64, total: Int64) {
        sendEvent(type: "progress", downloadId: downloadId, data: [
            "received": received,
            "total": total,
            "progress": total > 0 ? Double(received) / Double(total) : 0.0
        ])
    }

    // MARK: - Live Activity Manager (per-download Live Activities)

    private var liveActivities: [String: Activity<DownloadActivityAttributes>] = [:]
    private var activeDownloadCount: Int = 0
    private var lastLiveActivityUpdate: [String: Date] = [:]
    private var lastReportedProgress: [String: Int] = [:]

    @available(iOS 16.2, *)
    private func shouldThrottleLiveActivity(downloadId: String, progressPercent: Int) -> Bool {
        if let lastPct = lastReportedProgress[downloadId], lastPct == progressPercent {
            return true
        }
        if let lastUpdate = lastLiveActivityUpdate[downloadId],
           Date().timeIntervalSince(lastUpdate) < 0.5 {
            return true
        }
        return false
    }

    @available(iOS 16.2, *)
    private func createLiveActivity(downloadId: String, fileName: String) {
        guard liveActivityEnabled, liveActivities[downloadId] == nil else { return }
        let attributes = DownloadActivityAttributes(downloadId: downloadId)
        let state = DownloadActivityAttributes.ContentState(
            fileName: fileName,
            progress: 0,
            speed: "",
            eta: "--",
            downloadedSize: "",
            totalSize: "",
            status: "Queued",
            isCompleted: false
        )
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            liveActivities[downloadId] = activity
            lastReportedProgress[downloadId] = 0
            lastLiveActivityUpdate[downloadId] = Date()
        } catch {
            debugPrint("Failed to start Live Activity: \(error)")
            liveActivityErrorSink?(["event": "startError", "error": error.localizedDescription])
        }
    }

    @available(iOS 16.2, *)
    private func updateLiveActivityProgress(downloadId: String, received: Int64, total: Int64, fileName: String) {
        guard let activity = liveActivities[downloadId] else { return }
        let progress = total > 0 ? Double(received) / Double(total) : 0.0
        let progressPercent = Int(progress * 100)
        guard !shouldThrottleLiveActivity(downloadId: downloadId, progressPercent: progressPercent) else { return }

        lastReportedProgress[downloadId] = progressPercent
        lastLiveActivityUpdate[downloadId] = Date()

        let state = DownloadActivityAttributes.ContentState(
            fileName: fileName,
            progress: progress,
            speed: "",
            eta: "--",
            downloadedSize: formatBytes(received),
            totalSize: formatBytes(total),
            status: "Downloading",
            isCompleted: false
        )
        Task {
            await activity.update(using: state)
        }
    }

    @available(iOS 16.2, *)
    private func updateLiveActivityStatus(downloadId: String, fileName: String, progress: Double, status: String, isCompleted: Bool) {
        guard let activity = liveActivities[downloadId] else { return }
        let state = DownloadActivityAttributes.ContentState(
            fileName: fileName,
            progress: progress,
            speed: "",
            eta: "--",
            downloadedSize: "",
            totalSize: "",
            status: status,
            isCompleted: isCompleted
        )
        Task {
            await activity.update(using: state)
        }
    }

    @available(iOS 16.2, *)
    private func endLiveActivity(downloadId: String, finalProgress: Double, status: String, isCompleted: Bool) {
        guard let activity = liveActivities.removeValue(forKey: downloadId) else { return }
        lastReportedProgress.removeValue(forKey: downloadId)
        lastLiveActivityUpdate.removeValue(forKey: downloadId)

        let state = DownloadActivityAttributes.ContentState(
            fileName: "",
            progress: finalProgress,
            speed: "",
            eta: "--",
            downloadedSize: "",
            totalSize: "",
            status: status,
            isCompleted: isCompleted
        )
        Task {
            if isCompleted {
                await activity.update(using: state)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await activity.end(dismissalPolicy: .default)
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }

    @available(iOS 16.2, *)
    func endAllLiveActivities() {
        for (downloadId, activity) in liveActivities {
            Task {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
        liveActivities.removeAll()
        lastReportedProgress.removeAll()
        lastLiveActivityUpdate.removeAll()
        activeDownloadCount = 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }

    func downloadStateChanged(activeCount: Int, primaryInfo: [String: Any]?) {
        guard #available(iOS 16.2, *), liveActivityEnabled else { return }
        let previousCount = activeDownloadCount
        activeDownloadCount = activeCount

        if activeCount > 0 {
            if previousCount == 0 && liveActivities.isEmpty {
                let downloadId: String
                if let id = primaryInfo?["downloadId"] as? String {
                    downloadId = id
                } else if let firstId = activeTasks.keys.first {
                    downloadId = firstId
                } else {
                    downloadId = "active"
                }
                let fileName = primaryInfo?["fileName"] as? String ?? "Downloading..."
                createLiveActivity(downloadId: downloadId, fileName: fileName)
            }
        } else if previousCount > 0 {
            endAllLiveActivities()
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let downloadId = taskIdMap[downloadTask.taskIdentifier] else { return }
        progressMap[downloadId] = (totalBytesWritten, totalBytesExpectedToWrite)
        sendProgress(downloadId: downloadId, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        if #available(iOS 16.2, *), liveActivityEnabled {
            let fileName = fileNameMap[downloadId] ?? "Downloading..."
            updateLiveActivityProgress(downloadId: downloadId, received: totalBytesWritten, total: totalBytesExpectedToWrite, fileName: fileName)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let downloadId = taskIdMap[downloadTask.taskIdentifier],
              let desc = downloadTask.taskDescription else { return }
        let parts = desc.split(separator: "|", maxSplits: 1)
        guard parts.count == 2 else { return }
        let fileName = String(parts[1])

        let destinationDir: URL
        if let customDir = saveDirMap[downloadId] {
            destinationDir = URL(fileURLWithPath: customDir)
        } else if let persistentURL = persistentFolderURL {
            destinationDir = persistentURL
        } else {
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            destinationDir = documentsDir.appendingPathComponent("DirXplore", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let destinationUrl = destinationDir.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: destinationUrl)
        do {
            try FileManager.default.moveItem(at: location, to: destinationUrl)
            sendEvent(type: "completed", downloadId: downloadId, data: [
                "fileName": fileName,
                "savePath": destinationUrl.path
            ])
            if #available(iOS 16.2, *), liveActivityEnabled {
                endLiveActivity(downloadId: downloadId, finalProgress: 1.0, status: "Completed", isCompleted: true)
            }
        } catch {
            sendEvent(type: "error", downloadId: downloadId, data: ["message": "Failed to move file: \(error.localizedDescription)"])
            if #available(iOS 16.2, *), liveActivityEnabled {
                endLiveActivity(downloadId: downloadId, finalProgress: 0, status: "Failed", isCompleted: false)
            }
        }

        activeTasks.removeValue(forKey: downloadId)
        taskIdMap.removeValue(forKey: downloadTask.taskIdentifier)
        progressMap.removeValue(forKey: downloadId)
        retryCountMap.removeValue(forKey: downloadId)
        resumeDataMap.removeValue(forKey: downloadId)
        fileNameMap.removeValue(forKey: downloadId)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadId = taskIdMap[task.taskIdentifier] else { return }
        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled {
                if resumeDataMap[downloadId] == nil {
                    sendEvent(type: "cancelled", downloadId: downloadId, data: [:])
                    if #available(iOS 16.2, *), liveActivityEnabled {
                        endLiveActivity(downloadId: downloadId, finalProgress: 0, status: "Cancelled", isCompleted: false)
                    }
                }
            } else if error.domain == NSURLErrorDomain && error.userInfo[NSURLSessionDownloadTaskResumeData] != nil {
                let resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                if let data = resumeData {
                    resumeDataMap[downloadId] = data
                    sendEvent(type: "paused", downloadId: downloadId, data: ["resumable": true])
                } else {
                    sendEvent(type: "error", downloadId: downloadId, data: ["message": error.localizedDescription])
                }
            } else {
                let attempt = retryCountMap[downloadId] ?? 0
                if attempt < maxRetries, let downloadUrl = downloadUrlMap[downloadId] {
                    retryCountMap[downloadId] = attempt + 1
                    let parts = downloadId.split(separator: "|")
                    let fileName = parts.last ?? "file"
                    let delay = Double(1 << attempt)
                    debugPrint("Retrying download \(downloadId) in \(delay)s (attempt \(attempt + 1)/\(maxRetries))")
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self = self, self.retryCountMap[downloadId] != nil else { return }
                        let resumeData = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                        let newTask: URLSessionDownloadTask
                        if let data = resumeData {
                            newTask = self.backgroundSession.downloadTask(withResumeData: data)
                        } else {
                            var request = URLRequest(url: URL(string: downloadUrl)!)
                            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                            newTask = self.backgroundSession.downloadTask(with: request)
                        }
                        newTask.taskDescription = task.taskDescription ?? "\(downloadId)|\(fileName)"
                        self.activeTasks[downloadId] = newTask
                        self.taskIdMap[newTask.taskIdentifier] = downloadId
                        newTask.resume()
                        self.sendEvent(type: "resumed", downloadId: downloadId, data: ["fileName": fileName])
                    }
                } else {
                    sendEvent(type: "error", downloadId: downloadId, data: ["message": error.localizedDescription])
                    retryCountMap.removeValue(forKey: downloadId)
                    if #available(iOS 16.2, *), liveActivityEnabled {
                        let progress = progressMap[downloadId].map { Double($0.0) / Double(max($0.1, 1)) } ?? 0
                        endLiveActivity(downloadId: downloadId, finalProgress: progress, status: "Failed", isCompleted: false)
                    }
                }
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }

}

extension DownloadManager: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
