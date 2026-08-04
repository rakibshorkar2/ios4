import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:local_auth/local_auth.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'screens/pin_lock_screen.dart';
import 'screens/browser_tab.dart';
import 'screens/download_tab.dart';
import 'screens/proxy_tab.dart';
import 'screens/settings_tab.dart';
import 'screens/brwsr_tab.dart';
import 'widgets/liquid_glass_nav_bar.dart';


import 'providers/app_state.dart';
import 'providers/proxy_provider.dart';
import 'providers/download_provider.dart';
import 'providers/browser_provider.dart';
import 'providers/brwsr_provider.dart';

import 'services/proxy_tunnel.dart';
import 'services/haptic_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (task == 'autoResumeDownloads') {
      final dummyProvider = DownloadProvider();
      await dummyProvider.init();

      await Future.delayed(const Duration(seconds: 10));
      return true;
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit initialization failed: $e');
  }

  try {
    await LiquidGlassWidgets.initialize();
  } catch (e) {
    debugPrint('LiquidGlassWidgets initialization failed: $e');
  }

  Workmanager().initialize(callbackDispatcher);

  Workmanager().registerPeriodicTask(
    "auto-resume-task",
    "autoResumeDownloads",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
  );

  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (e) {
    debugPrint('Failed to set high refresh rate: $e');
  }

  final appState = AppState();
  await appState.init();

  final proxyProvider = AppProxyProvider();
  await proxyProvider.init();

  final dlProvider = DownloadProvider();
  await dlProvider.init();
  dlProvider.setMaxConcurrent(appState.maxConcurrentDownloads);
  dlProvider.onAllDownloadsComplete = () => appState.notifyDownloadsComplete();

  await ProxyTunnel().start();

  runApp(
    LiquidGlassWidgets.wrap(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: proxyProvider),
          ChangeNotifierProvider.value(value: dlProvider),
          ChangeNotifierProvider(create: (_) => BrowserProvider()),
          ChangeNotifierProvider(create: (_) => BRWSRProvider()),
        ],
        child: const OpenDirAppWrapper(),
      ),
    ),
  );
}

class OpenDirAppWrapper extends StatefulWidget {
  const OpenDirAppWrapper({super.key});

  @override
  State<OpenDirAppWrapper> createState() => _OpenDirAppWrapperState();
}

class _OpenDirAppWrapperState extends State<OpenDirAppWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateWakelock();
      _requestNotificationPermission();
      _initHaptics();
    });
  }

  void _initHaptics() {
    final state = Provider.of<AppState>(context, listen: false);
    HapticService.setEnabled(state.hapticFeedbackEnabled);
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (Platform.isIOS && status.isRestricted) {
      await Permission.notification.request();
    } else if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  void _updateWakelock() {
    final state = Provider.of<AppState>(context, listen: false);
    WakelockPlus.toggle(enable: state.keepScreenAwake);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    WakelockPlus.toggle(enable: state.keepScreenAwake);
    HapticService.setEnabled(state.hapticFeedbackEnabled);

    return const OpenDirApp();
  }
}

class OpenDirApp extends StatelessWidget {
  const OpenDirApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightScheme;
        ColorScheme darkScheme;

        if (lightDynamic != null && darkDynamic != null) {
          lightScheme = lightDynamic.harmonized();
          darkScheme = darkDynamic.harmonized();
        } else {
          lightScheme = ColorScheme.fromSeed(seedColor: Colors.blueAccent);
          darkScheme = ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          );
        }

        if (appState.trueAmoledDark && appState.themeMode != ThemeMode.light) {
          darkScheme = darkScheme.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: Colors.black,
            surfaceContainer: const Color(0xFF0D1117),
            surfaceContainerHigh: const Color(0xFF161B22),
            surfaceContainerHighest: const Color(0xFF1C2128),
          );
        }

        return MaterialApp(
          title: 'DirXplore',
          themeMode: appState.themeMode,
          theme: ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: lightScheme,
            cupertinoOverrideTheme: const CupertinoThemeData(
              textTheme: CupertinoTextThemeData(
                primaryColor: CupertinoColors.activeBlue,
              ),
            ),
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: darkScheme,
            cupertinoOverrideTheme: const CupertinoThemeData(
              brightness: Brightness.dark,
              textTheme: CupertinoTextThemeData(
                primaryColor: CupertinoColors.activeBlue,
              ),
            ),
            scaffoldBackgroundColor: (appState.trueAmoledDark &&
                    appState.themeMode != ThemeMode.light)
                ? Colors.black
                : null,
            appBarTheme: AppBarTheme(
              backgroundColor: (appState.trueAmoledDark &&
                      appState.themeMode != ThemeMode.light)
                  ? Colors.black
                  : null,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          home: const BiometricLockWrapper(child: MainLayout()),
        );
      },
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const BrowserTab(),
    const DownloadTab(),
    const ProxyTab(),
    const BRWSRTab(),
    const SettingsTab(),
  ];

  DateTime? _lastPressedAt;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        final now = DateTime.now();
        const maxDuration = Duration(seconds: 2);
        final isWarning = _lastPressedAt == null ||
            now.difference(_lastPressedAt!) > maxDuration;

        if (isWarning) {
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        Navigator.pop(context);
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _tabs,
        ),
        bottomNavigationBar: LiquidGlassNavBar(
          currentIndex: _currentIndex,
          onTabSelected: (index) {
            HapticService.light();
            setState(() => _currentIndex = index);
          },
        ),
      ),
    );
  }
}

