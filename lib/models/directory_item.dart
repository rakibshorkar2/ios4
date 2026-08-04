enum DirectoryItemType {
  directory,
  video,
  audio,
  image,
  archive,
  document,
  other
}

class DirectoryItem {
  final String name;
  final String url;
  final DirectoryItemType type;
  final String? size;
  bool isSelected;

  DirectoryItem({
    required this.name,
    required this.url,
    required this.type,
    String? size,
    this.isSelected = false,
  }) : size = _formatSize(size);

  static String? _formatSize(String? s) {
    if (s == null || s.isEmpty || s == '-') return null;
    s = s.trim().toUpperCase();
    double b = 0;
    try {
      if (s.endsWith('K') || s.endsWith('KB')) {
        b = double.parse(s.replaceAll(RegExp(r'[KMBG]'), '').trim()) * 1024;
      } else if (s.endsWith('M') || s.endsWith('MB')) {
        b = double.parse(s.replaceAll(RegExp(r'[KMBG]'), '').trim()) *
            1024 *
            1024;
      } else if (s.endsWith('G') || s.endsWith('GB')) {
        b = double.parse(s.replaceAll(RegExp(r'[KMBG]'), '').trim()) *
            1024 *
            1024 *
            1024;
      } else {
        b = double.parse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
      }
      if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
      if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(2)} MB';
      if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
      return '${b.toInt()} B';
    } catch (_) {
      return s;
    }
  }

  bool get isDirectory => type == DirectoryItemType.directory;

  String get typeTag {
    switch (type) {
      case DirectoryItemType.directory:
        return '[DIR]';
      case DirectoryItemType.video:
        return '[VID]';
      case DirectoryItemType.audio:
        return '[AUD]';
      case DirectoryItemType.image:
        return '[IMG]';
      case DirectoryItemType.archive:
        return '[ZIP]';
      case DirectoryItemType.document:
        return '[DOC]';
      case DirectoryItemType.other:
        return '[FIL]';
    }
  }

  static DirectoryItemType typeFromExtension(String name) {
    final ext = name.split('.').last.toLowerCase();
    const videoExt = [
      'mp4',
      'mkv',
      'avi',
      'mov',
      'wmv',
      'flv',
      'm4v',
      'webm',
      'ts',
      'm2ts'
    ];
    const audioExt = ['mp3', 'flac', 'aac', 'ogg', 'wav', 'opus', 'm4a', 'wma'];
    const imageExt = [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'svg',
      'tiff'
    ];
    const archiveExt = ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso'];
    const docExt = [
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'txt',
      'epub',
      'mobi',
      'srt',
      'nfo'
    ];

    if (videoExt.contains(ext)) return DirectoryItemType.video;
    if (audioExt.contains(ext)) return DirectoryItemType.audio;
    if (imageExt.contains(ext)) return DirectoryItemType.image;
    if (archiveExt.contains(ext)) return DirectoryItemType.archive;
    if (docExt.contains(ext)) return DirectoryItemType.document;
    return DirectoryItemType.other;
  }
}
