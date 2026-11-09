# Disc Image Studio — native macOS frontend

A native SwiftUI macOS workspace for [DiscImageStudio](https://github.com/JiaFeiMiao-K-Cat/DiscImageStudio).
The UI, layer compositor, tone preview, project editor, calibration canvas and `.discproj`
reader/writer are Swift; the mature physical CD/DVD/BD-R encoders and calibration fitters
stay in the upstream .NET engine and are driven through its cross-platform CLI. Burning
uses macOS DiscRecording (`/usr/bin/drutil`).

![Home](docs/home.png)

![Design](docs/design.png)

![Calibrate](docs/calibration.png)

![Burn](docs/burn.png)

## Why this exists

The upstream desktop app is WPF and Windows-only. The engine already ships an experimental
Linux/macOS CLI, so this frontend gives macOS a first-class native window:

- **Design** — import PNG/JPEG/BMP/GIF/TIFF/HEIC layers by picker or drag-and-drop, place them
  in millimetres, rotate/scale, and see the live tone projection.
- **Preview** — asks the engine to render the real CD/DVD geometry projection or read back an
  already generated artifact. Blu-ray uses the native tone projection (there is no standalone
  BD preview command upstream).
- **Export** — generates CD WAV/CUE, CD data ISO, DVD ISO or single-layer BD-R ISO through the
  same engine, including hybrid disc folders and the experimental DVD read-compatibility mode.
- **Calibrate** — creates boundary or fine calibration targets from the current geometry,
  hands generated artifacts to the Burn workspace, rectifies a photo of the burned disc, traces
  the boundary or one cross arm, and applies fitted radii and pitch coefficients to the project.
  Coarse-stage solving is not exposed yet.
- **Burn** — discovers drives and media through macOS DiscRecording, then writes a generated
  CD audio WAV (`-audio`) or CD/DVD/BD ISO (`-data`) with test burn, verify, eject and speed
  options. It warns when the inserted media does not look blank. CD/DVD burning is the supported
  path; BD-R is best-effort because DiscRecording's Blu-ray writer support is limited. The
  source can be the project export or a calibration artifact.
- **Projects** — reads and writes upstream `.discproj` schema 2, including tone and Blu-ray
  polarity settings, so a project can move between the Windows app and this frontend.

## Requirements

- macOS 14 or newer (Apple Silicon or Intel).
- Xcode 15+ with the macOS SDK, or the command-line tools plus a matching Swift toolchain.
- XcodeGen is optional; the generated `DiscImageStudioMac.xcodeproj` is committed.
- .NET 10 SDK to build/run the engine. The app can also bundle a self-contained engine so an
  end user does not need .NET installed.
- For burning, an optical recorder recognized by macOS and blank media. CD/DVD is the supported
  path; BD-R is best-effort.

## Build and run

From the repository root:

```bash
# 1. Build the cross-platform engine (framework-dependent is enough for development).
dotnet build src/DiscImageStudio.Cli/DiscImageStudio.Cli.csproj -c Release

# 2. Build the native app. The script finds Xcode even when xcode-select points at CLT.
macos/scripts/build-app.sh

# 3. Launch it.
open "macos/build/Build/Products/Debug/Disc Image Studio.app"
```

The app discovers the engine in this order:

1. `DIS_IMAGE_STUDIO_CLI` environment variable
2. the path chosen in **Settings → Engine**
3. `Contents/Resources/cli/disc-image-studio` inside the app bundle
4. the developer build under `src/DiscImageStudio.Cli/bin/{Release,Debug}/net10.0/`
5. Homebrew / user install / `PATH`

If you build the app with the engine bundled, the app is self-contained apart from macOS:

```bash
BUNDLE_CLI=self-contained macos/scripts/build-app.sh
# or BUNDLE_CLI=framework when .NET 10 is installed on the target Mac
```

`build-cli.sh` publishes just the engine to `macos/build/cli`:

```bash
macos/scripts/build-cli.sh
```

## Verify

```bash
# 30 unit tests, including tiny CD, DVD and BD-R generations through the .NET CLI.
cd macos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project DiscImageStudioMac.xcodeproj -scheme DiscImageStudioMac \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test

# Ask the upstream C# ProjectJsonStore to load a project written by Swift.
macos/scripts/verify-project-compat.sh

# Generate/rectify/solve synthetic calibration targets through the CLI.
macos/scripts/verify-calibration.sh
```

The integration tests render native composites, build the engine argument vectors, and generate a tiny CD WAV/CUE, DVD ISO and BD-R ISO. The compatibility script uses the upstream
`ProjectJsonStore.Load` implementation, not a reimplementation. No test writes optical media;
checking a real burn requires blank media and a compatible drive.

`verify-calibration.sh` exercises target creation, synthetic photo rectification and a fine
fit without needing a drive or media.

## Layout

```text
macos/
├── project.yml                     XcodeGen specification
├── DiscImageStudioMac.xcodeproj    Generated Xcode project
├── scripts/                        build, CLI publish, compatibility check
└── DiscImageStudioMac/
    ├── Kit/Models/                 .discproj schema 2, family, tone, presets
    ├── Kit/Services/               project store, compositor, CLI runner, commands, drutil wrapper
    ├── Kit/ViewModels/             workspace, burn and calibration orchestration
    ├── App/Views/                  SwiftUI screens and calibration canvas
    ├── Resources/                  app icon and Info.plist
    └── Tests/                      XCTest unit + engine integration tests
```

### Rendering split

- `DesignRenderer` implements the same square-composite convention as the WPF
  `DesignComposer`: the square centre is the disc centre and its side spans
  `2 × contentOuterRadiusMm`. Layers are stored topmost-first and painted bottom-up.
- The tone preview ports `ToneProfile`'s brightness/gamma/hash-dither math so the design card
  matches the engine's look.
- Export hands the 8192 px composite to the CLI. The engine applies the final tone mapping,
  ECC/EFM and filesystem layout.

### Calibration and burning

- `CalibrationViewModel` asks the CLI to create target artwork, rectify photos and fit the
  track geometry. Target generation and fitting use the upstream Core `CalibrationTarget`,
  `CalibrationPhotoRectifier`, `CalibrationBoundaryFitter` and `CalibrationCrossFitter`;
  Swift owns the photo/trace canvas and point capture. Generating a target artifact writes
  a matching `.calibration.json` sidecar next to it.
- `BurnService` wraps `/usr/bin/drutil`. CD audio uses `-audio` with the WAV staged in a
  temporary directory; ISO images use `-data`. Drive/media discovery comes from
  `drutil list` and `drutil -drive <n> status`, and `-test`, `-verify`, `-eject` and `-speed`
  map to the workspace options. CD/DVD burning is supported; BD-R depends on DiscRecording support and
  is best-effort.

## Current scope

Implemented: project create/open/save/save-as, recent projects, family presets, geometry
validation, layer stack editing, drag/drop import, direct canvas drag + magnification,
tone controls, native design/tone previews, CD/DVD engine previews, artifact read-back,
CD/DVD/BD export, hybrid disc folders, volume labels, cancellation, engine diagnostics,
boundary/fine calibration target generation, photo rectification, boundary/cross tracing,
track-geometry fitting, CD audio/ISO burning through DiscRecording (drive/media discovery,
test burn, verify, eject, speed), Settings and About.

Deliberately not included yet:

- **Coarse calibration stage** — the UI exposes boundary and fine targets only; coarse-stage
  solving is not exposed yet.
- **Guaranteed BD-R burning** — DiscRecording's Blu-ray writer support is limited. Some BD-R
  drives and media are rejected even when the ISO is valid; CD/DVD burning is the supported
  path and BD-R is best-effort.
- **Exact DVD/BD custom-usable-sector image scaling** — the CLI maps the picture over the full
  geometry; built-in presets use full geometry, and CD supports `--usable-sectors` natively.

## License

GPL-3.0-or-later, same as upstream. See `../LICENSE` and the upstream
[third-party notices](../THIRD-PARTY-NOTICES.txt). The app icon is derived from the upstream
project asset.
