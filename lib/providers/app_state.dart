import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io' show Platform;

class AppState with ChangeNotifier {
  static const MethodChannel _iosChannel =
      MethodChannel('com.dirxplore/ios_download');
  ThemeMode _themeMode = ThemeMode.system;
  String _defaultSavePath = '';
  int _maxConcurrentDownloads = 1;
  String _appVersion = 'Unknown';
  bool _initialized = false;

  // Added Phase 1-4 Toggles
  bool _trueAmoledDark = false;
  bool _showDownloadNotifications = true;
  int _speedLimitCap = 0; // 0 means no limit (in KB/s)
  bool _keepScreenAwake = false;
  int _keepScreenAwakeTimerMinutes = 0;
  Timer? _keepAwakeTimer;
  bool _smartFolderRouting = false;
  bool _downloadOnWifiOnly = false;
  bool _pauseLowBattery = false;
  bool _requireBiometrics = false;
  String _lockType = 'none'; // 'none', 'device', 'custom'
  String _customPinHash = '';
  String _securityQuestion = '';
  String _securityAnswer = '';
  int _autoLockSeconds = 0; // 0 = Immediate, 30, 60, 120
  bool _hapticFeedbackEnabled = true;

  // Retry settings
  int _retryCount = 3;
  int _retryDelaySeconds = 10;
  bool _autoRetry = true;

  // Scheduler settings
  bool _enableScheduler = false;
  bool _schedulerWifiOnly = false;
  bool _schedulerChargingOnly = false;

  // Auto-categorization
  bool _autoCategorizeEnabled = true;

  // BRWSR Settings
  bool _brwsrLiveActivityEnabled = true;
  bool _brwsrBackgroundServiceEnabled = false;


  ThemeMode get themeMode => _themeMode;
  String get defaultSavePath => _defaultSavePath;
  int get maxConcurrentDownloads => _maxConcurrentDownloads;
  String get appVersion => _appVersion;
  bool get isInitialized => _initialized;

  // Added Getters
  bool get trueAmoledDark => _trueAmoledDark;
  bool get showDownloadNotifications => _showDownloadNotifications;
  int get speedLimitCap => _speedLimitCap;
  bool get keepScreenAwake => _keepScreenAwake;
  int get keepScreenAwakeTimerMinutes => _keepScreenAwakeTimerMinutes;
  bool get smartFolderRouting => _smartFolderRouting;
  bool get downloadOnWifiOnly => _downloadOnWifiOnly;
  bool get pauseLowBattery => _pauseLowBattery;
  bool get requireBiometrics => _requireBiometrics;
  String get lockType => _lockType;
  String get customPinHash => _customPinHash;
  String get securityQuestion => _securityQuestion;
  String get securityAnswer => _securityAnswer;
  int get autoLockSeconds => _autoLockSeconds;
  bool get hapticFeedbackEnabled => _hapticFeedbackEnabled;

  // Retry
  int get retryCount => _retryCount;
  int get retryDelaySeconds => _retryDelaySeconds;
  bool get autoRetry => _autoRetry;

  // Scheduler
  bool get enableScheduler => _enableScheduler;
  bool get schedulerWifiOnly => _schedulerWifiOnly;
  bool get schedulerChargingOnly => _schedulerChargingOnly;

  // Auto-categorize
  bool get autoCategorizeEnabled => _autoCategorizeEnabled;

  // BRWSR Settings Getters
  bool get brwsrLiveActivityEnabled => _brwsrLiveActivityEnabled;
  bool get brwsrBackgroundServiceEnabled => _brwsrBackgroundServiceEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Set platform-appropriate default save path
    if (_defaultSavePath.isEmpty) {
      if (Platform.isAndroid) {
        _defaultSavePath = '/storage/emulated/0/Download/DirXplore';
      } else if (Platform.isIOS) {
        try {
          final path = await _iosChannel.invokeMethod<String>('getSavePath');
          _defaultSavePath = path ?? '${(await getApplicationDocumentsDirectory()).path}/DirXplore';
        } catch (_) {
          final dir = await getApplicationDocumentsDirectory();
          _defaultSavePath = '${dir.path}/DirXplore';
        }
      } else {
        try {
          final dir = await getApplicationDocumentsDirectory();
          _defaultSavePath = '${dir.path}/DirXplore';
        } catch (_) {
          _defaultSavePath = '/storage/emulated/0/Download/DirXplore';
        }
      }
    }

    // Load Theme
    final tIdx = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[tIdx];

