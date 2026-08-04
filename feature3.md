I want to add an **experimental background execution mode** to my existing Flutter iOS app for testing on my own sideloaded iPhone.

Do not modify any existing download logic, SOCKS5 implementation, or Flutter UI unless required.

Implement the following:

### Background Audio

* Enable the iOS **Audio** background mode.
* Create a native Swift `BackgroundAudioService`.
* Configure an `AVAudioSession` for playback.
* Play a silent looping audio track only while there is at least one active download.
* Automatically stop the audio session when there are no active downloads.
* Ensure the audio service starts and stops cleanly without memory leaks.

### Background Location

* Enable the iOS **Location Updates** background mode.
* Create a native Swift `BackgroundLocationService`.
* Request the appropriate location permissions.
* Start location updates only while there is at least one active download.
* Stop location updates immediately when all downloads have stopped, completed, failed, or are paused.
* Handle authorization changes gracefully.

### Flutter Integration

Use a Flutter `MethodChannel` to expose these methods:

* `startBackgroundServices()`
* `stopBackgroundServices()`

The Flutter download manager should:

* Call `startBackgroundServices()` when the first active download begins.
* Call `stopBackgroundServices()` when there are no active downloads remaining.

### Dynamic Island

Do not change the existing Live Activity implementation except to ensure:

* Live Activity starts only while downloads are active.
* Live Activity ends when there are no active downloads.

### Code Quality

* Keep the implementation modular.
* Add clear comments explaining each native iOS change.
* Do not modify unrelated files.
* At the end, provide:

  * A list of all files created or modified.
  * A summary of every Xcode capability enabled.
  * Any `Info.plist` keys added.
  * Any permissions that must be granted on the device.
