import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../models/proxy_model.dart';
import 'dart:io';
import 'package:socks5_proxy/socks_client.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  late Dio _dio;
  late Dio _cleanDio;
  ProxyModel? _activeProxy;

  DioClient._internal() {
    _dio = _createDio();
    _cleanDio = _createDio();
    _applyProxyAdapter();
  }

  Dio _createDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => status != null && status < 500,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ));
  }

  Dio get dio => _dio;
  Dio get cleanDio => _cleanDio;

  void setProxy(ProxyModel? proxy) {
    _activeProxy = proxy;
    _applyProxyAdapter();
  }

  bool _isLocalIp(String host) {
    return host.startsWith('127.') || host == 'localhost';
  }

  Future<String> resolveRedirects(String url, {int maxRedirects = 20}) async {
    final visited = <String>{};
    String currentUrl = url;
    final cookieJar = <String, String>{};

    for (int i = 0; i < maxRedirects; i++) {
      if (visited.contains(currentUrl)) {
        throw DioException(
          requestOptions: RequestOptions(path: currentUrl),
          message: 'Redirect loop detected',
        );
      }
      visited.add(currentUrl);

      final headers = <String, dynamic>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };

      if (cookieJar.isNotEmpty) {
        final cookieStr =
            cookieJar.entries.map((e) => '${e.key}=${e.value}').join('; ');
        headers['Cookie'] = cookieStr;
      }

      late Response response;
      bool useGet = false;
      try {
        final headResp = await _dio.head(
          currentUrl,
          options: Options(
            followRedirects: false,
            headers: headers,
            validateStatus: (status) => true,
          ),
        );
        if ((headResp.statusCode ?? 0) >= 400) {
          useGet = true;
        } else {
          response = headResp;
        }
      } on DioException {
        useGet = true;
      }

      if (useGet) {
        response = await _dio.get(
          currentUrl,
          options: Options(
            followRedirects: false,
            headers: {
              ...headers,
              'Range': 'bytes=0-0',
            },
            validateStatus: (status) => true,
            responseType: ResponseType.stream,
          ),
        );
      }

      final statusCode = response.statusCode ?? 500;

      final setCookie = response.headers.value('set-cookie');
      if (setCookie != null && setCookie.isNotEmpty) {
        for (final part in setCookie.split(';')) {
          final eq = part.indexOf('=');
          if (eq > 0) {
            final key = part.substring(0, eq).trim();
            final value = part.substring(eq + 1).trim();
            cookieJar[key] = value;
          }
        }
      }

      if (_isRedirect(statusCode)) {
        final location = response.headers.value('location');
        if (location == null || location.isEmpty) {
          throw DioException(
            requestOptions: RequestOptions(path: currentUrl),
            message: 'Redirect response without Location header',
          );
        }
        currentUrl = _resolveUrl(currentUrl, location);
      } else {
        return currentUrl;
      }
    }

    throw DioException(
      requestOptions: RequestOptions(path: currentUrl),
      message: 'Exceeded maximum redirect count ($maxRedirects)',
    );
  }

  bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  String _resolveUrl(String base, String location) {
    final baseUri = Uri.parse(base);
    final locationUri = Uri.tryParse(location);
    if (locationUri == null) return location;
    if (locationUri.hasScheme) return location;
    return baseUri.resolve(location).toString();
  }

  void _applyProxyAdapter() {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;

        if (_activeProxy != null && _activeProxy!.isActive) {
          if (_activeProxy!.protocol == ProxyProtocol.SOCKS5 || _activeProxy!.protocol == ProxyProtocol.SOCKS4) {
             client.connectionFactory = (uri, proxyHost, proxyPort) async {
               if (_isLocalIp(uri.host)) {
                 // Bypass SOCKS proxy: connect directly
                 return Socket.startConnect(uri.host, uri.port);
                 } else {
                 return _createSocksConnectionTask(
                   uri,
                   _activeProxy!.host,
                   _activeProxy!.port,
                   _activeProxy!.username,
                   _activeProxy!.password,
                 );
               }
             };
          } else {
            // HTTP / HTTPS Proxy Handling
            final proxyStr = '${_activeProxy!.host}:${_activeProxy!.port}';
            client.findProxy = (uri) {
              if (_isLocalIp(uri.host)) return 'DIRECT';
              return 'PROXY $proxyStr; DIRECT';
            };
            
            if (_activeProxy!.username != null &&
                _activeProxy!.username!.isNotEmpty) {
              client.addProxyCredentials(
                _activeProxy!.host,
                _activeProxy!.port,
                '', // Realm
                HttpClientBasicCredentials(
                    _activeProxy!.username!, _activeProxy!.password ?? ''),
              );
            }
          }
        }
        return client;
      },
    );
  }

  // Helper for quick proxy server ping tests (TCP handshake latency only)
  Future<int?> pingProxy(ProxyModel proxy) async {
    try {
      final start = DateTime.now();
      // Only measure the time it takes to establish a TCP connection to the proxy server itself
      final socket = await Socket.connect(proxy.host, proxy.port, timeout: const Duration(seconds: 5));
      final end = DateTime.now();
      socket.destroy();
      return end.difference(start).inMilliseconds;
    } catch (e) {
      return -1; // Failed
    }
  }

  Future<ConnectionTask<Socket>> _createSocksConnectionTask(
      Uri uri, String proxyHost, int proxyPort, String? username, String? password) async {
    
    // Determine the IP type of proxy host. If it's a domain name, use type "any" for DNS.
    InternetAddress proxyAddress;
    try {
      proxyAddress = InternetAddress(proxyHost, type: InternetAddressType.IPv4);
    } catch (_) {
      final lookup = await InternetAddress.lookup(proxyHost);
      proxyAddress = lookup.first;
    }

    // Determine the IP type of target host. Some proxies reject Remote DNS, so we resolve locally.
    InternetAddress targetAddress;
    try {
      targetAddress = InternetAddress(uri.host, type: InternetAddressType.IPv4);
    } catch (_) {
      try {
        final lookup = await InternetAddress.lookup(uri.host);
        targetAddress = lookup.first;
      } catch (_) {
        // Fallback to sending the raw host if local DNS lookup fails
        targetAddress = InternetAddress(uri.host, type: InternetAddressType.unix);
      }
    }

    final clientFuture = SocksTCPClient.connect(
      [
        ProxySettings(
          proxyAddress,
          proxyPort,
          username: username,
          password: password,
        )
      ],
      targetAddress,
      uri.port,
    );
    
    // Secure connection after establishing Socks connection if HTTPS
    if (uri.scheme == 'https') {
      Future<SecureSocket> secureClient;
      return ConnectionTask.fromSocket(
        secureClient = clientFuture.then((client) => client.secure(
          uri.host, 
          onBadCertificate: (cert) => true, // Ignore bad certs globally since validateStatus allows all
        )), 
        () async { (await secureClient).close().ignore(); }
      );
    }

    return ConnectionTask.fromSocket(clientFuture, () async {
      (await clientFuture).close().ignore();
    });
  }
}
