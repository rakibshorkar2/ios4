import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/directory_item.dart';
import '../providers/download_provider.dart';

class DownloadPreviewScreen extends StatefulWidget {
  final String folderUrl;
  final String folderName;
  final String baseSaveDir;
  final List<DirectoryItem> initialItems;

  const DownloadPreviewScreen({
    super.key,
    required this.folderUrl,
    required this.folderName,
    required this.baseSaveDir,
    required this.initialItems,
  });

  @override
  State<DownloadPreviewScreen> createState() => _DownloadPreviewScreenState();
}

class _DownloadPreviewScreenState extends State<DownloadPreviewScreen> {
  late List<DirectoryItem> _items;
  final Set<int> _selectedIndices = {};
  String _filterQuery = '';
  final TextEditingController _regexController = TextEditingController();
  bool _useRegex = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    // Smart Default: Select videos and archives by default
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final nameLower = item.name.toLowerCase();
      if (item.type == DirectoryItemType.video ||
          item.type == DirectoryItemType.archive ||
          nameLower.contains('1080p') ||
          nameLower.contains('720p') ||
          nameLower.contains('bluray')) {
        _selectedIndices.add(i);
      }
    }
  }

  List<DirectoryItem> get _filteredItems {
    if (_filterQuery.isEmpty) return _items;

    try {
      if (_useRegex) {
        final regex = RegExp(_filterQuery, caseSensitive: false);
        return _items.where((item) => regex.hasMatch(item.name)).toList();
      } else {
        return _items
            .where((item) =>
                item.name.toLowerCase().contains(_filterQuery.toLowerCase()))
            .toList();
      }
    } catch (e) {
      return _items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;
    final dlProvider = context.read<DownloadProvider>();

    // Calculate current visible selected count
    final filteredIndices =
        filtered.map((item) => _items.indexOf(item)).toSet();
    final visibleSelectedCount =
        _selectedIndices.intersection(filteredIndices).length;
    final allVisibleSelected = filteredIndices.isNotEmpty &&
        filteredIndices.every((idx) => _selectedIndices.contains(idx));

    return Scaffold(
      appBar: AppBar(
        title: Text('Preview: ${widget.folderName}'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                if (allVisibleSelected) {
                  // Deselect visible
                  _selectedIndices.removeAll(filteredIndices);
                } else {
                  // Select visible
                  _selectedIndices.addAll(filteredIndices);
                }
              });
            },
            child: Text(_filterQuery.isEmpty
                ? (allVisibleSelected ? 'DESELECT ALL' : 'SELECT ALL')
                : (allVisibleSelected
                    ? 'DESELECT FILTERED'
                    : 'SELECT FILTERED')),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _regexController,
                    decoration: InputDecoration(
                      hintText: _useRegex
                          ? 'Regex filter (e.g. .*720p.*)'
                          : 'Filter files...',
                      prefixIcon: const Icon(Icons.filter_list),
                      suffixIcon: _filterQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _regexController.clear();
                                setState(() => _filterQuery = '');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) => setState(() => _filterQuery = val),
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Regex'),
                  selected: _useRegex,
                  onSelected: (val) => setState(() => _useRegex = val),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildQuickChip('All', ''),
                _buildQuickChip('Videos', r'mp4|mkv|avi|webm'),
                _buildQuickChip('Archives', r'zip|rar|7z'),
                _buildQuickChip('1080p', '1080p'),
                _buildQuickChip('720p', '720p'),
                _buildQuickChip('High Res', r'bluray|bdrip|imax'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                final originalIndex = _items.indexOf(item);
                final isSelected = _selectedIndices.contains(originalIndex);

                return CheckboxListTile(
                  title: Text(item.name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(item.size ?? 'Unknown size',
                      style: const TextStyle(fontSize: 12)),
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedIndices.add(originalIndex);
                      } else {
                        _selectedIndices.remove(originalIndex);
                      }
                    });
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Smarter counter: shows visible selection if filtered
                Expanded(
                  child: Text(
                    _filterQuery.isEmpty
                        ? '${_selectedIndices.length} files selected'
                        : '$visibleSelectedCount / ${filtered.length} filtered files selected (${_selectedIndices.length} total)',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Add to Queue'),
                  onPressed: _selectedIndices.isEmpty
                      ? null
                      : () {
                          final selectedItems =
                              _selectedIndices.map((i) => _items[i]).toList();
                          final batchId =
                              DateTime.now().millisecondsSinceEpoch.toString();

                          for (var item in selectedItems) {
                            dlProvider.addDownload(
                              item.url,
                              item.name,
                              widget.baseSaveDir,
                              batchId: batchId,
                              batchName: widget.folderName,
                            );
                          }
                          Navigator.pop(context);
                        },
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, String query) {
    final isSelected = _filterQuery == query && (query.isEmpty || _useRegex);
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (val) {
          setState(() {
            if (val) {
              _filterQuery = query;
              _regexController.text = query;
              if (query.isNotEmpty &&
                  (query.contains('|') ||
                      query == '1080p' ||
                      query == '720p')) {
                _useRegex = true;
              }
            } else {
              _filterQuery = '';
              _regexController.text = '';
            }
          });
        },
      ),
    );
  }
}
