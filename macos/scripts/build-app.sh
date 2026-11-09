#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS="$ROOT/macos"
CONFIG="${CONFIG:-Debug}"
BUNDLE_CLI="${BUNDLE_CLI:-0}"

if ! xcodebuild -version >/dev/null 2>&1; then
  for app in /Applications/Xcode*.app; do
    if [[ -d "$app/Contents/Developer" ]]; then
      export DEVELOPER_DIR="$app/Contents/Developer"
      break
    fi
  done
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: xcodebuild is not available. Install Xcode or set DEVELOPER_DIR." >&2
  exit 1
fi

if [[ -x "$(command -v xcodegen || true)" ]]; then
  (cd "$MACOS" && xcodegen generate)
elif [[ ! -d "$MACOS/DiscImageStudioMac.xcodeproj" ]]; then
  echo "error: xcodegen is required to create the Xcode project." >&2
  exit 1
fi

(cd "$MACOS" && xcodebuild \
  -project DiscImageStudioMac.xcodeproj \
  -scheme DiscImageStudioMac \
  -configuration "$CONFIG" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build)

APP="$MACOS/build/Build/Products/$CONFIG/Disc Image Studio.app"

if [[ "$BUNDLE_CLI" != "0" ]]; then
  DOTNET="${DOTNET:-$(command -v dotnet || true)}"
  if [[ -z "$DOTNET" && -x "$HOME/.dotnet/dotnet" ]]; then
    DOTNET="$HOME/.dotnet/dotnet"
  fi
  if [[ -z "$DOTNET" ]]; then
    echo "error: dotnet is required to bundle the CLI." >&2
    exit 1
  fi

  case "$(uname -m)" in
    arm64) RID="osx-arm64" ;;
    x86_64) RID="osx-x64" ;;
    *) echo "error: unsupported architecture $(uname -m)" >&2; exit 1 ;;
  esac

  SELF_CONTAINED="true"
  if [[ "$BUNDLE_CLI" == "framework" ]]; then
    SELF_CONTAINED="false"
  fi

  rm -rf "$MACOS/build/cli"
  "$DOTNET" publish "$ROOT/src/DiscImageStudio.Cli/DiscImageStudio.Cli.csproj" \
    -c Release \
    -r "$RID" \
    --self-contained "$SELF_CONTAINED" \
    -o "$MACOS/build/cli"

  mkdir -p "$APP/Contents/Resources/cli"
  cp -R "$MACOS/build/cli/." "$APP/Contents/Resources/cli/"
  echo "Bundled CLI: $APP/Contents/Resources/cli"
fi

echo
echo "Built: $APP"
