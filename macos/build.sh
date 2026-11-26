#!/bin/sh
# Builds the macOS widget into macos/bin/Agent Meter.app. A running copy is asked to quit first, so the new
# build replaces it; start the app again afterwards (open "macos/bin/Agent Meter.app").
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cd "$here"
swift build -c release
app="$here/bin/Agent Meter.app"
if pgrep -x AgentMeter >/dev/null 2>&1; then
  osascript -e 'tell application id "com.agentmeter.widget" to quit' >/dev/null 2>&1 || true
  sleep 1
fi
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/AgentMeter "$app/Contents/MacOS/AgentMeter"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agent Meter</string>
  <key>CFBundleDisplayName</key><string>Agent Meter</string>
  <key>CFBundleIdentifier</key><string>com.agentmeter.widget</string>
  <key>CFBundleExecutable</key><string>AgentMeter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# An ad-hoc signature is enough for a copy built on this Mac to open normally.
codesign --force --sign - "$app" >/dev/null 2>&1 || true
echo "Built: $app"
