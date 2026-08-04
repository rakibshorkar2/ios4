import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:ui';
import '../providers/download_provider.dart';
import '../providers/app_state.dart';
import '../services/dio_client.dart';
import '../services/haptic_service.dart';

class NewDownloadSheet extends StatefulWidget {
  const NewDownloadSheet({super.key});

  @override
  State<NewDownloadSheet> createState() => _NewDownloadSheetState();
}

class _NewDownloadSheetState extends State<NewDownloadSheet>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _filenameController = TextEditingController();
  final _batchController = TextEditingController();
  final _customHeadersController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _metadataFailed = false;

  bool _infoFetched = false;
  int _fileSize = -1;
  String _fileType = '';
  bool? _resumeSupported;
  String _detectedFileName = '';
  String _resolvedUrl = '';
  String _originalUrl = '';
  int _redirectCount = 0;
  String _host = '';

  bool _isBatchMode = false;
  bool _showAdvanced = false;
  bool _linkAnalysisExpanded = false;

  final Map<String, String> _customHeaders = {};

  late AnimationController _chevronController;
  late Animation<double> _chevronAnimation;

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _chevronAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _chevronController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _filenameController.dispose();
    _batchController.dispose();
    _customHeadersController.dispose();
    _chevronController.dispose();
    super.dispose();
  }

  void _toggleLinkAnalysis() {
    setState(() {
      _linkAnalysisExpanded = !_linkAnalysisExpanded;
      if (_linkAnalysisExpanded) {
        _chevronController.forward();
      } else {
        _chevronController.reverse();
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      if (_isBatchMode) {
        _batchController.text = data.text!.trim();
      } else {
        _urlController.text = data.text!.trim();
      }
      if (_infoFetched) {
        setState(() {
          _infoFetched = false;
          _error = null;
        });
      }
    }
  }

  String? _validateUrl(String url) {
    if (url.isEmpty) return 'Please enter a URL';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Invalid URL format';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Only HTTP and HTTPS URLs are supported';
    }
    return null;
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (path.isNotEmpty) {
      return path.last;
    }
    return 'download';
  }

  String _fileNameFromContentDisposition(String? disposition) {
    if (disposition == null) return '';
    final match = RegExp(
      r"filename\*?=(?:UTF-8''\s*)?([^;\s]+)",
    ).firstMatch(disposition);
    if (match != null) {
      return Uri.decodeComponent(
        match.group(1)!.trim().replaceAll(RegExp(r'^"|"$'), ''),
      );
    }
    return '';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Unknown';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String get _linkAnalysisSummary {
    final parts = <String>[];
    if (_fileType.isNotEmpty) {
      final mime = _fileType.split('/').last;
      parts.add(mime.toUpperCase());
    }
    if (_fileSize > 0) {
      parts.add(_formatFileSize(_fileSize));
    }
    if (_resumeSupported == true) {
      parts.add('Resume Supported');
    } else if (_resumeSupported == false) {
      parts.add('No Resume');
    }
    if (parts.isEmpty) return 'Metadata unavailable';
    return parts.join(' • ');
  }

  Future<bool> _tryHeadRequest(String url) async {
    try {
      final dio = DioClient().dio;
      final headers = <String, dynamic>{};
      if (_customHeaders.isNotEmpty) headers.addAll(_customHeaders);
      final response = await dio.head(url, options: Options(headers: headers.isNotEmpty ? headers : null));
      _parseHeaders(response.headers);
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse &&
          e.response?.statusCode == 405) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _tryGetFallback(String url) async {
    final dio = DioClient().dio;
    final headers = <String, dynamic>{'Range': 'bytes=0-0'};
    if (_customHeaders.isNotEmpty) headers.addAll(_customHeaders);
    final response = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: headers,
      ),
    );
    _parseHeaders(response.headers);
    if (_fileSize <= 0) {
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
        if (match != null) {
          _fileSize = int.tryParse(match.group(1)!) ?? -1;
        }
      }
    }
  }

  void _parseHeaders(Headers headers) {
    final contentLength = headers.value(HttpHeaders.contentLengthHeader);
    final contentType = headers.value(HttpHeaders.contentTypeHeader);
    final contentDisposition = headers.value('content-disposition');
    final acceptRanges = headers.value(HttpHeaders.acceptRangesHeader);

    _fileSize = int.tryParse(contentLength ?? '') ?? -1;

    if (contentType != null) {
      _fileType = contentType.split(';').first;
    }

    final ranges = acceptRanges?.toLowerCase();
    if (ranges == 'bytes') {
      _resumeSupported = true;
    } else if (ranges != null && ranges.isNotEmpty) {
      _resumeSupported = false;
    } else {
      _resumeSupported = null;
    }

    if (_detectedFileName.isEmpty) {
      final cd = _fileNameFromContentDisposition(contentDisposition);
      if (cd.isNotEmpty) {
        _detectedFileName = cd;
      }
    }
  }

  Future<void> _fetchInfo() async {
    final url = _urlController.text.trim();
    final validationError = _validateUrl(url);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _infoFetched = false;
      _metadataFailed = false;
      _fileSize = -1;
      _fileType = '';
      _resumeSupported = null;
      _linkAnalysisExpanded = false;
      _chevronController.reset();
    });

    try {
      HapticService.medium();

      _originalUrl = url;
      _host = Uri.parse(url).host;
      _redirectCount = 0;

      String resolvedUrl;
      try {
        resolvedUrl = await DioClient().resolveRedirects(url);
        _redirectCount = 1;
      } catch (_) {
        resolvedUrl = url;
      }
      _resolvedUrl = resolvedUrl;

      try {
        final headOk = await _tryHeadRequest(resolvedUrl);
        if (!headOk) {
          await _tryGetFallback(resolvedUrl);
        }
      } catch (_) {}

      if (_detectedFileName.isEmpty) {
        _detectedFileName = _fileNameFromUrl(resolvedUrl);
      }
      if (_detectedFileName.isEmpty) {
        _detectedFileName = _fileNameFromUrl(url);
      }

      if (_filenameController.text.trim().isEmpty && _detectedFileName.isNotEmpty) {
        _filenameController.text = _detectedFileName;
      }

      if (!mounted) return;
      setState(() {
        _infoFetched = true;
        _isLoading = false;
      });
    } catch (e) {
      if (_detectedFileName.isEmpty) {
        _detectedFileName = _fileNameFromUrl(url);
      }
      if (_filenameController.text.trim().isEmpty && _detectedFileName.isNotEmpty) {
        _filenameController.text = _detectedFileName;
      }
      if (!mounted) return;
      setState(() {
        _infoFetched = true;
        _metadataFailed = true;
        _isLoading = false;
        _error = 'Metadata could not be retrieved. Download anyway?';
      });
    }
  }

  Future<void> _startDownload() async {
    final url = _resolvedUrl.isNotEmpty ? _resolvedUrl : _urlController.text.trim();
    final fileName = _filenameController.text.trim();
    final originalUrl = _originalUrl.isNotEmpty ? _originalUrl : url;

    if (!mounted) return;
    final appState = context.read<AppState>();
    final dlProvider = context.read<DownloadProvider>();
    await dlProvider.addDownload(url, fileName, appState.defaultSavePath,
        originalUrl: originalUrl,
        customHeaders: _customHeaders.isNotEmpty ? _customHeaders : null,
        redirectCount: _redirectCount,
        resolvedUrl: _resolvedUrl.isNotEmpty ? _resolvedUrl : null);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added: $fileName')),
      );
    }
  }

  Future<void> _startBatchDownload() async {
    final text = _batchController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please enter at least one URL');
      return;
    }

    if (!mounted) return;
    final appState = context.read<AppState>();
    final dlProvider = context.read<DownloadProvider>();
    final result = await dlProvider.batchAddDownloads(text, appState.defaultSavePath);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${result['valid']} download(s)${result['invalid']! > 0 ? ', ${result['invalid']} invalid URL(s) skipped' : ''}'),
        ),
      );
    }
  }

  void _addCustomHeader() {
    final text = _customHeadersController.text.trim();
    if (text.isEmpty) return;
    final eq = text.indexOf(':');
    if (eq <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use format: Header: Value')),
      );
      return;
    }
    final key = text.substring(0, eq).trim();
    final value = text.substring(eq + 1).trim();
    if (key.isEmpty || value.isEmpty) return;
    setState(() {
      _customHeaders[key] = value;
      _customHeadersController.clear();
    });
  }

  void _removeCustomHeader(String key) {
    setState(() => _customHeaders.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        snap: true,
        snapSizes: const [0.5, 0.85, 0.95],
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade900.withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    _buildDragHandle(cs),
                    _buildTitleRow(cs),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_isBatchMode) ...[
                              _buildUrlField(cs),
                              const SizedBox(height: 8),
                              _buildActionRow(cs),
                              if (_showAdvanced) ...[
                                const SizedBox(height: 8),
                                _buildAdvancedSection(cs),
                              ],
                              const SizedBox(height: 10),
                              _buildFilenameField(cs),
                              if (_infoFetched && !_metadataFailed) ...[
                                const SizedBox(height: 12),
                                _buildLinkAnalyzerCard(cs),
                              ],
                              if (_metadataFailed) ...[
                                const SizedBox(height: 12),
                                _buildMetadataFailedWarning(cs),
                              ],
                            ] else ...[
                              _buildBatchField(cs),
                              const SizedBox(height: 8),
                              _buildBatchPasteButton(cs),
                            ],
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                    _buildBottomActions(cs),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDragHandle(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Center(
        child: Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text('New Download',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          ToggleButtons(
            isSelected: [!_isBatchMode, _isBatchMode],
            onPressed: (i) {
              setState(() {
                _isBatchMode = i == 1;
                _infoFetched = false;
                _error = null;
              });
            },
            borderRadius: BorderRadius.circular(12),
            constraints: const BoxConstraints(minWidth: 60, minHeight: 30),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Single', style: TextStyle(fontSize: 12))),
              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Batch', style: TextStyle(fontSize: 12))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUrlField(ColorScheme cs) {
    return TextField(
      controller: _urlController,
      decoration: InputDecoration(
        labelText: 'URL',
        hintText: 'https://example.com/file.zip',
        prefixIcon: const Icon(Icons.link),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        errorText: _error,
      ),
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      onChanged: (_) {
        if (_infoFetched) setState(() { _infoFetched = false; _error = null; });
      },
    );
  }

  Widget _buildActionRow(ColorScheme cs) {
    return Row(
      children: [
        TextButton.icon(
          icon: const Icon(Icons.content_paste, size: 16),
          label: const Text('Paste', style: TextStyle(fontSize: 12)),
          onPressed: _pasteFromClipboard,
        ),
        const Spacer(),
        TextButton.icon(
          icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, size: 16),
          label: Text(_showAdvanced ? 'Hide Advanced' : 'Advanced', style: const TextStyle(fontSize: 12)),
          onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
        ),
      ],
    );
  }

  Widget _buildAdvancedSection(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Custom Headers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface)),
          const SizedBox(height: 8),
          if (_customHeaders.isNotEmpty) ...[
            Wrap(
              spacing: 6, runSpacing: 4,
              children: _customHeaders.entries.map((e) => Chip(
                label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 10)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => _removeCustomHeader(e.key),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _customHeadersController,
                    decoration: const InputDecoration(
                      hintText: 'Header: Value',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addCustomHeader(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: _addCustomHeader,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilenameField(ColorScheme cs) {
    return TextField(
      controller: _filenameController,
      decoration: InputDecoration(
        labelText: 'Filename',
        hintText: 'Auto-detected from URL',
        prefixIcon: const Icon(Icons.description),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textInputAction: TextInputAction.next,
      onChanged: (_) {
        if (_infoFetched) setState(() => _infoFetched = false);
      },
    );
  }

  Widget _buildBatchField(ColorScheme cs) {
    return TextField(
      controller: _batchController,
      maxLines: 6,
      decoration: InputDecoration(
        labelText: 'Paste URLs (one per line)',
        hintText: 'https://example.com/file1.zip\nhttps://example.com/file2.zip',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        errorText: _error,
      ),
      keyboardType: TextInputType.multiline,
    );
  }

  Widget _buildBatchPasteButton(ColorScheme cs) {
    return TextButton.icon(
      icon: const Icon(Icons.content_paste, size: 16),
      label: const Text('Paste from Clipboard', style: TextStyle(fontSize: 12)),
      onPressed: _pasteFromClipboard,
    );
  }

  Widget _buildLinkAnalyzerCard(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: _linkAnalysisExpanded
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : BorderRadius.circular(16),
            onTap: _toggleLinkAnalysis,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.analytics, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('Link Analysis',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.primary)),
                  const Spacer(),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        _linkAnalysisSummary,
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: _chevronAnimation,
                    child: Icon(Icons.expand_more, size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _linkAnalysisExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        _infoRow(Icons.description, 'Filename', _detectedFileName, cs),
                        const SizedBox(height: 8),
                        _infoRow(Icons.storage, 'Size', _fileSize > 0 ? _formatFileSize(_fileSize) : 'Unknown', cs),
                        const SizedBox(height: 8),
                        _infoRow(Icons.insert_drive_file, 'MIME Type', _fileType.isNotEmpty ? _fileType : 'Unknown', cs),
                        const SizedBox(height: 8),
                        _infoRow(Icons.dns, 'Host', _host, cs),
                        const SizedBox(height: 8),
                        _infoRow(Icons.alt_route, 'Final URL', _resolvedUrl.isNotEmpty && _resolvedUrl != _originalUrl
                            ? '${_resolvedUrl.substring(0, _resolvedUrl.length > 40 ? 40 : _resolvedUrl.length)}...' : 'Same as original', cs),
                        const SizedBox(height: 8),
                        _infoRow(Icons.repeat, 'Redirects', '$_redirectCount', cs),
                        const SizedBox(height: 8),
                        _infoRow(
                          _resumeSupported == true ? Icons.replay : Icons.block,
                          'Resume Support',
                          _resumeSupported == true ? 'Yes' : (_resumeSupported == false ? 'No' : 'Unknown'),
                          cs,
                          valueColor: _resumeSupported == true ? Colors.green : (_resumeSupported == false ? cs.error : cs.onSurface.withValues(alpha: 0.5)),
                        ),
                        if (_customHeaders.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _infoRow(Icons.list, 'Custom Headers', '${_customHeaders.length} header(s)', cs),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataFailedWarning(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Metadata could not be retrieved. Download anyway?',
              style: TextStyle(color: cs.error, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _isLoading
                ? FilledButton.icon(
                    onPressed: null,
                    icon: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    label: const Text('Fetching...'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                : _isBatchMode
                    ? FilledButton.icon(
                        onPressed: _startBatchDownload,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Add All'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    : _infoFetched || _metadataFailed
                        ? FilledButton.icon(
                            onPressed: _startDownload,
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Download'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: _fetchInfo,
                            icon: const Icon(Icons.search),
                            label: const Text('Fetch Info'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, ColorScheme cs,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 15, color: cs.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.7), fontSize: 12)),
        const Spacer(),
        Flexible(
          child: Text(value,
              style: TextStyle(color: valueColor ?? cs.onSurface, fontSize: 12, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
