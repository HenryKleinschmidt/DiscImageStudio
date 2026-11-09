using DiscImageStudio.Core;

namespace DiscImageStudio.Cli;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 0 || args[0] is "--help" or "-h" or "help")
        {
            Console.WriteLine("Disc Image Studio | experimental Linux and macOS CLI for offline CD, DVD and Blu-ray image generation");
            Console.WriteLine("Usage: disc-image-studio COMMAND [OPTIONS]");
            foreach (IOpticalDiscModule module in ConsoleModuleRunner.Catalog.Modules)
            {
                Console.WriteLine($"\n{module.Descriptor.DisplayName}");
                foreach (DiscCommandDescriptor command in module.Descriptor.Commands)
                    Console.WriteLine($"  {command.Name,-20} {command.Description}");
            }
            Console.WriteLine("\nCalibration");
            Console.WriteLine("  calibration-create   Create a target preview, encoding image and calibration session");
            Console.WriteLine("  calibration-rectify  Rectify a disc photo from outer/hole boundary points");
            Console.WriteLine("  calibration-solve    Fit a boundary or fine target from rectified points");
            return 0;
        }

        try
        {
            if (args[0].StartsWith("calibration-", StringComparison.Ordinal))
                return CalibrationCommands.Run(args);
            return ConsoleModuleRunner.Run(args);
        }
        catch (OperationCanceledException)
        {
            Console.Error.WriteLine("Cancelled.");
            return 130;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"error: {error.Message}");
            return 1;
        }
    }
}
