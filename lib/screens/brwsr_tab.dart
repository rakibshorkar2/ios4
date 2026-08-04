import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io' show Platform;
import '../providers/brwsr_provider.dart';
import '../providers/download_provider.dart';
import '../providers/app_state.dart';
import '../services/haptic_service.dart';

class BRWSRTab extends StatefulWidget {
  const BRWSRTab({super.key});

  @override
  State<BRWSRTab> createState() => _BRWSRTabState();
}

class _BRWSRTabState extends State<BRWSRTab> with AutomaticKeepAliveClientMixin {
  late TextEditingController _urlController;
  final FocusNode _urlFocusNode = FocusNode();
  final TextEditingController _findController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();

    _urlFocusNode.addListener(() {
      final provider = context.read<BRWSRProvider>();
      final activeTab = provider.activeTab;
      if (_urlFocusNode.hasFocus && activeTab != null) {
        _urlController.text = activeTab.url;
        _urlController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _urlController.text.length,
        );
      } else if (activeTab != null) {
        _urlController.text = _formatDisplayUrl(activeTab.url);
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    _findController.dispose();
    super.dispose();
  }

  String _formatDisplayUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) {
        return uri.host;
      }
    } catch (_) {}
    return url;
  }

  void _submitUrl(String input, BRWSRProvider provider) {
    _urlFocusNode.unfocus();
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    String finalUrl = trimmed;
    final isUrlPattern = RegExp(
      r'^(https?:\/\/)?([\w\d\-]+\.)+[\w\d\-]+(\/.*)?$',
      caseSensitive: false,
    ).hasMatch(trimmed);

    if (isUrlPattern || trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('localhost')) {
      if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
        finalUrl = 'https://$trimmed';
      }
    } else {
      // Treat as search query
      finalUrl = 'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
    }

    final activeTab = provider.activeTab;
    if (activeTab != null && activeTab.controller != null) {
      activeTab.controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(finalUrl)),
      );
    } else {
      provider.updateActiveTabUrl(finalUrl);
    }
  }

  void _updateDynamicIslandProgress(AppState appState, String title, double progress) {
    if (Platform.isIOS) {
      try {
        const liveChannel = MethodChannel('com.dirxplore/live_activity');
        if (appState.brwsrLiveActivityEnabled) {
          liveChannel.invokeMethod(
            'updateActiveDownloads',
            {
              'count': 1,
              'primary': {
                'title': 'BRWSR: $title',
                'progress': progress,
                'speed': 0.0,
              }
            },
          );
        } else {
          liveChannel.invokeMethod('disable');
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<BRWSRProvider>();
    final appState = context.watch<AppState>();
    final activeTab = provider.activeTab;

    if (activeTab != null && !_urlFocusNode.hasFocus) {
      _urlController.text = _formatDisplayUrl(activeTab.url);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        elevation: 0,
        backgroundColor: activeTab?.isIncognito == true
            ? Colors.grey[900]
            : Theme.of(context).appBarTheme.backgroundColor,
        title: _buildAddressBar(context, provider, activeTab),
        actions: [
          IconButton(
            icon: Icon(
              provider.adBlockerEnabled ? Icons.shield : Icons.shield_outlined,
              color: provider.adBlockerEnabled ? Colors.green : Colors.grey,
            ),
            tooltip: 'Ad Blocker Stats',
            onPressed: () => _showAdBlockerDialog(context, provider),
          ),
          IconButton(
            icon: Icon(
              provider.isBookmarked(activeTab?.url ?? '')
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color: provider.isBookmarked(activeTab?.url ?? '')
                  ? Colors.amber
                  : null,
            ),
            onPressed: () {
              HapticService.light();
              provider.toggleBookmark();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(provider.isBookmarked(activeTab?.url ?? '')
                      ? 'Bookmark added'
                      : 'Bookmark removed'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Linear Progress Bar
            if (activeTab != null && activeTab.isLoading)
              LinearProgressIndicator(
                value: activeTab.progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
                minHeight: 2.5,
              ),

            // Main Web View
            Expanded(
              child: activeTab == null
                  ? const Center(child: Text('No tabs open'))
                  : IndexedStack(
                      index: provider.activeTabIndex,
                      children: provider.tabs.asMap().entries.map((entry) {
                        final index = entry.key;
                        final tab = entry.value;
                        return _buildWebViewForTab(context, provider, appState, tab, index);
                      }).toList(),
                    ),
            ),

            // Find in Page Bar
            if (provider.isFindInPageActive)
              _buildFindInPageBar(context, provider),

            // Bottom Navigation Toolbar
            _buildBottomToolbar(context, provider, activeTab),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressBar(
      BuildContext context, BRWSRProvider provider, BRWSRTabData? activeTab) {
    final isHttps = activeTab?.url.startsWith('https://') ?? false;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _urlController,
        focusNode: _urlFocusNode,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        style: const TextStyle(fontSize: 14),
        onSubmitted: (val) => _submitUrl(val, provider),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          border: InputBorder.none,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (activeTab?.isIncognito == true)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.visibility_off, size: 16, color: Colors.purpleAccent),
                  ),
                Icon(
                  isHttps ? Icons.lock : Icons.lock_open,
                  size: 16,
                  color: isHttps ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ),
          suffixIcon: activeTab?.isLoading == true
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    activeTab?.controller?.stopLoading();
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () {
                    activeTab?.controller?.reload();
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildWebViewForTab(
      BuildContext context, BRWSRProvider provider, AppState appState, BRWSRTabData tab, int index) {
    if (tab.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                'Webpage Unreachable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                tab.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  provider.clearActiveTabError();
                  tab.controller?.reload();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    const defaultDesktopUserAgent =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

    return InAppWebView(
      key: ValueKey('brwsr_tab_${tab.id}'),
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
      findInteractionController: tab.findController,
      initialSettings: InAppWebViewSettings(
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        incognito: tab.isIncognito,
        cacheEnabled: !tab.isIncognito,
        contentBlockers: provider.getAdBlockerRules(),
        userAgent: tab.isDesktopMode ? defaultDesktopUserAgent : null,
        preferredContentMode: tab.isDesktopMode
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.MOBILE,
        useOnDownloadStart: true,
      ),
      onWebViewCreated: (controller) {
        provider.setTabController(index, controller);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        return NavigationActionPolicy.ALLOW;
      },
      onLoadStart: (controller, url) {
        if (url != null && index == provider.activeTabIndex) {
          provider.updateActiveTabUrl(url.toString());
          _updateDynamicIslandProgress(appState, tab.title, 0.1);
        }
      },
      onLoadStop: (controller, url) async {
        if (url != null && index == provider.activeTabIndex) {
          provider.updateActiveTabUrl(url.toString());
          final title = await controller.getTitle() ?? url.toString();
          provider.updateActiveTabTitle(title);

          final canGoBack = await controller.canGoBack();
          final canGoForward = await controller.canGoForward();
          provider.updateActiveTabNavigationState(
            canGoBack: canGoBack,
            canGoForward: canGoForward,
          );

          provider.recordHistory(url.toString(), title);
          _updateDynamicIslandProgress(appState, title, 1.0);
        }
      },
      onProgressChanged: (controller, progress) {
        if (index == provider.activeTabIndex) {
          final p = progress / 100.0;
          provider.updateActiveTabProgress(p);
          _updateDynamicIslandProgress(appState, tab.title, p);
        }
      },
      onTitleChanged: (controller, title) {
        if (title != null && index == provider.activeTabIndex) {
          provider.updateActiveTabTitle(title);
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true && index == provider.activeTabIndex) {
          tab.errorMessage = error.description;
          provider.clearActiveTabError();
        }
      },
      onDownloadStartRequest: (controller, downloadStartRequest) async {
        _handleDownloadStart(context, downloadStartRequest);
      },
      onLoadResource: (controller, resource) {
        // Simple heuristic for blocked ad requests
        final url = resource.url.toString();
        if (provider.adBlockerEnabled &&
            (url.contains('doubleclick') ||
                url.contains('pagead') ||
                url.contains('googlesyndication') ||
                url.contains('adservice'))) {
          provider.registerAdBlockedOnPage();
        }
      },
    );
  }

  void _handleDownloadStart(
      BuildContext context, DownloadStartRequest request) {
    final url = request.url.toString();
    final suggestedFilename = request.suggestedFilename ??
        url.split('/').last.split('?').first;
    final filename = suggestedFilename.isEmpty ? 'download' : suggestedFilename;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Do you want to download $filename?'),
            const SizedBox(height: 8),
            Text(
              url,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final appState = ctx.read<AppState>();
              final dlProvider = ctx.read<DownloadProvider>();
              final messenger = ScaffoldMessenger.of(context);

              Map<String, String>? customHeaders;
              if (url.contains('drive.usercontent.google.com') || url.contains('drive.google.com')) {
                try {
                  final cookies = CookieManager.instance().getCookies(url: WebUri.uri(Uri.parse(url)));
                  final allCookies = await cookies;
                  if (allCookies.isNotEmpty) {
                    final cookieStr = allCookies.map((c) => '${c.name}=${c.value}').join('; ');
                    customHeaders = {'Cookie': cookieStr};
                  }
                } catch (e) {
                  debugPrint('Error getting Google Drive cookies: $e');
                }
              }

              // Before creating a new download, check whether an existing
              // download matches this file. If so, refresh its URL and
              // resume it instead of creating a duplicate.
              final refreshResult =
                  await dlProvider.autoRefreshMatchingDownload(
                url,
                filename,
                customHeaders: customHeaders,
              );
              if (refreshResult == DownloadLinkRefreshResult.updated) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('Download link updated automatically.')),
                );
              } else if (refreshResult == DownloadLinkRefreshResult.updateFailed) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('Unable to update existing download link.')),
                );
              } else {
                await dlProvider.addDownload(
                  url,
                  filename,
                  appState.defaultSavePath,
                  originalUrl: url,
                  customHeaders: customHeaders,
                );
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Download started: $filename'),
                  ),
                );
              }
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Widget _buildFindInPageBar(BuildContext context, BRWSRProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findController,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Find in page...',
                isDense: true,
                border: InputBorder.none,
              ),
              onChanged: (val) => provider.updateFindQuery(val),
            ),
          ),
          if (provider.totalMatches > 0)
            Text(
              '${provider.currentMatchIndex + 1}/${provider.totalMatches}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            )
          else if (provider.findQuery.isNotEmpty)
            const Text(
              'No matches',
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 20),
            onPressed: () => provider.findPrevious(),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 20),
            onPressed: () => provider.findNext(),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              _findController.clear();
              provider.closeFindInPage();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar(
      BuildContext context, BRWSRProvider provider, BRWSRTabData? activeTab) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Back
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: activeTab?.canGoBack == true
                ? () {
                    HapticService.light();
                    activeTab?.controller?.goBack();
                  }
                : null,
          ),
          // Forward
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 20),
            onPressed: activeTab?.canGoForward == true
                ? () {
                    HapticService.light();
                    activeTab?.controller?.goForward();
                  }
                : null,
          ),
          // Home
          IconButton(
            icon: const Icon(Icons.home_outlined, size: 24),
            onPressed: () {
              HapticService.light();
              activeTab?.controller?.loadUrl(
                urlRequest: URLRequest(url: WebUri('https://www.google.com')),
              );
            },
          ),
          // Tabs Badge Switcher
          InkWell(
            onTap: () {
              HapticService.light();
              _showTabSwitcher(context, provider);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${provider.tabs.length}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          // Menu Options
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              HapticService.light();
              _showBrowserMenu(context, provider, activeTab);
            },
          ),
        ],
      ),
    );
  }

  void _showTabSwitcher(BuildContext context, BRWSRProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final tabs = provider.tabs;
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Modal Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tabs (${tabs.length})',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.visibility_off, color: Colors.purpleAccent),
                            tooltip: 'New Private Tab',
                            onPressed: () {
                              provider.addNewTab(isIncognito: true);
                              Navigator.pop(ctx);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 28),
                            tooltip: 'New Tab',
                            onPressed: () {
                              provider.addNewTab();
                              Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: tabs.length,
                      itemBuilder: (context, index) {
                        final tab = tabs[index];
                        final isActive = index == provider.activeTabIndex;
                        return Card(
                          elevation: isActive ? 4 : 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              provider.switchTab(index);
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (tab.isIncognito)
                                        const Icon(Icons.visibility_off,
                                            size: 16, color: Colors.purpleAccent),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          tab.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          provider.closeTab(index);
                                          setModalState(() {});
                                        },
                                        child: const Icon(Icons.close, size: 18),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    tab.url,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      tab.isIncognito ? Icons.visibility_off : Icons.public,
                                      size: 32,
                                      color: tab.isIncognito ? Colors.purple : Colors.blueAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showBrowserMenu(
      BuildContext context, BRWSRProvider provider, BRWSRTabData? activeTab) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.bookmarks),
                title: const Text('Bookmarks & History'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showBookmarksAndHistoryModal(context, provider);
                },
              ),
              ListTile(
                leading: const Icon(Icons.find_in_page),
                title: const Text('Find in Page'),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.openFindInPage();
                },
              ),
              ListTile(
                leading: Icon(
                  activeTab?.isDesktopMode == true
                      ? Icons.desktop_windows
                      : Icons.phone_iphone,
                ),
                title: Text(
                  activeTab?.isDesktopMode == true
                      ? 'Request Mobile Site'
                      : 'Request Desktop Site',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.toggleDesktopMode();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share Webpage'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (activeTab?.url != null && activeTab!.url.isNotEmpty) {
                    Share.share(activeTab.url);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Link'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (activeTab?.url != null) {
                    Clipboard.setData(ClipboardData(text: activeTab!.url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URL copied to clipboard')),
                    );
                  }
                },
              ),
              SwitchListTile(
                secondary: Icon(
                  provider.adBlockerEnabled ? Icons.shield : Icons.shield_outlined,
                  color: provider.adBlockerEnabled ? Colors.green : Colors.grey,
                ),
                title: const Text('Built-in Ad Blocker'),
                subtitle: Text(
                  'Blocked ${provider.totalAdsBlockedSession} requests this session',
                ),
                value: provider.adBlockerEnabled,
                onChanged: (val) {
                  provider.toggleAdBlocker();
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBookmarksAndHistoryModal(
      BuildContext context, BRWSRProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.bookmark), text: 'Bookmarks'),
                    Tab(icon: Icon(Icons.history), text: 'History'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Bookmarks List
                      provider.bookmarks.isEmpty
                          ? const Center(child: Text('No bookmarks saved'))
                          : ListView.builder(
                              itemCount: provider.bookmarks.length,
                              itemBuilder: (context, index) {
                                final item = provider.bookmarks[index];
                                return ListTile(
                                  leading: const Icon(Icons.bookmark_outline),
                                  title: Text(item.title, maxLines: 1),
                                  subtitle: Text(item.url, maxLines: 1),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () {
                                      provider.removeBookmark(item.id);
                                    },
                                  ),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    provider.activeTab?.controller?.loadUrl(
                                      urlRequest: URLRequest(url: WebUri(item.url)),
                                    );
                                  },
                                );
                              },
                            ),

                      // History List
                      provider.history.isEmpty
                          ? const Center(child: Text('No browsing history'))
                          : Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      provider.clearHistory();
                                    },
                                    icon: const Icon(Icons.delete_sweep),
                                    label: const Text('Clear History'),
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: provider.history.length,
                                    itemBuilder: (context, index) {
                                      final item = provider.history[index];
                                      return ListTile(
                                        leading: const Icon(Icons.history),
                                        title: Text(item.title, maxLines: 1),
                                        subtitle: Text(item.url, maxLines: 1),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.close, size: 18),
                                          onPressed: () {
                                            provider.removeHistoryItem(item.id);
                                          },
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          provider.activeTab?.controller?.loadUrl(
                                            urlRequest: URLRequest(url: WebUri(item.url)),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAdBlockerDialog(BuildContext context, BRWSRProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              provider.adBlockerEnabled ? Icons.shield : Icons.shield_outlined,
              color: provider.adBlockerEnabled ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            const Text('BRWSR Ad Blocker'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${provider.adBlockerEnabled ? "Enabled (Blocking Ads)" : "Disabled"}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: provider.adBlockerEnabled ? Colors.green : Colors.redAccent,
              ),
            ),
            const SizedBox(height: 12),
            Text('Ads & trackers blocked on this page: ${provider.activeTab?.adsBlockedCount ?? 0}'),
            const SizedBox(height: 4),
            Text('Total blocked this session: ${provider.totalAdsBlockedSession}'),
            const SizedBox(height: 12),
            const Text(
              'Blocks known advertising domains, analytics trackers, and popup scripts using native content rule lists.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.toggleAdBlocker();
              Navigator.pop(ctx);
            },
            child: Text(provider.adBlockerEnabled ? 'Turn OFF' : 'Turn ON'),
          ),
        ],
      ),
    );
  }
}
