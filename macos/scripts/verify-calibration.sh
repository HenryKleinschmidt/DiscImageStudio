#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI_PROJECT="$ROOT/src/DiscImageStudio.Cli/DiscImageStudio.Cli.csproj"
CLI_DLL="$ROOT/src/DiscImageStudio.Cli/bin/Release/net10.0/disc-image-studio.dll"

DOTNET="${DOTNET:-$(command -v dotnet || true)}"
if [[ -z "$DOTNET" && -x "$HOME/.dotnet/dotnet" ]]; then
  DOTNET="$HOME/.dotnet/dotnet"
fi
if [[ -z "$DOTNET" ]]; then
  echo "error: dotnet 10 SDK is required for the calibration CLI check." >&2
  exit 1
fi

PYTHON="${PYTHON:-$(command -v python3 || true)}"
if [[ -z "$PYTHON" ]]; then
  echo "error: python3 is required to validate the calibration JSON." >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/disc-image-studio-calibration.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

INNER_RADIUS=24
OUTER_RADIUS=58
SECTORS=2295104
PREVIEW_SIZE=800

cat > "$WORK/check-json.py" <<'PY'
import json
import math
import os
import sys


def bad(message):
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def load(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        bad(f"cannot read JSON {path}: {error}")


def require_file(path, label):
    if not isinstance(path, str) or not path:
        bad(f"missing {label} in JSON output")
    if not os.path.isfile(path):
        bad(f"{label} does not exist: {path}")
    return path


def require_png(path, label):
    with open(path, "rb") as handle:
        if handle.read(8) != b"\x89PNG\r\n\x1a\n":
            bad(f"{label} is not a PNG file: {path}")


def check_create(path):
    document = load(path)
    for key in ("targetId", "previewPath", "burnImagePath", "sessionPath"):
        if not isinstance(document.get(key), str) or not document[key]:
            bad(f"create output is missing {key}")
    for key in ("previewPath", "burnImagePath", "sessionPath"):
        require_file(document[key], key)
    require_png(document["previewPath"], "previewPath")
    require_png(document["burnImagePath"], "burnImagePath")
    if document.get("previewSize") != 800 or document.get("burnImageSize") != 8192:
        bad("create output has unexpected preview or burn image size")
    print(f"targetId={document['targetId']} preview={document['previewSize']}px "
          f"burn={document['burnImageSize']}px")


def check_solve(path, expected_inner, expected_outer, tolerance):
    document = load(path)
    if document.get("succeeded") is not True:
        bad(f"solve did not succeed: {document.get('warnings')}")
    best = document.get("best")
    if not isinstance(best, dict):
        bad("solve output has no best parameters")
    try:
        inner = float(best["innerRadiusMm"])
        outer = float(best["outerRadiusMm"])
    except (KeyError, TypeError, ValueError):
        bad("best parameters are missing innerRadiusMm/outerRadiusMm")
    if not math.isfinite(inner) or not math.isfinite(outer):
        bad(f"solve returned non-finite radii: {inner}, {outer}")
    expected_inner = float(expected_inner)
    expected_outer = float(expected_outer)
    tolerance = float(tolerance)
    if abs(inner - expected_inner) > tolerance or abs(outer - expected_outer) > tolerance:
        bad(f"solved radii are not close enough: inner={inner:.6f} "
            f"(expected {expected_inner:.6f}), outer={outer:.6f} "
            f"(expected {expected_outer:.6f}), tolerance={tolerance}")
    rms = float(document.get("rmsErrorMm") or 0)
    print(f"inner={inner:.6f}mm outer={outer:.6f}mm rms={rms:.6g}mm")


def check_rectify(path, expected_output):
    document = load(path)
    if document.get("succeeded") is not True:
        bad(f"rectify did not succeed: {document.get('message')}")
    output = require_file(document.get("output"), "output")
    if os.path.realpath(output) != os.path.realpath(expected_output):
        bad(f"rectify output path mismatch: {output} != {expected_output}")
    require_png(output, "output")
    pixel_size = document.get("pixelSize")
    if not isinstance(pixel_size, int) or pixel_size <= 0:
        bad("rectify output has no positive pixelSize")
    print(f"output={output} pixelSize={pixel_size} "
          f"outerRms={float(document.get('outerRmsPixels') or 0):.3f}px "
          f"holeRms={float(document.get('holeRmsPixels') or 0):.3f}px")


if len(sys.argv) < 2:
    bad("usage: check-json.py create|solve|rectify ...")
command = sys.argv[1]
if command == "create" and len(sys.argv) == 3:
    check_create(sys.argv[2])
elif command == "solve" and len(sys.argv) == 6:
    check_solve(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
elif command == "rectify" and len(sys.argv) == 4:
    check_rectify(sys.argv[2], sys.argv[3])
else:
    bad(f"invalid arguments for {command}")
PY

cat > "$WORK/solve-points.py" <<'PY'
import json
import sys

inner = float(sys.argv[1])
outer = float(sys.argv[2])
output = sys.argv[3]
count = 25
points = []
for index in range(count):
    radius = inner + (outer - inner) * index / (count - 1)
    # The fine target's first cross arm runs along -Y from the inner to the outer radius.
    points.append({"x": 0.0, "y": -radius})
payload = {
    "traces": [{"armIndex": 0, "points": points}],
    "radiusRangeMm": 0.02,
    "fitPitch": True,
    "autoRange": None,
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY

cat > "$WORK/rectify-points.py" <<'PY'
import json
import math
import sys

size = int(sys.argv[1])
outer = float(sys.argv[2])
output = sys.argv[3]

# calibration-create renders the preview with canvasRadius = max(60, outerRadiusMm)
# and pixel-centre sampling, so disc coordinates map as below.
canvas = max(60.0, outer)
step = 2.0 * canvas / size
centre = size / 2.0 - 0.5
outer_pixels = outer / step
hole_pixels = 7.5 / step

outer_points = []
hole_points = []
for index in range(16):
    angle = math.tau * index / 16
    cosine, sine = math.cos(angle), math.sin(angle)
    outer_points.append({"x": centre + outer_pixels * cosine, "y": centre + outer_pixels * sine})
    hole_points.append({"x": centre + hole_pixels * cosine, "y": centre + hole_pixels * sine})

with open(output, "w", encoding="utf-8") as handle:
    json.dump({"outer": outer_points, "hole": hole_points}, handle)
PY

printf 'Building the calibration CLI...\n'
if ! "$DOTNET" build "$CLI_PROJECT" -c Release --nologo -v minimal >"$WORK/build.log" 2>&1; then
  cat "$WORK/build.log" >&2
  fail "dotnet build failed"
fi
if [[ ! -f "$CLI_DLL" ]]; then
  fail "built CLI not found at $CLI_DLL"
fi
pass "built DiscImageStudio.Cli in Release"

FINE_JSON="$WORK/fine-create.json"
if ! "$DOTNET" "$CLI_DLL" calibration-create \
    --kind dvd \
    --stage fine \
    --inner-radius "$INNER_RADIUS" \
    --outer-radius "$OUTER_RADIUS" \
    --sectors "$SECTORS" \
    --preview-output "$WORK/fine-preview.png" \
    --preview-size "$PREVIEW_SIZE" \
    --burn-output "$WORK/fine-burn.png" \
    --session-output "$WORK/fine.calibration.json" >"$FINE_JSON"; then
  fail "calibration-create failed for the fine target"
fi
if ! SUMMARY="$("$PYTHON" "$WORK/check-json.py" create "$FINE_JSON")"; then
  fail "fine target JSON or generated files are invalid"
fi
pass "fine target created and verified ($SUMMARY)"

"$PYTHON" "$WORK/solve-points.py" "$INNER_RADIUS" "$OUTER_RADIUS" "$WORK/fine-points.json"
if ! "$DOTNET" "$CLI_DLL" calibration-solve \
    --session "$WORK/fine.calibration.json" \
    --points "$WORK/fine-points.json" >"$WORK/fine-solve.json"; then
  fail "calibration-solve failed for the fine target"
fi
if ! SUMMARY="$("$PYTHON" "$WORK/check-json.py" solve "$WORK/fine-solve.json" \
    "$INNER_RADIUS" "$OUTER_RADIUS" 0.005)"; then
  fail "fine target solve result is not close to the input geometry"
fi
pass "fine target solved back to the input geometry ($SUMMARY)"

BOUNDARY_JSON="$WORK/boundary-create.json"
if ! "$DOTNET" "$CLI_DLL" calibration-create \
    --kind dvd \
    --stage boundary \
    --inner-radius "$INNER_RADIUS" \
    --outer-radius "$OUTER_RADIUS" \
    --sectors "$SECTORS" \
    --preview-output "$WORK/boundary-preview.png" \
    --preview-size "$PREVIEW_SIZE" \
    --burn-output "$WORK/boundary-burn.png" \
    --session-output "$WORK/boundary.calibration.json" >"$BOUNDARY_JSON"; then
  fail "calibration-create failed for the boundary target"
fi
if ! SUMMARY="$("$PYTHON" "$WORK/check-json.py" create "$BOUNDARY_JSON")"; then
  fail "boundary target JSON or generated files are invalid"
fi
pass "boundary target created and verified ($SUMMARY)"

"$PYTHON" "$WORK/rectify-points.py" "$PREVIEW_SIZE" "$OUTER_RADIUS" "$WORK/rectify-points.json"
if ! "$DOTNET" "$CLI_DLL" calibration-rectify \
    --photo "$WORK/fine-preview.png" \
    --points "$WORK/rectify-points.json" \
    --physical-outer-radius "$OUTER_RADIUS" \
    --output "$WORK/rectified.png" >"$WORK/rectify.json"; then
  fail "calibration-rectify failed for the synthetic photo"
fi
if ! SUMMARY="$("$PYTHON" "$WORK/check-json.py" rectify "$WORK/rectify.json" \
    "$WORK/rectified.png")"; then
  fail "rectify result JSON or output PNG is invalid"
fi
pass "synthetic photo rectified and verified ($SUMMARY)"

pass "calibration CLI end-to-end verification complete"
