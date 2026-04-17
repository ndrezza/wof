using Tailblaze.App;

// Resolve data directory: CLI arg > env var > default relative path
var dataDir = ResolveDataDir(args);

if (!Directory.Exists(dataDir))
{
    Console.Error.WriteLine($"Data directory not found: {dataDir}");
    Console.Error.WriteLine();
    Console.Error.WriteLine("Usage: tailblaze [data-dir]");
    Console.Error.WriteLine("  Or set COWORK_DATA_DIR environment variable");
    Console.Error.WriteLine("  Default: walks up from exe to find sibling tools/cowork-mcp");
    return 1;
}

var tasksJson = Path.Combine(dataDir, "tasks.json");
if (!File.Exists(tasksJson))
{
    Console.Error.WriteLine($"No tasks.json found in: {dataDir}");
    return 1;
}

Console.WriteLine($"Tailblaze — watching {dataDir}");
TailblazeApp.Run(dataDir);
return 0;

static string ResolveDataDir(string[] args)
{
    // 1. CLI argument
    if (args.Length > 0 && Directory.Exists(args[0]))
        return Path.GetFullPath(args[0]);

    // 2. Environment variable
    var envDir = Environment.GetEnvironmentVariable("COWORK_DATA_DIR");
    if (!string.IsNullOrEmpty(envDir) && Directory.Exists(envDir))
        return Path.GetFullPath(envDir);

    // 3. Walk up from the exe and try known cowork-mcp sub-paths.
    //    Covers both layouts:
    //      - ContextAndInternalIT: <repo>/tools/cowork-mcp
    //      - WOF:                  <repo>/core/mcp/wof-cowork
    string[] candidates = {
        Path.Combine("tools", "cowork-mcp"),
        Path.Combine("core", "mcp", "wof-cowork"),
    };
    var dir = new DirectoryInfo(AppContext.BaseDirectory);
    while (dir is not null)
    {
        foreach (var rel in candidates)
        {
            var candidate = Path.Combine(dir.FullName, rel);
            if (Directory.Exists(candidate))
                return candidate;
        }
        dir = dir.Parent;
    }

    // 4. Last-resort relative fallback (will likely not exist)
    return Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "cowork-mcp"));
}
