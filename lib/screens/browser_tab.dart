import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../providers/browser_provider.dart';
import '../providers/download_provider.dart';
import '../providers/app_state.dart';
import '../models/directory_item.dart';
import '../services/proxy_tunnel.dart';
import '../services/haptic_service.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'media_player_screen.dart';
import 'download_preview_screen.dart';

class BrowserTab extends StatefulWidget {
  const BrowserTab({super.key});

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = 'http://172.16.50.4/';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BrowserProvider>().loadUrl(_urlCtrl.text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final browserState = context.watch<BrowserProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Directory Browser'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_back, size: 20),
                      onPressed:
                          browserState.canGoBack ? () { HapticService.light(); browserState.goBack(); } : null,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      onPressed: () { HapticService.light(); browserState.goUp(); },
                    ),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _urlCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'URL',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (val) => browserState.loadUrl(val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Filter',
                            prefixIcon: Icon(Icons.filter_list, size: 18),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: browserState.setSearchQuery,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.search, size: 20),
                      onPressed: () { HapticService.light(); browserState.loadUrl(_urlCtrl.text); },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () { HapticService.light(); browserState.loadUrl(browserState.currentUrl); },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade700),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: browserState.selectedCategory,
                            isExpanded: true,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.blueGrey),
                            items: browserState.categories.map((c) {
                              return DropdownMenuItem(value: c, child: Text(c));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) { HapticService.selection(); browserState.setCategory(val); }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              browserState.isFallbackMode ? Icons.folder_open : Icons.public,
              color: browserState.isFallbackMode ? Colors.orange : Colors.blue,
            ),
            tooltip: browserState.isFallbackMode
                ? 'Switch to Native Mode'
                : 'Switch to WebView Mode',
            onPressed: () {
              HapticService.medium();
              browserState.toggleFallbackMode();
            },
          ),
          IconButton(
            icon: Icon(browserState.isCurrentBookmarked
                ? Icons.star
                : Icons.star_border),
            color: browserState.isCurrentBookmarked ? Colors.amber : null,
            tooltip: 'Bookmark Page',
            onPressed: () { HapticService.light(); browserState.toggleBookmark(); },
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks),
            tooltip: 'Bookmarks',
            onPressed: () => _showBookmarksDialog(context, browserState),
          ),
          if (!browserState.isFallbackMode) ...[
            IconButton(
              icon:
                  Icon(browserState.isGridView ? Icons.list : Icons.grid_view),
              tooltip: 'Toggle View',
              onPressed: () { HapticService.light(); browserState.toggleViewMode(); },
            ),
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: 'Toggle Sort Options',
              onPressed: () { HapticService.light(); browserState.toggleSort(); },
            ),
          ],
        ],
      ),
      body: browserState.isFallbackMode
          ? _buildWebView(context, browserState)
          : Column(
              children: [
                if (browserState.breadcrumbs.isNotEmpty)
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: browserState.breadcrumbs.length,
                      separatorBuilder: (c, i) => const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.grey),
                      itemBuilder: (context, index) {
                        return InkWell(
                          onTap: () {
                            HapticService.light();
                            browserState.loadBreadcrumb(index);
                            _urlCtrl.text = browserState.currentUrl;
                          },
                          child: Center(
                            child: Text(
                              browserState.breadcrumbs[index],
                              style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: browserState.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : browserState.errorMessage.isNotEmpty
                          ? Center(
                              child: Text(browserState.errorMessage,
                                  style: const TextStyle(color: Colors.red)))
                          : (browserState.isGridView
                              ? GridView.builder(
                                  padding: const EdgeInsets.all(8.0),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 0.85,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                                  itemCount: browserState.items.length + 1,
                                  itemBuilder: (context, index) {
                                    if (index == browserState.items.length) {
                                      return const SizedBox(height: 100);
                                    }
                                    final item = browserState.items[index];
                                    return InkWell(
                                      onTap: () {
                                        HapticService.light();
                                        if (item.isDirectory) {
                                          _urlCtrl.text = item.url;
                                          browserState.loadUrl(item.url);
                                        } else {
                                          _showItemOptions(context, item);
                                        }
                                      },
                                      onLongPress: () {
                                        HapticService.medium();
                                        browserState.toggleSelection(item);
                                      },
                                      child: Card(
                                        color: item.isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                            : null,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Stack(
                                              alignment: Alignment.topRight,
                                              children: [
                                                Center(
                                                  child: Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                      if (!item.isDirectory &&
                                                          [
                                                            'jpg',
                                                            'jpeg',
                                                            'png',
                                                            'gif',
                                                            'webp'
                                                          ].contains(item.name
                                                              .split('.')
                                                              .last
                                                              .toLowerCase()))
                                                        Positioned.fill(
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .vertical(
                                                                    top: Radius
                                                                        .circular(
                                                                            12)),
                                                            child:
                                                                Image.network(
                                                              item.url,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (_,
                                                                      __,
                                                                      ___) =>
                                                                  Icon(
                                                                _getIconForExtension(
                                                                    item.name),
                                                                size: 48,
                                                                color: _getColorForExtension(
                                                                    item.name),
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      else
                                                        Icon(
                                                          item.isDirectory
                                                              ? Icons.folder
                                                              : _getIconForExtension(
                                                                  item.name),
                                                          size: 48,
                                                          color: item
                                                                  .isDirectory
                                                              ? Colors.amber
                                                              : _getColorForExtension(
                                                                  item.name),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                if (item.isSelected)
                                                  const Icon(Icons.check_circle,
                                                      color: Colors.green,
                                                      size: 18),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            if (!item.isDirectory &&
                                                _isPlayableMedia(item.name))
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  InkWell(
                                                    onTap: () {
                                                      final videoFiles = browserState.items.where((i) => !i.isDirectory && _isPlayableMedia(i.name)).toList();
    final playlist = videoFiles.map((i) => <String, String>{ 'url': ProxyTunnel().getTunnelUrl(i.url), 'title': i.name }).toList();
                                                       final initialIndex = videoFiles.indexWhere((i) => i.url == item.url);
                                                      
                                                      Navigator.push(
                                                          context,
                                                          CupertinoPageRoute(
                                                            builder: (_) =>
                                                                MediaPlayerScreen(
                                                                    url: playlist[initialIndex]['url']!,
                                                                    title: playlist[initialIndex]['title']!,
                                                                    playlist: playlist,
                                                                    initialIndex: initialIndex),
                                                          ));
                                                    },
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black45,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                      ),
                                                      child: const Icon(
                                                          Icons.play_arrow,
                                                          color: Colors.white,
                                                          size: 20),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  InkWell(
                                                    onTap: () =>
                                                        _showItemOptions(
                                                            context, item),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black45,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                      ),
                                                      child: const Icon(
                                                          Icons.open_in_new,
                                                          color: Colors.white,
                                                          size: 20),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            if (!item.isDirectory &&
                                                _isPlayableMedia(item.name))
                                              const SizedBox(height: 4),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4.0),
                                              child: Text(
                                                item.name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : ListView.builder(
                                  itemExtent: 72.0,
                                  itemCount: browserState.items.length + 1,
                                  itemBuilder: (context, index) {
                                    if (index == browserState.items.length) {
                                      return const SizedBox(height: 100);
                                    }
                                    final item = browserState.items[index];
                                    return ListTile(
                                      leading: Icon(
                                        item.isDirectory
                                            ? Icons.folder
                                            : _getIconForExtension(item.name),
                                        color: item.isDirectory
                                            ? Colors.amber
                                            : _getColorForExtension(item.name),
                                      ),
                                      title: Text(
                                        item.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13, height: 1.1),
                                      ),
                                      subtitle: item.size != null &&
                                              item.size!.isNotEmpty
                                          ? Text(item.size!,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.blueAccent))
                                          : null,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 0),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!item.isDirectory &&
                                              _isPlayableMedia(item.name))
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              icon: const Icon(
                                                  Icons.play_circle_outline,
                                                  color: Colors.blue,
                                                  size: 22),
                                              tooltip: 'Play in app',
                                              onPressed: () {
                                                final tunnelUrl = ProxyTunnel()
                                                    .getTunnelUrl(item.url);
                                                Navigator.push(
                                                    context,
                                                    CupertinoPageRoute(
                                                      builder: (_) =>
                                                          MediaPlayerScreen(
                                                              url: tunnelUrl,
                                                              title: item.name),
                                                    ));
                                              },
                                            ),
                                          if (!item.isDirectory &&
                                              _isPlayableMedia(item.name))
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              icon: const Icon(
                                                  Icons.open_in_new,
                                                  color: Colors.orange,
                                                  size: 22),
                                              tooltip: 'External options',
                                              onPressed: () => _showItemOptions(
                                                  context, item),
                                            ),
                                          SizedBox(
                                            width: 24,
                                            child: Checkbox(
                                              value: item.isSelected,
                                              onChanged: (val) {
                                                HapticService.selection();
                                                browserState.toggleSelection(item);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () {
                                        HapticService.light();
                                        if (item.isDirectory) {
                                          _urlCtrl.text = item.url;
                                          browserState.loadUrl(item.url);
                                        } else {
                                          _showItemOptions(context, item);
                                        }
                                      },
                                    );
                                  },
                                )),
                ),
              ],
            ),
      floatingActionButton: browserState.getSelectedItems().isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(bottom: 90.0),
              child: FloatingActionButton.extended(
                onPressed: () async {
                  HapticService.medium();
                  bool hasPermission = Platform.isIOS; // iOS sandbox is always accessible
                  if (!Platform.isIOS) {
                    hasPermission = await Permission.manageExternalStorage.isGranted ||
                        await Permission.storage.isGranted;
                    if (!hasPermission) {
                      final statusManage =
                          await Permission.manageExternalStorage.request();
                      final statusStorage = await Permission.storage.request();
                      if (statusManage.isGranted || statusStorage.isGranted) {
                        hasPermission = true;
                      }
                    }
                  }

                  if (!hasPermission) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Storage permission is required to download files.')),
                      );
                    }
                    return;
                  }
                  if (!mounted) {
                    return;
                  }
                  if (!context.mounted) {
                    return;
                  }

                  final dlProvider = context.read<DownloadProvider>();
                  final appState = context.read<AppState>();
                  final selected = browserState.getSelectedItems();

                  final List<DirectoryItem> filesToQueueDirectly = [];

                  for (var item in selected) {
                    if (item.isDirectory) {
                      // Show loading dialog while crawling
                      if (context.mounted) {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) =>
                              const Center(child: CircularProgressIndicator()),
                        );
                      }

                      final items =
                          await dlProvider.crawlFolder(item.url, item.name);

                      if (context.mounted) {
                        Navigator.pop(context); // Remove loading dialog
                      }

                      if (context.mounted) {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (context) => DownloadPreviewScreen(
                              folderUrl: item.url,
                              folderName: item.name,
                              baseSaveDir: appState.defaultSavePath,
                              initialItems: items,
                            ),
                          ),
                        );
                      }
                    } else {
                      filesToQueueDirectly.add(item);
                    }
                  }

                  for (var item in filesToQueueDirectly) {
                    dlProvider.addDownload(
                        item.url, item.name, appState.defaultSavePath);
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('Added ${selected.length} items to queue')),
                    );
                  }

                  browserState.selectAll(false);
                },
                icon: const Icon(Icons.download),
                label: Text(
                    'Queue Selected (${browserState.getSelectedItems().length})'),
              ),
            )
          : null,
    );
  }

  Widget _buildWebView(BuildContext context, BrowserProvider browserState) {
    final initialUrl = browserState.currentUrl.isNotEmpty
        ? WebUri(browserState.currentUrl)
        : WebUri('http://new.circleftp.net/');

    final mediaExtensions = [
      'mp4',
      'mkv',
      'avi',
      'mov',
      'webm',
      'mp3',
      'flac',
      'wav'
    ];
    final downloadExtensions = [
      'zip',
      'rar',
      '7z',
      'tar',
      'gz',
      'apk',
      'pdf',
      'iso',
      'img'
    ];

    return InAppWebView(
      key: ValueKey(initialUrl.toString()),
      initialUrlRequest: URLRequest(url: initialUrl),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useShouldOverrideUrlLoading: true,
        useOnDownloadStart: true,
        userAgent:
            'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36',
      ),
      onWebViewCreated: (controller) {
        // controller available if needed later
      },
      onLoadStart: (controller, url) {
        if (url != null) {
          _urlCtrl.text = url.toString();
        }
      },
      onLoadStop: (controller, url) async {
        if (url != null) {
          _urlCtrl.text = url.toString();
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        final ext = url.split('?').first.split('.').last.toLowerCase();

        if (mediaExtensions.contains(ext) || downloadExtensions.contains(ext)) {
          final name = Uri.parse(url)
              .pathSegments
              .lastWhere((s) => s.isNotEmpty, orElse: () => 'file');

          final item = DirectoryItem(
            name: name,
            url: url,
            type: DirectoryItem.typeFromExtension(name),
            size: null,
          );

          if (context.mounted) {
            _showItemOptions(context, item);
          }

          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },
      onDownloadStartRequest: (controller, request) {
        final url = request.url.toString();
        final name = Uri.parse(url)
            .pathSegments
            .lastWhere((s) => s.isNotEmpty, orElse: () => 'file');

        final item = DirectoryItem(
          name: name,
          url: url,
          type: DirectoryItem.typeFromExtension(name),
          size: null,
        );

        if (context.mounted) {
          _showItemOptions(context, item);
        }
      },
    );
  }

  void _showItemOptions(BuildContext context, DirectoryItem item) {
    if (item.isDirectory) return;

    final bool isMedia = _isPlayableMedia(item.name);
    final browserState = context.read<BrowserProvider>();
    final videoFiles = isMedia ? browserState.items.where((i) => !i.isDirectory && _isPlayableMedia(i.name)).toList() : [];
    final playlist = videoFiles.map((i) => <String, String>{ 'url': ProxyTunnel().getTunnelUrl(i.url), 'title': i.name }).toList();
    final initialIndex = videoFiles.indexWhere((i) => i.url == item.url);

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        message: const Text('Choose Action'),
        actions: [
          if (isMedia)
            CupertinoActionSheetAction(
              onPressed: () {
                HapticService.medium();
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => MediaPlayerScreen(
                      url: playlist.isNotEmpty ? playlist[initialIndex >= 0 ? initialIndex : 0]['url'] ?? item.url : item.url,
                      title: item.name,
                      playlist: playlist,
                      initialIndex: initialIndex >= 0 ? initialIndex : 0,
                    ),
                  ),
                );
              },
              child: const Row(
                children: [
                  Icon(Icons.play_circle_fill, color: CupertinoColors.activeBlue, size: 22),
                  SizedBox(width: 12),
                  Text('Play in App'),
                ],
              ),
            ),
          if (isMedia && (Platform.isAndroid || Platform.isIOS))
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                final tunnelUrl = ProxyTunnel().getTunnelUrl(item.url);
                if (Platform.isAndroid) {
                  try {
                    final intent = AndroidIntent(
                      action: 'action_view',
                      package: 'org.videolan.vlc',
                      data: tunnelUrl,
                      type: 'video/*',
                      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                    );
                    await intent.launch();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('VLC could not be launched. Ensure it is installed.')));
                    }
                  }
                } else if (Platform.isIOS) {
                  try {
                    // Present share sheet with the original URL so user can open in VLC
                    // VLC on iOS can't reach the local proxy tunnel, so use original URL
                    const iosChannel = MethodChannel('com.dirxplore/ios_download');
                    await iosChannel.invokeMethod('openURL', {'url': item.url});
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('VLC for iOS is not installed.')));
                    }
                  }
                }
              },
              child: const Row(
                children: [
                  Icon(Icons.play_arrow, color: CupertinoColors.activeOrange, size: 22),
                  SizedBox(width: 12),
                  Text('Play with VLC'),
                ],
              ),
            ),
          if (isMedia && Platform.isAndroid)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                final tunnelUrl = ProxyTunnel().getTunnelUrl(item.url);
                try {
                  final intent = AndroidIntent(
                    action: 'action_view',
                    package: 'com.mxtech.videoplayer.ad',
                    data: tunnelUrl,
                    type: 'video/*',
                    flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                  );
                  await intent.launch();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('MX Player could not be launched. Ensure it is installed.')));
                  }
                }
              },
              child: const Row(
                children: [
                  Icon(Icons.play_arrow, color: CupertinoColors.systemPurple, size: 22),
                  SizedBox(width: 12),
                  Text('Play with MX Player'),
                ],
              ),
            ),
          if (Platform.isAndroid)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                final tunnelUrl = ProxyTunnel().getTunnelUrl(item.url);
                try {
                  final intent = AndroidIntent(
                    action: 'action_view',
                    package: 'idm.internet.download.manager',
                    data: tunnelUrl,
                    flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                  );
                  await intent.launch();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('1DM could not be launched. Ensure it is installed.')));
                  }
                }
              },
              child: const Row(
                children: [
                  Icon(Icons.download, color: CupertinoColors.activeGreen, size: 22),
                  SizedBox(width: 12),
                  Text('Download using 1DM'),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              HapticService.medium();
              Navigator.pop(ctx);
              context.read<BrowserProvider>().toggleSelection(item);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Selected, tap Queue Selected below to start')));
            },
            child: const Row(
              children: [
                Icon(Icons.download_done, color: CupertinoColors.activeGreen, size: 22),
                SizedBox(width: 12),
                Text('Queue in App'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  bool _isPlayableMedia(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext);
  }

  IconData _getIconForExtension(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
      return Icons.video_file;
    }
    if (['mp3', 'wav', 'flac'].contains(ext)) {
      return Icons.audio_file;
    }
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return Icons.image;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.folder_zip;
    }
    if (['apk'].contains(ext)) {
      return Icons.android;
    }
    return Icons.insert_drive_file;
  }

  Color _getColorForExtension(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
      return Colors.purple;
    }
    if (['mp3', 'wav', 'flac'].contains(ext)) {
      return Colors.orange;
    }
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return Colors.green;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Colors.red;
    }
    if (['apk'].contains(ext)) {
      return Colors.greenAccent.shade700;
    }
    return Colors.blueGrey;
  }

  void _showBookmarksDialog(
      BuildContext context, BrowserProvider browserState) {
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Bookmarks'),
            content: SizedBox(
              width: double.maxFinite,
              child: Consumer<BrowserProvider>(
                builder: (context, provider, child) {
                  if (provider.bookmarks.isEmpty) {
                    return const Text(
                        'No bookmarks saved yet.\nTap the star icon to save a folder.');
                  }
                  return ListView.builder(
                      shrinkWrap: true,
                      itemCount: provider.bookmarks.length,
                      itemBuilder: (context, index) {
                        final b = provider.bookmarks[index];
                        return ListTile(
                          leading: const Icon(Icons.folder_special,
                              color: Colors.amber),
                          title: Text(b['name'] ?? 'Unknown',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(b['url'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => provider.removeBookmark(b['url']!),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _urlCtrl.text = b['url']!;
                            provider.loadUrl(b['url']!);
                          },
                        );
                      });
                },
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'))
            ],
          );
        });
  }
}
