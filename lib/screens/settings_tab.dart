import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform;
import 'dart:ui';
import '../providers/app_state.dart';
import 'security_setup_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background gradient or image could go here
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: appState.trueAmoledDark &&
                        Theme.of(context).brightness == Brightness.dark
                    ? Colors.black
                    : null,
                gradient: appState.trueAmoledDark &&
                        Theme.of(context).brightness == Brightness.dark
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.surface,
                          Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
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
              _buildGlassSection(
                context,
                'UI & APPEARANCE',
                [
                  _buildGlassTile(
                    title: const Text('Theme'),
                    trailing: DropdownButton<ThemeMode>(
                      value: appState.themeMode,
                      underline: const SizedBox(),
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
                  ),
                  _buildGlassSwitchTile(
                    title: 'True AMOLED Black',
                    subtitle: 'Pure black background for OLED screens',
                    value: appState.trueAmoledDark,
                    onChanged: (val) => appState.setTrueAmoledDark(val),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'DOWNLOAD SETTINGS',
                [
                  _buildGlassTile(
                    title: const Text('Default Save Directory'),
                    subtitle: Text(appState.defaultSavePath,
                        style: const TextStyle(fontSize: 10)),
                    trailing: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () async {
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
                              SnackBar(
                                content: Text('Downloads will now save to a persistent folder outside the app sandbox.'),
                                duration: const Duration(seconds: 4),
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
                      },
                    ),
                  ),
                  _buildGlassTile(
                    title: const Text('Max Concurrent Downloads'),
                    subtitle: Text(
                        '${appState.maxConcurrentDownloads} files at once'),
                    trailing: DropdownButton<int>(
                      value: appState.maxConcurrentDownloads,
                      underline: const SizedBox(),
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
                  ),
                  _buildGlassSwitchTile(
                    title: 'Show Download Notifications',
                    subtitle: 'Display progress in notification panel',
                    value: appState.showDownloadNotifications,
                    onChanged: (val) =>
                        appState.setShowDownloadNotifications(val),
                  ),
                  _buildGlassTile(
                    title: const Text('Speed Limiter (Per Download)'),
                    subtitle: appState.speedLimitCap == 0
                        ? const Text('Unlimited')
                        : Text('${appState.speedLimitCap} KB/s'),
                    trailing: SizedBox(
                      width: 120,
                      child: Slider(
                        value: appState.speedLimitCap.toDouble(),
                        min: 0,
                        max: 10000,
                        divisions: 20,
                        onChanged: (val) =>
                            appState.setSpeedLimitCap(val.toInt()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'SMART AUTOMATION',
                [
                  _buildGlassSwitchTile(
                    title: 'Smart Folder Routing',
                    subtitle: 'Auto-sort by extension',
                    value: appState.smartFolderRouting,
                    onChanged: (val) => appState.setSmartFolderRouting(val),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Download on Wi-Fi Only',
                    value: appState.downloadOnWifiOnly,
                    onChanged: (val) => appState.setDownloadOnWifiOnly(val),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Pause If Battery < 15%',
                    value: appState.pauseLowBattery,
                    onChanged: (val) => appState.setPauseLowBattery(val),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Keep Screen Awake',
                    subtitle: 'Prevent sleep while downloading',
                    value: appState.keepScreenAwake,
                    onChanged: (val) => appState.setKeepScreenAwake(val),
                  ),
                  if (appState.keepScreenAwake)
                    _buildGlassTile(
                      title: Row(
                        children: [
                          const Text('Auto-off Timer'),
                          const Spacer(),
                          Text(
                            appState.keepScreenAwakeTimerMinutes == 0
                                ? 'Off'
                                : '${appState.keepScreenAwakeTimerMinutes} min',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      subtitle: const Text('Turn off screen wake after set time'),
                      trailing: SizedBox(
                        width: 120,
                        child: Slider(
                          value: appState.keepScreenAwakeTimerMinutes.toDouble(),
                          min: 0,
                          max: 60,
                          divisions: 12,
                          label: appState.keepScreenAwakeTimerMinutes == 0
                              ? 'Off'
                              : '${appState.keepScreenAwakeTimerMinutes} min',
                          onChanged: (val) =>
                              appState.setKeepScreenAwakeTimerMinutes(val.round()),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'SMART RETRY',
                [
                  _buildGlassTile(
                    title: const Text('Max Retry Count'),
                    subtitle: Text('${appState.retryCount} retries'),
                    trailing: DropdownButton<int>(
                      value: appState.retryCount,
                      underline: const SizedBox(),
                      items: [1, 2, 3, 5, 10].map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
                      onChanged: (val) {
                        if (val != null) appState.setRetryCount(val);
                      },
                    ),
                  ),
                  _buildGlassTile(
                    title: const Text('Retry Delay'),
                    subtitle: Text('${appState.retryDelaySeconds} seconds'),
                    trailing: DropdownButton<int>(
                      value: appState.retryDelaySeconds,
                      underline: const SizedBox(),
                      items: [5, 10, 15, 30, 60, 120].map((e) => DropdownMenuItem(value: e, child: Text('${e}s'))).toList(),
                      onChanged: (val) {
                        if (val != null) appState.setRetryDelaySeconds(val);
                      },
                    ),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Auto Retry',
                    subtitle: 'Automatically retry failed downloads',
                    value: appState.autoRetry,
                    onChanged: (val) => appState.setAutoRetry(val),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'DOWNLOAD SCHEDULER',
                [
                  _buildGlassSwitchTile(
                    title: 'Enable Scheduler',
                    subtitle: 'Respect scheduling preferences for downloads',
                    value: appState.enableScheduler,
                    onChanged: (val) => appState.setEnableScheduler(val),
                  ),
                  if (appState.enableScheduler) ...[
                    _buildGlassSwitchTile(
                      title: 'Wi-Fi Only Scheduling',
                      subtitle: 'Only download queued items on Wi-Fi',
                      value: appState.schedulerWifiOnly,
                      onChanged: (val) => appState.setSchedulerWifiOnly(val),
                    ),
                    _buildGlassSwitchTile(
                      title: 'Charging Only',
                      subtitle: 'Only download while device is charging',
                      value: appState.schedulerChargingOnly,
                      onChanged: (val) => appState.setSchedulerChargingOnly(val),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'AUTO-CATEGORIZATION',
                [
                  _buildGlassSwitchTile(
                    title: 'Auto-Categorize Downloads',
                    subtitle: 'Sort completed downloads by file type',
                    value: appState.autoCategorizeEnabled,
                    onChanged: (val) => appState.setAutoCategorizeEnabled(val),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'HAPTICS & FEEDBACK',
                [
                  _buildGlassSwitchTile(
                    title: 'Haptic Feedback',
                    subtitle: 'Vibration on taps and actions',
                    value: appState.hapticFeedbackEnabled,
                    onChanged: (val) => appState.setHapticFeedbackEnabled(val),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'SECURITY & PRIVACY',
                [
                  _buildGlassTile(
                    title: const Text('App Lock Type'),
                    subtitle: Text(appState.lockType == 'none'
                        ? 'Disabled'
                        : appState.lockType == 'device'
                            ? 'Device (Fingerprint/PIN/Pattern)'
                            : 'Custom App PIN'),
                    trailing: DropdownButton<String>(
                      value: appState.lockType,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('None')),
                        DropdownMenuItem(
                            value: 'device', child: Text('Device')),
                        DropdownMenuItem(
                            value: 'custom', child: Text('Custom PIN')),
                      ],
                      onChanged: (val) {
                        if (val == 'custom' && appState.customPinHash.isEmpty) {
                          _showSecuritySetup(context);
                        } else {
                          if (val != null) appState.setLockType(val);
                        }
                      },
                    ),
                  ),
                  _buildGlassTile(
                    title: const Text('Inactivity Auto-Lock'),
                    subtitle: Text(appState.autoLockSeconds == 0
                        ? 'Immediate'
                        : appState.autoLockSeconds == 30
                            ? '30 Seconds'
                            : '${appState.autoLockSeconds ~/ 60} Minute(s)'),
                    trailing: DropdownButton<int>(
                      value: appState.autoLockSeconds,
                      underline: const SizedBox(),
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
                  ),
                  if (appState.lockType == 'custom')
                    _buildGlassTile(
                      title: const Text('Configure Custom PIN'),
                      subtitle: const Text('Change PIN or security question'),
                      leading: const Icon(Icons.security),
                      onTap: () => _showSecuritySetup(context),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'BRWSR TAB SETTINGS',
                [
                  _buildGlassSwitchTile(
                    title: 'Live Activity (Dynamic Island)',
                    subtitle: 'Show BRWSR web progress on Dynamic Island / Lock Screen',
                    value: appState.brwsrLiveActivityEnabled,
                    onChanged: (val) => appState.setBrwsrLiveActivityEnabled(val),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Background Keep-Alive Service',
                    subtitle: 'Keep BRWSR active in background via silent audio & location',
                    value: appState.brwsrBackgroundServiceEnabled,
                    onChanged: (val) => appState.setBrwsrBackgroundServiceEnabled(val),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'ABOUT',
                [
                  _buildGlassTile(
                    title: const Text('Version'),
                    subtitle: Text(appState.appVersion),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Center(
                child: Text(
                  'Created by RAKIB',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          // Blurred Header Container
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: MediaQuery.of(context).padding.top + kToolbarHeight,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.8),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassSection(
      BuildContext context, String title, List<Widget> children) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12)),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.15), // Optimized "Faux Glass"
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassTile({
    required Widget title,
    Widget? subtitle,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildGlassSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: value,
      onChanged: onChanged,
    );
  }

  void _showSecuritySetup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SecuritySetupScreen()),
    );
  }

}
