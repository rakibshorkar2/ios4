I already have a working Flutter app for iPhone. Do **not** modify the existing Flutter UI, navigation, business logic, or features unless required for Dynamic Island support.

Your task is to add **Live Activities and Dynamic Island** support for iOS only.

Requirements:

* Add an iOS Widget Extension with Live Activities enabled.
* Use Apple's **ActivityKit** and **WidgetKit**.
* Enable the required iOS capabilities and entitlements.
* Configure `Info.plist` with the required Live Activities settings.
* Implement native Swift code only where necessary.
* Communicate between Flutter and Swift using a `MethodChannel`.
* Expose these Flutter methods:

  * `startLiveActivity(title, progress, speed, eta)`
  * `updateLiveActivity(progress, speed, eta)`
  * `endLiveActivity()`
* Design a clean Dynamic Island UI showing:

  * File name
  * Download progress
  * Download speed
  * ETA
  * Completed state
* Support both the Lock Screen Live Activity and Dynamic Island on supported iPhones.
* Ensure updates are efficient and avoid unnecessary UI refreshes.
* Keep the implementation compatible with release builds and sideloaded IPAs.
* Do not remove or break any existing Flutter functionality.
* Add clear comments to all newly added Swift code.
* At the end, provide a list of every file created or modified and explain what each change does.
