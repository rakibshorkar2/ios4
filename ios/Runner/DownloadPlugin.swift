import Flutter
import UIKit
import UserNotifications

class DownloadPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()

        let downloadChannel = FlutterMethodChannel(name: "com.dirxplore/ios_download", binaryMessenger: messenger)
        let instance = DownloadPlugin()
        registrar.addMethodCallDelegate(instance, channel: downloadChannel)

        let eventChannel = FlutterEventChannel(name: "com.dirxplore/ios_download_events", binaryMessenger: messenger)
        eventChannel.setStreamHandler(DownloadManager.shared)

        let liveActivityChannel = FlutterMethodChannel(name: "com.dirxplore/live_activity", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(instance, channel: liveActivityChannel)

        let liveActivityErrorChannel = FlutterEventChannel(name: "com.dirxplore/live_activity_errors", binaryMessenger: messenger)
        liveActivityErrorChannel.setStreamHandler(instance)

        let proxyChannel = FlutterMethodChannel(name: "com.dirxplore/proxy_config", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(instance, channel: proxyChannel)

        let notificationChannel = FlutterMethodChannel(name: "com.dirxplore/notifications", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(instance, channel: notificationChannel)

        let backgroundChannel = FlutterMethodChannel(name: "com.dirxplore/background_services", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(instance, channel: backgroundChannel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // Download methods
        case "startDownload":
            if let args = call.arguments as? [String: Any],
               let url = args["url"] as? String,
               let fileName = args["fileName"] as? String,
               let downloadId = args["downloadId"] as? String {
                let saveDir = args["saveDir"] as? String
                DownloadManager.shared.startDownload(url: url, fileName: fileName, downloadId: downloadId, saveDir: saveDir)
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing parameters", details: nil))
            }

        case "pauseDownload":
            if let args = call.arguments as? [String: Any],
               let downloadId = args["downloadId"] as? String {
                DownloadManager.shared.pauseDownload(downloadId: downloadId)
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing downloadId", details: nil))
            }

        case "cancelDownload":
            if let args = call.arguments as? [String: Any],
               let downloadId = args["downloadId"] as? String {
                DownloadManager.shared.cancelDownload(downloadId: downloadId)
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing downloadId", details: nil))
            }

        case "cancelAll":
            DownloadManager.shared.cancelAll()
            result(true)

        case "getSavePath":
            if let persistentURL = DownloadManager.shared.persistentFolderURL {
                result(persistentURL.path)
            } else {
                let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dir = documentsDir.appendingPathComponent("DirXplore", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                result(dir.path)
            }

        case "openFileLocation":
            if let args = call.arguments as? [String: Any],
               let path = args["path"] as? String {
                let fileURL = URL(fileURLWithPath: path)
                DispatchQueue.main.async {
                    self.presentActivityVC(items: [fileURL])
                }
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
            }

        case "openURL":
            if let args = call.arguments as? [String: Any],
               let urlStr = args["url"] as? String,
               let url = URL(string: urlStr) {
                DispatchQueue.main.async {
                    self.presentActivityVC(items: [url])
                }
            }
            result(nil)

        case "saveToFiles":
            if let args = call.arguments as? [String: Any],
               let path = args["path"] as? String {
                let fileURL = URL(fileURLWithPath: path)
                DispatchQueue.main.async {
                    let docPicker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
                    self.presentVC(docPicker)
                }
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
            }

        case "pickDownloadFolder":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
                self.presentVC(picker)
            }

        case "getPersistentDownloadFolder":
            guard let bookmarkData = UserDefaults.standard.data(forKey: "persistentDownloadFolderBookmark") else {
                result(nil)
                return
            }
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    let accessOK = url.startAccessingSecurityScopedResource()
                    defer { if accessOK { url.stopAccessingSecurityScopedResource() } }
                    let newBookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(newBookmark, forKey: "persistentDownloadFolderBookmark")
                }
                result(url.path)
            } catch {
                result(nil)
            }

        // Live Activity methods
        case "isSupported":
            if #available(iOS 16.1, *) {
                result(true)
            } else {
                result(false)
            }

        case "enable":
            DownloadManager.shared.liveActivityEnabled = true
            result(true)

        case "disable":
            DownloadManager.shared.liveActivityEnabled = false
            if #available(iOS 16.2, *) {
                DownloadManager.shared.endAllLiveActivities()
            }
            result(true)

        case "isEnabled":
            result(DownloadManager.shared.liveActivityEnabled)

        case "updateActiveDownloads":
            if let args = call.arguments as? [String: Any],
               let count = args["count"] as? Int {
                let primary = args["primary"] as? [String: Any]
                DownloadManager.shared.downloadStateChanged(activeCount: count, primaryInfo: primary)
            }
            result(nil)

        // Proxy methods
        case "setProxy":
            if let args = call.arguments as? [String: Any] {
                let host = args["host"] as? String ?? ""
                let port = args["port"] as? Int ?? 0
                let username = args["username"] as? String ?? ""
                let password = args["password"] as? String ?? ""
                let protocolStr = args["protocol"] as? String ?? "http"
                let enabled = args["enabled"] as? Bool ?? false
                DownloadManager.shared.setProxy(host: host, port: port, username: username, password: password, enabled: enabled, protocol: protocolStr)
            }
            result(nil)

        // Notification methods
        case "show":
            if let args = call.arguments as? [String: Any],
               let title = args["title"] as? String,
               let body = args["body"] as? String {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
            result(nil)

        // Background Services
        case "startBackgroundServices":
            BackgroundAudioService.shared.start()
            BackgroundLocationService.shared.start()
            result(nil)

        case "stopBackgroundServices":
            BackgroundAudioService.shared.stop()
            BackgroundLocationService.shared.stop()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func presentActivityVC(items: [Any]) {
        guard let vc = rootVC() else { return }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.present(activityVC, animated: true)
    }

    private func presentVC(_ viewController: UIViewController) {
        guard let vc = rootVC() else { return }
        vc.present(viewController, animated: true)
    }

    private func rootVC() -> UIViewController? {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.keyWindow?.rootViewController
        }
        return nil
    }

    // MARK: - FlutterStreamHandler (Live Activity errors)

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        DownloadManager.shared.liveActivityErrorSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        DownloadManager.shared.liveActivityErrorSink = nil
        return nil
    }
}
