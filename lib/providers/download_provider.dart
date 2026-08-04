import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:disk_space_2/disk_space_2.dart';
import '../models/download_item.dart';
import '../services/dio_client.dart';
import '../services/html_parser.dart';
import '../services/database_helper.dart';
import '../models/directory_item.dart';

enum DownloadLinkRefreshResult { updated, noMatch, updateFailed }

class _ResumeNotSupportedException implements Exception {
  const _ResumeNotSupportedException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _DownloadInterruptedException implements Exception {
  const _DownloadInterruptedException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DownloadProvider with ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.example.dirBrowser/downloads');
  static const MethodChannel _iosChannel =
      MethodChannel('com.dirxplore/ios_download');
  static const EventChannel _iosEvents =
      EventChannel('com.dirxplore/ios_download_events');
  static const MethodChannel _liveActivityChannel =
      MethodChannel('com.dirxplore/live_activity');
  static const EventChannel _liveActivityErrorChannel =
      EventChannel('com.dirxplore/live_activity_errors');
  static const MethodChannel _iosNotificationChannel =
      MethodChannel('com.dirxplore/notifications');
  static const MethodChannel _backgroundServiceChannel =
      MethodChannel('com.dirxplore/background_services');
  StreamSubscription? _iosEventSub;
  StreamSubscription? _liveActivityErrorSub;

  final bool _isIOS = Platform.isIOS;

  final List<DownloadItem> _queue = [];
  final Map<String, CancelToken> _cancelTokens = {};
  int _maxConcurrent = 3;
  int _activeCount = 0;
  DateTime _lastNotifyTime = DateTime.now();
  DateTime _lastSaveTime = DateTime.now();
  double _totalStorage = 0;
  double _freeStorage = 0;
  bool _isProcessingQueue = false;
  void Function()? onAllDownloadsComplete;

  bool _backgroundServicesRunning = false;

  double get totalStorage => _totalStorage;
  double get freeStorage => _freeStorage;

  Future<void> updateStorageInfo() async {
    try {
      _totalStorage = await DiskSpace.getTotalDiskSpace ?? 0;
      _freeStorage = await DiskSpace.getFreeDiskSpace ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Storage update error: $e');
    }
  }

  // Selection State
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  List<DownloadItem> get queue => _queue;
  Set<String> get selectedIds => _selectedIds;
  bool get isSelectionMode => _isSelectionMode;

  Future<void> init() async {
    await _loadQueue();
    await updateStorageInfo();
    _channel.setMethodCallHandler(_handleNotificationAction);

    if (_isIOS) {
      _iosEventSub = _iosEvents.receiveBroadcastStream().listen(_handleiOSEvent);
      _liveActivityErrorSub = _liveActivityErrorChannel.receiveBroadcastStream().listen((event) {
        debugPrint('Live Activity error: $event');
      });
      _iosChannel.invokeMethod('getSavePath').then((path) {
        if (path is String) {
          debugPrint('iOS save path: $path');
        }
      }).catchError((e) { debugPrint('Channel method error: $e'); });
      enableLiveActivity();
    }
  }

  void _handleiOSEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;
    final downloadId = event['downloadId'] as String?;
    if (downloadId == null) return;

    final item = _queue.firstWhere(
      (i) => i.id == downloadId,
      orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''),
    );
    if (item.id.isEmpty) return;

