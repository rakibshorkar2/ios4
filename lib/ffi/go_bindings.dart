import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io' show Platform;
import 'dart:convert';
import '../models/directory_item.dart';

typedef DeepCrawlC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> targetUrl, ffi.Pointer<Utf8> proxyUri);
typedef DeepCrawlDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> targetUrl, ffi.Pointer<Utf8> proxyUri);

typedef FreeCStringC = ffi.Void Function(ffi.Pointer<Utf8> ptr);
typedef FreeCStringDart = void Function(ffi.Pointer<Utf8> ptr);

class GoCrawler {
  static final GoCrawler _instance = GoCrawler._internal();
  factory GoCrawler() => _instance;

  late ffi.DynamicLibrary _lib;
  late DeepCrawlDart _deepCrawlFunc;
  late FreeCStringDart _freeCStringFunc;

  GoCrawler._internal() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libcrawler.so');
    } else if (Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('libcrawler.so');
    } else {
      return;
    }

    _deepCrawlFunc = _lib.lookupFunction<DeepCrawlC, DeepCrawlDart>('DeepCrawl');
    _freeCStringFunc = _lib.lookupFunction<FreeCStringC, FreeCStringDart>('FreeCString');
  }

  List<DirectoryItem> deepCrawl(String targetUrl, {String proxyUri = ""}) {
    if (!Platform.isAndroid && !Platform.isLinux) {
      throw UnsupportedError('Go crawler not available on this platform.');
    }

    final targetUrlPtr = targetUrl.toNativeUtf8();
    final proxyUriPtr = proxyUri.toNativeUtf8();

    final resultPtr = _deepCrawlFunc(targetUrlPtr, proxyUriPtr);
    
    final jsonResult = resultPtr.toDartString();
    _freeCStringFunc(resultPtr);
    
    malloc.free(targetUrlPtr);
    malloc.free(proxyUriPtr);

    if (jsonResult.startsWith('{"error"')) {
       final errorMap = jsonDecode(jsonResult);
       throw Exception("Native Crawler Error: ${errorMap['error']}");
    }

    final List<dynamic> jsonList = jsonDecode(jsonResult);
    return jsonList.map((item) => DirectoryItem(
      name: item['name'],
      url: item['url'],
      type: item['type'] == 'directory' ? DirectoryItemType.directory : DirectoryItem.typeFromExtension(item['name']),
      size: item['size'],
    )).toList();
  }
}
