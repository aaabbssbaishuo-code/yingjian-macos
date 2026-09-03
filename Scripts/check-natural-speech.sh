#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT_DIR/.build/swift-module-cache}"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security

BIN_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
RUNTIME_DIR="$ROOT_DIR/.build/artifacts/quicklenstranslator/SherpaOnnxMacOSRuntime/sherpa-onnx.xcframework/macos-arm64_x86_64"
swiftc -O -parse-as-library -target arm64-apple-macosx15.0 \
    Tests/Smoke/NaturalSpeechAudioSessionChecks.swift \
    Sources/QuickLensTranslator/NaturalSpeechAudioSession.swift \
    Sources/QuickLensTranslator/KokoroSpeechEngine.swift \
    Sources/QuickLensTranslator/SpeechSettings.swift \
    Sources/QuickLensTranslator/SpeechService.swift \
    Sources/QuickLensTranslator/NaturalVoicePackManager.swift \
    "$BIN_DIR/SherpaOnnx.build/SherpaOnnx.swift.o" \
    -I "$BIN_DIR/Modules" -I "$RUNTIME_DIR/Headers" \
    -L "$RUNTIME_DIR" -lsherpa-onnx-c-api \
    -o "$ROOT_DIR/.build/natural-speech-checks"
DYLD_LIBRARY_PATH="$RUNTIME_DIR" "$ROOT_DIR/.build/natural-speech-checks" "$@"
