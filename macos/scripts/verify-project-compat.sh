#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS="$ROOT/macos"
CONFIG="${CONFIG:-Debug}"
APP="$MACOS/build/Build/Products/$CONFIG/Disc Image Studio.app"

DOTNET="${DOTNET:-$(command -v dotnet || true)}"
if [[ -z "$DOTNET" && -x "$HOME/.dotnet/dotnet" ]]; then
  DOTNET="$HOME/.dotnet/dotnet"
fi
if [[ -z "$DOTNET" ]]; then
  echo "error: dotnet 10 SDK is required for the C# loader check." >&2
  exit 1
fi

if [[ ! -x "$APP/Contents/MacOS/Disc Image Studio" ]]; then
  CONFIG="$CONFIG" "$MACOS/scripts/build-app.sh" >/dev/null
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/disc-image-studio-compat.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if [[ $# -ge 1 ]]; then
  PROJECT="$1"
  EXPECTED_NAME=""
else
  PROJECT="$WORK/swift-fixture.discproj"
  EXPECTED_NAME="SwiftUI Compatibility Fixture"
  "$APP/Contents/MacOS/Disc Image Studio" --write-sample-project "$PROJECT"
fi

mkdir -p "$WORK/validator"
cat > "$WORK/validator/Validator.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="$ROOT/src/DiscImageStudio.Core/DiscImageStudio.Core.csproj" />
  </ItemGroup>
</Project>
EOF

cat > "$WORK/validator/Program.cs" <<'EOF'
using DiscImageStudio.Core;

string path = args[0];
ProjectDocument document = ProjectJsonStore.Load(path);
Console.WriteLine($"C# loaded: {document.Name}");
Console.WriteLine($"  family={document.DiscFamily}, layers={document.Layers.Count}, sectors={document.Geometry.Sectors}");
Console.WriteLine($"  tone=dither {document.Tone?.DitherStrength}, levels {document.Tone?.Levels}");
Console.WriteLine($"  output={document.Outputs.OutputPath}");
string? expectedName = args.Length > 1 && !string.IsNullOrEmpty(args[1]) ? args[1] : null;
if (expectedName is not null
    && (document.Name != expectedName
        || document.Family != OpticalDiscFamily.Dvd
        || document.Layers.Count != 1
        || document.Tone is not { DitherStrength: 0.75, Levels: 2 }))
{
    Console.Error.WriteLine("fixture did not round-trip as expected");
    return 1;
}
Console.WriteLine("OK: upstream ProjectJsonStore accepted the project.");
return 0;
EOF

"$DOTNET" run --project "$WORK/validator/Validator.csproj" -c Release -- "$PROJECT" "$EXPECTED_NAME"
