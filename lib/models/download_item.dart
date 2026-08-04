import 'dart:convert';

enum DownloadStatus { queued, downloading, paused, error, done }

enum DownloadCategory {
  movies,
  tvShows,
  music,
  images,
  documents,
  archives,
  apps,
  other;

  static DownloadCategory fromFileName(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'wmv', 'flv', 'm4v'].contains(ext)) return DownloadCategory.movies;
    if (['mp3', 'flac', 'wav', 'aac', 'ogg', 'wma', 'm4a'].contains(ext)) return DownloadCategory.music;
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'heic'].contains(ext)) return DownloadCategory.images;
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'csv'].contains(ext)) return DownloadCategory.documents;
    if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso'].contains(ext)) return DownloadCategory.archives;
    if (['apk', 'ipa', 'exe', 'dmg', 'deb', 'rpm'].contains(ext)) return DownloadCategory.apps;
    if (['mp4', 'mkv', 'avi', 'srt', 'vtt', 'sub'].contains(ext)) return DownloadCategory.tvShows;
    return DownloadCategory.other;
  }

  static DownloadCategory fromMimeType(String? mime) {
    if (mime == null) return DownloadCategory.other;
    final m = mime.toLowerCase();
    if (m.startsWith('video/')) return DownloadCategory.movies;
    if (m.startsWith('audio/')) return DownloadCategory.music;
    if (m.startsWith('image/')) return DownloadCategory.images;
    if (m.startsWith('text/') || m.startsWith('application/pdf')) return DownloadCategory.documents;
    if (m.contains('zip') || m.contains('rar') || m.contains('tar') || m.contains('7z')) return DownloadCategory.archives;
    if (m.contains('apk') || m.contains('x-msdownload')) return DownloadCategory.apps;
    return DownloadCategory.other;
  }
}

enum ScheduleType { immediate, queueOnly, wifiOnly, chargingOnly, scheduled }

class DownloadItem {
  final String id;
  String url;
  final String fileName;
  String savePath;
  String? batchId;
  String? batchName;
  DownloadStatus status;
  int totalBytes;
  int downloadedBytes;
  double speedBytesPerSec;
  int etaSeconds;
  int retryCount;
  int maxRetries;
  String? errorMessage;
  DateTime addedAt;
  String? originalUrl;

  // Custom headers stored as JSON string
  String? customHeadersJson;
  Map<String, String> get customHeaders {
    if (customHeadersJson == null) return {};
    try {
      final decoded = jsonDecode(customHeadersJson!);
      return Map<String, String>.from(decoded);
    } catch (_) {
      return {};
    }
  }

  // Mirror URLs stored as JSON array
  String? mirrorUrlsJson;
  List<String> get mirrorUrls {
    if (mirrorUrlsJson == null) return [];
    try {
      final decoded = jsonDecode(mirrorUrlsJson!);
      return List<String>.from(decoded);
    } catch (_) {
      return [];
    }
  }

  DownloadCategory category;
  ScheduleType scheduleType;
  DateTime? scheduledAt;

  // Checksums
  String? expectedMd5;
  String? expectedSha1;
  String? expectedSha256;
  String? calculatedMd5;
  String? calculatedSha1;
  String? calculatedSha256;

  // Redirect info
  int redirectCount;
  String? resolvedUrl;

