# Development

## Build and run

```bash
brew install xcodegen
```

```bash
scripts/build.sh Debug
```

`xcodegen generate` recreates `SimCamLite.xcodeproj` from `project.yml`; run it after adding or removing files. Signing
reads `SIMCAM_DEVELOPMENT_TEAM` from the gitignored `Config/Environment.xcconfig` (see
`Config/Environment.example.xcconfig`).

Build the inject framework, install it to `/Users/Shared/SimCamLite` and launch an app with it:

```bash
scripts/dev-inject.sh com.example.app
```

Stream the logs of the injected framework:

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "dev.ifateam.simcamlite"'
```

Link the CLI of your build onto `PATH`:

```bash
scripts/install-cli.sh
```

## Project layout

| Folder | Contents |
| --- | --- |
| `Shared/` | Shared memory format: seqlock, 2 streams × 3 slots of 1920×1440 BGRA, client slots |
| `Loader/` | Tiny dylib that only `dlopen`s the framework in user apps |
| `Inject/` | Fake AVFoundation objects, swizzling, frame pump, photo capture |
| `HostBridge/` | C API the macOS app uses to write frames and heartbeats |
| `App/` | SwiftUI macOS app: sources, render pipeline, simulator management, updates, control server for the CLI |
| `Common/` | Protocol and socket shared by the app and the CLI |
| `CLI/` | The `simcam` command-line tool |
| `scripts/` | Build, DMG and release scripts |

## README screenshots

Open the main window, stream into a camera app on a booted simulator, then run:

```bash
scripts/make-screenshots.sh
```

It captures the Camera, Simulator and Settings sections and the simulator screen, puts the screen inside
`assets/frames/iphone.png`, and writes the images to `assets/screenshots/`. It needs Pillow (`pip3 install pillow`).
