import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'dio_client.dart';

class ProxyTunnel {
  static final ProxyTunnel _instance = ProxyTunnel._internal();
  factory ProxyTunnel() => _instance;

  ProxyTunnel._internal();

  HttpServer? _server;
  int get port => _server?.port ?? 8080;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
  }

  String getTunnelUrl(String targetUrl) {
    if (_server == null) return targetUrl;
    
    // Add the filename to the path so external players recognize the extension
    final uri = Uri.parse(targetUrl);
    String filename = p.basename(uri.path);
    if (filename.isEmpty || !filename.contains('.')) {
      filename = 'media.mp4';
    }
    
    final encodedUrl = Uri.encodeComponent(targetUrl);
    return 'http://127.0.0.1:${_server!.port}/stream/$filename?url=$encodedUrl';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final targetUrl = request.uri.queryParameters['url'];
    if (targetUrl == null) {
      request.response.statusCode = 400;
      request.response.write('Missing target URL');
      await request.response.close();
      return;
    }

    try {
      final dio = DioClient().dio;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      
      final response = await dio.get<ResponseBody>(
        targetUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: range != null ? {'Range': range} : null,
          validateStatus: (status) => true,
        ),
      );

      final httpResponse = request.response;
      httpResponse.statusCode = response.statusCode ?? 200;
      
      // Mirror necessary headers back to the external player
      response.headers.forEach((name, values) {
         if (name.toLowerCase() != HttpHeaders.transferEncodingHeader) {
             for (final value in values) {
                httpResponse.headers.add(name, value);
             }
         }
      });

      await httpResponse.addStream(response.data!.stream);
      await httpResponse.close();
    } catch (e) {
      try {
        request.response.statusCode = 500;
        request.response.write(e.toString());
        await request.response.close();
      } catch (_) {}
    }
  }
}