    // Load Settings
    _defaultSavePath =
        prefs.getString('savePath') ?? _defaultSavePath;
    _maxConcurrentDownloads = prefs.getInt('maxConcurrent') ?? 1;

    // Load Added Feature Toggles
    _trueAmoledDark = prefs.getBool('trueAmoledDark') ?? true;
    _showDownloadNotifications =
        prefs.getBool('showDownloadNotifications') ?? true;
    _speedLimitCap = prefs.getInt('speedLimitCap') ?? 0;
    _keepScreenAwake = prefs.getBool('keepScreenAwake') ?? false;
    _keepScreenAwakeTimerMinutes = prefs.getInt('keepScreenAwakeTimerMinutes') ?? 0;
    _smartFolderRouting = prefs.getBool('smartFolderRouting') ?? false;
    _downloadOnWifiOnly = prefs.getBool('downloadOnWifiOnly') ?? false;
    _pauseLowBattery = prefs.getBool('pauseLowBattery') ?? false;
    _requireBiometrics = prefs.getBool('requireBiometrics') ?? false;
    _lockType = prefs.getString('lockType') ?? 'none';
    _customPinHash = prefs.getString('customPinHash') ?? '';
    _securityQuestion = prefs.getString('securityQuestion') ?? '';
    _securityAnswer = prefs.getString('securityAnswer') ?? '';
    _autoLockSeconds = prefs.getInt('autoLockSeconds') ?? 0;
    _hapticFeedbackEnabled = prefs.getBool('hapticFeedbackEnabled') ?? true;

    _retryCount = prefs.getInt('retryCount') ?? 3;
    _retryDelaySeconds = prefs.getInt('retryDelaySeconds') ?? 10;
    _autoRetry = prefs.getBool('autoRetry') ?? true;
    _enableScheduler = prefs.getBool('enableScheduler') ?? false;
    _schedulerWifiOnly = prefs.getBool('schedulerWifiOnly') ?? false;
    _schedulerChargingOnly = prefs.getBool('schedulerChargingOnly') ?? false;
    _autoCategorizeEnabled = prefs.getBool('autoCategorizeEnabled') ?? true;

    _brwsrLiveActivityEnabled = prefs.getBool('brwsrLiveActivityEnabled') ?? true;
    _brwsrBackgroundServiceEnabled = prefs.getBool('brwsrBackgroundServiceEnabled') ?? false;

    if (Platform.isIOS) {
      try {
        const liveChannel = MethodChannel('com.dirxplore/live_activity');
        const bgChannel = MethodChannel('com.dirxplore/background_services');
        if (!_brwsrLiveActivityEnabled) {
          await liveChannel.invokeMethod('disable');
        }
        if (!_brwsrBackgroundServiceEnabled) {
          await bgChannel.invokeMethod('stopBackgroundServices');
        }
      } catch (e) {
        debugPrint('Init channels sync error: $e');
      }
    }

    // Load App Version
    final info = await PackageInfo.fromPlatform();
    _appVersion = info.version;

    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setDefaultSavePath(String path) async {
    _defaultSavePath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savePath', path);
  }

  Future<String?> pickDownloadFolder() async {
    if (!Platform.isIOS) return null;
    try {
      final path = await _iosChannel.invokeMethod<String>('pickDownloadFolder');
      if (path != null && path.isNotEmpty) {
        _defaultSavePath = path;
        notifyListeners();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('savePath', path);
      }
      return path;
    } catch (e) {
      debugPrint('pickDownloadFolder error: $e');
      return null;
    }
  }

  Future<void> setMaxConcurrentDownloads(int max) async {
    _maxConcurrentDownloads = max;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maxConcurrent', max);
  }

  // --- Added Setters ---

  Future<void> setTrueAmoledDark(bool val) async {
    _trueAmoledDark = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trueAmoledDark', val);
  }

  Future<void> setShowDownloadNotifications(bool val) async {
    _showDownloadNotifications = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showDownloadNotifications', val);
  }

  Future<void> setSpeedLimitCap(int val) async {
    _speedLimitCap = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('speedLimitCap', val);
  }

