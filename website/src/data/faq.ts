export interface FaqItem {
  q: string;
  a: string;
}

export const FAQS: FaqItem[] = [
  {
    q: 'Do I need to modify my app’s code or add an SDK?',
    a: 'No. SimCam Lite never touches your app’s source code or dependencies. It injects a small loader via DYLD_INSERT_LIBRARIES that loads SimCamLiteInject.framework into Simulator user apps and emulates AVFoundation.',
  },
  {
    q: 'Does it work when I press Run in Xcode with the debugger attached?',
    a: 'Yes. Because Xcode sets its own DYLD_INSERT_LIBRARIES (for Main Thread Checker and diagnostics), open “Run from Xcode” in SimCam Lite—or run `simcam xcode setup`—once per project. Committing the shared scheme change is safe: Macs without SimCam Lite ignore the missing dylib.',
  },
  {
    q: 'Which macOS and iOS Simulator versions are supported?',
    a: 'SimCam Lite requires macOS 14.0 (Sonoma) or newer and Xcode with an iOS Simulator runtime (targeting iOS 16.0+ simulator apps).',
  },
  {
    q: 'Can I test QR code scanning and third-party camera libraries?',
    a: 'Yes—any app or library reading frames from AVCaptureVideoDataOutput, AVCapturePhotoOutput, or AVCaptureVideoPreviewLayer (including Vision, VisionKit data scanners on video frames, React Native, and Flutter camera plugins) receives the live feed. Note that AVFoundation’s built-in AVCaptureMetadataOutput QR detection is not emulated yet.',
  },
  {
    q: 'What features are currently not supported?',
    a: 'SimCam Lite does not yet support movie file recording (AVCaptureMovieFileOutput), built-in AVCaptureMetadataOutput detection, or multi-camera sessions (AVCaptureMultiCamSession). Audio input via AVCaptureAudioDataOutput (48 kHz mono 16-bit PCM) is supported.',
  },
  {
    q: 'Is SimCam Lite really free for teams and CI?',
    a: 'Yes. SimCam Lite is 100% free and MIT-licensed open source. There are no seat limits, watermarks, or commercial CI add-ons.',
  },
];
