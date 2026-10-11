# How injection works

SimCam Lite never modifies the app under test. A small loader is injected with `DYLD_INSERT_LIBRARIES`; it loads
`SimCamLiteInject.framework` into user apps (system processes are skipped), and the framework emulates `AVFoundation`:
capture devices, sessions, video data output, photo output, the preview layer and the rotation coordinator.

On launch the Mac app copies `SimCamLiteLoader.dylib` and `SimCamLiteInject.framework` to `/Users/Shared/SimCamLite/`
and streams frames (30 fps by default, 60 fps from the toolbar or the menu bar) through the shared memory file
`/Users/Shared/SimCamLite/frames.shm`.

If SimCam Lite quits, injected apps keep running and show a "SimCamLite – Host app is not running" frame.

## 1. Every app on a simulator

Turn on **Use SimCamLite in every app on this simulator** in the Simulator section. It is equivalent to:

```bash
xcrun simctl spawn booted launchctl setenv DYLD_INSERT_LIBRARIES /Users/Shared/SimCamLite/SimCamLiteLoader.dylib
```

Every app launched afterwards is injected.

`launchctl setenv` is lost when the simulator shuts down, so SimCam Lite remembers the choice per simulator UDID and
turns it back on whenever that simulator boots, as long as the app is running. It checks every 3 seconds, and restores
simulators that are already booted when it launches. Apps opened in the first few seconds after boot may not be
injected.

**Every simulator as it boots** (Simulator section, menu bar › Simulators › *Inject into Every Simulator*, or
`simcam inject auto on`) applies to all simulators, including ones you never turned on. Turning the per-simulator toggle
off, or `simcam inject off`, forgets that simulator.

## 2. A single app

Press **Launch** next to an app in the Apps list. It is equivalent to:

```bash
SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=/Users/Shared/SimCamLite/SimCamLiteLoader.dylib xcrun simctl launch --terminate-running-process booted <bundle-id>
```

## 3. Running from Xcode with the debugger

Xcode's Run sets its own `DYLD_INSERT_LIBRARIES` (Main Thread Checker, `libLogRedirect`, …), which **overrides** the
simulator-wide variable, so option 1 has no effect there. Set up each project once:

- In **Run from Xcode**, follow the checklist and choose **Set Up Project…**, or drop a `.xcworkspace` / `.xcodeproj`
  onto it (menu bar › Simulators › *Set Up Xcode Project…* works too). Each project lists its schemes with a toggle and
  the reason a scheme was skipped. From Terminal, inside the project folder:

  ```bash
  simcam xcode setup
  ```

- SimCam Lite adds `DYLD_INSERT_LIBRARIES` = `/Users/Shared/SimCamLite/SimCamLiteLoader.dylib` to Run › Environment
  Variables of schemes that run an **iOS app**, based on the target's `SDKROOT` and `SUPPORTED_PLATFORMS`. macOS and Mac
  Catalyst schemes are **skipped**: macOS dyld kills a process that loads the simulator loader. If the scheme already
  sets the variable, the loader is appended with `:`.
- Stop and Run again in Xcode. Xcode appends its own libraries and the debugger works as usual. Committing the change to
  a shared scheme is safe: on Macs without SimCam Lite, the simulator's dyld ignores the missing library.
- To remove it, press ⊖ next to the project or run `simcam xcode remove`; the schemes return to their original state.
  `simcam xcode status` shows the current state.
- Schemes Xcode created but never saved: open Product › Scheme › Manage Schemes… once and run setup again. Schemes whose
  platform can't be determined: pass `--force`, or add the variable yourself (copy button in the panel) in Edit Scheme ›
  Run › Arguments › Environment Variables.

## Other app behavior

- Every option (back and front sources, Fill/rotate/mirror, fps, profile, *Same as back*, the selected simulator) is
  saved and restored on the next launch. The Mac camera source is only restored if camera access was granted; a file
  that no longer exists falls back to the test pattern.
- The **QR…** source remembers the 8 most recent codes and pre-fills a link from the clipboard. Menu bar › *QR Code from
  Clipboard* does the same in one click.
- A device profile change applies to apps opened after the change.
- **Connected apps** shows which apps use SimCam Lite, the camera in use, frame count and photos taken.

## Command line details

`simcam` lives in `SimCamLite.app/Contents/MacOS/simcam`. **Install Command Line Tool…** (Settings, the menu bar or the
app menu) symlinks it to `/usr/local/bin/simcam`, asking for an administrator password if needed, or to `~/.local/bin`.
The app detects links that point to a moved copy of the app. The CLI talks to the running app over
`~/Library/Application Support/SimCamLite/control.sock`.

- Simulator commands take `--device <name|UDID>` when several simulators are booted.
- `simcam source --front follow` makes the front camera reuse the back source.
- `simcam source camera --device "FaceTime"` picks a Mac camera (`simcam cameras` lists them).
- `simcam boot` accepts `--runtime 26.5` and `--wait`; `simcam inject on --persist` keeps injection across simulator
  restarts.
- `simcam status --json` prints machine-readable output.
