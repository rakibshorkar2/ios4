import 'dart:math';
import 'dart:io' show File, Platform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';
import '../services/thumbnail_service.dart';
import '../services/haptic_service.dart';
import 'new_download_sheet.dart';

class DownloadTab extends StatefulWidget {
  const DownloadTab({super.key});

  @override
  State<DownloadTab> createState() => _DownloadTabState();
}

class _DownloadTabState extends State<DownloadTab> {
  final Set<String> _expandedBatchIds = {};

  @override
  Widget build(BuildContext context) {
    final dlProvider = context.watch<DownloadProvider>();
    final queue = dlProvider.queue;
    final cs = Theme.of(context).colorScheme;

    final Map<String?, List<DownloadItem>> grouped = {};
    for (var item in queue) {
      grouped.putIfAbsent(item.batchId, () => []).add(item);
    }

    final batchIds = grouped.keys.toList();
    batchIds.sort((a, b) {
      if (a == null) return -1;
      if (b == null) return 1;
      return a.compareTo(b);
    });

    final isSelectionMode = dlProvider.isSelectionMode;

    return Scaffold(
      bottomNavigationBar: isSelectionMode
          ? _buildSelectionToolbar(context, dlProvider)
          : null,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            centerTitle: false,
            toolbarHeight: 44,
            expandedHeight: 104,
            surfaceTintColor: Colors.transparent,
            actions: isSelectionMode
                ? const []
                : [
                    IconButton(
                      icon: const Icon(Icons.more_horiz),
                      tooltip: 'More options',
                      onPressed: () => _showMoreMenu(context, dlProvider),
                    ),
                  ],
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              collapseMode: CollapseMode.parallax,
              titlePadding:
                  const EdgeInsetsDirectional.only(start: 16, bottom: 14),
              title: Text(
                'Downloads',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildStorageCard(context, dlProvider),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: _buildQuickActions(context, dlProvider),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          if (queue.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else
            SliverList.builder(
              itemCount: batchIds.length + 1,
              itemBuilder: (context, index) {
                if (index == batchIds.length) {
                  return const SizedBox(height: 48);
                }
                final bId = batchIds[index];
                final items = grouped[bId]!;
                if (bId == null) {
                  return Column(
                    children: items
                        .asMap()
                        .entries
                        .map((entry) => _buildDownloadCard(
                            context, dlProvider, entry.value,
                            index: entry.key + 1))
                        .toList(),
                  );
                }
                return _buildBatchTile(
                    context, dlProvider, items,
                    index: index + 1);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar(
      BuildContext context, DownloadProvider dlProvider) {
    final cs = Theme.of(context).colorScheme;
    final count = dlProvider.selectedIds.length;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: cs.inverseSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count Selected',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onInverseSurface,
                ),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                icon: Icon(Icons.select_all,
                    size: 18, color: cs.onInverseSurface),
                label: Text('Select All',
                    style: TextStyle(color: cs.onInverseSurface)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 44),
                ),
                onPressed: () {
                  HapticService.light();
                  dlProvider.selectAll();
                },
              ),
              TextButton.icon(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: cs.error),
                label: Text('Delete', style: TextStyle(color: cs.error)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 44),
                ),
                onPressed: () {
                  HapticService.heavy();
                  _confirmDeleteSelected(context, dlProvider);
                },
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: Icon(Icons.close, color: cs.onInverseSurface),
                  tooltip: 'Cancel',
                  onPressed: () {
                    HapticService.light();
                    dlProvider.clearSelection();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStorageCard(
      BuildContext context, DownloadProvider dlProvider) {
    final cs = Theme.of(context).colorScheme;
    final totalBytes = dlProvider.totalStorage;
    final freeBytes = dlProvider.freeStorage;
    if (totalBytes <= 0) return const SizedBox.shrink();

    final usedBytes = totalBytes - freeBytes;
    final usedFraction =
        totalBytes > 0 ? (usedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
    final usedPct = (usedFraction * 100).round();
    final barColor =
        usedFraction > 0.9 ? cs.error : cs.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text('Device Storage',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onSurface)),
                const Spacer(),
                Text('$usedPct% Used',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: barColor)),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: usedFraction,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: barColor,
              backgroundColor: cs.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Free ${_formatStorageGB(freeBytes)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.7))),
                const Spacer(),
                Text('Total ${_formatStorageGB(totalBytes)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(
      BuildContext context, DownloadProvider dlProvider) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _QuickActionButton(
            icon: Icons.add_rounded,
            label: 'New',
            color: cs.primary,
            onTap: () {
              HapticService.light();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const NewDownloadSheet(),
              );
            },
          ),
          const SizedBox(width: 8),
          _QuickActionButton(
            icon: Icons.pause_rounded,
            label: 'Pause',
            color: Colors.orange,
            onTap: () {
              HapticService.medium();
              dlProvider.pauseAll();
            },
          ),
          const SizedBox(width: 8),
          _QuickActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Resume',
            color: Colors.green,
            onTap: () {
              HapticService.medium();
              dlProvider.resumeAll();
            },
          ),
          const SizedBox(width: 8),
          _QuickActionButton(
            icon: Icons.checklist,
            label: 'Select',
            color: cs.tertiary,
            onTap: () {
              HapticService.light();
              dlProvider.toggleSelectionMode();
            },
          ),
          const SizedBox(width: 8),
          _QuickActionButton(
            icon: Icons.more_horiz,
            label: 'More',
            color: cs.onSurface.withValues(alpha: 0.75),
            onTap: () => _showMoreMenu(context, dlProvider),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(
      BuildContext context, DownloadProvider dlProvider) {
    HapticService.light();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Downloads'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmClearDone(context, dlProvider);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cleaning_services_rounded,
                    color: CupertinoColors.systemOrange, size: 22),
                SizedBox(width: 12),
                Text('Clear Finished Tasks'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await dlProvider.exportQueue();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.upload_file, color: CupertinoColors.activeBlue, size: 22),
                SizedBox(width: 12),
                Text('Export Queue'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await dlProvider.importQueue();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(success
                          ? 'Queue imported successfully!'
                          : 'Import cancelled or failed.')),
                );
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.download_rounded,
                    color: CupertinoColors.activeGreen, size: 22),
                SizedBox(width: 12),
                Text('Import Queue'),
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

  void _showRefreshLinkDialog(BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final controller = TextEditingController(text: item.originalUrl ?? item.url);
    bool isValidating = false;

    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return CupertinoAlertDialog(
          title: const Text('Refresh Download Link'),
          content: Column(
            children: [
              const Text('Enter a new URL for this download.\nProgress will be preserved if the server supports resume.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                placeholder: 'New URL',
                clearButtonMode: OverlayVisibilityMode.editing,
              ),
              if (isValidating) const SizedBox(height: 10),
              if (isValidating) const CupertinoActivityIndicator(),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: !isValidating ? false : true,
              onPressed: isValidating
                  ? null
                  : () async {
                      setState(() => isValidating = true);
                      final success = await dlProvider.refreshLink(item.id, controller.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(success ? 'Link updated successfully' : 'Failed to validate new link')),
                        );
                      }
                    },
              child: const Text('Update & Resume'),
            ),
          ],
        );
      }),
    );
  }

  void _showUpdateLinkDialog(BuildContext context, DownloadProvider dlProvider, DownloadItem item) async {
    String? clipboardUrl;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      final uri = Uri.tryParse(text);
      if (uri != null && uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        clipboardUrl = text;
      }
    } catch (_) {}
    if (!context.mounted) return;

    final controller = TextEditingController();
    String? errorText;
    bool isUpdating = false;

    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return CupertinoAlertDialog(
          title: const Text('Update Download Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste a new download URL.\nThe existing download progress will be preserved.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: controller,
                placeholder: 'https://',
                autofocus: true,
                autocorrect: false,
                clearButtonMode: OverlayVisibilityMode.editing,
                onChanged: (_) {
                  if (errorText != null) setState(() => errorText = null);
                },
              ),
              if (clipboardUrl != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  icon: const Icon(Icons.content_paste, size: 14),
                  label: const Text('Paste from Clipboard',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() {
                    controller.text = clipboardUrl!;
                    errorText = null;
                  }),
                ),
              ],
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!,
                    style: const TextStyle(
                        color: CupertinoColors.destructiveRed, fontSize: 12)),
              ],
              if (isUpdating) ...[
                const SizedBox(height: 10),
                const Center(child: CupertinoActivityIndicator()),
              ],
            ],
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: isUpdating ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: false,
              onPressed: isUpdating
                  ? null
                  : () async {
                      final newUrl = controller.text.trim();
                      if (newUrl.isEmpty) {
                        setState(() => errorText = 'Please enter a URL.');
                        return;
                      }
                      final uri = Uri.tryParse(newUrl);
                      if (uri == null || !uri.hasScheme ||
                          (uri.scheme != 'http' && uri.scheme != 'https')) {
                        setState(() =>
                            errorText = 'Invalid URL. Only http:// or https:// links are allowed.');
                        return;
                      }
                      setState(() {
                        isUpdating = true;
                        errorText = null;
                      });
                      try {
                        await dlProvider.updateDownloadUrl(item.id, newUrl);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Download link updated')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setState(() {
                            isUpdating = false;
                            errorText = e is ArgumentError
                                ? e.message.toString()
                                : e is StateError
                                    ? e.message
                                    : e.toString();
                          });
                        }
                      }
                    },
              child: const Text('Update'),
            ),
          ],
        );
      }),
    );
  }

  void _confirmClearDone(BuildContext context, DownloadProvider dlProvider) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clear Finished Tasks?'),
        content: const Text('This will remove completed and failed tasks from the list.'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              dlProvider.clearDone();
              Navigator.pop(ctx);
            },
            child: const Text('Clear List'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchTile(BuildContext context, DownloadProvider dlProvider,
      List<DownloadItem> items,
      {int? index}) {
    final batchName = items.first.batchName ?? 'Folder Download';
    final String batchId = items.first.batchId!;
    final bool isExpanded = _expandedBatchIds.contains(batchId);
    final cs = Theme.of(context).colorScheme;

    final int totalItems = items.length;
    final int doneItems =
        items.where((i) => i.status == DownloadStatus.done).length;
    final double avgProgress =
        items.fold(0.0, (sum, i) => sum + i.progress) / totalItems;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            ListTile(
              onTap: () {
                HapticService.light();
                setState(() {
                  if (isExpanded) {
                    _expandedBatchIds.remove(batchId);
                  } else {
                    _expandedBatchIds.add(batchId);
                  }
                });
              },
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.folder, color: cs.onPrimaryContainer, size: 20),
              ),
              title: Text('${index != null ? "$index. " : ""}$batchName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
              subtitle: Text(
                  '$doneItems / $totalItems files complete (${(avgProgress * 100).toInt()}%)',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.more_vert, color: cs.onSurface.withValues(alpha: 0.7)),
                    onPressed: () =>
                        _showBatchOptions(context, dlProvider, batchId, items),
                  ),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.onSurface.withValues(alpha: 0.6)),
                ],
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: items
                      .asMap()
                      .entries
                      .map((entry) => _buildDownloadCard(
                          context, dlProvider, entry.value,
                          isNested: true, index: entry.key + 1))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBatchOptions(BuildContext context, DownloadProvider dlProvider,
      String batchId, List<DownloadItem> items) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Batch Actions'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              HapticService.medium();
              dlProvider.resumeBatch(batchId);
              Navigator.pop(context);
            },
            child: const Row(
              children: [
                Icon(Icons.play_circle, color: CupertinoColors.activeGreen, size: 22),
                SizedBox(width: 12),
                Text('Resume All in Batch'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              HapticService.medium();
              dlProvider.pauseBatch(batchId);
              Navigator.pop(context);
            },
            child: const Row(
              children: [
                Icon(Icons.pause_circle, color: CupertinoColors.systemOrange, size: 22),
                SizedBox(width: 12),
                Text('Pause All in Batch'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              HapticService.heavy();
              Navigator.pop(context);
              _confirmRemoveBatch(context, dlProvider, batchId);
            },
            child: const Row(
              children: [
                Icon(Icons.delete_sweep, color: CupertinoColors.destructiveRed, size: 22),
                SizedBox(width: 12),
                Text('Remove Batch'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _confirmRemoveBatch(
      BuildContext context, DownloadProvider dlProvider, String batchId) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remove Batch?'),
        content: const Text('Are you sure you want to remove all items in this batch?'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              dlProvider.stopBatch(batchId);
              Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item,
      {bool isNested = false, int? index}) {
    final bool isSelected = dlProvider.selectedIds.contains(item.id);
    final bool isSelectionMode = dlProvider.isSelectionMode;

    final Widget card = _DownloadCardView(
      item: item,
      isNested: isNested,
      index: index,
      onPause: () {
        HapticService.light();
        dlProvider.pause(item.id);
      },
      onResume: () {
        HapticService.light();
        dlProvider.resume(item.id);
      },
      onUpdateLink: () {
        HapticService.light();
        _showUpdateLinkDialog(context, dlProvider, item);
      },
      onDelete: () {
        HapticService.heavy();
        _confirmSafeDelete(context, dlProvider, item);
      },
      onMore: () => _showItemMoreMenu(context, dlProvider, item),
    );

    if (isSelectionMode) {
      return RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            children: [
              CupertinoCheckbox(
                value: isSelected,
                onChanged: (_) => dlProvider.toggleSelection(item.id),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => dlProvider.toggleSelection(item.id),
                  child: AbsorbPointer(child: card),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: _wrapSlidable(context, dlProvider, item, card),
      ),
    );
  }

  Widget _wrapSlidable(BuildContext context, DownloadProvider dlProvider,
      DownloadItem item, Widget card) {
    final cs = Theme.of(context).colorScheme;
    final bool canPause = item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.queued;
    final bool canResume = item.status == DownloadStatus.paused ||
        item.status == DownloadStatus.error;
    final bool canUpdateLink = item.status == DownloadStatus.paused ||
        item.status == DownloadStatus.queued ||
        item.status == DownloadStatus.error;

    return Slidable(
      key: ValueKey('swipe_${item.id}'),
      startActionPane: canPause || canResume
          ? ActionPane(
              motion: const BehindMotion(),
              extentRatio: 0.28,
              children: [
                SlidableAction(
                  onPressed: (_) {
                    HapticService.light();
                    if (canResume) {
                      dlProvider.resume(item.id);
                    } else {
                      dlProvider.pause(item.id);
                    }
                  },
                  backgroundColor:
                      canResume ? Colors.green : Colors.orange,
                  foregroundColor: Colors.white,
                  icon: canResume
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: canResume ? 'Resume' : 'Pause',
                  borderRadius: BorderRadius.circular(12),
                ),
              ],
            )
          : null,
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.48,
        children: [
          if (canUpdateLink)
            SlidableAction(
              onPressed: (_) {
                HapticService.light();
                _showUpdateLinkDialog(context, dlProvider, item);
              },
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              icon: Icons.link_rounded,
              label: 'Update Link',
              borderRadius: BorderRadius.circular(12),
            ),
          SlidableAction(
            onPressed: (_) {
              HapticService.heavy();
              _confirmSafeDelete(context, dlProvider, item);
            },
            backgroundColor: cs.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: card,
    );
  }

  void _showItemMoreMenu(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    HapticService.light();
    final cs = Theme.of(context).colorScheme;
    final file = File(item.savePath);
    final fileExists = file.existsSync();
    final isDone = item.status == DownloadStatus.done;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(item.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        message: Text(item.host,
            style: const TextStyle(fontSize: 12)),
        actions: [
          if (isDone && fileExists)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                Share.shareXFiles([XFile(item.savePath)],
                    text: item.fileName);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.ios_share,
                      color: CupertinoColors.activeBlue, size: 22),
                  SizedBox(width: 12),
                  Text('Share'),
                ],
              ),
            ),
          if (isDone && fileExists && Platform.isIOS)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                HapticService.light();
                dlProvider.saveToFiles(item.savePath);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save_alt,
                      color: cs.tertiary, size: 22),
                  const SizedBox(width: 12),
                  const Text('Save to Files'),
                ],
              ),
            ),
          if (isDone && fileExists && Platform.isIOS)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                HapticService.light();
                dlProvider.revealFile(item.savePath);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open,
                      color: cs.secondary, size: 22),
                  const SizedBox(width: 12),
                  const Text('Reveal in Files'),
                ],
              ),
            ),
          if (isDone)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                HapticService.light();
                _showVerifyHashDialog(context, dlProvider, item);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user,
                      color: CupertinoColors.activeGreen, size: 22),
                  SizedBox(width: 12),
                  Text('Verify File Hash'),
                ],
              ),
            ),
          if (item.status == DownloadStatus.error)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                HapticService.light();
                _showRefreshLinkDialog(context, dlProvider, item);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh,
                      color: CupertinoColors.systemOrange, size: 22),
                  SizedBox(width: 12),
                  Text('Refresh Link'),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticService.light();
              _showSpeedLimitDialog(context, dlProvider, item);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.speed, color: CupertinoColors.systemOrange, size: 22),
                SizedBox(width: 12),
                Text('Speed Limit'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: item.url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Download URL copied')),
                );
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link, color: CupertinoColors.activeBlue, size: 22),
                SizedBox(width: 12),
                Text('Copy URL'),
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

  void _showSpeedLimitDialog(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final ctrl = TextEditingController(
        text: item.speedLimitKbps != null ? '${item.speedLimitKbps}' : '');

    void apply(int? kbps) {
      dlProvider.setItemSpeedLimit(item.id, kbps);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kbps == null
                ? 'Speed limit removed for this download'
                : 'Speed limit set to $kbps KB/s for this download'),
          ),
        );
      }
    }

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Speed Limit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Limit the download speed for this file only.\n0 or empty = unlimited (uses global setting).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            CupertinoTextField(
              controller: ctrl,
              placeholder: 'KB/s',
              keyboardType: TextInputType.number,
              autofocus: true,
              clearButtonMode: OverlayVisibilityMode.editing,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              apply(null);
            },
            child: const Text('Unlimited'),
          ),
          CupertinoDialogAction(
            child: const Text('Apply'),
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx);
              apply(v?.clamp(0, 100000));
            },
          ),
        ],
      ),
    );
  }

  void _confirmSafeDelete(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    bool deleteFile = false;
    showCupertinoDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return CupertinoAlertDialog(
                title: const Text('Delete Task?'),
                content: Column(
                  children: [
                    Text(
                        'Are you sure you want to remove "${item.fileName}" from the queue?'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        CupertinoCheckbox(
                          value: deleteFile,
                          onChanged: (val) {
                            setState(() => deleteFile = val ?? false);
                          },
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text('Delete file from storage as well',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () {
                      dlProvider.stop(item.id);
                      if (deleteFile) {
                        final f = File(item.savePath);
                        if (f.existsSync()) f.deleteSync();
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('Delete'),
                  ),
                ]);
          });
        });
  }

  void _confirmDeleteSelected(
      BuildContext context, DownloadProvider dlProvider) {
    bool deleteFile = false;
    showCupertinoDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return CupertinoAlertDialog(
              title: const Text('Delete Selected?'),
              content: Column(
                children: [
                  Text(
                      'Are you sure you want to remove ${dlProvider.selectedIds.length} items?'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CupertinoCheckbox(
                        value: deleteFile,
                        onChanged: (val) {
                          setState(() => deleteFile = val ?? false);
                        },
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text('Delete files from storage as well',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () {
                    dlProvider.deleteSelected(deleteFiles: deleteFile);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Delete'),
                ),
              ],
            );
          });
        });
  }

  void _showVerifyHashDialog(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final ctrl = TextEditingController();
    bool isVerifying = false;
    bool? isValid;
    String? algorithm;

    showCupertinoDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return CupertinoAlertDialog(
              title: const Text('Verify File Hash'),
              content: Column(
                children: [
                  Text('Check hash for: ${item.fileName}',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _hashAlgoChip('MD5', setState, algorithm, (v) => algorithm = v),
                      const SizedBox(width: 4),
                      _hashAlgoChip('SHA1', setState, algorithm, (v) => algorithm = v),
                      const SizedBox(width: 4),
                      _hashAlgoChip('SHA256', setState, algorithm, (v) => algorithm = v),
                    ],
                  ),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: ctrl,
                    placeholder: 'Expected hash value',
                  ),
                  const SizedBox(height: 10),
                  if (isVerifying) const CupertinoActivityIndicator(),
                  if (!isVerifying && isValid != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isValid! ? Icons.check_circle : Icons.cancel,
                            color: isValid! ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(isValid! ? 'Hash Matches!' : 'Hash Mismatch!',
                            style: TextStyle(
                                color: isValid! ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold))
                      ],
                    ),
                  if (item.calculatedMd5 != null || item.calculatedSha1 != null || item.calculatedSha256 != null) ...[
                    const SizedBox(height: 8),
                    Text('Auto-computed checksums:', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                    if (item.calculatedMd5 != null) Text('MD5: ${item.calculatedMd5}', style: const TextStyle(fontSize: 8)),
                    if (item.calculatedSha1 != null) Text('SHA1: ${item.calculatedSha1}', style: const TextStyle(fontSize: 8)),
                    if (item.calculatedSha256 != null) Text('SHA256: ${item.calculatedSha256}', style: const TextStyle(fontSize: 8)),
                  ],
                ],
              ),
              actions: [
                if (!isVerifying)
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                if (!isVerifying)
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    onPressed: () async {
                      if (ctrl.text.trim().isEmpty || algorithm == null) return;
                      setState(() {
                        isVerifying = true;
                        isValid = null;
                      });

                      final result = await dlProvider.verifyFileHash(
                          item.savePath, ctrl.text);

                      if (context.mounted) {
                        setState(() {
                          isVerifying = false;
                          isValid = result;
                        });
                      }
                    },
                    child: const Text('Verify'),
                  ),
              ],
            );
          });
        });
  }

  Widget _hashAlgoChip(String label, StateSetter setState, String? selected, Function(String) onSelected) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () => setState(() => onSelected(label)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black)),
      ),
    );
  }

  String _formatStorageGB(dynamic mb) {
    final b = (mb is int ? mb.toDouble() : mb) as double;
    if (b <= 0) return '0 GB';
    final decimalGB = b * 1024 * 1024 / (1000 * 1000 * 1000);
    return '${decimalGB.toStringAsFixed(1)} GB';
  }
}

