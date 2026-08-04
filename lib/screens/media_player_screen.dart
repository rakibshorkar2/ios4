import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:battery_plus/battery_plus.dart';

class MediaPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final List<Map<String, String>>? playlist;
  final int? initialIndex;

  const MediaPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.playlist,
    this.initialIndex,
  });

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late Player player;
  late VideoController controller;
  bool _initialized = false;
  Duration _savedPosition = Duration.zero;

  double _brightness = 0.5;
  double _volume = 0.5;
  bool _showOverlay = false;
  String _overlayType =
      ''; // 'brightness', 'volume', 'seek', 'speed', 'lock', 'audio', 'subtitle', 'fit'
  Timer? _overlayTimer;

  bool _isLocked = false;
  double _playbackSpeed = 1.0;
  BoxFit _fitMode = BoxFit.contain;
  Duration _tempSeekPosition = Duration.zero;
  bool _isSeekingHorizontally = false;

  // New features
  bool _isHWDecoder = true;
  bool _isABRepeat = false;
  Duration? _abStart;
  Duration? _abEnd;
  int _batteryLevel = 100;
  String _currentTime = "";
  final Battery _battery = Battery();
  Timer? _statusTimer;
  StreamSubscription? _posSub;
  bool _isLandscape = true;
  bool _showRipple = false;
  bool _rippleIsLeft = true;
  bool _isRocketMode = false;
  int _currentIndex = 0;
  late String _currentUrl;
  late String _currentTitle;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _currentTitle = widget.title;
    _currentIndex = widget.initialIndex ?? 0;
    
    player = Player();
    controller = VideoController(player);
    _initPlayer();
    _startStatusUpdates();
    _setupABRepeat();
  }

  void _startStatusUpdates() {
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _currentTime = DateFormat('HH:mm').format(DateTime.now());
        });
      }
    });
  }

  void _setupABRepeat() {
    _posSub = player.stream.position.listen((position) {
      if (_isABRepeat && _abStart != null && _abEnd != null) {
        if (position >= _abEnd!) {
          player.seek(_abStart!);
        }
      }
    });
  }

  void _toggleABRepeat() {
    setState(() {
      if (!_isABRepeat) {
        _isABRepeat = true;
        _abStart = player.state.position;
        _abEnd = null; // Wait for second tap for B
        _showControlOverlay('ab_start');
      } else if (_abEnd == null) {
        _abEnd = player.state.position;
        if (_abEnd! <= _abStart!) {
          _abEnd = _abStart! + const Duration(seconds: 5);
        }
        _showControlOverlay('ab_repeat_on');
      } else {
        _isABRepeat = false;
        _abStart = null;
        _abEnd = null;
        _showControlOverlay('ab_repeat_off');
      }
    });
  }

  Future<void> _initPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    final posMillis = prefs.getInt('playback_pos_$_currentUrl') ?? 0;
    _savedPosition = Duration(milliseconds: posMillis);
    _isHWDecoder = prefs.getBool('video_hw_decoder') ?? true;

    // Initialize brightness and volume
    try {
      _brightness = await ScreenBrightness().current;
    } catch (_) {
      _brightness = 0.5;
    }
    
    // We recreate the player if HW decoder choice changed or for initial load
    // But mid-playback recreate is complex, so we'll init with stored preference
    // OR just use native_video_view if available. media_kit defaults to HW.
    
    player.stream.volume.listen((v) => setState(() => _volume = v / 100.0));

    player.stream.playing.listen((playing) {
      if (playing && !_initialized && _savedPosition.inMilliseconds > 0) {
        _initialized = true;
        player.seek(_savedPosition);
      }
    });

    player.stream.completed.listen((completed) {
      if (completed) {
        _playNext();
      }
    });

    await player.open(Media(_currentUrl));
  }

  Future<void> _openMedia(String url, String title) async {
    // Save current position before switching
    if (player.state.position.inMilliseconds > 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('playback_pos_$_currentUrl', player.state.position.inMilliseconds);
    }

    setState(() {
      _currentUrl = url;
      _currentTitle = title;
      _initialized = false;
      _isABRepeat = false;
      _abStart = null;
      _abEnd = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final posMillis = prefs.getInt('playback_pos_$_currentUrl') ?? 0;
    _savedPosition = Duration(milliseconds: posMillis);

    await player.open(Media(url));
  }

  void _playNext() {
    if (widget.playlist == null || widget.playlist!.isEmpty) return;
    if (_currentIndex < widget.playlist!.length - 1) {
      _currentIndex++;
      final item = widget.playlist![_currentIndex];
      _openMedia(item['url']!, item['title']!);
    }
  }

  void _playPrevious() {
    if (widget.playlist == null || widget.playlist!.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      final item = widget.playlist![_currentIndex];
      _openMedia(item['url']!, item['title']!);
    }
  }

  Future<void> _toggleDecoder() async {
    final newHW = !_isHWDecoder;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('video_hw_decoder', newHW);
    
    // Changing VideoController to apply HW acceleration change
    setState(() {
      _isHWDecoder = newHW;
      controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(enableHardwareAcceleration: newHW),
      );
      _showControlOverlay('decoder');
    });
  }

  void _toggleRocketMode() {
    setState(() {
      _isRocketMode = !_isRocketMode;
      _showControlOverlay('rocket_mode');
    });
  }

  void _showControlOverlay(String type) {
    if (type == 'controls' && !_showOverlay) {
       // When showing controls on Windows, ensure cursor is visible
       SystemMouseCursors.basic;
    }
    setState(() {
      _overlayType = type;
      _showOverlay = true;
    });
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showOverlay = false);
      }
    });
  }

  void _handleVerticalDrag(DragUpdateDetails details, double screenWidth) {
    if (_isLocked) return;
    final isLeft = details.globalPosition.dx < screenWidth / 2;
    final delta = -details.primaryDelta! / 200.0; // Sensitivity adjustment

    if (isLeft) {
      // Brightness
      setState(() {
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
        ScreenBrightness().setScreenBrightness(_brightness);
        _showControlOverlay('brightness');
      });
    } else {
      // Volume
      setState(() {
        _volume = (_volume + delta).clamp(0.0, 1.0);
        player.setVolume(_volume * 100.0);
        _showControlOverlay('volume');
      });
    }
  }

  void _handleHorizontalDragUpdate(
      DragUpdateDetails details, double screenWidth) {
    if (_isLocked) return;
    if (!_isSeekingHorizontally) {
      _isSeekingHorizontally = true;
      _tempSeekPosition = player.state.position;
    }

    final sensitivity = _isRocketMode ? 2.0 : 1.0;
    final delta = (details.primaryDelta! / screenWidth) * sensitivity;
    final seekDelta =
        Duration(seconds: (player.state.duration.inSeconds * delta).toInt());

    setState(() {
      _tempSeekPosition = _tempSeekPosition + seekDelta;
      if (_tempSeekPosition < Duration.zero) _tempSeekPosition = Duration.zero;
      if (_tempSeekPosition > player.state.duration) {
        _tempSeekPosition = player.state.duration;
      }
      _showControlOverlay('seek');
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_isLocked) return;
    if (_isSeekingHorizontally) {
      player.seek(_tempSeekPosition);
      _isSeekingHorizontally = false;
    }
  }

  void _handleDoubleTap(TapDownDetails details, double screenWidth) {
    if (_isLocked) return;
    final isLeft = details.globalPosition.dx < screenWidth / 2;
    final seekAmount = isLeft ? -10 : 10;
    var newPosition = player.state.position + Duration(seconds: seekAmount);
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (newPosition > player.state.duration) {
      newPosition = player.state.duration;
    }

    player.seek(newPosition);
    setState(() {
      _showRipple = true;
      _rippleIsLeft = isLeft;
    });
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showRipple = false);
    });
    _showControlOverlay(isLeft ? 'seek_back' : 'seek_forward');
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _showControlOverlay('lock');
    });
  }

  void _toggleRotation() {
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
      _showControlOverlay('rotation');
    });
  }

  void _cycleFitMode() {
    setState(() {
      if (_fitMode == BoxFit.contain) {
        _fitMode = BoxFit.cover;
      } else if (_fitMode == BoxFit.cover) {
        _fitMode = BoxFit.fill;
      } else {
        _fitMode = BoxFit.contain;
      }
      _showControlOverlay('fit');
    });
  }

  void _showSpeedBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: speeds.map((speed) {
              return ListTile(
                title: Text(
                  '${speed}x',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _playbackSpeed == speed ? Colors.blue : Colors.white,
                    fontWeight: _playbackSpeed == speed
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _playbackSpeed = speed;
                    player.setRate(speed);
                    _showControlOverlay('speed');
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showAudioTrackBottomSheet() {
    final tracks = player.state.tracks.audio;
    final current = player.state.track.audio;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Audio Tracks',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isSelected = track == current;
                    return ListTile(
                      title: Text(
                        track.title ?? track.language ?? 'Track ${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.blue : Colors.white,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () {
                        player.setAudioTrack(track);
                        Navigator.pop(context);
                        _showControlOverlay('audio');
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSubtitleTrackBottomSheet() {
    final tracks = player.state.tracks.subtitle;
    final current = player.state.track.subtitle;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Subtitles',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isSelected = track == current;
                    return ListTile(
                      title: Text(
                        track.title ??
                            track.language ??
                            (index == 0 ? 'None' : 'Subtitle $index'),
                        style: TextStyle(
                          color: isSelected ? Colors.blue : Colors.white,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () {
                        player.setSubtitleTrack(track);
                        Navigator.pop(context);
                        _showControlOverlay('subtitle');
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _overlayTimer?.cancel();
    _statusTimer?.cancel();
    _posSub?.cancel();
    final int pos = player.state.position.inMilliseconds;
    if (pos > 0) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('playback_pos_$_currentUrl', pos);
      });
    }

    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: const MaterialVideoControlsThemeData(
          // We'll hide most of the default controls and build our own overlay
          controlsHoverDuration: Duration(seconds: 3),
          buttonBarHeight: 0,
          primaryButtonBar: [],
          bottomButtonBar: [],
          topButtonBar: [],
        ),
        fullscreen: const MaterialVideoControlsThemeData(
          buttonBarHeight: 0,
          primaryButtonBar: [],
          bottomButtonBar: [],
          topButtonBar: [],
        ),
        child: Stack(
          children: [
            GestureDetector(
              onVerticalDragUpdate: (details) =>
                  _handleVerticalDrag(details, size.width),
              onHorizontalDragUpdate: (details) =>
                  _handleHorizontalDragUpdate(details, size.width),
              onHorizontalDragEnd: _handleHorizontalDragEnd,
              onDoubleTapDown: (details) => _handleDoubleTap(details, size.width),
              onTap: () {
                setState(() {
                  _showOverlay = !_showOverlay;
                  _overlayType = 'controls';
                });
                if (_showOverlay) {
                  _overlayTimer?.cancel();
                  _overlayTimer = Timer(const Duration(seconds: 5), () {
                    if (mounted) setState(() => _showOverlay = false);
                  });
                }
              },
              child: MouseRegion(
                cursor: _showOverlay ? SystemMouseCursors.basic : SystemMouseCursors.none,
                onHover: (_) {
                  if (!_showOverlay) {
                    _showControlOverlay('controls');
                  }
                },
                child: Video(
                  controller: controller,
                  controls: (state) => const SizedBox.shrink(),
                  fit: _fitMode,
                ),
              ),
            ),

            // Custom Controls Overlay
            if (!_isLocked && _showOverlay && _overlayType == 'controls') ...[
              _buildTopBar(context),
              _buildSideControls(),
              _buildBottomBar(context),
            ],

            // Locked State Icon
            if (_isLocked)
              Center(
                child: IconButton(
                  color: Colors.white54,
                  iconSize: 64,
                  icon: const Icon(Icons.lock_outline),
                  onPressed: _toggleLock,
                ),
              ),

            // Double Tap Ripple Effect
            if (_showRipple)
              Positioned(
                left: _rippleIsLeft ? 0 : size.width / 2,
                top: 0,
                bottom: 0,
                width: size.width / 2,
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white10,
                  ),
                  child: Center(
                    child: Icon(
                      _rippleIsLeft ? Icons.fast_rewind : Icons.fast_forward,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),

            // Feedback Overlay (Brightness, Volume, Seek)
            if (_showOverlay && _overlayType != 'controls')
              Center(
                child: _buildFeedbackOverlay(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 80,
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        _currentTime,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _getBatteryIcon(_batteryLevel),
                        color: Colors.white70,
                        size: 12,
                      ),
                      Text(
                        ' $_batteryLevel%',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.cast, color: Colors.white),
              onPressed: () => _showControlOverlay('cast_unavailable'),
            ),
            IconButton(
              icon: const Icon(Icons.playlist_play, color: Colors.white),
              onPressed: _showPlaylistBottomSheet,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              onPressed: _showInfoDialog,
            ),
            GestureDetector(
              onTap: _toggleDecoder,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isHWDecoder ? 'HW' : 'SW',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: _showMoreMenu,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getBatteryIcon(int level) {
    if (level > 80) return Icons.battery_full;
    if (level > 50) return Icons.battery_6_bar;
    if (level > 20) return Icons.battery_3_bar;
    return Icons.battery_alert;
  }

  Widget _buildSideControls() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Left side
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SideButton(
                  icon: Icons.video_collection_outlined,
                  onPressed: _showPlaylistBottomSheet,
                ),
                _SideButton(
                  icon: Icons.aspect_ratio,
                  onPressed: _cycleFitMode,
                ),
                _SideButton(
                  icon: Icons.screen_rotation,
                  onPressed: _toggleRotation,
                ),
              ],
            ),
          ),
          // Right side
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SideButton(
                  icon: Icons.repeat_one,
                  color: _isABRepeat ? Colors.orange : Colors.white,
                  onPressed: _toggleABRepeat,
                  label: 'AB',
                ),
                _SideButton(
                  icon: Icons.speed,
                  onPressed: _showSpeedBottomSheet,
                ),
                _SideButton(
                  icon: Icons.rocket_launch,
                  color: _isRocketMode ? Colors.orange : Colors.white,
                  onPressed: _toggleRocketMode,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _formatDuration(player.state.position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: player.state.position.inMilliseconds.toDouble(),
                      max: player.state.duration.inMilliseconds.toDouble(),
                      onChanged: (value) {
                        player.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                ),
                Text(
                  _formatDuration(player.state.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(_isLocked ? Icons.lock : Icons.lock_open_outlined,
                      color: Colors.white),
                  onPressed: _toggleLock,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: _playPrevious,
                ),
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  onPressed: () => player.seek(
                      player.state.position - const Duration(seconds: 10)),
                ),
                IconButton(
                  icon: Icon(
                      player.state.playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 48),
                  onPressed: () => player.playOrPause(),
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  onPressed: () => player.seek(
                      player.state.position + const Duration(seconds: 10)),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: _playNext,
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOverlayIcon(),
          const SizedBox(height: 8),
          _buildOverlayContent(),
        ],
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.audiotrack, color: Colors.white),
                title: const Text('Audio Tracks',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showAudioTrackBottomSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.subtitles, color: Colors.white),
                title:
                    const Text('Subtitles', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showSubtitleTrackBottomSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed, color: Colors.white),
                title: const Text('Playback Speed',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showSpeedBottomSheet();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPlaylistBottomSheet() {
    if (widget.playlist == null || widget.playlist!.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Playlist',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.playlist!.length,
                  itemBuilder: (context, index) {
                    final item = widget.playlist![index];
                    final isCurrent = index == _currentIndex;
                    return ListTile(
                      leading: Icon(
                        isCurrent ? Icons.play_circle_fill : Icons.video_library,
                        color: isCurrent ? Colors.blue : Colors.white70,
                      ),
                      title: Text(
                        item['title'] ?? 'Media ${index + 1}',
                        style: TextStyle(
                          color: isCurrent ? Colors.blue : Colors.white,
                        ),
                      ),
                      onTap: () {
                        _currentIndex = index;
                        _openMedia(item['url']!, item['title']!);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showInfoDialog() {
    final vTrack = player.state.track.video;
    final aTrack = player.state.track.audio;
    final width = player.state.width ?? 0;
    final height = player.state.height ?? 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Media Info', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Title: $_currentTitle',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Resolution: ${width}x$height',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Duration: ${_formatDuration(player.state.duration)}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Video Track: ${vTrack.title ?? vTrack.id}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Audio Track: ${aTrack.title ?? aTrack.id}',
                style: const TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  Widget _buildOverlayIcon() {
    IconData icon;
    switch (_overlayType) {
      case 'brightness':
        icon = Icons.brightness_6;
        break;
      case 'volume':
        icon = Icons.volume_up;
        break;
      case 'seek_forward':
        icon = Icons.fast_forward;
        break;
      case 'seek_back':
        icon = Icons.fast_rewind;
        break;
      case 'seek':
        icon = Icons.compare_arrows;
        break;
      case 'speed':
        icon = Icons.speed;
        break;
      case 'lock':
        icon = _isLocked ? Icons.lock : Icons.lock_open;
        break;
      case 'fit':
        icon = Icons.aspect_ratio;
        break;
      case 'audio':
        icon = Icons.audiotrack;
        break;
      case 'subtitle':
        icon = Icons.subtitles;
        break;
      default:
        icon = Icons.info;
    }
    return Icon(icon, color: Colors.white, size: 48);
  }

  Widget _buildOverlayContent() {
    if (_overlayType == 'brightness' || _overlayType == 'volume') {
      return SizedBox(
        width: 150,
        child: LinearProgressIndicator(
          value: _overlayType == 'brightness' ? _brightness : _volume,
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    } else if (_overlayType == 'seek') {
      return Text(
        '${_formatDuration(_tempSeekPosition)} / ${_formatDuration(player.state.duration)}',
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType.startsWith('seek_')) {
      return const Text(
        '10s',
        style: TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'speed') {
      return Text(
        '${_playbackSpeed}x',
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'lock') {
      return Text(
        _isLocked ? 'Locked' : 'Unlocked',
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'fit') {
      String mode = 'Contain';
      if (_fitMode == BoxFit.cover) mode = 'Cover';
      if (_fitMode == BoxFit.fill) mode = 'Fill';
      return Text(
        mode,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'audio') {
      return const Text(
        'Audio Track Changed',
        style: TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'subtitle') {
      return const Text(
        'Subtitle Track Changed',
        style: TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'ab_start') {
      return const Text(
        'A Point Set',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'ab_repeat_on') {
      return const Text(
        'AB Repeat ON',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'ab_repeat_off') {
      return const Text(
        'AB Repeat OFF',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'decoder') {
      return Text(
        _isHWDecoder ? 'HW Decoder' : 'SW Decoder',
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'rotation') {
      return Text(
        _isLandscape ? 'Landscape' : 'Portrait',
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'cast_unavailable') {
      return const Text(
        'Looking for devices...',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else if (_overlayType == 'rocket_mode') {
      return Text(
        _isRocketMode ? 'Rocket Mode: ON' : 'Rocket Mode: OFF',
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );
    }
    return const SizedBox.shrink();
  }
}

class _SideButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final String? label;

  const _SideButton({
    required this.icon,
    required this.onPressed,
    this.color = Colors.white,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: InkWell(
        onTap: onPressed,
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            if (label != null)
              Text(
                label!,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }
}
