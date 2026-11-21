# SimCam Lite 0.2.1

Test how your app handles camera permission, just like on a real iPhone.

### What's New

- **Ask for Camera Permission:** A new option in the camera menu. When it's on, apps see the iOS camera alert and can be denied, so you can test your permission flow. When it's off, apps always get camera access, as before.
- **Command line:** `simcam permission ask` or `simcam permission allow` switches the option, and `simcam status` shows it.

### System Requirements

- **macOS:** 14.0 (Sonoma) or newer.
- **Xcode:** with an iOS Simulator runtime installed.