class _DownloadCardView extends StatelessWidget {
  const _DownloadCardView({
    required this.item,
    required this.isNested,
    required this.index,
    required this.onPause,
    required this.onResume,
    required this.onUpdateLink,
    required this.onDelete,
    required this.onMore,
  });

  final DownloadItem item;
  final bool isNested;
  final int? index;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onUpdateLink;
  final VoidCallback onDelete;
  final VoidCallback onMore;

  Color _chipColor(ColorScheme cs) {
    switch (item.status) {
      case DownloadStatus.downloading:
        return cs.primary;
      case DownloadStatus.paused:
        return Colors.orange;
      case DownloadStatus.queued:
        return cs.onSurfaceVariant;
      case DownloadStatus.done:
        return Colors.green;
      case DownloadStatus.error:
        return cs.error;
    }
  }

  String _chipLabel() {
    switch (item.status) {
      case DownloadStatus.downloading:
        return 'Downloading';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.done:
        return 'Completed';
      case DownloadStatus.error:
        return 'Failed';
    }
  }

  String _metaLeft() {
    if (item.totalBytes <= 0) return 'Size unknown';
    return '${_fmt(item.downloadedBytes)} / ${_fmt(item.totalBytes)}';
  }

  String _fmt(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDownloading = item.status == DownloadStatus.downloading;

    return Container(
      padding: EdgeInsets.all(isNested ? 10 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(item: item, size: isNested ? 40 : 48),
              SizedBox(width: isNested ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index != null ? "$index. " : ""}${item.fileName}',
                      maxLines: isNested ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isNested ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    if (item.category != DownloadCategory.other) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.categoryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Status: ${_chipLabel()}',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _chipColor(cs).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _chipLabel(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _chipColor(cs),
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isNested ? 8 : 10),
          LinearProgressIndicator(
            value: item.progress,
            minHeight: isNested ? 6 : 8,
            borderRadius: BorderRadius.circular(4),
            color: item.status == DownloadStatus.error
                ? cs.error
                : cs.primary,
            backgroundColor: cs.surfaceContainerHighest,
          ),
          SizedBox(height: isNested ? 4 : 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _metaLeft(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isNested ? 11 : 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
              if (isDownloading) ...[
                const SizedBox(width: 8),
                Text(
                  '${_fmtSpeed(item.speedBytesPerSec)} · ETA ${_fmtEta(item.etaSeconds)}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: isNested ? 11 : 12,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
          if (item.errorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              item.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.error),
            ),
          ],
          SizedBox(height: isNested ? 6 : 8),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          SizedBox(height: isNested ? 4 : 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (item.status == DownloadStatus.downloading ||
                    item.status == DownloadStatus.queued)
                  _CardActionPill(
                    icon: Icons.pause_rounded,
                    label: 'Pause',
                    color: Colors.orange,
                    onTap: onPause,
                  ),
                if (item.status == DownloadStatus.paused ||
                    item.status == DownloadStatus.error)
                  _CardActionPill(
                    icon: Icons.play_arrow_rounded,
                    label: 'Resume',
                    color: Colors.green,
                    onTap: onResume,
                  ),
                if (item.status == DownloadStatus.paused ||
                    item.status == DownloadStatus.queued ||
                    item.status == DownloadStatus.error)
                  _CardActionPill(
                    icon: Icons.link_rounded,
                    label: 'Update Link',
                    color: cs.primary,
                    onTap: onUpdateLink,
                  ),
                _CardActionPill(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: cs.error,
                  onTap: onDelete,
                ),
                _CardActionPill(
                  icon: Icons.more_horiz,
                  label: 'More',
                  color: cs.onSurface.withValues(alpha: 0.75),
                  onTap: onMore,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item, required this.size});

  final DownloadItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: ThumbnailService().getThumbnail(item.savePath),
      builder: (context, snapshot) {
        final hasThumb = snapshot.hasData && snapshot.data != null;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            image: hasThumb
                ? DecorationImage(
                    image: FileImage(File(snapshot.data!)),
                    fit: BoxFit.cover)
                : null,
          ),
          child: !hasThumb
              ? Icon(
                  Icons.description_rounded,
                  size: size * 0.5,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.5),
                )
              : null,
        );
      },
    );
  }
}

class _CardActionPill extends StatelessWidget {
  const _CardActionPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.download_rounded,
                size: 44,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No Downloads Yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start downloading files from Browser or BRWSR.',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtSpeed(double speed) {
  if (speed <= 0) return '0 B/s';
  if (speed > 1024 * 1024) {
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (speed > 1024) {
    return '${(speed / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${speed.toStringAsFixed(0)} B/s';
}

String _fmtEta(int etaSeconds) {
  if (etaSeconds <= 0) return '0s';
  int mm = etaSeconds ~/ 60;
  int ss = etaSeconds % 60;
  int hh = mm ~/ 60;
  mm = mm % 60;
  if (hh > 0) return '${hh}h ${mm}m';
  if (mm > 0) return '${mm}m ${ss}s';
  return '${ss}s';
}
