using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using DiscImageStudio.Core.Calibration;
using DiscImageStudio.ImageIO;

namespace DiscImageStudio.Cli;

/// <summary>
/// Cross-platform calibration helpers used by the native macOS frontend. The geometry,
/// target artwork, photo rectifier and fitters all come from the same Core assembly as
/// the WPF application; only the bitmap rendering is reimplemented on the portable
/// raster codec.
/// </summary>
internal static class CalibrationCommands
{
    private const int BurnImageSize = 8192;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    internal static int Run(string[] args)
    {
        try
        {
            if (args.Length < 1) throw new ArgumentException("Expected calibration-create, calibration-rectify or calibration-solve.");
            return args[0] switch
            {
                "calibration-create" => Create(args.AsSpan(1)),
                "calibration-rectify" => Rectify(args.AsSpan(1)),
                "calibration-solve" => Solve(args.AsSpan(1)),
                _ => throw new ArgumentException($"Unknown calibration command '{args[0]}'."),
            };
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"error: {error.Message}");
            return 1;
        }
    }

    // MARK: - Target creation

    private static int Create(ReadOnlySpan<string> args)
    {
        Dictionary<string, string> o = Parse(args);
        CalibrationDiscKind kind = Required(o, "kind").ToLowerInvariant() switch
        {
            "cd" => CalibrationDiscKind.Cd,
            "dvd" => CalibrationDiscKind.Dvd,
            "bd" or "bluray" or "blu-ray" => CalibrationDiscKind.BluRay,
            _ => throw new ArgumentException("--kind must be cd, dvd or bd."),
        };
        string stage = Required(o, "stage").ToLowerInvariant();
        CalibrationArtwork artwork = stage switch
        {
            "coarse" => CalibrationArtwork.AngleSweepBands,
            "boundary" => CalibrationArtwork.WavyBoundary,
            "fine" => CalibrationArtwork.ReferenceCross,
            _ => throw new ArgumentException("--stage must be coarse, boundary or fine."),
        };
        double inner = Number(Required(o, "inner-radius"));
        double outer = Number(Required(o, "outer-radius"));
        long sectors = Long(Required(o, "sectors"));
        long? usable = o.TryGetValue("usable-sectors", out string? usableText) && !string.IsNullOrWhiteSpace(usableText)
            ? Long(usableText) : null;
        double pitchLinear = Number(Optional(o, "pitch-linear", "0"));
        double pitchQuadratic = Number(Optional(o, "pitch-quadratic", "0"));
        double pitchCubic = Number(Optional(o, "pitch-cubic", "0"));
        bool invert = Boolean(Optional(o, "invert", "false"));
        bool dvdCompatibility = Boolean(Optional(o, "dvd-read-compatibility", "false"));

        CalibrationParameters parameters = kind switch
        {
            CalibrationDiscKind.Cd => new CalibrationParameters(
                kind, inner, outer, sectors, 1200, pitchLinear, pitchQuadratic, pitchCubic,
                UsableSectors: usable),
            CalibrationDiscKind.Dvd => new CalibrationParameters(
                kind, inner, outer, sectors, 133.3, pitchLinear, pitchQuadratic, pitchCubic,
                DvdReadCompatibility: dvdCompatibility, UsableSectors: usable),
            CalibrationDiscKind.BluRay => new CalibrationParameters(
                kind, inner, outer, sectors, 74.5, pitchLinear, pitchQuadratic, pitchCubic,
                BluRayInvertMapping: invert,
                DrawingStartSector: 0,
                DrawingEndSectorExclusive: usable ?? sectors,
                UsableSectors: usable ?? sectors),
            _ => throw new ArgumentException("Unsupported calibration disc kind."),
        };
        parameters.Validate();
        CalibrationTarget target = CalibrationTarget.Create(parameters, artwork: artwork);

        string previewPath = Required(o, "preview-output");
        int previewSize = (int)Math.Clamp(Long(Optional(o, "preview-size", "1600")), 128, 8192);
        double canvasRadius = Math.Max(60, outer);
        byte[] preview = RenderPlanar(target, canvasRadius, previewSize, encoding: false);
        EnsureParent(previewPath);
        RasterCodec.SavePng(previewPath, previewSize, previewSize, preview, grayscale: true);

        string burnPath = Required(o, "burn-output");
        byte[] burn = RenderPlanar(target, canvasRadius, BurnImageSize, encoding: true);
        EnsureParent(burnPath);
        RasterCodec.SavePng(burnPath, BurnImageSize, BurnImageSize, burn, grayscale: true);

        string sessionPath = Required(o, "session-output");
        EnsureParent(sessionPath);
        CalibrationSession session = new(target, [], new CalibrationFitOptions(
            SearchCenter: parameters,
            RadiusRangeMm: artwork == CalibrationArtwork.WavyBoundary ? .01 : .02,
            AutoRange: artwork == CalibrationArtwork.WavyBoundary ? false : null));
        CalibrationSessionJson.Save(sessionPath, session);

        WriteJson(new
        {
            targetId = target.Id,
            kind = kind.ToString(),
            stage,
            innerRadiusMm = parameters.InnerRadiusMm,
            outerRadiusMm = parameters.OuterRadiusMm,
            sectors = parameters.Sectors,
            usableSectors = parameters.UsableSectors,
            pitchLinear = parameters.PitchLinear,
            pitchQuadratic = parameters.PitchQuadratic,
            pitchCubic = parameters.PitchCubic,
            drawingInnerRadiusMm = target.DrawingInnerRadiusMm,
            drawingOuterRadiusMm = target.DrawingOuterRadiusMm,
            previewPath = Path.GetFullPath(previewPath),
            burnImagePath = Path.GetFullPath(burnPath),
            sessionPath = Path.GetFullPath(sessionPath),
            previewSize,
            burnImageSize = BurnImageSize,
        });
        return 0;
    }

    // MARK: - Planar target rendering

    private static byte[] RenderPlanar(CalibrationTarget target, double canvasRadius, int size, bool encoding)
    {
        byte[] pixels = new byte[checked(size * size)];
        if (encoding)
        {
            // Match CalibrationPatternRenderer.RenderEncodingImage: the ordinary
            // encoder image convention for each family.
            double centre = target.Parameters.Kind == CalibrationDiscKind.Cd ? size / 2.0 : (size - 1) / 2.0;
            double scale = target.Parameters.OuterRadiusMm
                / (target.Parameters.Kind == CalibrationDiscKind.Dvd ? (size - 1) / 2.0 : size / 2.0);
            Parallel.For(0, size, y =>
            {
                double ym = (y - centre) * scale;
                for (int x = 0; x < size; x++)
                {
                    double xm = (x - centre) * scale;
                    pixels[y * size + x] = target.Sample(xm, ym);
                }
            });
        }
        else
        {
            double step = 2 * canvasRadius / size;
            Parallel.For(0, size, y =>
            {
                double ym = (y + 0.5) * step - canvasRadius;
                for (int x = 0; x < size; x++)
                {
                    double xm = (x + 0.5) * step - canvasRadius;
                    pixels[y * size + x] = target.Sample(xm, ym);
                }
            });
        }
        return pixels;
    }

    // MARK: - Photo rectification

    private sealed record PointDto(double X, double Y);
    private sealed record RectifyInput(List<PointDto>? Outer, List<PointDto>? Hole);

    private static int Rectify(ReadOnlySpan<string> args)
    {
        Dictionary<string, string> o = Parse(args);
        string photo = Required(o, "photo");
        string pointsPath = Required(o, "points");
        string output = Required(o, "output");
        double physicalOuter = Number(Optional(o, "physical-outer-radius", "60"));
        double canvasRadius = Number(Optional(o, "canvas-radius", (physicalOuter + 3).ToString(CultureInfo.InvariantCulture)));

        RectifyInput input = JsonSerializer.Deserialize<RectifyInput>(File.ReadAllText(pointsPath), JsonOptions)
            ?? throw new ArgumentException("Rectification points are empty.");
        List<CalibrationPoint> outer = (input.Outer ?? []).Select(p => new CalibrationPoint(p.X, p.Y)).ToList();
        List<CalibrationPoint> hole = (input.Hole ?? []).Select(p => new CalibrationPoint(p.X, p.Y)).ToList();
        CalibrationPhotoFitResult fit = CalibrationPhotoRectifier.Fit(outer, hole, physicalOuter, 7.5);
        if (!fit.Succeeded || fit.Transform is null)
        {
            WriteJson(new
            {
                succeeded = false,
                message = fit.Message,
                outerRmsPixels = fit.OuterRmsPixels,
                holeRmsPixels = fit.HoleRmsPixels,
                canvasOuterRadiusMm = canvasRadius,
                pixelSize = 0,
            });
            return 0;
        }

        BgraRaster raster = RasterCodec.LoadBgra32(photo, 256L * 1024 * 1024, CalibrationPhotoLimits.MaxPixelCount);
        if (!CalibrationPhotoLimits.Contains(raster.Width, raster.Height))
            throw new ArgumentException("Photo dimensions exceed the calibration limits.");
        int pixelSize = RectifiedPixelSize(fit.Transform, canvasRadius);
        byte[] rectified = RectifyPixels(raster, fit.Transform, canvasRadius, pixelSize);
        EnsureParent(output);
        RasterCodec.SavePng(output, pixelSize, pixelSize, rectified, grayscale: false);

        WriteJson(new
        {
            succeeded = true,
            message = fit.Message,
            outerRmsPixels = fit.OuterRmsPixels,
            holeRmsPixels = fit.HoleRmsPixels,
            canvasOuterRadiusMm = canvasRadius,
            pixelSize,
            output = Path.GetFullPath(output),
            transform = fit.Transform.DiscToSourceMatrix9,
        });
        return 0;
    }

    private static int RectifiedPixelSize(CalibrationPhotoTransform transform, double canvasRadius)
    {
        double[] m = transform.DiscToSourceMatrix9;
        double maxScale = ScaleAt(0, 0);
        for (int ring = 1; ring <= 2; ring++)
        for (int i = 0; i < 64; i++)
        {
            double angle = i * Math.Tau / 64, radius = canvasRadius * ring / 2;
            maxScale = Math.Max(maxScale, ScaleAt(radius * Math.Cos(angle), radius * Math.Sin(angle)));
        }
        double size = Math.Ceiling(2 * canvasRadius * maxScale - 1e-9);
        return (int)Math.Clamp(size, 32, CalibrationPhotoLimits.MaxRectifiedDimension);

        double ScaleAt(double x, double y)
        {
            double w = m[6] * x + m[7] * y + m[8];
            double u = (m[0] * x + m[1] * y + m[2]) / w;
            double v = (m[3] * x + m[4] * y + m[5]) / w;
            double ux = (m[0] - m[6] * u) / w, uy = (m[1] - m[7] * u) / w;
            double vx = (m[3] - m[6] * v) / w, vy = (m[4] - m[7] * v) / w;
            double a = ux * ux + vx * vx, b = ux * uy + vx * vy, c = uy * uy + vy * vy;
            return Math.Sqrt((a + c + Math.Sqrt((a - c) * (a - c) + 4 * b * b)) / 2);
        }
    }

    private static byte[] RectifyPixels(BgraRaster raster, CalibrationPhotoTransform transform,
        double canvasRadius, int pixelSize)
    {
        double[] matrix = transform.DiscToSourceMatrix9;
        byte[] source = raster.Pixels;
        int sourceStride = checked(raster.Width * 4);
        int stride = checked(pixelSize * 4);
        byte[] pixels = new byte[checked(stride * pixelSize)];
        double step = 2 * canvasRadius / pixelSize;
        Parallel.For(0, pixelSize, y =>
        {
            double ym = (y + 0.5) * step - canvasRadius;
            for (int x = 0; x < pixelSize; x++)
            {
                double xm = (x + 0.5) * step - canvasRadius;
                int destination = y * stride + x * 4;
                if (xm * xm + ym * ym > canvasRadius * canvasRadius)
                {
                    SetWhite(pixels, destination);
                    continue;
                }
                double divisor = matrix[6] * xm + matrix[7] * ym + matrix[8];
                double sx = (matrix[0] * xm + matrix[1] * ym + matrix[2]) / divisor;
                double sy = (matrix[3] * xm + matrix[4] * ym + matrix[5]) / divisor;
                if (!double.IsFinite(sx) || !double.IsFinite(sy) || sx < 0 || sy < 0
                    || sx > raster.Width - 1 || sy > raster.Height - 1)
                {
                    SetWhite(pixels, destination);
                    continue;
                }
                int x0 = (int)Math.Floor(sx), y0 = (int)Math.Floor(sy);
                int x1 = Math.Min(x0 + 1, raster.Width - 1), y1 = Math.Min(y0 + 1, raster.Height - 1);
                double fx = sx - x0, fy = sy - y0;
                for (int channel = 0; channel < 4; channel++)
                {
                    double value = source[y0 * sourceStride + x0 * 4 + channel] * (1 - fx) * (1 - fy)
                        + source[y0 * sourceStride + x1 * 4 + channel] * fx * (1 - fy)
                        + source[y1 * sourceStride + x0 * 4 + channel] * (1 - fx) * fy
                        + source[y1 * sourceStride + x1 * 4 + channel] * fx * fy;
                    pixels[destination + channel] = (byte)Math.Clamp((int)Math.Round(value), 0, 255);
                }
            }
        });
        return pixels;
    }

    private static void SetWhite(byte[] pixels, int offset)
    {
        pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = pixels[offset + 3] = 255;
    }

    // MARK: - Fit

    private sealed record TraceDto(int ArmIndex, List<PointDto>? Points);
    private sealed record SegmentDto(int Id, List<PointDto>? Points);
    private sealed record SolveInput(
        List<TraceDto>? Traces, List<SegmentDto>? Segments,
        double? RadiusRangeMm, bool? FitPitch, bool? AutoRange, double? PitchCoefficientRange);

    private static int Solve(ReadOnlySpan<string> args)
    {
        Dictionary<string, string> o = Parse(args);
        string sessionPath = Required(o, "session");
        string pointsPath = Required(o, "points");
        CalibrationSession session = CalibrationSessionJson.Load(sessionPath);
        CalibrationTarget target = session.Target;
        SolveInput input = JsonSerializer.Deserialize<SolveInput>(File.ReadAllText(pointsPath), JsonOptions)
            ?? throw new ArgumentException("Calibration points are empty.");
        double range = input.RadiusRangeMm ?? 0.02;
        CalibrationFitOptions options = new(
            SearchCenter: target.Parameters,
            RadiusRangeMm: range,
            FitDvdPitch: input.FitPitch ?? true,
            PitchCoefficientRange: input.PitchCoefficientRange ?? .05,
            AutoRange: input.AutoRange);
        CalibrationFitResult result;
        if (target.HasBoundaryPattern)
        {
            List<CalibrationBoundarySegment> segments = (input.Segments ?? [])
                .Select(segment => new CalibrationBoundarySegment(
                    segment.Id,
                    (segment.Points ?? []).Select(p => new CalibrationPoint(p.X, p.Y)).ToArray()))
                .ToList();
            result = CalibrationBoundaryFitter.Fit(target, segments, options);
        }
        else
        {
            List<CalibrationCrossTrace> traces = (input.Traces ?? [])
                .Select(trace => new CalibrationCrossTrace(
                    trace.ArmIndex,
                    (trace.Points ?? []).Select(p => new CalibrationPoint(p.X, p.Y)).ToArray()))
                .ToList();
            result = CalibrationCrossFitter.Fit(target, traces, options);
        }

        WriteJson(new
        {
            succeeded = result.Succeeded,
            reliable = result.IsReliable,
            boundaryLimited = result.BoundaryLimited,
            requiresShapeConfirmation = result.RequiresShapeConfirmation,
            rotationRadians = result.RotationRadians,
            rmsErrorMm = result.RmsErrorMm,
            warnings = result.Warnings,
            best = result.BestParameters is { } best ? Describe(best) : null,
            candidates = result.Candidates.Select(candidate => new
            {
                parameters = Describe(candidate.Parameters),
                rotationRadians = candidate.RotationRadians,
                rmsErrorMm = candidate.RmsErrorMm,
                robustCost = candidate.RobustCost,
                maxErrorMm = candidate.MaxErrorMm,
                outlierCount = candidate.OutlierCount,
            }).ToArray(),
        });
        return 0;
    }

    private static object Describe(CalibrationParameters p) => new
    {
        kind = p.Kind.ToString(),
        innerRadiusMm = p.InnerRadiusMm,
        outerRadiusMm = p.OuterRadiusMm,
        sectors = p.Sectors,
        usableSectors = p.UsableSectors,
        pitchLinear = p.PitchLinear,
        pitchQuadratic = p.PitchQuadratic,
        pitchCubic = p.PitchCubic,
        invertMapping = p.BluRayInvertMapping,
    };

    // MARK: - Arguments

    private static Dictionary<string, string> Parse(ReadOnlySpan<string> args)
    {
        Dictionary<string, string> result = new(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < args.Length; i++)
        {
            string argument = args[i];
            if (!argument.StartsWith("--", StringComparison.Ordinal))
                throw new ArgumentException($"Expected a named option, got '{argument}'.");
            int equals = argument.IndexOf('=');
            string name = equals >= 0 ? argument[2..equals] : argument[2..];
            string value;
            if (equals >= 0) value = argument[(equals + 1)..];
            else if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal)) value = args[++i];
            else throw new ArgumentException($"Missing value for --{name}.");
            if (!result.TryAdd(name, value)) throw new ArgumentException($"Duplicate option --{name}.");
        }
        return result;
    }

    private static string Required(Dictionary<string, string> options, string name)
        => options.TryGetValue(name, out string? value) && !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new ArgumentException($"Missing required option --{name}.");

    private static string Optional(Dictionary<string, string> options, string name, string fallback)
        => options.TryGetValue(name, out string? value) ? value : fallback;

    private static double Number(string value)
        => double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double result)
            && double.IsFinite(result)
            ? result
            : throw new ArgumentException($"'{value}' is not a finite number.");

    private static long Long(string value)
        => long.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out long result)
            ? result
            : throw new ArgumentException($"'{value}' is not an integer.");

    private static bool Boolean(string value)
        => bool.TryParse(value, out bool result)
            ? result
            : throw new ArgumentException($"'{value}' is not true or false.");

    private static void EnsureParent(string path)
    {
        string? directory = Path.GetDirectoryName(Path.GetFullPath(path));
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
    }

    private static void WriteJson(object value)
        => Console.WriteLine(JsonSerializer.Serialize(value, JsonOptions));
}
