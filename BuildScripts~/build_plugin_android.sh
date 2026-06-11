#!/bin/bash -eu

export LIBWEBRTC_DOWNLOAD_URL=https://github.com/Unity-Technologies/com.unity.webrtc/releases/download/M116-20250805/webrtc-android.zip
export SOLUTION_DIR=$(pwd)/Plugin~
export PLUGIN_DIR=$(pwd)/Runtime/Plugins/Android

BUILD_TYPE="${1:-release}"
if [ "$BUILD_TYPE" = "debug" ]; then
  CMAKE_BUILD_TYPE="Debug"
else
  CMAKE_BUILD_TYPE="Release"
fi

# Use locally-built libwebrtc.aar if available (built by build_libwebrtc_android.sh),
# otherwise download the pre-built release from GitHub.
LOCAL_WEBRTC_AAR="$(pwd)/artifacts/lib/libwebrtc.aar"
if [ -f "$LOCAL_WEBRTC_AAR" ]; then
  echo "Using locally-built libwebrtc.aar: $LOCAL_WEBRTC_AAR"
  cp -f "$LOCAL_WEBRTC_AAR" "$PLUGIN_DIR/libwebrtc.aar"
else
  echo "Downloading libwebrtc.aar from $LIBWEBRTC_DOWNLOAD_URL"
  curl -L $LIBWEBRTC_DOWNLOAD_URL > webrtc.zip
  unzip -d $SOLUTION_DIR/webrtc webrtc.zip
  cp -f $SOLUTION_DIR/webrtc/lib/libwebrtc.aar $PLUGIN_DIR
fi

# If debug build, download android-binaries that contains Vulkan validation layer
if [ "$BUILD_TYPE" = "debug" ]; then
  if [ ! -d "$SOLUTION_DIR/android-binaries" ]; then
    wget -q --show-progress https://github.com/KhronosGroup/Vulkan-ValidationLayers/releases/download/vulkan-sdk-1.4.321.0/android-binaries-1.4.321.0.zip
    unzip -d "$(pwd)" android-binaries-1.4.321.0.zip
    mv "$(pwd)/android-binaries-1.4.321.0" $SOLUTION_DIR/android-binaries
  fi
fi

# Build UnityRenderStreaming Plugin 
cd "$SOLUTION_DIR"
for ARCH_ABI in "arm64-v8a" "x86_64"
do
  cmake . \
    -B build \
    -D CMAKE_SYSTEM_NAME=Android \
    -D CMAKE_ANDROID_API_MIN=24 \
    -D CMAKE_ANDROID_API=24 \
    -D CMAKE_ANDROID_ARCH_ABI=$ARCH_ABI \
    -D CMAKE_ANDROID_NDK=$ANDROID_NDK \
    -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE \
    -D CMAKE_ANDROID_STL_TYPE=c++_static

  cmake \
    --build build \
    --target WebRTCPlugin

  # libwebrtc.so move into libwebrtc.aar
  pushd $PLUGIN_DIR
  mkdir -p jni/$ARCH_ABI
  mv libwebrtc.so jni/$ARCH_ABI
  zip -g libwebrtc.aar jni/$ARCH_ABI/libwebrtc.so
  # If debug build, add Vulkan validation layer
  if [ "$BUILD_TYPE" = "debug" ]; then
    cp $SOLUTION_DIR/android-binaries/$ARCH_ABI/libVkLayer_khronos_validation.so jni/$ARCH_ABI
    zip -g libwebrtc.aar jni/$ARCH_ABI/libVkLayer_khronos_validation.so
  fi
  rm -r jni
  popd
  rm -rf build
done

# Align all .so files in the AAR to 16KB for 16KB page size support.
# zipalign is part of Android SDK Build-Tools; locate it via $ANDROID_HOME.
ZIPALIGN_CMD=""
if [ -n "${ANDROID_HOME:-}" ]; then
  LATEST_BUILD_TOOLS=$(ls "$ANDROID_HOME/build-tools" | sort -V | tail -1)
  ZIPALIGN_CMD="$ANDROID_HOME/build-tools/$LATEST_BUILD_TOOLS/zipalign"
elif command -v zipalign &>/dev/null; then
  ZIPALIGN_CMD="zipalign"
fi

if [ -n "$ZIPALIGN_CMD" ]; then
  TEMP_AAR="$PLUGIN_DIR/libwebrtc_aligned.aar"
  "$ZIPALIGN_CMD" -P 16 -f 4 "$PLUGIN_DIR/libwebrtc.aar" "$TEMP_AAR"
  mv "$TEMP_AAR" "$PLUGIN_DIR/libwebrtc.aar"
  echo "zipalign: .so files aligned to 16KB in libwebrtc.aar"
else
  echo "WARNING: zipalign not found. Set ANDROID_HOME to your Android SDK directory."
  echo "  Install build-tools via: sdkmanager 'build-tools;35.0.0'"
fi