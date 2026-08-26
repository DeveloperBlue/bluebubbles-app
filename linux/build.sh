#!/bin/bash
trap "exit" INT
set -eux

# Flutter version to build with; override with the FLUTTER_VERSION env var.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.6}"

cd "$(dirname "$0")/.."

# Switch the project to the pinned Flutter version via fvm.
# Set FLUTTER_CMD to bypass fvm and use a preinstalled Flutter instead.
if [ -z ${FLUTTER_CMD+x} ]; then
    fvm use "$FLUTTER_VERSION" --force
    FLUTTER_CMD="fvm flutter"
fi

# Clean the bundle output first: the tarball packages it wholesale, so leftover libs from
# removed plugins would get shipped. Only the bundle — the rest of the CMake tree holds the
# archives the plugins download during configure.
rm -rf build/linux/*/release/bundle

$FLUTTER_CMD pub get --enforce-lockfile
# --no-pub: reuse the lockfile-enforced resolution above (build otherwise re-runs
# pub get without --enforce-lockfile).
# Canary CI sets BUILD_NAME / BUILD_NUMBER so the in-app version is <bb>+<n>
# without rewriting pubspec.yaml. Official builds leave both unset.
extra=()
if [ -n "${BUILD_NAME:-}" ]; then extra+=(--build-name="$BUILD_NAME"); fi
if [ -n "${BUILD_NUMBER:-}" ]; then extra+=(--build-number="$BUILD_NUMBER"); fi
$FLUTTER_CMD build linux --release -v --no-pub "${extra[@]}"

arch=$(uname -m)
if [[ $arch == "x86_64" ]]; then
    folder="x64"
elif [[ $arch == "aarch64" ]]; then
    folder="arm64"
fi

# Inject version number into version.json. Official bump_desktop_versions.dart
# rewrites the hardcoded jq default below — keep that literal for the unset path.
tmp=$(mktemp)
chmod 644 "$tmp"
if [ -n "${BUILD_NAME:-}" ]; then
  jq --arg v "$BUILD_NAME" '.version = $v' build/linux/$folder/release/bundle/data/flutter_assets/version.json > "$tmp"
else
  jq '.version = "2.1.1.0"' build/linux/$folder/release/bundle/data/flutter_assets/version.json > "$tmp"
fi
mv "$tmp" build/linux/$folder/release/bundle/data/flutter_assets/version.json
chmod +x build/linux/$folder/release/bundle/bluebubbles

tar czvf bluebubbles-linux-"$arch".tar.gz -C build/linux/$folder/release/bundle .
sha256sum bluebubbles-linux-"$arch".tar.gz