    switch (type) {
      case 'started':
        item.status = DownloadStatus.downloading;
        notifyListeners();
        break;
      case 'restored':
        _activeCount++;
        item.status = DownloadStatus.downloading;
        notifyListeners();
        break;
      case 'progress':
        final received = event['received'] as int? ?? 0;
        final total = event['total'] as int? ?? 0;
        final dt = DateTime.now();
        if (item.downloadedBytes > 0) {
          final diff = received - item.downloadedBytes;
          final timeDiff = dt.difference(_lastNotifyTime).inMilliseconds;
          if (timeDiff > 0) {
            item.speedBytesPerSec = (item.speedBytesPerSec * 0.7) + ((diff / (timeDiff / 1000)) * 0.3);
          }
        }
        item.downloadedBytes = received;
        item.totalBytes = total;
        if (item.speedBytesPerSec > 0 && total > 0) {
          item.etaSeconds = ((total - received) / item.speedBytesPerSec).round();
        }
        if (dt.difference(_lastNotifyTime).inMilliseconds > 250) {
          _lastNotifyTime = dt;
          notifyListeners();
        }
        DatabaseHelper().updateDownload(item);
        break;
      case 'completed':
        item.status = DownloadStatus.done;
        item.speedBytesPerSec = 0;
        item.etaSeconds = 0;
        item.downloadedBytes = item.totalBytes;
        if (_activeCount > 0) _activeCount--;
        final savePath = event['savePath'] as String?;
        if (savePath != null) {
          item.savePath = savePath;
        }
        DatabaseHelper().updateDownload(item);
        updateStorageInfo();
        notifyListeners();
        _processQueue();
        break;
      case 'paused':
        item.status = DownloadStatus.paused;
        item.speedBytesPerSec = 0;
        if (_activeCount > 0) _activeCount--;
        DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        break;
      case 'cancelled':
        _queue.removeWhere((i) => i.id == downloadId);
        DatabaseHelper().deleteDownload(downloadId);
        if (_activeCount > 0) _activeCount--;
        if (_activeCount == 0) _stopForegroundIfNoActive();
        notifyListeners();
        _processQueue();
        break;
      case 'error':
        item.status = DownloadStatus.error;
        item.errorMessage = event['message'] as String? ?? 'Download failed';
        if (_activeCount > 0) _activeCount--;
        DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        break;
      case 'resumed':
        item.status = DownloadStatus.downloading;
        notifyListeners();
        break;
    }
    _syncLiveActivityState();
  }

  @override
  void dispose() {
    _iosEventSub?.cancel();
    super.dispose();
  }

  Future<void> _handleNotificationAction(MethodCall call) async {
    if (call.method == 'onNotificationAction') {
      final String action = call.arguments['action'];
      // final int notificationId = call.arguments['id']; // Unused for now as we use fixed ID 1001

      // For now, we assume 1001 is the active download.
      // In a multi-notification setup, we'd map notificationId to download ID.
      // Since currently startForegroundService uses a fixed ID 1001:
      final activeItem = _queue.firstWhere(
        (i) => i.status == DownloadStatus.downloading,
        orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''),
      );

      if (activeItem.id.isNotEmpty) {
        if (action == 'pause') {
          pause(activeItem.id);
        } else if (action == 'resume') {
          resume(activeItem.id);
        } else if (action == 'cancel') {
          stop(activeItem.id);
        }
      }
    }
  }

  Future<void> _loadQueue() async {
    _queue.clear();
    _activeCount = 0;
    _queue.addAll(await DatabaseHelper().getDownloads());
    for (final item in _queue) {
      if (item.status == DownloadStatus.downloading) {
        item.status = DownloadStatus.queued;
        await DatabaseHelper().updateDownload(item);
      }
    }
    notifyListeners();
    _processQueue();
  }

  Future<void> _saveQueue() async {
    // With SQLite, we update items individually.
    // This method can remain as a legacy call or trigger bulk sync if needed.
  }

  void setMaxConcurrent(int max) {
    _maxConcurrent = max;
    _processQueue();
  }

  Future<void> addDownload(String url, String fileName, String saveDir,
      {String? batchId, String? batchName, String? originalUrl,
      Map<String, String>? customHeaders,
      List<String>? mirrorUrls,
      DownloadCategory? category,
      ScheduleType? scheduleType,
      DateTime? scheduledAt,
      int? maxRetries,
      String? expectedMd5,
      String? expectedSha1,
      String? expectedSha256,
      int? redirectCount,
      String? resolvedUrl}) async {
    if (_queue.any((i) => i.url == url)) {
      final existing = _queue.firstWhere((i) => i.url == url);
      if (existing.status == DownloadStatus.paused ||
          existing.status == DownloadStatus.error) {
        resume(existing.id);
      }
      return;
    }

    final id = '${DateTime.now().millisecondsSinceEpoch}_${url.hashCode}';

    String finalSaveDir = saveDir;
    final prefs = await SharedPreferences.getInstance();
    final bool autoCategorize = prefs.getBool('autoCategorizeEnabled') ?? true;
    final bool smartRouting = prefs.getBool('smartFolderRouting') ?? false;

    final cat = category ?? (autoCategorize ? DownloadCategory.fromFileName(fileName) : DownloadCategory.other);

    if (smartRouting) {
      String subDir;
      switch (cat) {
        case DownloadCategory.movies: subDir = 'Movies'; break;
        case DownloadCategory.tvShows: subDir = 'TV Shows'; break;
        case DownloadCategory.music: subDir = 'Music'; break;
        case DownloadCategory.images: subDir = 'Images'; break;
        case DownloadCategory.documents: subDir = 'Documents'; break;
        case DownloadCategory.archives: subDir = 'Archives'; break;
        case DownloadCategory.apps: subDir = 'Apps'; break;
        case DownloadCategory.other: subDir = 'Others'; break;
      }
      finalSaveDir = p.join(saveDir, subDir);
    }

    if (batchName != null && batchName.trim().isNotEmpty) {
      finalSaveDir = p.join(finalSaveDir, batchName.trim());
    }

    final savePath = p.join(finalSaveDir, fileName);

    final String? headersJson = customHeaders != null && customHeaders.isNotEmpty
        ? jsonEncode(customHeaders) : null;
    final String? mirrorsJson = mirrorUrls != null && mirrorUrls.isNotEmpty
        ? jsonEncode(mirrorUrls) : null;

    final prefsRetry = prefs.getInt('retryCount') ?? 3;
    final itemMaxRetries = maxRetries ?? prefsRetry;

    _queue.add(DownloadItem(
      id: id,
      url: url,
      originalUrl: originalUrl,
      fileName: fileName,
      savePath: savePath,
      batchId: batchId,
      batchName: batchName,
      customHeadersJson: headersJson,
      mirrorUrlsJson: mirrorsJson,
      category: cat,
      scheduleType: scheduleType ?? ScheduleType.immediate,
      scheduledAt: scheduledAt,
      maxRetries: itemMaxRetries,
      expectedMd5: expectedMd5,
      expectedSha1: expectedSha1,
      expectedSha256: expectedSha256,
      redirectCount: redirectCount ?? 0,
      resolvedUrl: resolvedUrl,
    ));

    await DatabaseHelper().insertDownload(_queue.last);
    await updateStorageInfo();
    notifyListeners();
    _processQueue();
  }

  Future<List<DirectoryItem>> crawlFolder(
      String folderUrl, String folderName) async {
    final List<DirectoryItem> allItems = [];
    await _crawlRecursive(folderUrl, allItems);
    return allItems;
  }

  Future<void> _crawlRecursive(
      String folderUrl, List<DirectoryItem> results) async {
    try {
      final dio = DioClient().dio;
      final response = await dio.get(folderUrl);
      final htmlStr = response.data.toString();
      final items =
          await HtmlParserService.parseApacheDirectoryAsync(htmlStr, folderUrl);

      for (var item in items) {
        if (item.isDirectory) {
          await _crawlRecursive(item.url, results);
        } else {
          results.add(item);
        }
      }
    } catch (e) {
      debugPrint("Crawl error: $e");
    }
  }

  void addRecursiveDownload(
      String folderUrl, String folderName, String baseSaveDir) async {
    // Legacy support: auto-queueing movies/subs
    final items = await crawlFolder(folderUrl, folderName);
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();

    for (var item in items) {
      final ext = item.name.split('.').last.toLowerCase();
      if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'srt', 'vtt', 'sub']
          .contains(ext)) {
        addDownload(item.url, item.name, baseSaveDir,
            batchId: batchId, batchName: folderName);
      }
    }
  }

  void pause(String id) {
    if (!_queue.any((i) => i.id == id)) return;
    final item = _queue.firstWhere((i) => i.id == id);

    if (item.status == DownloadStatus.downloading) {
      _cancelTokens[id]?.cancel('Paused by user');
      _cancelTokens.remove(id);
      item.status = DownloadStatus.paused;
      item.speedBytesPerSec = 0;
      notifyListeners();
    } else {
      item.status = DownloadStatus.paused;
      item.speedBytesPerSec = 0;
      _saveQueue();
      updateStorageInfo();
      notifyListeners();
    }
    _syncLiveActivityState();
  }

  void _stopForegroundIfNoActive() {
    if (_activeCount <= 1) {
      // 1 because we are about to decrement
      _channel.invokeMethod(
          'stopForegroundService', {'id': 1001}).catchError((e) { debugPrint('Channel method error: $e'); });
    }
  }

  void resume(String id) {
    final item = _queue.firstWhere((i) => i.id == id);
    item.status = DownloadStatus.queued;
    item.errorMessage = null;
    _saveQueue();
    notifyListeners();
    _processQueue();
    _syncLiveActivityState();
  }

  void stop(String id) {
    if (!_queue.any((i) => i.id == id)) return;
    final item = _queue.firstWhere((i) => i.id == id);

    if (item.status == DownloadStatus.downloading) {
      _cancelTokens[id]?.cancel('Stopped by user');
      _cancelTokens.remove(id);
    }

    _queue.removeWhere((i) => i.id == id);
    DatabaseHelper().deleteDownload(id);
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _syncLiveActivityState();
  }

  void resumeBatch(String batchId) {
    bool hasResumed = false;
    for (var i in _queue) {
      if (i.batchId == batchId &&
          (i.status == DownloadStatus.paused ||
              i.status == DownloadStatus.error)) {
        i.status = DownloadStatus.queued;
        i.errorMessage = null;
        DatabaseHelper().updateDownload(i);
        hasResumed = true;
      }
    }
    if (hasResumed) {
      _saveQueue();
      notifyListeners();
      _processQueue();
      _syncLiveActivityState();
    }
  }

  void pauseBatch(String batchId) {
    bool hasPaused = false;
    for (var i in _queue) {
      if (i.batchId == batchId) {
        if (i.status == DownloadStatus.downloading) {
          _cancelTokens[i.id]?.cancel('Paused by user');
          _cancelTokens.remove(i.id);
          i.status = DownloadStatus.paused;
          i.speedBytesPerSec = 0;
          hasPaused = true;
        } else if (i.status == DownloadStatus.queued) {
          i.status = DownloadStatus.paused;
          hasPaused = true;
        }
        DatabaseHelper().updateDownload(i);
      }
    }
    if (hasPaused) {
      _saveQueue();
      notifyListeners();
      _syncLiveActivityState();
    }
  }

  void stopBatch(String batchId) {
    final batchItems = _queue.where((i) => i.batchId == batchId).toList();
    for (var i in batchItems) {
      if (i.status == DownloadStatus.downloading) {
        _cancelTokens[i.id]?.cancel('Stopped by user');
        _cancelTokens.remove(i.id);
      }
      DatabaseHelper().deleteDownload(i.id);
    }
    _queue.removeWhere((i) => i.batchId == batchId);
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _syncLiveActivityState();
  }

  void clearDone() {
    _queue.removeWhere((i) =>
        i.status == DownloadStatus.done || i.status == DownloadStatus.error);
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _syncLiveActivityState();
  }

  void clearAll() {
    for (final token in _cancelTokens.values) {
      token.cancel('Cleared');
    }
    _cancelTokens.clear();
    _queue.clear();
    _activeCount = 0;
    _isSelectionMode = false;
    _selectedIds.clear();
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _syncLiveActivityState();
  }

  // --- Selection Features ---

  void toggleSelectionMode() {
    _isSelectionMode = !_isSelectionMode;
    if (!_isSelectionMode) {
      _selectedIds.clear();
    }
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedIds.add(id);
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedIds.clear();
    _selectedIds.addAll(_queue.map((e) => e.id));
    _isSelectionMode = true;
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  void deleteSelected({bool deleteFiles = false}) {
    for (String id in _selectedIds) {
      _cancelTokens[id]?.cancel('Deleted by user');
      _cancelTokens.remove(id);

      if (deleteFiles) {
        final itemIndex = _queue.indexWhere((i) => i.id == id);
        if (itemIndex != -1) {
          final f = File(_queue[itemIndex].savePath);
          if (f.existsSync()) {
            f.deleteSync();
          }
        }
      }

      _queue.removeWhere((i) => i.id == id);
    }

    // Recalculate active count if we deleted running items
    _activeCount =
        _queue.where((i) => i.status == DownloadStatus.downloading).length;
    if (_activeCount == 0) {
      _stopForegroundIfNoActive();
    }

    _selectedIds.clear();
    _isSelectionMode = false;
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _processQueue();
  }

  void pauseAll() {
    // 1. Cancel all active transfers
    for (final id in _cancelTokens.keys.toList()) {
      _cancelTokens[id]?.cancel('Paused by user');
      _cancelTokens.remove(id);
    }

    // 2. Set all queued items to paused
    for (final item in _queue) {
      if (item.status == DownloadStatus.queued ||
          item.status == DownloadStatus.downloading) {
        item.status = DownloadStatus.paused;
        item.speedBytesPerSec = 0;
      }
    }

    _activeCount = 0;
    _stopForegroundIfNoActive();
    _saveQueue();
    notifyListeners();
    _syncLiveActivityState();
  }

  void resumeAll() {
    for (final item in _queue) {
      if (item.status == DownloadStatus.paused ||
          item.status == DownloadStatus.error) {
        resume(item.id);
      }
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final wifiOnly = prefs.getBool('downloadOnWifiOnly') == true;
      final lowBatteryPause = prefs.getBool('pauseLowBattery') == true;
      _maxConcurrent = prefs.getInt('maxConcurrent') ?? 1;

      while (_activeCount < _maxConcurrent) {
        final now = DateTime.now();
        final nextItem = _queue.firstWhere(
          (i) => i.status == DownloadStatus.queued &&
              (i.scheduleType != ScheduleType.scheduled ||
               (i.scheduledAt != null && i.scheduledAt!.isBefore(now))),
          orElse: () =>
              DownloadItem(id: '', url: '', fileName: '', savePath: ''),
        );

        if (nextItem.id.isEmpty) break; // Nothing to download

        // 1. Charging Only Check
        if (nextItem.scheduleType == ScheduleType.chargingOnly) {
          // On iOS we can't easily detect charging status, skip this for now
        }

        // 2. Wi-Fi Check
        if (wifiOnly || nextItem.scheduleType == ScheduleType.wifiOnly) {
          var connectivityResult = await (Connectivity().checkConnectivity());
          if (!connectivityResult.contains(ConnectivityResult.wifi)) {
            nextItem.status = DownloadStatus.paused;
            nextItem.errorMessage = 'Paused: Waiting for Wi-Fi';
            DatabaseHelper().updateDownload(nextItem);
            notifyListeners();
            continue;
          }
        }

        // 2. Battery Check
        if (lowBatteryPause) {
          final battery = Battery();
          final level = await battery.batteryLevel;
          if (level < 15) {
            nextItem.status = DownloadStatus.paused;
            nextItem.errorMessage = 'Paused: Battery below 15%';
            DatabaseHelper().updateDownload(nextItem);
            notifyListeners();
            continue;
          }
        }

        _startDownload(nextItem);
      }
    } finally {
      _isProcessingQueue = false;
      _syncLiveActivityState();
    }
  }

  // --- Link Refresh ---
  Future<bool> refreshLink(String id, String newUrl) async {
    final item = _queue.firstWhere((i) => i.id == id,
        orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''));
    if (item.id.isEmpty) return false;

    if (item.status == DownloadStatus.downloading) {
      _cancelTokens[id]?.cancel('Link refreshed');
      _cancelTokens.remove(id);
    }

    final originalUrl = item.originalUrl ?? item.url;
    try {
      final resolvedUrl = await DioClient().resolveRedirects(newUrl);
      final dio = DioClient().dio;
      final headResponse = await dio.head(resolvedUrl);
      final totalHeader = headResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '-1';
      final total = int.tryParse(totalHeader) ?? -1;
      final acceptRanges = headResponse.headers.value(HttpHeaders.acceptRangesHeader);
      final resumeSupported = acceptRanges?.toLowerCase() == 'bytes';

      if (resumeSupported && item.downloadedBytes > 0 && total > 0 && item.downloadedBytes < total) {
        item.url = resolvedUrl;
        item.originalUrl = originalUrl;
        item.totalBytes = total;
        item.retryCount = 0;
        item.errorMessage = null;
        item.status = DownloadStatus.queued;
        await DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        return true;
      } else if (item.downloadedBytes > 0) {
        item.downloadedBytes = 0;
        item.url = resolvedUrl;
        item.originalUrl = originalUrl;
        item.totalBytes = total;
        item.retryCount = 0;
        item.errorMessage = 'Server does not support resume. Download will restart.';
        item.status = DownloadStatus.queued;
        await DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        return true;
      } else {
        item.url = resolvedUrl;
        item.originalUrl = originalUrl;
        item.totalBytes = total;
        item.retryCount = 0;
        item.errorMessage = null;
        item.status = DownloadStatus.queued;
        await DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        return true;
      }
    } catch (e) {
      item.errorMessage = 'Invalid or expired link: $e';
      item.status = DownloadStatus.error;
      await DatabaseHelper().updateDownload(item);
      notifyListeners();
      return false;
    }
  }

  // --- Update Download Link ---
  Future<void> updateDownloadUrl(String downloadId, String newUrl,
      {String? expectedFileName}) async {
    debugPrint('Updating download URL...');

    final trimmed = newUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (trimmed.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Invalid URL. Only http:// or https:// links are allowed.');
    }

    final index = _queue.indexWhere((i) => i.id == downloadId);
    if (index == -1) {
      throw StateError('Unable to update download link');
    }

    final item = _queue[index];
    debugPrint('Old URL: ${item.url}');
    debugPrint('New URL: $trimmed');

    try {
      final dio = DioClient().dio;
      final headHeaders = <String, dynamic>{};
      if (item.customHeaders.isNotEmpty) {
        headHeaders.addAll(item.customHeaders);
      }
      final headResponse = await dio.head(
        trimmed,
        options: Options(headers: headHeaders.isNotEmpty ? headHeaders : null),
      );
      final headers = headResponse.headers;
      final newTotal = int.tryParse(
              headers.value(HttpHeaders.contentLengthHeader) ?? '-1') ??
          -1;
      final newEtag = headers.value(HttpHeaders.etagHeader);
      final newMime =
          headers.value(HttpHeaders.contentTypeHeader)?.split(';').first.trim();
      final newLastModified = headers.value(HttpHeaders.lastModifiedHeader);
      final newCdName = _filenameFromContentDisposition(
          headers.value('content-disposition'));
      final acceptRanges = headers.value(HttpHeaders.acceptRangesHeader);

      // --- File identity verification ---
      final oldDriveId = _extractDriveFileId(item.url);
      final newDriveId = _extractDriveFileId(trimmed);
      final sameDriveId =
          oldDriveId != null && newDriveId != null && oldDriveId == newDriveId;

      // Google Drive file IDs are the strongest identifier: a different ID
      // means a different file, no matter what the other headers say.
      if (oldDriveId != null && newDriveId != null && oldDriveId != newDriveId) {
        debugPrint('Metadata mismatch');
        throw StateError('The new download link belongs to a different file.');
      }

      // When no stable file ID is available, compare every other identifier.
      if (!sameDriveId) {
        // Expected total size
        if (item.totalBytes > 0 &&
            newTotal > 0 &&
            _sizeMismatch(item.totalBytes, newTotal)) {
          debugPrint('Metadata mismatch');
          throw StateError('The new download link belongs to a different file.');
        }
        // Filename (Content-Disposition or expected file name)
        final expectedName = expectedFileName ?? item.fileName;
        if (newCdName != null &&
            expectedName.isNotEmpty &&
            !_sameFileName(newCdName, expectedName)) {
          debugPrint('Metadata mismatch');
          throw StateError('The new download link belongs to a different file.');
        }
        // MIME type
        if (item.mimeType != null &&
            newMime != null &&
            newMime.isNotEmpty &&
            item.mimeType != newMime) {
          debugPrint('Metadata mismatch');
          throw StateError('The new download link belongs to a different file.');
        }
        // ETag
        if (item.etag != null &&
            newEtag != null &&
            newEtag.isNotEmpty &&
            item.etag != newEtag) {
          debugPrint('Metadata mismatch');
          throw StateError('The new download link belongs to a different file.');
        }
        // Last-Modified
        if (item.lastModified != null &&
            newLastModified != null &&
            newLastModified.isNotEmpty &&
            item.lastModified != newLastModified) {
          debugPrint('Metadata mismatch');
          throw StateError('The new download link belongs to a different file.');
        }
      }

      // --- Resume support verification (only with a partial file) ---
      final partialFile = File(item.savePath);
      if (item.downloadedBytes > 0 && await partialFile.exists()) {
        debugPrint('Verifying resume support');
        if (acceptRanges?.toLowerCase() != 'bytes') {
          throw StateError('This download link cannot resume.');
        }
        debugPrint('Resume supported');
      }

      // Replace only the stored URL. Everything else (id, filename, local
      // file, downloaded bytes, total bytes, progress, metadata) is kept.
      if (item.status == DownloadStatus.downloading) {
        _cancelTokens[item.id]?.cancel('Link refreshed');
        _cancelTokens.remove(item.id);
      }
      item.url = trimmed;
      item.errorMessage = null;
      await DatabaseHelper().updateDownload(item);
      notifyListeners();

      debugPrint('Resuming from byte ${item.downloadedBytes}');
      resume(downloadId);
      debugPrint('Resume successful');
    } on StateError {
      rethrow;
    } catch (e) {
      debugPrint('Link update failed: $e');
      throw StateError('Unable to update download link');
    }
  }

  // --- Automatic link refresh (BRWSR tab) ---
  Future<DownloadLinkRefreshResult> autoRefreshMatchingDownload(
      String url, String fileName,
      {Map<String, String>? customHeaders}) async {
    final match =
        await _findMatchingDownload(url, fileName, customHeaders: customHeaders);
    if (match == null) {
      return DownloadLinkRefreshResult.noMatch;
    }
    debugPrint('Matching file found');
    debugPrint('Updating URL automatically');
    try {
      await updateDownloadUrl(match.id, url, expectedFileName: fileName);
      return DownloadLinkRefreshResult.updated;
    } catch (e) {
      debugPrint('Automatic link update failed: $e');
      return DownloadLinkRefreshResult.updateFailed;
    }
  }

  Future<DownloadItem?> _findMatchingDownload(String url, String fileName,
      {Map<String, String>? customHeaders}) async {
    debugPrint('Searching for matching download...');
    final incomingDriveId = _extractDriveFileId(url);

    int? incomingTotal;
    String? incomingEtag;
    String? incomingMime;
    String? incomingLastModified;
    String? incomingCdName;
    try {
      final dio = DioClient().dio;
      final headHeaders = <String, dynamic>{};
      if (customHeaders != null && customHeaders.isNotEmpty) {
        headHeaders.addAll(customHeaders);
      }
      final headResponse = await dio.head(
        url,
        options: Options(headers: headHeaders.isNotEmpty ? headHeaders : null),
      );
      final headers = headResponse.headers;
      incomingTotal = int.tryParse(
          headers.value(HttpHeaders.contentLengthHeader) ?? '-1');
      incomingEtag = headers.value(HttpHeaders.etagHeader);
      incomingMime =
          headers.value(HttpHeaders.contentTypeHeader)?.split(';').first.trim();
      incomingLastModified = headers.value(HttpHeaders.lastModifiedHeader);
      incomingCdName = _filenameFromContentDisposition(
          headers.value('content-disposition'));
    } catch (e) {
      debugPrint('Incoming link metadata fetch failed: $e');
    }

    DownloadItem? bestMatch;
    int bestScore = 0;
    for (final item in _queue) {
      // Only Downloading / Paused / Waiting / Failed items can be refreshed.
      if (item.status == DownloadStatus.done || item.id.isEmpty) continue;
      final score = _matchConfidence(
        item,
        url,
        fileName,
        incomingDriveId,
        incomingTotal,
        incomingEtag,
        incomingMime,
        incomingCdName,
        incomingLastModified,
      );
      if (score > bestScore) {
        bestScore = score;
        bestMatch = item;
      }
    }
    if (bestMatch == null || bestScore < 60) return null;
    return bestMatch;
  }

  int _matchConfidence(
    DownloadItem item,
    String newUrl,
    String fileName,
    String? incomingDriveId,
    int? incomingTotal,
    String? incomingEtag,
    String? incomingMime,
    String? incomingCdName,
    String? incomingLastModified,
  ) {
    int score = 0;
    final itemDriveId = _extractDriveFileId(item.url);

    if (itemDriveId != null && incomingDriveId != null) {
      if (itemDriveId == incomingDriveId) {
        score += 100;
      } else {
        return -1; // Definite mismatch.
      }
    }

    final itemName = item.fileName.toLowerCase();
    final fileNameMatches =
        fileName.isNotEmpty && itemName == fileName.toLowerCase();
    final cdNameMatches =
        incomingCdName != null && itemName == incomingCdName.toLowerCase();
    if (fileNameMatches || cdNameMatches) {
      score += 30;
    }

    if (item.totalBytes > 0 && incomingTotal != null && incomingTotal > 0) {
      if (!_sizeMismatch(item.totalBytes, incomingTotal)) {
        score += 30;
      } else if (itemDriveId == null || incomingDriveId == null) {
        return -1; // Sizes conflict and no stable id to disambiguate.
      }
    }

    if (item.etag != null && incomingEtag != null && incomingEtag.isNotEmpty) {
      if (item.etag == incomingEtag) {
        score += 30;
      } else if (itemDriveId == null || incomingDriveId == null) {
        return -1;
      }
    }

    if (item.mimeType != null &&
        incomingMime != null &&
        incomingMime.isNotEmpty &&
        item.mimeType == incomingMime) {
      score += 20;
    }

    if (item.lastModified != null &&
        incomingLastModified != null &&
        incomingLastModified.isNotEmpty &&
        item.lastModified == incomingLastModified) {
      score += 20;
    }

    return score;
  }

  // Stable identifier helpers used for file identity checks
  String? _extractDriveFileId(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host.contains('drive.google.com') ||
          host.contains('drive.usercontent.google.com') ||
          host.contains('usercontent.google.com')) {
        final id = uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) return id;
      }
    } catch (_) {}
    return null;
  }

  String? _filenameFromContentDisposition(String? value) {
    if (value == null || value.isEmpty) return null;
    final utf8Match = RegExp(
      r"filename\*\s*=\s*UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(value);
    if (utf8Match != null) {
      try {
        return Uri.decodeComponent(utf8Match.group(1)!.trim());
      } catch (_) {
        return utf8Match.group(1)!.trim();
      }
    }
    final plainMatch = RegExp(r'filename\s*=\s*"?([^";]+)"?',
            caseSensitive: false)
        .firstMatch(value);
    if (plainMatch != null) return plainMatch.group(1)!.trim();
    return null;
  }

  bool _sameFileName(String a, String b) {
    final nameA = a.split('/').last.trim().toLowerCase();
    final nameB = b.split('/').last.trim().toLowerCase();
    return nameA == nameB;
  }

  bool _sizeMismatch(int a, int b) {
    if (a <= 0 || b <= 0) return false;
    final larger = a > b ? a : b;
    return (a - b).abs() > (larger * 0.01) + 1024;
  }

  void _captureMetadata(DownloadItem item, Headers headers) {
    try {
      final etag = headers.value(HttpHeaders.etagHeader);
      if (etag != null && etag.isNotEmpty) item.etag = etag;
      final mime = headers.value(HttpHeaders.contentTypeHeader);
      if (mime != null && mime.isNotEmpty) {
        item.mimeType = mime.split(';').first.trim();
      }
      final lastModified = headers.value(HttpHeaders.lastModifiedHeader);
      if (lastModified != null && lastModified.isNotEmpty) {
        item.lastModified = lastModified;
      }
      final contentDisposition =
          headers.value('content-disposition');
      if (contentDisposition != null && contentDisposition.isNotEmpty) {
        item.contentDisposition = contentDisposition;
      }
    } catch (e) {
      debugPrint('Metadata capture failed: $e');
    }
  }

  // --- Batch URL Import ---
  Future<Map<String, int>> batchAddDownloads(String urlsText, String saveDir) async {
    final lines = urlsText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    int validCount = 0;
    int invalidCount = 0;

    for (final line in lines) {
      final uri = Uri.tryParse(line);
      if (uri != null && uri.hasScheme && uri.hasAuthority && (uri.scheme == 'http' || uri.scheme == 'https')) {
        final fileName = line.split('/').last.split('?').first;
        final name = fileName.isNotEmpty ? fileName : 'download_${DateTime.now().millisecondsSinceEpoch}';
        await addDownload(line, name, saveDir);
        validCount++;
      } else {
        invalidCount++;
      }
    }
    return {'valid': validCount, 'invalid': invalidCount};
  }

  // --- Mirror URL Switch ---
  Future<bool> switchToMirror(String id) async {
    final item = _queue.firstWhere((i) => i.id == id,
        orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''));
    if (item.id.isEmpty || item.mirrorUrls.isEmpty) return false;

    if (item.status == DownloadStatus.downloading) {
      _cancelTokens[id]?.cancel('Switching to mirror');
      _cancelTokens.remove(id);
    }

    for (final mirrorUrl in item.mirrorUrls) {
      if (mirrorUrl == item.url) continue;
      try {
        await DioClient().resolveRedirects(mirrorUrl);
        item.url = mirrorUrl;
        item.retryCount = 0;
        item.errorMessage = null;
        item.status = DownloadStatus.queued;
        await DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        return true;
      } catch (_) {
        continue;
      }
    }

    item.errorMessage = 'All mirrors failed';
    item.status = DownloadStatus.error;
    await DatabaseHelper().updateDownload(item);
    notifyListeners();
    return false;
  }

  // --- Auto-categorize completed download ---
  void autoCategorizeItem(DownloadItem item) {
    if (item.category != DownloadCategory.other) return;
    final ext = item.fileName.split('.').last.toLowerCase();

    final categoryMap = <String, DownloadCategory>{
      'mp4': DownloadCategory.movies, 'mkv': DownloadCategory.movies,
      'avi': DownloadCategory.movies, 'mov': DownloadCategory.movies,
      'webm': DownloadCategory.movies, 'wmv': DownloadCategory.movies,
      'flv': DownloadCategory.movies, 'm4v': DownloadCategory.movies,
      'mp3': DownloadCategory.music, 'flac': DownloadCategory.music,
      'wav': DownloadCategory.music, 'aac': DownloadCategory.music,
      'ogg': DownloadCategory.music, 'wma': DownloadCategory.music,
      'm4a': DownloadCategory.music,
      'jpg': DownloadCategory.images, 'jpeg': DownloadCategory.images,
      'png': DownloadCategory.images, 'gif': DownloadCategory.images,
      'bmp': DownloadCategory.images, 'webp': DownloadCategory.images,
      'svg': DownloadCategory.images, 'heic': DownloadCategory.images,
      'pdf': DownloadCategory.documents, 'doc': DownloadCategory.documents,
      'docx': DownloadCategory.documents, 'xls': DownloadCategory.documents,
      'xlsx': DownloadCategory.documents, 'ppt': DownloadCategory.documents,
      'pptx': DownloadCategory.documents, 'txt': DownloadCategory.documents,
      'rtf': DownloadCategory.documents, 'csv': DownloadCategory.documents,
      'zip': DownloadCategory.archives, 'rar': DownloadCategory.archives,
      '7z': DownloadCategory.archives, 'tar': DownloadCategory.archives,
      'gz': DownloadCategory.archives, 'bz2': DownloadCategory.archives,
      'xz': DownloadCategory.archives, 'iso': DownloadCategory.archives,
      'apk': DownloadCategory.apps, 'ipa': DownloadCategory.apps,
      'exe': DownloadCategory.apps, 'dmg': DownloadCategory.apps,
      'srt': DownloadCategory.tvShows, 'vtt': DownloadCategory.tvShows,
      'sub': DownloadCategory.tvShows,
    };

    item.category = categoryMap[ext] ?? DownloadCategory.other;
  }

  Future<void> _startDownload(DownloadItem item) async {
    _activeCount++;
    item.status = DownloadStatus.downloading;
    notifyListeners();
    await DatabaseHelper().updateDownload(item);
    _showiOSNotification("Download Started", item.fileName);

    // Start Foreground Service (Android only)
    if (!_isIOS) {
      _channel.invokeMethod('startForegroundService', {
        'url': item.url,
        'filename': item.fileName,
        'id': 1001,
      }).catchError((e) { debugPrint('Channel method error: $e'); });
    }

    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;

    final file = File(item.savePath);
    // Ensure parent directory exists for organized downloads
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // TRUST PERSISTED PROGRESS: file.length() is unreliable due to pre-allocation
    // Actually, if file exists and we are starting, we can check its size to resume.
    if (!await file.exists()) {
      item.downloadedBytes = 0;
    } else {
      // If the file exists but downloadedBytes in queue is 0 (e.g., added a new link for an existing file),
      // we check the file size on disk and use it to resume.
      if (item.downloadedBytes == 0) {
        item.downloadedBytes = await file.length();
      }
    }
    int existingBytes = item.downloadedBytes;

    try {
      final dio = DioClient().dio;
      final headHeaders = <String, dynamic>{};
      if (item.customHeaders.isNotEmpty) {
        headHeaders.addAll(item.customHeaders);
      }
      final headResponse = await dio.head(item.url, options: Options(headers: headHeaders));
      final totalHeader =
          headResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '-1';
      final total = int.tryParse(totalHeader) ?? -1;

      // A HEAD Content-Length is only trusted when it is larger than the
      // stored size (or when no size is stored yet). A suspiciously small
      // value (e.g. an HTML error page served for an expired link) must
      // never shrink the stored total or trigger a false completion.
      if (total > 0) {
        if (item.totalBytes <= 0 || total >= item.totalBytes) {
          item.totalBytes = total;
        }
      }

      // Check if already fully downloaded based on disk size.
      // Completion only when the bytes already on disk reached a *verified*
      // server size. Never infer completion from the HTTP status alone.
      final totalIsVerified =
          total > 0 &&
          total >= item.totalBytes &&
          total >= existingBytes - 1024;
      if (existingBytes > 0 && existingBytes >= total && totalIsVerified) {
        item.status = DownloadStatus.done;
        item.speedBytesPerSec = 0;
        item.etaSeconds = 0;
        item.downloadedBytes = total;
        item.totalBytes = total;
        _cancelTokens.remove(item.id);
        await updateStorageInfo();
        _showiOSNotification("Download Complete", item.fileName);

        if (!_isIOS) {
          _channel.invokeMethod('stopForegroundService', {
            'id': 1001,
            'filename': item.fileName,
            'success': true,
          }).catchError((e) { debugPrint('Channel method error: $e'); });
        }

        // Finalize state
        if (_activeCount > 0) {
          _stopForegroundIfNoActive();
          _activeCount--;
        }
        await DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        return; // Early return for completed file
      }

      await _downloadSingle(item, existingBytes, cancelToken);

      // Completion only after the final byte has been written to disk.
      // A stream that ended early (or a server that lied about the size)
      // is an interruption, never a completion.
      if (!cancelToken.isCancelled &&
          item.totalBytes > 0 &&
          item.downloadedBytes < item.totalBytes) {
        throw const _DownloadInterruptedException(
            'Download interrupted before completion.');
      }
      debugPrint('Download completed normally');

      item.status = DownloadStatus.done;
      item.speedBytesPerSec = 0;
      item.etaSeconds = 0;
      item.downloadedBytes = item.totalBytes;
      _cancelTokens.remove(item.id);
      autoCategorizeItem(item);
      await updateStorageInfo();

      if (!_isIOS) {
        _channel.invokeMethod('stopForegroundService', {
          'id': 1001,
          'filename': item.fileName,
          'success': true,
        }).catchError((e) { debugPrint('Channel method error: $e'); });
      }
    } catch (e) {
      _handleDownloadError(item, e);
    } finally {
      if (!_isIOS) {
        _stopForegroundIfNoActive();
      }
      if (_activeCount > 0) {
        _activeCount--;
      }
      await DatabaseHelper().updateDownload(item);
      notifyListeners();
      _processQueue();
    }
  }

  Future<void> _downloadSingle(
      DownloadItem item, int existingBytes, CancelToken cancelToken) async {
    final dio = DioClient().dio;
    final file = File(item.savePath);
    item.downloadedBytes = existingBytes;

    if (existingBytes > 0) {
      debugPrint('Resuming from byte $existingBytes');
    }

    final requestHeaders = <String, dynamic>{};
    if (item.customHeaders.isNotEmpty) {
      requestHeaders.addAll(item.customHeaders);
    }
    if (existingBytes > 0) {
      requestHeaders['Range'] = 'bytes=$existingBytes-';
    }

    final response = await dio.get<ResponseBody>(
      item.url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: requestHeaders.isNotEmpty ? requestHeaders : null,
      ),
    );

    _captureMetadata(item, response.headers);

    // If we asked for a range and the server answered with a full 200 OK,
    // it does not support resuming. Do NOT write to the partial file.
    if (existingBytes > 0 && response.statusCode != 206) {
      debugPrint('Server rejected Range request');
      throw const _ResumeNotSupportedException(
          'This download link cannot resume.');
    }

    // Metadata is only trustworthy from a real file response (a 200 for a
    // fresh download, or a 206 for a resumed one).
    if (existingBytes == 0 || response.statusCode == 206) {
      _captureMetadata(item, response.headers);
    }

    // CRITICAL: For pre-allocated files, FileMode.append is WRONG.
    // It will append to the END of the pre-allocated (full size) file.
    // We must use 'write' or 'r+' and set position manually.
    final raf = file.openSync(mode: FileMode.append);
    if (existingBytes > 0) {
      raf.setPositionSync(existingBytes);
    }
    final stream = response.data!.stream;

    DateTime lastUpdate = DateTime.now();
    int bytesSinceUpdate = 0;

    await for (final chunk in stream) {
      if (cancelToken.isCancelled) break;
      raf.writeFromSync(chunk);
      item.downloadedBytes += chunk.length;
      bytesSinceUpdate += chunk.length;

      final now = DateTime.now();
      if (now.difference(lastUpdate).inMilliseconds >= 500) {
        _updateProgress(
            item, bytesSinceUpdate, now.difference(lastUpdate).inMilliseconds);
        lastUpdate = now;
        bytesSinceUpdate = 0;
      }
    }
    raf.closeSync();
  }

  void _updateProgress(
      DownloadItem item, int bytesSinceLastUpdate, int diffMs) {
    if (diffMs == 0) return;

    // Smooth out speed calculation
    double currentSpeed = (bytesSinceLastUpdate / (diffMs / 1000)).toDouble();
    if (item.speedBytesPerSec == 0) {
      item.speedBytesPerSec = currentSpeed;
    } else {
      item.speedBytesPerSec =
          (item.speedBytesPerSec * 0.7) + (currentSpeed * 0.3);
    }

    if (item.speedBytesPerSec > 0 && item.totalBytes > 0) {
      final remaining = item.totalBytes - item.downloadedBytes;
      item.etaSeconds = (remaining / item.speedBytesPerSec).round();
    }

    int progressPercent = 0;
    if (item.totalBytes > 0) {
      progressPercent =
          ((item.downloadedBytes / item.totalBytes) * 100).toInt();
    }

    _channel.invokeMethod('updateProgress', {
      'id': 1001,
      'progress': progressPercent,
      'speed':
          '${(item.speedBytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s',
      'filename': item.fileName,
      'eta': _formatDuration(item.etaSeconds),
      'size':
          '${_formatSize(item.downloadedBytes)} / ${_formatSize(item.totalBytes)}',
    }).catchError((e) { debugPrint('Channel method error: $e'); });
    _syncLiveActivityState();

    final now = DateTime.now();
    if (now.difference(_lastNotifyTime).inMilliseconds > 250) {
      _lastNotifyTime = now;
      notifyListeners();
      // Periodically persist to DB in case of crash (every 5 seconds)
      if (now.difference(_lastSaveTime).inSeconds > 5) {
        _lastSaveTime = now;
        DatabaseHelper().updateDownload(item);
      }
    }
  }

  void _handleDownloadError(DownloadItem item, dynamic e) {
    if (e is DioException && CancelToken.isCancel(e)) {
      return;
    }

    // Server ignored the Range header (200 instead of 206). Never overwrite
    // the partial file and never restart the download automatically.
    if (e is _ResumeNotSupportedException) {
      item.status = DownloadStatus.error;
      item.speedBytesPerSec = 0;
      item.errorMessage = e.message;
      _showiOSNotification("Download Failed", item.fileName);
      DatabaseHelper().updateDownload(item);
      return;
    }

    bool permanentError = false;
    if (e is DioException) {
      final statusCode = e.response?.statusCode;
      switch (statusCode) {
        case 401:
          item.errorMessage = 'Authentication required. The link may need valid credentials.';
          permanentError = true;
          break;
        case 403:
          item.errorMessage = 'Access denied. The link may have expired.';
          permanentError = true;
          break;
        case 404:
          item.errorMessage = 'File not found. The link may have expired.';
          permanentError = true;
          break;
        case 410:
          item.errorMessage = 'This download link has expired.';
          permanentError = true;
          break;
        case 429:
          item.errorMessage = 'Too many requests. Retrying...';
          break;
        case 500:
          item.errorMessage = 'Server error. Retrying...';
          break;
        case 503:
          item.errorMessage = 'Server unavailable. Retrying...';
          break;
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        if (item.errorMessage == null || !item.errorMessage!.contains('Retrying')) {
          item.errorMessage = 'Connection timed out. Retrying...';
        }
      }
    }

    if (permanentError) {
      item.status = DownloadStatus.error;
      item.speedBytesPerSec = 0;
      _showiOSNotification("Download Failed", item.fileName);
    } else if (item.retryCount < item.maxRetries) {
      item.retryCount++;
      item.status = DownloadStatus.queued;
      // Try mirror URL if available on retry
      if (item.mirrorUrls.isNotEmpty && item.retryCount > 1) {
        _tryMirrorAfterDelay(item);
      }
    } else {
      // All retries exhausted - try mirrors before final error
      if (item.mirrorUrls.isNotEmpty) {
        switchToMirror(item.id);
        return;
      }
      item.status = DownloadStatus.error;
      if (item.errorMessage == null || !item.errorMessage!.contains('Retrying')) {
        item.errorMessage = e.toString();
      }
      _showiOSNotification("Download Failed", item.fileName);
    }
    DatabaseHelper().updateDownload(item);
  }

  void _tryMirrorAfterDelay(DownloadItem item) {
    Future.delayed(const Duration(seconds: 3), () {
      switchToMirror(item.id);
    });
  }

  // --- Integrity Checker (Isolate) ---
  Future<bool> verifyFileHash(String filePath, String expectedHash) async {
    expectedHash = expectedHash.trim().toLowerCase();
    if (expectedHash.isEmpty) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final String calculatedHash = await Isolate.run(() async {
        final f = File(filePath);
        final stream = f.openRead();
        if (expectedHash.length == 32) {
          final digest = await md5.bind(stream).first;
          return digest.toString();
        } else if (expectedHash.length == 40) {
          final digest = await sha1.bind(stream).first;
          return digest.toString();
        } else {
          final digest = await sha256.bind(stream).first;
          return digest.toString();
        }
      });

      return calculatedHash.toLowerCase() == expectedHash;
    } catch (e) {
      debugPrint('Hash verification error: $e');
      return false;
    }
  }

  Future<String?> computeChecksum(String filePath, String algorithm) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      return await Isolate.run(() async {
        final f = File(filePath);
        final stream = f.openRead();
        switch (algorithm.toLowerCase()) {
          case 'md5':
            return (await md5.bind(stream).first).toString();
          case 'sha1':
            return (await sha1.bind(stream).first).toString();
          case 'sha256':
            return (await sha256.bind(stream).first).toString();
          default:
            return null;
        }
      });
    } catch (e) {
      debugPrint('Checksum compute error: $e');
      return null;
    }
  }

  // Verify all checksums on a completed download item
  Future<void> verifyDownloadChecksums(DownloadItem item) async {
    if (!await File(item.savePath).exists()) return;
    if (item.expectedMd5 != null) {
      item.calculatedMd5 = await computeChecksum(item.savePath, 'md5');
    }
    if (item.expectedSha1 != null) {
      item.calculatedSha1 = await computeChecksum(item.savePath, 'sha1');
    }
    if (item.expectedSha256 != null) {
      item.calculatedSha256 = await computeChecksum(item.savePath, 'sha256');
    }
    DatabaseHelper().updateDownload(item);
    notifyListeners();
  }

  // --- Live Activities (iOS 16.1+) ---
  Future<bool> isLiveActivitySupported() async {
    if (!_isIOS) return false;
    try {
      return await _liveActivityChannel.invokeMethod('isSupported') ?? false;
    } catch (e) {
      debugPrint('Live Activity isSupported error: $e');
      return false;
    }
  }

  void _syncLiveActivityState() {
    if (!_isIOS) return;
    final active = _queue.where((d) => d.status == DownloadStatus.downloading).toList();

    if (active.isNotEmpty && !_backgroundServicesRunning) {
      _backgroundServicesRunning = true;
      _backgroundServiceChannel.invokeMethod('startBackgroundServices')
          .catchError((e) => debugPrint('startBackgroundServices error: $e'));
    } else if (active.isEmpty && _backgroundServicesRunning) {
      _backgroundServicesRunning = false;
      _backgroundServiceChannel.invokeMethod('stopBackgroundServices')
          .catchError((e) => debugPrint('stopBackgroundServices error: $e'));
    }

    if (active.isEmpty) {
      if (onAllDownloadsComplete != null) onAllDownloadsComplete!();
      _liveActivityChannel.invokeMethod('updateActiveDownloads', {
        'count': 0,
        'primary': null,
      }).catchError((e) => debugPrint('updateActiveDownloads error: $e'));
    } else {
      final primary = active.first;
      _liveActivityChannel.invokeMethod('updateActiveDownloads', {
        'count': active.length,
        'primary': {
          'fileName': primary.fileName,
          'progress': primary.progress,
          'speed': '${(primary.speedBytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s',
          'eta': _formatDuration(primary.etaSeconds),
          'downloadedSize': _formatSize(primary.downloadedBytes),
          'totalSize': _formatSize(primary.totalBytes),
          'status': primary.statusLabel,
        },
      }).catchError((e) => debugPrint('updateActiveDownloads error: $e'));
    }
  }

  void _showiOSNotification(String title, String body) {
    if (!_isIOS) return;
    _iosNotificationChannel.invokeMethod('show', {
      'title': title,
      'body': body,
    }).catchError((e) => debugPrint('iOS notification error: $e'));
  }

  Future<void> enableLiveActivity() async {
    if (!_isIOS) return;
    try {
      await _liveActivityChannel.invokeMethod('enable');
      debugPrint('Live Activity enabled');
    } catch (e) {
      debugPrint('Live Activity enable error: $e');
    }
  }

  Future<void> disableLiveActivity() async {
    if (!_isIOS) return;
    try {
      await _liveActivityChannel.invokeMethod('disable');
    } catch (e) {
      debugPrint('Live Activity disable error: $e');
    }
  }

  Future<bool> isLiveActivityEnabled() async {
    if (!_isIOS) return false;
    try {
      return await _liveActivityChannel.invokeMethod('isEnabled') ?? true;
    } catch (e) {
      debugPrint('Live Activity isEnabled error: $e');
      return false;
    }
  }

  // --- Export / Import Queue ---
  Future<void> exportQueue() async {
    try {
      final jsonStr = jsonEncode(_queue.map((item) => item.toJson()).toList());
      // Create a temporary file
      final directory = Directory.systemTemp;
      final file = File(p.join(directory.path, 'dirxplore_queue_backup.json'));
      await file.writeAsString(jsonStr);

      // Share it
      await Share.shareXFiles([XFile(file.path)],
          text: 'DirXplore Download Queue Backup');
    } catch (e) {
      debugPrint('Export error: $e');
    }
  }

  Future<bool> importQueue() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonStr = await file.readAsString();
        final List<dynamic> list = jsonDecode(jsonStr);

        // Merge with existing queue or replace? Let's merge (avoiding duplicates by URL)
        int importedCount = 0;
        for (var itemJson in list) {
          final newItem = DownloadItem.fromJson(itemJson);
          if (!_queue.any((i) => i.url == newItem.url)) {
            // Reset status of imported items that were downloading/queued to paused
            // so they don't all start at once unexpectedly.
            if (newItem.status == DownloadStatus.downloading ||
                newItem.status == DownloadStatus.queued) {
              newItem.status = DownloadStatus.paused;
              newItem.speedBytesPerSec = 0;
            }
            _queue.add(newItem);
            importedCount++;
          }
        }

        if (importedCount > 0) {
          _saveQueue();
          notifyListeners();
          _processQueue();
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Import error: $e');
      return false;
    }
  }

  void revealFile(String path) {
    if (_isIOS) {
      _iosChannel.invokeMethod('openFileLocation', {'path': path})
          .catchError((e) { debugPrint('revealFile error: $e'); });
    }
  }

  void saveToFiles(String path) {
    if (_isIOS) {
      _iosChannel.invokeMethod('saveToFiles', {'path': path})
          .catchError((e) { debugPrint('saveToFiles error: $e'); });
    }
  }
}

// Helper for older dart runtimes if bind() isn't available, but bind() is standard.
class ProxySink implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

String _formatSize(int bytes) {
  if (bytes < 0) return "Unknown";
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
