My Flutter iOS app already has a working Live Activity and Dynamic Island.

Current issue:
- The compact Dynamic Island appears while downloading.
- Tapping or long-pressing the Dynamic Island does NOT expand it.
- The expanded Dynamic Island UI is missing.

Find the cause and fix it.

Specifically:

1. Inspect the existing Widget Extension and Live Activity implementation.
2. Verify that DynamicIsland(...) is implemented inside ActivityConfiguration.
3. If only the Lock Screen Live Activity is implemented, add the complete Dynamic Island implementation.
4. Implement all Dynamic Island regions:
   - compactLeading
   - compactTrailing
   - minimal
   - expanded
5. In the expanded view display:
   - file icon
   - file name
   - progress bar
   - percentage
   - downloaded size / total size
   - download speed
   - ETA
   - download status
6. Use the existing Activity instead of creating a new one.
7. Keep updating the existing Live Activity from Flutter through the existing MethodChannel.
8. Verify that the ActivityAttributes and ContentState contain all values required by the expanded UI.
9. Verify that the Widget Extension target includes ActivityKit and WidgetKit and supports Dynamic Island.
10. Verify that Info.plist, entitlements and deployment target are correct.
11. If any required ActivityKit or WidgetKit code is missing, add it.
12. Explain exactly why the expanded Dynamic Island was not appearing.
13. Do not modify unrelated Flutter code.

The goal is that when I long-press the Dynamic Island during a download, it expands into Apple's standard expanded Dynamic Island showing live download progress.