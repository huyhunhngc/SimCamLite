export interface ChangelogHighlight {
  title: string;
  description: string;
}

export interface ChangelogRelease {
  version: string;
  date: string;
  summary: string;
  latest?: boolean;
  highlights: ChangelogHighlight[];
  fixes?: string[];
}

export const CHANGELOG_RELEASES: ChangelogRelease[] = [
  {
    version: '0.2.6',
    date: 'Nov 25, 2026',
    summary: 'Resizing the window is smooth again while the cameras stream.',
    latest: true,
    highlights: [
      {
        title: 'Smoother window',
        description:
          "The camera previews now draw outside the window's layout, so streaming video no longer makes the app re-measure the whole window on every frame. Resizing and scrolling the Camera screen stay smooth, even with 4K video at 60 fps, and the app uses less CPU.",
      },
    ],
  },
  {
    version: '0.2.5',
    date: 'Nov 25, 2026',
    summary: 'Apps can now test 4K video in the simulator.',
    highlights: [
      {
        title: '4K video format',
        description:
          'Back cameras now offer a 3840 × 2160 format, and the 4K session preset delivers real 4K frames so apps looking for 4K can preview and record it. Software encoding in the simulator saves fewer frames per second than a real iPhone while preserving full picture size.',
      },
    ],
  },
  {
    version: '0.2.4',
    date: 'Nov 25, 2026',
    summary: 'The camera picture now turns with the simulator, the way a real phone sees the world.',
    highlights: [
      {
        title: 'Follow Simulator Rotation',
        description:
          'Turn the simulator sideways and apps receive a landscape view of your source—upright once the app applies device rotation, just like on a real iPhone. Held portrait, the frame stays identical to before. Enabled by default and toggleable in the menu or stream settings.',
      },
    ],
  },
  {
    version: '0.2.3',
    date: 'Nov 21, 2026',
    summary: 'Sound now records when an app turns on the microphone while the camera is already running.',
    highlights: [
      {
        title: 'Live microphone pump',
        description:
          'Apps that request microphone input after the camera session has already started (for example, right after the first permission prompt) now receive audio samples in their recordings.',
      },
    ],
  },
  {
    version: '0.2.2',
    date: 'Nov 21, 2026',
    summary: 'Test every camera and microphone permission case in one click.',
    highlights: [
      {
        title: 'Permission presets',
        description:
          'Right-click an app in the sidebar (or click the hand button on hover) and choose fresh install, camera denied, microphone not asked, microphone denied, or both allowed. SimCam Lite resets or sets TCC permissions and restarts the app.',
      },
      {
        title: 'Command line',
        description:
          'Run `simcam permission <app> <case>` (for example `simcam permission com.example.app mic-denied`) to trigger the same presets from Terminal or CI.',
      },
    ],
  },
  {
    version: '0.2.1',
    date: 'Nov 21, 2026',
    summary: 'Test how your app handles camera permission, just like on a real iPhone.',
    highlights: [
      {
        title: 'Ask for Camera Permission',
        description:
          'When enabled in the camera menu, injected apps see the real iOS camera permission prompt and can be denied so you can verify your permission recovery UI. When off, apps continue receiving automatic access.',
      },
      {
        title: 'Command line',
        description:
          'Switch modes with `simcam permission ask` or `simcam permission allow`, and inspect the active mode in `simcam status`.',
      },
    ],
  },
  {
    version: '0.2.0',
    date: 'Nov 19, 2026',
    summary: 'Better support for camera apps that pick their own format and record video with sound.',
    highlights: [
      {
        title: 'Microphone audio',
        description:
          'Apps using AVCaptureAudioDataOutput now receive 48 kHz mono 16-bit PCM audio from your Mac’s microphone (or silence if microphone permission isn’t granted).',
      },
      {
        title: 'Selectable camera formats',
        description:
          'Cameras expose 1920×1080, 1920×1440, and 4032×3024 formats. Apps can select a format via `activeFormat` and receive frames at that size.',
      },
      {
        title: 'Rec. 709 color tagging',
        description:
          'Frames are tagged as Rec. 709 so apps inspecting color space metadata accept them cleanly.',
      },
    ],
    fixes: [
      'Apps calling `commitConfiguration` or `stopRunning` on a simulated session no longer reset the camera.',
      'Choosing a camera format no longer crashes apps.',
    ],
  },
  {
    version: '0.1.0',
    date: 'Oct 11, 2026',
    summary:
      'First public release of SimCam Lite: a free, MIT-licensed camera for the iOS Simulator with zero changes to your app’s code.',
    highlights: [
      {
        title: 'Any source as the camera',
        description:
          'Stream a photo, looping video, generated QR code, Mac camera, or test pattern with independent back and front cameras.',
      },
      {
        title: 'Simulator manager & Run from Xcode',
        description:
          'Boot simulators, launch single apps or inject every app, and set up Xcode projects once to keep using Run and the debugger.',
      },
      {
        title: 'CLI, Homebrew & Sparkle updates',
        description:
          'Control everything from Terminal with `simcam`, install via `brew install --cask huyhunhngc/tap/simcam-lite`, and receive automatic signed updates.',
      },
    ],
  },
];
