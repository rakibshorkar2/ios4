import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';
import '../models/proxy_model.dart';
import '../services/dio_client.dart';

class AppProxyProvider with ChangeNotifier {
  List<ProxyModel> _proxies = [];
  Database? _db;

  List<ProxyModel> get proxies => _proxies;
  ProxyModel? get activeProxy => _proxies.where((p) => p.isActive).firstOrNull;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'proxies.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE proxies (
            id TEXT PRIMARY KEY,
            protocol INTEGER,
            host TEXT,
            port INTEGER,
            username TEXT,
            password TEXT,
            isActive INTEGER
          )
        ''');
      },
    );
    await _loadProxies();
  }

  Future<void> _loadProxies() async {
    if (_db == null) return;
    final maps = await _db!.query('proxies');

    if (maps.isEmpty) {
      try {
        final yamlString = await rootBundle.loadString('bypassempire.yaml');
        final yamlDoc = loadYaml(yamlString);
        if (yamlDoc is YamlMap) {
          final proxiesList = yamlDoc['proxies'];
          if (proxiesList is YamlList) {
            int count = 0;
            for (var item in proxiesList) {
              if (item is! YamlMap) continue;
              final type = item['type']?.toString() ?? 'socks5';
              final server = item['server']?.toString() ?? '';
              final port = item['port']?.toString() ?? '1080';
              final user = item['username']?.toString() ?? '';
              final pass = item['password']?.toString() ?? '';
              if (server.isEmpty) continue;
              String uriStr = '$type://';
              if (user.isNotEmpty) uriStr += '$user:$pass@';
              uriStr += '$server:$port';
              final model = ProxyModel.fromUri(uriStr);
              if (model != null) {
                model.isActive = count == 6; // Enable proxy #7 by default
                await _db!.insert('proxies', model.toMap(),
                    conflictAlgorithm: ConflictAlgorithm.ignore);
                count++;
              }
            }
            debugPrint('Imported $count proxies from bypassempire.yaml');
            if (count > 0) return _loadProxies();
          }
        }
      } catch (e) {
        debugPrint('Failed to load bypassempire.yaml: $e');
      }
    }

    _proxies = maps.map((m) => ProxyModel.fromMap(m)).toList();

    // Apply active proxy to Dio, or null if none active (direct connection)
    final active = activeProxy;
    DioClient().setProxy(active);

    // Sync proxy config to iOS native downloader
    if (Platform.isIOS) {
      _syncProxyToIOS(active);
    }

    notifyListeners();
  }

  Future<void> addProxy(ProxyModel proxy) async {
    if (_db == null) return;
    await _db!.insert('proxies', proxy.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _loadProxies();
  }

  Future<void> addProxies(List<ProxyModel> proxies) async {
    if (_db == null || proxies.isEmpty) return;
    final batch = _db!.batch();
    for (var proxy in proxies) {
      batch.insert('proxies', proxy.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await _loadProxies();
  }

  Future<void> updateProxy(ProxyModel proxy) async {
    if (_db == null) return;
    await _db!.update('proxies', proxy.toMap(),
        where: 'id = ?', whereArgs: [proxy.id]);
    await _loadProxies();
  }

  Future<void> deleteProxy(String id) async {
    if (_db == null) return;
    await _db!.delete('proxies', where: 'id = ?', whereArgs: [id]);
    await _loadProxies();
  }

  Future<void> toggleProxy(String id, bool active) async {
    if (_db == null) return;

    // If turning one on, turn all others off first
    if (active) {
      await _db!.update('proxies', {'isActive': 0});
    }

    await _db!.update('proxies', {'isActive': active ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    await _loadProxies();
  }

  static const MethodChannel _iosProxyChannel =
      MethodChannel('com.dirxplore/proxy_config');

  void _syncProxyToIOS(ProxyModel? proxy) {
    _iosProxyChannel.invokeMethod('setProxy', {
      'host': proxy?.host ?? '',
      'port': proxy?.port ?? 0,
      'username': proxy?.username ?? '',
      'password': proxy?.password ?? '',
      'protocol': proxy?.protocol.name ?? '',
      'enabled': proxy?.isActive ?? false,
    }).catchError((e) { debugPrint('syncProxyToIOS error: $e'); });
  }

  Future<void> testProxyLatency(ProxyModel proxy) async {
    final ms = await DioClient().pingProxy(proxy);
    final idx = _proxies.indexWhere((p) => p.id == proxy.id);
    if (idx != -1) {
      _proxies[idx].latencyMs = ms;
      notifyListeners();
    }
  }

  Future<void> testAllProxies() async {
    // Run tests sequentially to avoid overwhelming network but with no delay between them
    for (var proxy in _proxies) {
      // testProxyLatency already handles notifyListeners()
      await testProxyLatency(proxy);
    }
  }
}