  Future<void> setKeepScreenAwake(bool val) async {
    _keepAwakeTimer?.cancel();
    _keepAwakeTimer = null;
    _keepScreenAwake = val;
    if (val && _keepScreenAwakeTimerMinutes > 0) {
      _keepAwakeTimer = Timer(Duration(minutes: _keepScreenAwakeTimerMinutes), () {
        setKeepScreenAwake(false);
      });
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keepScreenAwake', val);
  }

  Future<void> setKeepScreenAwakeTimerMinutes(int minutes) async {
    _keepScreenAwakeTimerMinutes = minutes.clamp(0, 60);
    if (_keepScreenAwake) {
      _keepAwakeTimer?.cancel();
      _keepAwakeTimer = null;
      if (minutes > 0) {
        _keepAwakeTimer = Timer(Duration(minutes: minutes), () {
          setKeepScreenAwake(false);
        });
      }
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('keepScreenAwakeTimerMinutes', _keepScreenAwakeTimerMinutes);
  }

  void notifyDownloadsComplete() {
    if (!_keepScreenAwake) return;
    _keepAwakeTimer?.cancel();
    _keepAwakeTimer = null;
    _keepScreenAwake = false;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('keepScreenAwake', false);
    });
  }

  Future<void> setSmartFolderRouting(bool val) async {
    _smartFolderRouting = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smartFolderRouting', val);
  }

  Future<void> setDownloadOnWifiOnly(bool val) async {
    _downloadOnWifiOnly = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('downloadOnWifiOnly', val);
  }

  Future<void> setPauseLowBattery(bool val) async {
    _pauseLowBattery = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pauseLowBattery', val);
  }

  Future<void> setRequireBiometrics(bool val) async {
    _requireBiometrics = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('requireBiometrics', val);
  }

  Future<void> setLockType(String type) async {
    _lockType = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lockType', type);
  }

  Future<void> setCustomPin(String pin, String question, String answer) async {
    _customPinHash = pin; // In real app, use sha256 or similar
    _securityQuestion = question;
    _securityAnswer = answer;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customPinHash', pin);
    await prefs.setString('securityQuestion', question);
    await prefs.setString('securityAnswer', answer);
  }

  Future<void> resetCustomPin() async {
    _customPinHash = '';
    _securityQuestion = '';
    _securityAnswer = '';
    _lockType = 'none';
    _requireBiometrics = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('customPinHash');
    await prefs.remove('securityQuestion');
    await prefs.remove('securityAnswer');
    await prefs.setBool('requireBiometrics', false);
    await prefs.setString('lockType', 'none');
  }

  bool get isSecurityEnabled => _lockType != 'none';

  Future<void> setAutoLockSeconds(int seconds) async {
    _autoLockSeconds = seconds;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('autoLockSeconds', seconds);
  }

  Future<void> setHapticFeedbackEnabled(bool val) async {
    _hapticFeedbackEnabled = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hapticFeedbackEnabled', val);
  }

  // Retry settings
  Future<void> setRetryCount(int val) async {
    _retryCount = val.clamp(1, 10);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('retryCount', _retryCount);
  }

  Future<void> setRetryDelaySeconds(int val) async {
    _retryDelaySeconds = val.clamp(5, 300);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('retryDelaySeconds', _retryDelaySeconds);
  }

  Future<void> setAutoRetry(bool val) async {
    _autoRetry = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoRetry', val);
  }

  // Scheduler settings
  Future<void> setEnableScheduler(bool val) async {
    _enableScheduler = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableScheduler', val);
  }

  Future<void> setSchedulerWifiOnly(bool val) async {
    _schedulerWifiOnly = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('schedulerWifiOnly', val);
  }

  Future<void> setSchedulerChargingOnly(bool val) async {
    _schedulerChargingOnly = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('schedulerChargingOnly', val);
  }

  Future<void> setAutoCategorizeEnabled(bool val) async {
    _autoCategorizeEnabled = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoCategorizeEnabled', val);
  }

  Future<void> setBrwsrLiveActivityEnabled(bool enabled) async {
    _brwsrLiveActivityEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('brwsrLiveActivityEnabled', enabled);
    if (Platform.isIOS) {
      try {
        const liveChannel = MethodChannel('com.dirxplore/live_activity');
        if (enabled) {
          await liveChannel.invokeMethod('enable');
        } else {
          await liveChannel.invokeMethod('disable');
        }
      } catch (e) {
        debugPrint('LiveActivity toggle error: $e');
      }
    }
  }

  Future<void> setBrwsrBackgroundServiceEnabled(bool enabled) async {
    _brwsrBackgroundServiceEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('brwsrBackgroundServiceEnabled', enabled);
    if (Platform.isIOS) {
      try {
        const bgChannel = MethodChannel('com.dirxplore/background_services');
        if (enabled) {
          await bgChannel.invokeMethod('startBackgroundServices');
        } else {
          await bgChannel.invokeMethod('stopBackgroundServices');
        }
      } catch (e) {
        debugPrint('BackgroundService toggle error: $e');
      }
    }
  }
}
