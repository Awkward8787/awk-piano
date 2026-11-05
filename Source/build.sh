#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-../AwkPiano.app}"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources" .build
SDK="$(xcrun --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macos14.0" -module-cache-path .build/ModuleCache Sources/*.swift Tests/SelfTests.swift -o ".build/AwkPiano-$ARCH" -framework AppKit -framework SwiftUI -framework CoreMIDI -framework AVFoundation
done
lipo -create .build/AwkPiano-arm64 .build/AwkPiano-x86_64 -output "$DEST/Contents/MacOS/AwkPiano"
cp Info.plist "$DEST/Contents/Info.plist"
if [ -f AwkPiano.icns ]; then cp AwkPiano.icns "$DEST/Contents/Resources/AwkPiano.icns"; fi
xattr -cr "$DEST"
codesign --force --deep --sign - "$DEST"
echo "Built $DEST for Apple silicon and Intel Macs."
