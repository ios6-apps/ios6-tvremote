#!/bin/bash
# build.sh device  -> build/TVRemote.ipa (armv7, iOS 6, unsigned; install with ideviceinstaller on an AppSync device)
# build.sh sim     -> build/sim/TVRemote.app (arm64 simulator, for previewing the layout; TV_MOCK=host:port points it at tools/mock_tv.py)
# SDK93 must point at an iOS 9.3 SDK (stub frameworks are enough, we link with -undefined dynamic_lookup).
set -e
cd "$(dirname "$0")"
SRC=(src/*.m)
FRAMEWORKS=(-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AudioToolbox)
CFLAGS=(-DMBEDTLS_CONFIG_FILE='"hn_mbedtls_config.h"' -Ithird_party -Ithird_party/mbedtls/include -Ithird_party/mbedtls/library -Isrc)
if [ "$1" = device ]; then
    : "${SDK93:?set SDK93 to the iOS 9.3 SDK path}"
    rm -rf build/device; mkdir -p build/device/Payload/TVRemote.app
    # compile with ARC but link without it: the Xcode toolchain has no libarclite, and iOS 6's libobjc already has the ARC entry points we use
    OBJS=()
    for f in third_party/mbedtls/library/*.c src/*.c; do
        o=build/device/$(basename "$f" .c).o
        xcrun clang -arch armv7 -miphoneos-version-min=6.0 -isysroot "$SDK93" -Os -w "${CFLAGS[@]}" -c "$f" -o "$o" &
        OBJS+=("$o")
        while [ "$(jobs -r | wc -l)" -ge 8 ]; do sleep 0.1; done
    done
    wait
    for f in "${SRC[@]}"; do
        o=build/device/$(basename "$f" .m).o
        xcrun clang -arch armv7 -miphoneos-version-min=6.0 -isysroot "$SDK93" -fobjc-arc -Os -Wno-deprecated-declarations -Isrc -c "$f" -o "$o"
        OBJS+=("$o")
    done
    xcrun clang -arch armv7 -miphoneos-version-min=6.0 -isysroot "$SDK93" "${FRAMEWORKS[@]}" -undefined dynamic_lookup \
        "${OBJS[@]}" -o build/device/Payload/TVRemote.app/TVRemote
    cp Info.plist res/*.png build/device/Payload/TVRemote.app/
    (cd build/device && zip -q -r ../TVRemote.ipa Payload)
    echo "built build/TVRemote.ipa"
else
    SIM=$(xcrun --sdk iphonesimulator --show-sdk-path)
    rm -rf build/sim; mkdir -p build/sim/TVRemote.app build/sim/obj
    for f in third_party/mbedtls/library/*.c src/*.c; do
        xcrun clang -arch arm64 -mios-simulator-version-min=15.0 -isysroot "$SIM" -O1 -w "${CFLAGS[@]}" -c "$f" -o build/sim/obj/$(basename "$f" .c).o &
        while [ "$(jobs -r | wc -l)" -ge 8 ]; do sleep 0.1; done
    done
    wait
    xcrun clang -arch arm64 -mios-simulator-version-min=15.0 -isysroot "$SIM" -fobjc-arc -O0 -DTV_PREVIEW -Wno-deprecated-declarations -Isrc \
        "${FRAMEWORKS[@]}" "${SRC[@]}" build/sim/obj/*.o -o build/sim/TVRemote.app/TVRemote
    cp Info.plist res/*.png build/sim/TVRemote.app/
    echo "built build/sim/TVRemote.app"
fi