  // Server metadata used to verify file identity across link refreshes
  String? etag;
  String? mimeType;
  String? lastModified;
  String? contentDisposition;

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.batchId,
    this.batchName,
    this.status = DownloadStatus.queued,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds = 0,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.errorMessage,
    DateTime? addedAt,
    this.originalUrl,
    this.customHeadersJson,
    this.mirrorUrlsJson,
    this.category = DownloadCategory.other,
    this.scheduleType = ScheduleType.immediate,
    this.scheduledAt,
    this.expectedMd5,
    this.expectedSha1,
    this.expectedSha256,
    this.calculatedMd5,
    this.calculatedSha1,
    this.calculatedSha256,
    this.redirectCount = 0,
    this.resolvedUrl,
    this.etag,
    this.mimeType,
    this.lastModified,
    this.contentDisposition,
  }) : addedAt = addedAt ?? DateTime.now();

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  String get statusLabel {
    switch (status) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.downloading:
        return 'Downloading';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.error:
        return 'Error';
      case DownloadStatus.done:
        return 'Done';
    }
  }

  String get categoryLabel {
    switch (category) {
      case DownloadCategory.movies:
        return 'Movies';
      case DownloadCategory.tvShows:
        return 'TV Shows';
      case DownloadCategory.music:
        return 'Music';
      case DownloadCategory.images:
        return 'Images';
      case DownloadCategory.documents:
        return 'Documents';
      case DownloadCategory.archives:
        return 'Archives';
      case DownloadCategory.apps:
        return 'Apps';
      case DownloadCategory.other:
        return 'Other';
    }
  }

  String get host {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return 'Unknown';
    }
  }

  DownloadItem copyWith({
    DownloadStatus? status,
    int? totalBytes,
    int? downloadedBytes,
    double? speedBytesPerSec,
    int? etaSeconds,
    int? retryCount,
    String? errorMessage,
  }) =>
      DownloadItem(
        id: id,
        url: url,
        fileName: fileName,
        savePath: savePath,
        batchId: batchId,
        batchName: batchName,
        status: status ?? this.status,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
        etaSeconds: etaSeconds ?? this.etaSeconds,
        retryCount: retryCount ?? this.retryCount,
        errorMessage: errorMessage ?? this.errorMessage,
        addedAt: addedAt,
        originalUrl: originalUrl,
        customHeadersJson: customHeadersJson,
        mirrorUrlsJson: mirrorUrlsJson,
        category: category,
        scheduleType: scheduleType,
        scheduledAt: scheduledAt,
        maxRetries: maxRetries,
        expectedMd5: expectedMd5,
        expectedSha1: expectedSha1,
        expectedSha256: expectedSha256,
        calculatedMd5: calculatedMd5,
        calculatedSha1: calculatedSha1,
        calculatedSha256: calculatedSha256,
        redirectCount: redirectCount,
        resolvedUrl: resolvedUrl,
        etag: etag,
        mimeType: mimeType,
        lastModified: lastModified,
        contentDisposition: contentDisposition,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'fileName': fileName,
    'savePath': savePath,
    'batchId': batchId,
    'batchName': batchName,
    'status': status.index,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'retryCount': retryCount,
    'maxRetries': maxRetries,
    'errorMessage': errorMessage,
    'addedAt': addedAt.toIso8601String(),
    if (originalUrl != null) 'originalUrl': originalUrl,
    if (customHeadersJson != null) 'customHeadersJson': customHeadersJson,
    if (mirrorUrlsJson != null) 'mirrorUrlsJson': mirrorUrlsJson,
    'category': category.index,
    'scheduleType': scheduleType.index,
    if (scheduledAt != null) 'scheduledAt': scheduledAt!.toIso8601String(),
    if (expectedMd5 != null) 'expectedMd5': expectedMd5,
    if (expectedSha1 != null) 'expectedSha1': expectedSha1,
    if (expectedSha256 != null) 'expectedSha256': expectedSha256,
    if (calculatedMd5 != null) 'calculatedMd5': calculatedMd5,
    if (calculatedSha1 != null) 'calculatedSha1': calculatedSha1,
    if (calculatedSha256 != null) 'calculatedSha256': calculatedSha256,
    'redirectCount': redirectCount,
    if (resolvedUrl != null) 'resolvedUrl': resolvedUrl,
    if (etag != null) 'etag': etag,
    if (mimeType != null) 'mimeType': mimeType,
    if (lastModified != null) 'lastModified': lastModified,
    if (contentDisposition != null) 'contentDisposition': contentDisposition,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      id: json['id'],
      url: json['url'],
      fileName: json['fileName'],
      savePath: json['savePath'],
      batchId: json['batchId'],
      batchName: json['batchName'],
      status: DownloadStatus.values[json['status'] ?? 0],
      totalBytes: json['totalBytes'] ?? 0,
      downloadedBytes: json['downloadedBytes'] ?? 0,
      retryCount: json['retryCount'] ?? 0,
      maxRetries: json['maxRetries'] ?? 3,
      errorMessage: json['errorMessage'],
      addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt']) : null,
      originalUrl: json['originalUrl'],
      customHeadersJson: json['customHeadersJson'],
      mirrorUrlsJson: json['mirrorUrlsJson'],
      category: json['category'] != null ? DownloadCategory.values[json['category']] : DownloadCategory.other,
      scheduleType: json['scheduleType'] != null ? ScheduleType.values[json['scheduleType']] : ScheduleType.immediate,
      scheduledAt: json['scheduledAt'] != null ? DateTime.parse(json['scheduledAt']) : null,
      expectedMd5: json['expectedMd5'],
      expectedSha1: json['expectedSha1'],
      expectedSha256: json['expectedSha256'],
      calculatedMd5: json['calculatedMd5'],
      calculatedSha1: json['calculatedSha1'],
      calculatedSha256: json['calculatedSha256'],
      redirectCount: json['redirectCount'] ?? 0,
      resolvedUrl: json['resolvedUrl'],
      etag: json['etag'],
      mimeType: json['mimeType'],
      lastModified: json['lastModified'],
      contentDisposition: json['contentDisposition'],
    );
  }
}
