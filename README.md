# SimCamLite

Giả lập camera cho iOS Simulator: nguồn hình là ảnh, video (loop), camera của Mac hoặc test pattern. App iOS **không cần sửa code** — thư viện được inject qua `DYLD_INSERT_LIBRARIES` và giả lập `AVFoundation` (device, session, video data output, photo output, preview layer, rotation coordinator).

Camera emulator for the iOS Simulator (image / looping video / Mac camera / test pattern), injected with `DYLD_INSERT_LIBRARIES`; no changes to the app under test.

## Build

```bash
brew install xcodegen
scripts/build.sh            # → build/SimCamLite.app
```

Mở `build/SimCamLite.app`. Khi khởi động, app copy `SimCamLiteLoader.dylib` và `SimCamLiteInject.framework` vào `/Users/Shared/SimCamLite/` và bắt đầu phát 30 fps (chọn 60 fps ở thanh trạng thái hoặc menu bar) vào `/Users/Shared/SimCamLite/frames.shm`.

## Sử dụng

- **Back camera / Front camera**: bấm *Pattern*, *File…* (ảnh hoặc video), *Mac camera*, hoặc kéo-thả file vào khung preview. Tuỳ chọn Fill/Fit, xoay 90°, mirror, pause video.
- **Front camera uses back source**: bỏ chọn để dùng nguồn riêng cho camera trước.
- **Device profile**: Triple (0.5x · 1x · 3x), Dual Wide, Single. Áp dụng cho app mở sau khi đổi.
- **Connected apps**: app nào đang dùng SimCamLite, camera đang dùng, số frame, số ảnh đã chụp.

## Inject vào app

1. **Toàn bộ simulator** — bật *Inject into every app launched* trong panel Simulator (tương đương):
   ```bash
   xcrun simctl spawn booted launchctl setenv DYLD_INSERT_LIBRARIES /Users/Shared/SimCamLite/SimCamLiteLoader.dylib
   ```
   Mọi app mở sau đó được inject. Loader chỉ nạp framework vào app của người dùng, bỏ qua process hệ thống.
2. **Một app** — nút *Launch* trong danh sách Apps (tương đương):
   ```bash
   SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=/Users/Shared/SimCamLite/SimCamLiteLoader.dylib xcrun simctl launch --terminate-running-process booted <bundle-id>
   ```
3. **Chạy từ Xcode** — Edit Scheme › Run › Arguments › Environment Variables:
   `DYLD_INSERT_LIBRARIES` = `/Users/Shared/SimCamLite/SimCamLiteLoader.dylib` (nút copy trong panel Simulator).

Tắt host app → app iOS vẫn chạy và hiển thị khung "SimCamLite – Host app is not running".

## Phát triển

```bash
scripts/dev-inject.sh com.example.app   # build inject, cài vào /Users/Shared/SimCamLite, launch app kèm inject
xcrun simctl spawn booted log stream --predicate 'subsystem == "dev.ifateam.simcamlite"'
```

| Thư mục | Nội dung |
| --- | --- |
| `Shared/` | Định dạng shared memory (seqlock, 2 stream × 3 slot 1920×1440 BGRA, client slots) |
| `Loader/` | Dylib nhỏ, chỉ `dlopen` framework cho app người dùng |
| `Inject/` | Fake AVFoundation objects, swizzle, frame pump, photo capture |
| `HostBridge/` | C API ghi frame/heartbeat cho app macOS |
| `App/` | App macOS SwiftUI: nguồn hình, render pipeline, quản lý simulator |

Giới hạn hiện tại: chưa hỗ trợ `AVCaptureMovieFileOutput`, audio, metadata output (QR), multi-cam.
