using System.Text.Json;
using Tailblaze.Models;

namespace Tailblaze.Services;

public sealed class TaskStore
{
    private readonly string _tasksJsonPath;

    public TaskStore(string dataDir)
    {
        _tasksJsonPath = Path.Combine(dataDir, "tasks.json");
    }

    public string TasksJsonPath => _tasksJsonPath;

    public List<CoworkTask> Load()
    {
        if (!File.Exists(_tasksJsonPath))
            return [];

        try
        {
            using var stream = new FileStream(
                _tasksJsonPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite);

            var tasks = JsonSerializer.Deserialize<List<CoworkTask>>(stream);
            return tasks ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
        catch (IOException)
        {
            return [];
        }
    }

    public string? GetLogPath(string taskId, string dataDir)
    {
        var logPath = Path.Combine(dataDir, "logs", $"{taskId}.log");
        return File.Exists(logPath) ? logPath : null;
    }
}