class BiometricLockWrapper extends StatefulWidget {
  final Widget child;
  const BiometricLockWrapper({super.key, required this.child});

  @override
  State<BiometricLockWrapper> createState() => _BiometricLockWrapperState();
}

class _BiometricLockWrapperState extends State<BiometricLockWrapper>
    with WidgetsBindingObserver {
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  DateTime? _lastAuthSuccessTime;
  Timer? _inactivityTimer;
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final now = DateTime.now();

    if (state == AppLifecycleState.resumed) {
      final appState = Provider.of<AppState>(context, listen: false);

      if (appState.lockType != 'none' &&
          _isAuthenticated &&
          !_isAuthenticating) {
        final timeSinceLastAuth = _lastAuthSuccessTime != null
            ? now.difference(_lastAuthSuccessTime!)
            : const Duration(hours: 1);

        if (timeSinceLastAuth > const Duration(seconds: 3)) {
          if (appState.autoLockSeconds == 0) {
            setState(() => _isAuthenticated = false);
            _checkAuth();
          } else {
            _resetInactivityTimer();
          }
        } else {
          _resetInactivityTimer();
        }
      } else if (_isAuthenticated) {
        _resetInactivityTimer();
      }
    } else if (state == AppLifecycleState.paused) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.lockType != 'none' &&
          appState.autoLockSeconds == 0 &&
          !_isAuthenticating) {
        setState(() => _isAuthenticated = false);
      }
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.autoLockSeconds > 0 && _isAuthenticated) {
      _inactivityTimer = Timer(Duration(seconds: appState.autoLockSeconds), () {
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
          });
        }
      });
    }
  }

  Future<void> _checkAuth() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.lockType == 'none') {
      setState(() => _isAuthenticated = true);
      return;
    }

    if (appState.lockType == 'custom') {
      return;
    }

    if (_isAuthenticating) return;

    try {
      setState(() => _isAuthenticating = true);
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) {
        setState(() {
          _isAuthenticated = true;
          _isAuthenticating = false;
        });
        _resetInactivityTimer();
        return;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate to access DirXplore',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (mounted) {
        setState(() {
          _isAuthenticated = didAuthenticate;
          if (didAuthenticate) {
            _lastAuthSuccessTime = DateTime.now();
          }
        });

        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted) {
          setState(() {
            _isAuthenticating = false;
          });
          if (didAuthenticate) {
            _resetInactivityTimer();
          }
        }
      }
    } catch (e) {
      debugPrint('Biometric Error: $e');
      if (mounted) {
        setState(() {
          _isAuthenticated = true;
          _isAuthenticating = false;
        });
        _resetInactivityTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.lockType == 'none' || _isAuthenticated) {
      return Listener(
        onPointerDown: (_) => _resetInactivityTimer(),
        onPointerMove: (_) => _resetInactivityTimer(),
        child: widget.child,
      );
    }

    if (appState.lockType == 'custom') {
      return PinLockScreen(
        onAuthenticated: () {
          setState(() => _isAuthenticated = true);
          _resetInactivityTimer();
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(color: Colors.black.withValues(alpha: 0.8)),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fingerprint,
                    size: 100, color: Colors.blueAccent),
                const SizedBox(height: 20),
                const Text('App Locked',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('Unlock with your device security',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 48),
                ElevatedButton.icon(
                  onPressed: _checkAuth,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock Now'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
