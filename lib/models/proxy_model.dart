import 'dart:math';

// ignore_for_file: constant_identifier_names
enum ProxyProtocol { SOCKS5, SOCKS4, HTTP, HTTPS }

class ProxyModel {
  final String id;
  final ProxyProtocol protocol;
  final String host;
  final int port;
  final String? username;
  final String? password;
  bool isActive;
  int? latencyMs; // null = not tested, -1 = failed

  ProxyModel({
    required this.id,
    required this.protocol,
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.isActive = false,
    this.latencyMs,
  });

  String get protocolString => protocol.name.toLowerCase();

  String get uri {
    final auth = (username != null && username!.isNotEmpty)
        ? '$username:${password ?? ''}@'
        : '';
    return '$protocolString://$auth$host:$port';
  }

  String get displayUri {
    final auth =
        (username != null && username!.isNotEmpty) ? '$username:***@' : '';
    return '${protocol.name}://$auth$host:$port';
  }

  /// Parse from a URI string like socks5://user:pass@1.2.3.4:1080
  static ProxyModel? fromUri(String raw) {
    try {
      // Sanitize: remove spaces (some users might have spaces before/after delimiters)
      // and remove trailing slashes which aren't needed for basic proxy config
      var sanitized = raw.trim().replaceAll(' ', '');
      if (sanitized.endsWith('/')) {
        sanitized = sanitized.substring(0, sanitized.length - 1);
      }

      final uri = Uri.parse(sanitized);
      ProxyProtocol proto;
      switch (uri.scheme.toLowerCase()) {
        case 'socks5':
          proto = ProxyProtocol.SOCKS5;
          break;
        case 'socks4':
          proto = ProxyProtocol.SOCKS4;
          break;
        case 'https':
          proto = ProxyProtocol.HTTPS;
          break;
        default:
          proto = ProxyProtocol.HTTP;
      }
      return ProxyModel(
        id: DateTime.now().millisecondsSinceEpoch.toString() +
            (Random().nextInt(1000).toString()),
        protocol: proto,
        host: uri.host,
        port: uri.port,
        username: uri.hasAuthority && uri.userInfo.contains(':')
            ? uri.userInfo.split(':')[0]
            : (uri.userInfo.isNotEmpty ? uri.userInfo : null),
        password: uri.hasAuthority && uri.userInfo.contains(':')
            ? uri.userInfo.split(':').sublist(1).join(':')
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'protocol': protocol.index,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'isActive': isActive ? 1 : 0,
      };

  factory ProxyModel.fromMap(Map<String, dynamic> m) => ProxyModel(
        id: m['id'] as String,
        protocol: ProxyProtocol.values[m['protocol'] as int],
        host: m['host'] as String,
        port: m['port'] as int,
        username: m['username'] as String?,
        password: m['password'] as String?,
        isActive: (m['isActive'] as int) == 1,
      );

  ProxyModel copyWith({
    bool? isActive,
    int? latencyMs,
    String? username,
    String? password,
  }) =>
      ProxyModel(
        id: id,
        protocol: protocol,
        host: host,
        port: port,
        username: username ?? this.username,
        password: password ?? this.password,
        isActive: isActive ?? this.isActive,
        latencyMs: latencyMs ?? this.latencyMs,
      );
}
