#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOTNET="${DOTNET:-$(command -v dotnet || true)}"
if [[ -z "$DOTNET" && -x "$HOME/.dotnet/dotnet" ]]; then
  DOTNET="$HOME/.dotnet/dotnet"
fi
if [[ -z "$DOTNET" ]]; then
  echo "error: dotnet 10 SDK is required." >&2
  exit 1
fi

case "$(uname -m)" in
  arm64) RID="osx-arm64" ;;
  x86_64) RID="osx-x64" ;;
  *) echo "error: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

OUT="${OUT:-$ROOT/macos/build/cli}"
rm -rf "$OUT"
"$DOTNET" publish "$ROOT/src/DiscImageStudio.Cli/DiscImageStudio.Cli.csproj" \
  -c Release \
  -r "$RID" \
  --self-contained "${SELF_CONTAINED:-false}" \
  -o "$OUT"

echo "CLI published to $OUT"
