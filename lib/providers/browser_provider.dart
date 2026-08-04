import 'package:flutter/foundation.dart';
import '../models/directory_item.dart';
import '../services/dio_client.dart';
import '../services/html_parser.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class BrowserProvider with ChangeNotifier {
  final List<String> _history = [];
  String _currentUrl = '';
  List<DirectoryItem> _items = [];
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isFallbackMode = false;

  List<Map<String, String>> _bookmarks = [];

  BrowserProvider() {
    _loadBookmarks();
  }

  // Sorting & Filtering
  String _searchQuery = '';
  String _selectedCategory = 'All Categories';
  bool _foldersFirst = true;

  String get currentUrl => _currentUrl;
  List<DirectoryItem> get items => _getFilteredAndSortedItems();
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get canGoBack => _history.length > 1;
  bool get isFallbackMode => _isFallbackMode;

  List<Map<String, String>> get bookmarks => _bookmarks;
  bool get isCurrentBookmarked =>
      _bookmarks.any((b) => b['url'] == _currentUrl);

  final Map<String, List<String>> _categories = {
    'All Categories': [],
    'Movies': ['1080p', '720p', 'bluray', 'mkv', 'mp4', 'avi', 'movie'],
    'Series/TV': ['s01', 'e01', 'season', 'episode', 'hdtv'],
    'Games': ['repack', 'iso', 'codex', 'skidrow', 'fitgirl', 'pc'],
    'Software': ['crack', 'keygen', 'setup', 'exe', 'mac', 'win'],
    'Anime': ['anime', 'sub', 'dub', '1080p', '720p', 'mkv'],
    'Images': ['jpg', 'png', 'gif', 'jpeg', 'webp'],
  };

  bool _isGridView = false;
  bool get isGridView => _isGridView;

  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  void toggleFallbackMode() {
    _isFallbackMode = !_isFallbackMode;
    notifyListeners();
  }

  List<String> get breadcrumbs {
    if (_currentUrl.isEmpty) return [];
    try {
      final uri = Uri.parse(_currentUrl);
      return [uri.host, ...uri.pathSegments.where((p) => p.isNotEmpty)];
    } catch (_) {
      return [];
    }
  }

  List<String> get categories => _categories.keys.toList();
  String get selectedCategory => _selectedCategory;

  void setCategory(String cat) {
    _selectedCategory = cat;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q.toLowerCase();
    notifyListeners();
  }

  void toggleSort() {
    _foldersFirst = !_foldersFirst;
    notifyListeners();
  }

  void toggleSelection(DirectoryItem item) {
    item.isSelected = !item.isSelected;
    notifyListeners();
  }

  void selectAll(bool select) {
    for (var item in _items) {
      item.isSelected = select;
    }
    notifyListeners();
  }

  List<DirectoryItem> getSelectedItems() {
    return _items.where((i) => i.isSelected).toList();
  }

  void goBack() {
    if (canGoBack) {
      _history.removeLast();
      _loadUrl(_history.last, addToHistory: false);
    }
  }

  void goUp() {
    if (_currentUrl.isEmpty) return;
    try {
      final uri = Uri.parse(_currentUrl);
      final paths = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (paths.isNotEmpty) {
        paths.removeLast();
        final newUri = uri.replace(pathSegments: paths);
        String finalUrl = newUri.toString();
        if (!finalUrl.endsWith('/')) finalUrl += '/';
        _loadUrl(finalUrl, addToHistory: true);
      }
    } catch (_) {}
  }

  // --- Bookmarks ---
  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('browser_bookmarks');
    if (str != null) {
      final List<dynamic> decoded = jsonDecode(str);
      _bookmarks = decoded.map((e) => Map<String, String>.from(e)).toList();
    }

    // Add defaults if missing
    final defaultBookmarks = [
      {'url': 'http://new.circleftp.net/', 'name': 'Circle FTP'},
      {'url': 'http://172.16.50.4/', 'name': 'Local FTP'},
    ];

    bool added = false;
    for (var db in defaultBookmarks) {
      if (!_bookmarks.any((b) => b['url'] == db['url'])) {
        _bookmarks.add(db);
        added = true;
      }
    }

    if (added) {
      await _saveBookmarks();
    }
    notifyListeners();
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('browser_bookmarks', jsonEncode(_bookmarks));
  }

  void toggleBookmark() {
    if (_currentUrl.isEmpty) return;
    final exists = _bookmarks.any((b) => b['url'] == _currentUrl);
    if (exists) {
      _bookmarks.removeWhere((b) => b['url'] == _currentUrl);
    } else {
      String name = _currentUrl;
      try {
        final uri = Uri.parse(_currentUrl);
        if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty) {
          name = uri.pathSegments.last;
        } else if (uri.pathSegments.length > 1) {
          name = uri.pathSegments[uri.pathSegments.length - 2];
        } else {
          name = uri.host;
        }
      } catch (_) {}
      _bookmarks.add({'url': _currentUrl, 'name': name});
    }
    _saveBookmarks();
    notifyListeners();
  }

  void removeBookmark(String url) {
    _bookmarks.removeWhere((b) => b['url'] == url);
    _saveBookmarks();
    notifyListeners();
  }
  // -----------------

  void loadBreadcrumb(int index) {
    if (_currentUrl.isEmpty) return;
    try {
      final uri = Uri.parse(_currentUrl);
      final paths = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (index == 0) {
        _loadUrl('${uri.scheme}://${uri.host}/', addToHistory: true);
      } else if (index <= paths.length) {
        final newPaths = paths.sublist(0, index);
        final newUri = uri.replace(pathSegments: newPaths);
        String finalUrl = newUri.toString();
        if (!finalUrl.endsWith('/')) finalUrl += '/';
        _loadUrl(finalUrl, addToHistory: true);
      }
    } catch (_) {}
  }

  Future<void> loadUrl(String url) async {
    if (!url.startsWith('http')) url = 'http://$url';
    if (!url.endsWith('/')) url += '/';
    _loadUrl(url, addToHistory: true);
  }

  Future<void> _loadUrl(String url, {bool addToHistory = true}) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final dio = DioClient().dio;
      final response = await dio.get(url);

      final htmlStr = response.data.toString();
      _items = await HtmlParserService.parseApacheDirectoryAsync(htmlStr, url);

      // Auto-fallback check: If it's a 200 OK but we got 0 directory items,
      // it's likely a custom website (like CircleFTP) and not a raw directory listing.
      if (_items.isEmpty && htmlStr.isNotEmpty && htmlStr.contains('<html')) {
        _isFallbackMode = true;
      } else {
        _isFallbackMode = false;
      }

      _currentUrl = url;
      if (addToHistory) {
        if (_history.isEmpty || _history.last != url) {
          _history.add(url);
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        _errorMessage =
            'Connection Timed Out. Please check your proxy or network.';
      } else {
        _errorMessage =
            'Network Error: ${e.message ?? e.error?.toString() ?? "Unknown connection issue."}';
      }
      _items = [];
    } catch (e) {
      _errorMessage = 'Error parsing directory: $e';
      _items = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<DirectoryItem> _getFilteredAndSortedItems() {
    var filtered = _items;

    // Apply Search Query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((i) => i.name.toLowerCase().contains(_searchQuery))
          .toList();
    }

    // Apply Category keywords
    if (_selectedCategory != 'All Categories') {
      final keywords = _categories[_selectedCategory]!;
      filtered = filtered.where((i) {
        final nameL = i.name.toLowerCase();
        return i.isDirectory || keywords.any((k) => nameL.contains(k));
      }).toList();
    }

    // Apply Sorting
    filtered.sort((a, b) {
      if (_foldersFirst) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }
}
