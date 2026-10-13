#!/bin/sh
# Builds an unsigned Release .ipa for sideloading (Sideloadly, AltStore).
# VLCKit ships armv7/armv7s slices and no signature slot, which breaks
# third-party signers, so it is thinned to arm64 and ad-hoc signed first.
set -e
cd "$(dirname "$0")/.."
OUT="${1:-$HOME/Desktop/Lumen.ipa}"

xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Release \
  -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build -quiet

rm -rf .build/ipa && mkdir -p .build/ipa/Payload
cp -R .build/Build/Products/Release-iphoneos/Lumen.app .build/ipa/Payload/
VLC=.build/ipa/Payload/Lumen.app/Frameworks/MobileVLCKit.framework
lipo "$VLC/MobileVLCKit" -thin arm64 -output "$VLC/MobileVLCKit.thin"
mv "$VLC/MobileVLCKit.thin" "$VLC/MobileVLCKit"
codesign -f -s - "$VLC"
codesign -f -s - .build/ipa/Payload/Lumen.app

rm -f "$OUT"
(cd .build/ipa && zip -qry "$OUT" Payload)
echo "IPA: $OUT"
