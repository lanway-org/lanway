Place the Xray desktop binary here (use Xray-core v26.6.1 to match the server
and the iOS/Android cores):
  xray_macos          (macOS, from Xray-macos-arm64-v8a.zip / Xray-macos-64.zip)
  xray_windows.exe    (Windows, from Xray-windows-64.zip)
These are bundled into the app and run as a local proxy on connect.

Fetch (macOS, Apple Silicon):
  curl -fsSL -o /tmp/x.zip https://github.com/XTLS/Xray-core/releases/download/v26.6.1/Xray-macos-arm64-v8a.zip
  unzip -o /tmp/x.zip xray -d . && mv -f xray xray_macos && chmod +x xray_macos

Fetch (Windows):
  Download https://github.com/XTLS/Xray-core/releases/download/v26.6.1/Xray-windows-64.zip
  and place xray.exe here as xray_windows.exe
