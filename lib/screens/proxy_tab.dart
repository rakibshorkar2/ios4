import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';
import 'dart:ui';
import '../providers/proxy_provider.dart';
import '../providers/app_state.dart';
import '../models/proxy_model.dart';

class ProxyTab extends StatelessWidget {
  const ProxyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final proxyProvider = context.watch<AppProxyProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proxy Manager'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: 'Test All',
            onPressed: () => proxyProvider.testAllProxies(),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import YAML',
            onPressed: () => _importYamlProxies(context),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Bulk Import',
            onPressed: () => _showBulkImportDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Proxy',
            onPressed: () => _showAddProxyDialog(context),
          )
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: Consumer<AppState>(
              builder: (context, appState, child) {
                final isAmoled = appState.trueAmoledDark &&
                    Theme.of(context).brightness == Brightness.dark;
                return Container(
                  decoration: BoxDecoration(
                    color: isAmoled ? Colors.black : null,
                    gradient: isAmoled
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.surface,
                              Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.8),
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
          proxyProvider.proxies.isEmpty
              ? const Center(
                  child: Text('No proxies added. Traffic goes DIRECT.'))
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top +
                        kToolbarHeight +
                        16,
                    bottom: 120,
                  ),
                  itemCount: proxyProvider.proxies.length,
                  itemBuilder: (context, index) {
                    final proxy = proxyProvider.proxies[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.security, size: 20),
                          ),
                          title: Text(
                            proxy.displayUri,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            proxy.latencyMs == null
                                ? 'Not tested'
                                : (proxy.latencyMs == -1
                                    ? 'Connection Failed'
                                    : 'Latency: ${proxy.latencyMs}ms'),
                            style: TextStyle(
                              fontSize: 12,
                              color: proxy.latencyMs == -1
                                  ? Colors.red
                                  : (proxy.latencyMs != null &&
                                          proxy.latencyMs! < 500
                                      ? Colors.green
                                      : Colors.orange),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: proxy.isActive,
                                onChanged: (val) =>
                                    proxyProvider.toggleProxy(proxy.id, val),
                                activeThumbColor:
                                    Theme.of(context).colorScheme.primary,
                              ),
                              PopupMenuButton(
                                icon: const Icon(Icons.more_vert, size: 20),
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'test',
                                    child: Text('Test Ping'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                                onSelected: (val) {
                                  if (val == 'test') {
                                    proxyProvider.testProxyLatency(proxy);
                                  }
                                  if (val == 'delete') {
                                    proxyProvider.deleteProxy(proxy.id);
                                  }
                                },
                              )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          // Blurred Header Container
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: MediaQuery.of(context).padding.top + kToolbarHeight,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.8),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddProxyDialog(BuildContext context) {
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '1080');
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Manual SOCKS5'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hostCtrl,
                decoration: const InputDecoration(
                    labelText: 'Host IP/Domain', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Port', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                    labelText: 'Username (Optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Password (Optional)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final host = hostCtrl.text.trim();
              final port = int.tryParse(portCtrl.text.trim()) ?? 1080;
              final user = userCtrl.text.trim();
              final pass = passCtrl.text.trim();

              if (host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Host cannot be empty')));
                return;
              }

              // Reconstruct into model
              String uriStr = 'socks5://';
              if (user.isNotEmpty) {
                uriStr += '$user:$pass@';
              }
              uriStr += '$host:$port';

              final model = ProxyModel.fromUri(uriStr);
              if (model != null) {
                context.read<AppProxyProvider>().addProxy(model);
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid proxy parameters!')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _importYamlProxies(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (!path.endsWith('.yaml') && !path.endsWith('.yml')) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Please select a valid .yaml or .yml file')));
          }
          return;
        }
        final file = File(path);
        final yamlString = await file.readAsString();
        final Object? yamlDoc = loadYaml(yamlString);

        YamlList? proxyList;
        if (yamlDoc is YamlList) {
          proxyList = yamlDoc;
        } else if (yamlDoc is YamlMap) {
          final dynamic listValue = yamlDoc['proxies'];
          if (listValue is YamlList) {
            proxyList = listValue;
          }
        }

        if (proxyList != null) {
          int count = 0;
          for (var item in proxyList) {
            if (item is YamlMap) {
              String type = item['type']?.toString() ?? 'socks5';
              String ip =
                  item['ip']?.toString() ?? item['server']?.toString() ?? '';
              String port = item['port']?.toString() ?? '1080';
              String user = item['username']?.toString() ?? '';
              String pass = item['password']?.toString() ?? '';
              if (ip.isEmpty) continue;

              String uriStr = '$type://';
              if (user.isNotEmpty) uriStr += '$user:$pass@';
              uriStr += '$ip:$port';

              final model = ProxyModel.fromUri(uriStr);
              if (model != null) {
                if (context.mounted) {
                  context.read<AppProxyProvider>().addProxy(model);
                  count++;
                }
              }
            }
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Imported $count proxies from YAML')));
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Invalid YAML structure. Expected a list.')));
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error parsing YAML: $e')));
      }
    }
  }

  void _showBulkImportDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Import Proxies'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste one or more proxy URIs (one per line):',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'socks5://host:port\nsocks5://user:pass@host:port',
                border: OutlineInputBorder(),
              ),
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
              final text = ctrl.text.trim();
              if (text.isEmpty) return;

              final lines = text.split('\n');
              final proxies = <ProxyModel>[];
              for (var line in lines) {
                final cleaned = line.trim();
                if (cleaned.isEmpty) continue;
                final model = ProxyModel.fromUri(cleaned);
                if (model != null) {
                  proxies.add(model);
                }
              }

              if (proxies.isNotEmpty) {
                await context.read<AppProxyProvider>().addProxies(proxies);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Imported ${proxies.length} proxies!')),
                  );
                }
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
}
