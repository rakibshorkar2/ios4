import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:io' show Platform;
import 'dart:typed_data';

typedef WriteChunkC = ffi.Int32 Function(ffi.Pointer<Utf8> filePath, ffi.Pointer<ffi.Uint8> data, ffi.Int32 length, ffi.Int64 offset);
typedef WriteChunkDart = int Function(ffi.Pointer<Utf8> filePath, ffi.Pointer<ffi.Uint8> data, int length, int offset);

class CppNativeIO {
  static final CppNativeIO _instance = CppNativeIO._internal();
  factory CppNativeIO() => _instance;

  late ffi.DynamicLibrary _lib;
  late WriteChunkDart _writeChunkFunc;

  CppNativeIO._internal() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libnative_io.so');
    } else if (Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('libnative_io.so');
    } else {
      return;
    }

    _writeChunkFunc = _lib.lookupFunction<WriteChunkC, WriteChunkDart>('WriteChunk');
  }

  bool writeChunk(String targetPath, Uint8List data, int offset) {
    if (!Platform.isAndroid && !Platform.isLinux) return true;
    if (data.isEmpty) return true;

    final targetPathPtr = targetPath.toNativeUtf8();
    
    final ffi.Pointer<ffi.Uint8> dataPtr = malloc.allocate<ffi.Uint8>(data.length);
    final nativeList = dataPtr.asTypedList(data.length);
    nativeList.setAll(0, data);

    try {
      final result = _writeChunkFunc(targetPathPtr, dataPtr, data.length, offset);
      return result == 1;
    } finally {
      malloc.free(targetPathPtr);
      malloc.free(dataPtr);
    }
  }
}
