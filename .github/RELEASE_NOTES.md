# SimCam Lite 0.2.0

Better support for camera apps that pick their own format and record video with sound.

### What's New

- **Microphone audio:** Apps that use `AVCaptureAudioDataOutput` now receive 48 kHz mono audio from your Mac's microphone, or silence when microphone access isn't granted.
- **More camera formats:** The camera now offers 1920×1080, 1920×1440 and 4032×3024 formats. Apps can choose one with `activeFormat`, and frames arrive at that size.
- **Correct colors:** Frames are tagged as Rec. 709, so apps that check the color space accept them.

### Fixes

- Apps that call `commitConfiguration` or `stopRunning` on a simulated session no longer reset the camera.
- Choosing a camera format no longer crashes apps.

### System Requirements

- **macOS:** 14.0 (Sonoma) or newer.
- **Xcode:** with an iOS Simulator runtime installed.
