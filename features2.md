The Dynamic Island and Live Activity implementation is working correctly.

Modify the implementation so that the Live Activity only exists while there is at least one **actively downloading** item.

Requirements:

* If there are **no active downloads**, immediately end the Live Activity.
* If a download is **paused**, treat it as inactive and end the Live Activity.
* If a download is **completed**, end the Live Activity.
* If a download is **failed**, end the Live Activity.
* If a download is **cancelled**, end the Live Activity.
* If the user removes the last active download, end the Live Activity.
* Do not leave a stale Live Activity visible in the Dynamic Island or on the Lock Screen.

When a download is resumed:

* If there is no existing Live Activity, create a new one.
* Continue updating it with the current progress.

If multiple downloads are supported:

* Keep the Live Activity visible as long as **at least one** download is actively downloading.
* If every download is paused, completed, failed, or cancelled, end the Live Activity.
* Optionally display the most active or highest-priority download in the Dynamic Island.

Implement a centralized `LiveActivityManager` that listens to download state changes instead of relying on individual download widgets.

The manager should react to these states:

* Downloading → Start or update the Live Activity.
* Paused → End the Live Activity if no other downloads are active.
* Completed → End the Live Activity if no other downloads are active.
* Failed → End the Live Activity if no other downloads are active.
* Cancelled → End the Live Activity if no other downloads are active.

Ensure the app never leaves an orphaned Live Activity after the last active download stops.

Do not modify any unrelated Flutter UI or download logic. Only update the Live Activity lifecycle so it accurately reflects whether there are any active downloads.
