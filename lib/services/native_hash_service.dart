import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:io' show Platform;

typedef GetFileHashC = ffi.Int32 Function(ffi.Pointer<Utf8> filePath,
    ffi.Pointer<Utf8> hashResult, ffi.Int32 algorithm);
typedef GetFileHashDart = int Function(
    ffi.Pointer<Utf8> filePath, ffi.Pointer<Utf8> hashResult, int algorithm);

typedef PreAllocateDiskC = ffi.Int32 Function(
    ffi.Pointer<Utf8> filePath, ffi.Int64 size);
typedef PreAllocateDiskDart = int Function(
    ffi.Pointer<Utf8> filePath, int size);

class NativeHashService {
  static final NativeHashService _instance = NativeHashService._internal();
  factory NativeHashService() => _instance;

  late ffi.DynamicLibrary _lib;
  late GetFileHashDart _getHashFunc;
  late PreAllocateDiskDart _preAllocateFunc;

  NativeHashService._internal() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libnative_io.so');
    } else {
      return;
    }

    _getHashFunc =
        _lib.lookupFunction<GetFileHashC, GetFileHashDart>('GetFileHash');
    _preAllocateFunc =
        _lib.lookupFunction<PreAllocateDiskC, PreAllocateDiskDart>(
            'PreAllocateDisk');
  }

  String? getFileHash(String filePath, {int algorithm = 0}) {
    if (!Platform.isAndroid) return null;

    final filePathPtr = filePath.toNativeUtf8();
    final hashResultPtr = malloc.allocate<Utf8>(256);

    try {
      final result = _getHashFunc(filePathPtr, hashResultPtr, algorithm);
      if (result == 1) {
        return hashResultPtr.toDartString();
      }
      return null;
    } finally {
      malloc.free(filePathPtr);
      malloc.free(hashResultPtr);
    }
  }

  bool preAllocateDisk(String filePath, int size) {
    if (!Platform.isAndroid) return true;

    final filePathPtr = filePath.toNativeUtf8();
    try {
      return _preAllocateFunc(filePathPtr, size) == 1;
    } finally {
      malloc.free(filePathPtr);
    }
  }
}
