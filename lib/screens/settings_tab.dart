import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform;
import '../providers/app_state.dart';
import 'security_setup_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  static const String _appName = 'DirXplore';
  static const String _developerName = 'RAKIB';
  static const String _appVersion = 'V3.0.2';

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final isAmoled = appState.trueAmoledDark &&
        Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background gradient (cheap single shader fill)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: isAmoled ? Colors.black : null,
                gradient: isAmoled
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.surface,
                          scheme.surfaceContainerHighest
                              .withValues(alpha: 0.8),
                        ],
                      ),
              ),
            ),
          ),
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
              bottom: 120,
            ),
            children: [
              _buildSection(
                context,
                title: 'Appearance',
                icon: Icons.palette_outlined,
                accent: scheme.primary,
                children: [
                  _buildDropdownTile<ThemeMode>(
                    context,
                    icon: Icons.brightness_6_outlined,
                    accent: scheme.primary,
                    title: 'Theme',
                    subtitle: 'App color theme',
                    value: appState.themeMode,
                    items: const [
                      DropdownMenuItem(
                          value: ThemeMode.system, child: Text('System')),
                      DropdownMenuItem(
                          value: ThemeMode.light, child: Text('Light')),
                      DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text('Material Dark')),
                    ],
                    onChanged: (val) {
                      if (val != null) appState.setThemeMode(val);
                    },
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.phone_android_outlined,
                    accent: scheme.primary,
                    title: 'True AMOLED Black',
                    subtitle: 'Pure black background for OLED screens',
                    value: appState.trueAmoledDark,
                    onChanged: (val) => appState.setTrueAmoledDark(val),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSection(
                context,
                title: 'Downloads',
                icon: Icons.download_outlined,
                accent: scheme.tertiary,
                children: [
                  _buildTile(
                    context,
                    icon: Icons.folder_open_outlined,
                    accent: scheme.tertiary,
                    title: 'Default Save Directory',
                    subtitle: appState.defaultSavePath,
                    chevron: true,
                    onTap: () => _pickSaveDirectory(context, appState),
                  ),
                  _buildDropdownTile<int>(
                    context,
                    icon: Icons.speed,
                    accent: scheme.tertiary,
                    title: 'Max Concurrent Downloads',
                    subtitle:
                        '${appState.maxConcurrentDownloads} files at once',
                    value: appState.maxConcurrentDownloads,
                    items: [1, 2, 3, 4, 5, 10]
                        .map((e) => DropdownMenuItem(
                            value: e, child: Text(e.toString())))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        appState.setMaxConcurrentDownloads(val);
                      }
                    },
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.notifications_none,
                    accent: scheme.tertiary,
                    title: 'Show Download Notifications',
                    subtitle: 'Display progress in notification panel',
                    value: appState.showDownloadNotifications,
                    onChanged: (val) =>
                        appState.setShowDownloadNotifications(val),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSection(
                context,
                title: 'Smart Automation',
                icon: Icons.auto_awesome_outlined,
                accent: scheme.secondary,
                children: [
                  _buildSwitchTile(
                    context,
                    icon: Icons.sort,
                    accent: scheme.secondary,
                    title: 'Smart Folder Routing',
                    subtitle: 'Auto-sort by extension',
                    value: appState.smartFolderRouting,
                    onChanged: (val) => appState.setSmartFolderRouting(val),
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.wifi_outlined,
                    accent: scheme.secondary,
                    title: 'Download on Wi-Fi Only',
                    value: appState.downloadOnWifiOnly,
                    onChanged: (val) => appState.setDownloadOnWifiOnly(val),
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.battery_alert,
                    accent: scheme.secondary,
                    title: 'Pause If Battery < 15%',
                    value: appState.pauseLowBattery,
                    onChanged: (val) => appState.setPauseLowBattery(val),
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.wb_sunny_outlined,
                    accent: scheme.secondary,
                    title: 'Keep Screen Awake',
                    subtitle: 'Prevent sleep while downloading',
                    value: appState.keepScreenAwake,
                    onChanged: (val) => appState.setKeepScreenAwake(val),
                  ),
                  if (appState.keepScreenAwake)
                    _buildSliderTile(
                      context,
                      icon: Icons.timer_outlined,
                      accent: scheme.secondary,
                      title: 'Auto-off Timer',
                      subtitle:
                          '${appState.keepScreenAwakeTimerMinutes == 0 ? "Off" : "${appState.keepScreenAwakeTimerMinutes} min"} '
                          '• Turn off screen wake after set time',
                      value:
                          appState.keepScreenAwakeTimerMinutes.toDouble(),
                      min: 0,
                      max: 60,
                      divisions: 12,
                      label: appState.keepScreenAwakeTimerMinutes == 0
                          ? 'Off'
                          : '${appState.keepScreenAwakeTimerMinutes} min',
                      onChanged: (val) => appState
                          .setKeepScreenAwakeTimerMinutes(val.round()),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSection(
                context,
                title: 'Smart Retry',
                icon: Icons.replay_outlined,
                accent: scheme.primary,
                children: [
                  _buildDropdownTile<int>(
                    context,
                    icon: Icons.repeat,
                    accent: scheme.primary,
                    title: 'Max Retry Count',
                    subtitle: '${appState.retryCount} retries',
                    value: appState.retryCount,
                    items: [1, 2, 3, 5, 10]
                        .map((e) => DropdownMenuItem(
                            value: e, child: Text(e.toString())))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) appState.setRetryCount(val);
                    },
                  ),
                  _buildDropdownTile<int>(
                    context,
                    icon: Icons.hourglass_bottom_outlined,
                    accent: scheme.primary,
                    title: 'Retry Delay',
                    subtitle: '${appState.retryDelaySeconds} seconds',
                    value: appState.retryDelaySeconds,
                    items: [5, 10, 15, 30, 60, 120]
                        .map((e) => DropdownMenuItem(
                            value: e, child: Text('${e}s')))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) appState.setRetryDelaySeconds(val);
                    },
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.autorenew,
                    accent: scheme.primary,
                    title: 'Auto Retry',
                    subtitle: 'Automatically retry failed downloads',
                    value: appState.autoRetry,
                    onChanged: (val) => appState.setAutoRetry(val),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSection(
                context,
                title: 'Download Scheduler',
                icon: Icons.schedule_outlined,
                accent: scheme.tertiary,
                children: [
                  _buildSwitchTile(
                    context,
                    icon: Icons.schedule_outlined,
                    accent: scheme.tertiary,
                    title: 'Enable Scheduler',
                    subtitle:
                        'Respect scheduling preferences for downloads',
                    value: appState.enableScheduler,
                    onChanged: (val) => appState.setEnableScheduler(val),
                  ),
                  if (appState.enableScheduler) ...[
                    _buildSwitchTile(
                      context,
                      icon: Icons.wifi_outlined,
                      accent: scheme.tertiary,
                      title: 'Wi-Fi Only Scheduling',
                      subtitle: 'Only download queued items on Wi-Fi',
                      value: appState.schedulerWifiOnly,
                      onChanged: (val) =>
                          appState.setSchedulerWifiOnly(val),
                    ),
                    _buildSwitchTile(
                      context,
                      icon: Icons.bolt_outlined,
                      accent: scheme.tertiary,
                      title: 'Charging Only',
                      subtitle: 'Only download while device is charging',
                      value: appState.schedulerChargingOnly,
                      onChanged: (val) =>
                          appState.setSchedulerChargingOnly(val),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              _buildSection(
                context,
                title: 'Auto-Categorization',
                icon: Icons.category_outlined,
                accent: scheme.secondary,
                children: [
                  _buildSwitchTile(
                    context,
                    icon: Icons.category_outlined,
                    accent: scheme.secondary,
                    title: 'Auto-Categorize Downloads',
                    subtitle: 'Sort completed downloads by file type',
                    value: appState.autoCategorizeEnabled,
                    onChanged: (val) =>
                        appState.setAutoCategorizeEnabled(val),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSection(
                context,
                title: 'Haptics & Feedback',
                icon: Icons.vibration_outlined,
                accent: scheme.primary,
                children: [
                  _buildSwitchTile(
                    context,
                    icon: Icons.vibration_outlined,
                    accent: scheme.primary,
                    title: 'Haptic Feedback',
                    subtitle: 'Vibration on taps and actions',
                    value: appState.hapticFeedbackEnabled,
                    onChanged: (val) =>
                        appState.setHapticFeedbackEnabled(val),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSection(
                context,
                title: 'Security & Privacy',
                icon: Icons.shield_outlined,
                accent: scheme.error,
                children: [
                  _buildDropdownTile<String>(
                    context,
                    icon: Icons.lock_outline,
                    accent: scheme.error,
                    title: 'App Lock Type',
                    subtitle: appState.lockType == 'none'
                        ? 'Disabled'
                        : appState.lockType == 'device'
                            ? 'Device (Fingerprint/PIN/Pattern)'
                            : 'Custom App PIN',
                    value: appState.lockType,
                    items: const [
                      DropdownMenuItem(
                          value: 'none', child: Text('None')),
                      DropdownMenuItem(
                          value: 'device', child: Text('Device')),
                      DropdownMenuItem(
                          value: 'custom', child: Text('Custom PIN')),
                    ],
                    onChanged: (val) {
                      if (val == 'custom' &&
                          appState.customPinHash.isEmpty) {
                        _showSecuritySetup(context);
                      } else {
                        if (val != null) appState.setLockType(val);
                      }
                    },
                  ),
                  _buildDropdownTile<int>(
                    context,
                    icon: Icons.timer_off_outlined,
                    accent: scheme.error,
                    title: 'Inactivity Auto-Lock',
                    subtitle: appState.autoLockSeconds == 0
                        ? 'Immediate'
                        : appState.autoLockSeconds == 30
                            ? '30 Seconds'
                            : '${appState.autoLockSeconds ~/ 60} Minute(s)',
                    value: appState.autoLockSeconds,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Immediate')),
                      DropdownMenuItem(value: 30, child: Text('30s')),
                      DropdownMenuItem(value: 60, child: Text('1m')),
                      DropdownMenuItem(value: 120, child: Text('2m')),
                    ],
                    onChanged: (val) {
                      if (val != null) appState.setAutoLockSeconds(val);
                    },
                  ),
                  if (appState.lockType == 'custom')
                    _buildTile(
                      context,
                      icon: Icons.pin_outlined,
                      accent: scheme.error,
                      title: 'Configure Custom PIN',
                      subtitle: 'Change PIN or security question',
                      chevron: true,
                      onTap: () => _showSecuritySetup(context),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSection(
                context,
                title: 'BRWSR Tab Settings',
                icon: Icons.language_outlined,
                accent: scheme.tertiary,
                children: [
                  _buildSwitchTile(
                    context,
                    icon: Icons.notifications_active_outlined,
                    accent: scheme.tertiary,
                    title: 'Live Activity (Dynamic Island)',
                    subtitle:
                        'Show BRWSR web progress on Dynamic Island / Lock Screen',
                    value: appState.brwsrLiveActivityEnabled,
                    onChanged: (val) =>
                        appState.setBrwsrLiveActivityEnabled(val),
                  ),
                  _buildSwitchTile(
                    context,
                    icon: Icons.wifi_tethering_outlined,
                    accent: scheme.tertiary,
                    title: 'Background Keep-Alive Service',
                    subtitle:
                        'Keep BRWSR active in background via silent audio & location',
                    value: appState.brwsrBackgroundServiceEnabled,
                    onChanged: (val) =>
                        appState.setBrwsrBackgroundServiceEnabled(val),
                  ),
                ],
              ),
              _buildAppInfoCard(context),
            ],
          ),
          // Solid translucent header (no BackdropFilter => low GPU load)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: MediaQuery.of(context).padding.top + kToolbarHeight,
              decoration: BoxDecoration(
                color: (isAmoled ? Colors.black : scheme.surface)
                    .withValues(alpha: 0.94),
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Section card
  // ---------------------------------------------------------------------
  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color accent,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon, size: 13, color: accent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 64,
                          endIndent: 16,
                          color:
                              scheme.outlineVariant.withValues(alpha: 0.12),
                        ),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Base tile
  // ---------------------------------------------------------------------
  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool chevron = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
            if (chevron)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Switch tile
  // ---------------------------------------------------------------------
  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _buildTile(
      context,
      icon: icon,
      accent: accent,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: accent,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Dropdown tile (chip style)
  // ---------------------------------------------------------------------
  Widget _buildDropdownTile<T>(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    String? subtitle,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return _buildTile(
      context,
      icon: icon,
      accent: accent,
      title: title,
      subtitle: subtitle,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: DropdownButton<T>(
          value: value,
          underline: const SizedBox(),
          isDense: true,
          style: TextStyle(fontSize: 13, color: scheme.onSurface),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Slider tile
  // ---------------------------------------------------------------------
  Widget _buildSliderTile(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    String? label,
    required ValueChanged<double> onChanged,
  }) {
    return _buildTile(
      context,
      icon: icon,
      accent: accent,
      title: title,
      subtitle: subtitle,
      trailing: SizedBox(
        width: 130,
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // App info card
  // ---------------------------------------------------------------------
  Widget _buildAppInfoCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.25),
                scheme.surface.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child:
                    Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              const Text(
                _appName,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Developed by $_developerName',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Version $_appVersion',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Save directory picker (kept identical behavior)
  // ---------------------------------------------------------------------
  Future<void> _pickSaveDirectory(BuildContext context, AppState appState) async {
    if (Platform.isIOS) {
      final picked = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Persistent Download Folder'),
          content: const Text(
            'Choose a folder outside the app sandbox (e.g. "On My iPhone" or iCloud Drive) so downloads survive app deletion.\n\n'
            'The default Documents folder is deleted with the app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Choose Folder'),
            ),
          ],
        ),
      );
      if (picked != true) return;
      final path = await appState.pickDownloadFolder();
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Downloads will now save to a persistent folder outside the app sandbox.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else {
      String? selectedDirectory =
          await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        appState.setDefaultSavePath(selectedDirectory);
      }
    }
  }

  void _showSecuritySetup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SecuritySetupScreen()),
    );
  }
}
