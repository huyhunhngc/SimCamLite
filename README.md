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

   Biến `launchctl setenv` mất khi simulator shutdown, nên SimCamLite **nhớ** lựa chọn này (theo UDID) và tự bật lại mỗi khi simulator đó boot, miễn là app đang chạy (kiểm tra mỗi 3 giây; khi mở app, simulator đang boot cũng được khôi phục). *Inject into every simulator as it boots* (panel Simulator, menu bar › Simulators › *Inject into Every Simulator*, hoặc `simcam inject auto on`) áp dụng cho mọi simulator, kể cả chưa từng bật. Tắt toggle (hoặc `simcam inject off`) thì quên simulator đó. App mở ngay trong vài giây đầu sau boot có thể chưa được inject.
2. **Một app** — nút *Launch* trong danh sách Apps (tương đương):
   ```bash
   SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=/Users/Shared/SimCamLite/SimCamLiteLoader.dylib xcrun simctl launch --terminate-running-process booted <bundle-id>
   ```
3. **Chạy từ Xcode (giữ debugger)** — Xcode Run tự set `DYLD_INSERT_LIBRARIES` (Main Thread Checker, `libLogRedirect`…), biến này **ghi đè** biến `launchctl setenv` của simulator nên cách 1 không có tác dụng. Thiết lập **một lần cho mỗi project**:
   - Panel Simulator › *Run from Xcode* › **Set Up Project…** (hoặc menu bar › Simulators › *Set Up Xcode Project…*), chọn `.xcworkspace`/`.xcodeproj`. Hoặc dùng CLI trong thư mục project:
     ```bash
     simcam xcode setup
     ```
   - SimCamLite thêm `DYLD_INSERT_LIBRARIES` = `/Users/Shared/SimCamLite/SimCamLiteLoader.dylib` vào Run › Environment Variables của các scheme chạy **app iOS** (đọc `SDKROOT`/`SUPPORTED_PLATFORMS` của target). Scheme macOS/Mac Catalyst bị **bỏ qua**: dyld trên macOS sẽ kill process khi gặp loader của simulator. Nếu scheme đã có biến này thì loader được nối thêm bằng `:`.
   - Sau đó Stop và Run lại trong Xcode. Xcode nối giá trị này với thư viện của nó, debugger hoạt động bình thường. Commit vào scheme shared cũng an toàn: máy không cài SimCamLite thì dyld của simulator bỏ qua thư viện thiếu.
   - Gỡ: nút ⊖ cạnh project trong panel, hoặc `simcam xcode remove` (scheme trở lại nguyên trạng). Xem trạng thái: `simcam xcode status`.
   - Scheme chưa có file (Xcode tự tạo, chưa lưu): mở Product › Scheme › Manage Schemes… một lần rồi chạy lại. Scheme không xác định được platform: thêm `--force` hoặc tự thêm biến (nút copy trong panel) vào Edit Scheme › Run › Arguments › Environment Variables.

Tắt host app → app iOS vẫn chạy và hiển thị khung "SimCamLite – Host app is not running".

## CLI (`simcam`)

`simcam` nằm trong `SimCamLite.app/Contents/MacOS/simcam`; cài vào PATH bằng menu **Install Command Line Tool…** (menu bar hoặc menu app, cũng có trong Permissions & Setup) — app tạo symlink `/usr/local/bin/simcam` (hỏi mật khẩu admin nếu cần, hoặc dùng `~/.local/bin`) và tự phát hiện symlink cũ trỏ tới bản app đã di chuyển. Khi phát triển có thể dùng `scripts/install-cli.sh`. CLI điều khiển chính app đang chạy qua socket `~/Library/Application Support/SimCamLite/control.sock`, nên GUI và CLI luôn cùng một trạng thái. Lệnh cần engine sẽ tự mở app ở chế độ nền.

| Lệnh | Mô tả |
| --- | --- |
| `simcam start [--fps 30\|60]` / `stop` / `quit` | Bắt đầu / dừng phát (app vẫn chạy) / thoát app |
| `simcam status [--json]` | Trạng thái, nguồn, app đang kết nối |
| `simcam fps 60`, `simcam profile triple\|dual\|single` | Frame rate, device profile |
| `simcam source [--front] pattern\|camera\|<file>` | Đặt nguồn (mặc định back); `--front follow` để front dùng lại nguồn back |
| `simcam source camera --device "FaceTime"` | Chọn Mac camera (`simcam cameras` để liệt kê) |
| `simcam adjust [--front] --fit --rotate 90 --mirror` | Fill/Fit, xoay, mirror |
| `simcam pause` / `resume [--front]` | Pause video |
| `simcam devices [--booted]` | Danh sách simulator iOS |
| `simcam boot ["iPhone 17 Pro"] [--runtime 26.5] [--wait] [--inject]` | Mở Simulator / boot theo tên hoặc UDID |
| `simcam apps`, `simcam launch <bundle-id\|tên app>` | Liệt kê / launch app kèm inject |
| `simcam inject on\|off\|status [--all] [--persist]` | Inject vào mọi app của simulator; `--persist` để app tự bật lại sau khi simulator khởi động lại (`off` cũng quên simulator) |
| `simcam inject auto on\|off\|status` | Tự inject mọi simulator khi boot (cùng cài đặt với GUI) |
| `simcam xcode setup\|remove\|status [path] [--scheme …]` | Thêm/gỡ loader trong scheme iOS để app chạy từ Xcode (có debugger) nạp SimCamLite |

Lệnh simulator nhận `--device <tên|UDID>` khi có nhiều simulator đang boot. `simcam help <lệnh>` để xem chi tiết; completion zsh: `simcam --generate-completion-script zsh`.

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
| `App/` | App macOS SwiftUI: nguồn hình, render pipeline, quản lý simulator, control server cho CLI |
| `Common/` | Giao thức + socket dùng chung giữa app và CLI |
| `CLI/` | Công cụ dòng lệnh `simcam` |

Giới hạn hiện tại: chưa hỗ trợ `AVCaptureMovieFileOutput`, audio, metadata output (QR), multi-cam.
