namespace Tailblaze.Services;

public sealed class TaskWatcher : IDisposable
{
    private FileSystemWatcher? _fsw;
    private readonly System.Timers.Timer? _debounce;
    private readonly System.Timers.Timer _pollTimer;
    private readonly string? _filePath;
    private volatile bool _disposed;
    private volatile bool _pending;
    private DateTime _lastKnownWrite;

    public event Action? TasksChanged;

    /// <summary>UTC timestamp of the last successful refresh (for status bar display).</summary>
    public DateTime LastRefreshUtc { get; private set; } = DateTime.UtcNow;

    public TaskWatcher(string tasksJsonPath)
    {
        _filePath = tasksJsonPath;
        _lastKnownWrite = File.Exists(tasksJsonPath) ? File.GetLastWriteTimeUtc(tasksJsonPath) : DateTime.MinValue;

        // Polling fallback — FSW is unreliable on Windows
        _pollTimer = new System.Timers.Timer(2000) { AutoReset = true };
        _pollTimer.Elapsed += (_, _) => CheckForChanges();
        _pollTimer.Start();

        _debounce = new System.Timers.Timer(200) { AutoReset = false };
        _debounce.Elapsed += (_, _) =>
        {
            _pending = false;
            FireChanged();
        };

        SetupFsw(tasksJsonPath);
    }

    public bool IsDisposed => _disposed;

    private void SetupFsw(string tasksJsonPath)
    {
        // Clean up existing FSW if any
        _fsw?.Dispose();
        _fsw = null;

        var dir = Path.GetDirectoryName(tasksJsonPath);
        var file = Path.GetFileName(tasksJsonPath);

        if (dir is null || !Directory.Exists(dir))
            return;

        try
        {
            _fsw = new FileSystemWatcher(dir, file)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size,
                InternalBufferSize = 16384, // 16KB buffer to reduce overflow risk
                EnableRaisingEvents = true
            };

            _fsw.Changed += OnFswChanged;
            _fsw.Created += OnFswChanged;
            _fsw.Error += OnFswError;
        }
        catch (Exception)
        {
            // FSW setup failed — polling fallback will cover us
            _fsw?.Dispose();
            _fsw = null;
        }
    }

    private void OnFswChanged(object sender, FileSystemEventArgs e)
    {
        if (_disposed || _pending) return;
        _pending = true;
        _debounce?.Stop();
        _debounce?.Start();
    }

    private void OnFswError(object sender, ErrorEventArgs e)
    {
        if (_disposed) return;

        // FSW died (buffer overflow, etc.) — recreate it
        try
        {
            if (_filePath is not null)
                SetupFsw(_filePath);
        }
        catch (Exception)
        {
            // Polling fallback will keep us alive
        }
    }

    private void CheckForChanges()
    {
        if (_disposed || _filePath is null || !File.Exists(_filePath)) return;

        try
        {
            var lastWrite = File.GetLastWriteTimeUtc(_filePath);
            if (lastWrite > _lastKnownWrite)
            {
                _lastKnownWrite = lastWrite;
                FireChanged();
            }
        }
        catch (Exception)
        {
            // File locked or other error — next poll will catch it
        }
    }

    private void FireChanged()
    {
        if (_disposed) return;

        try
        {
            if (_filePath is not null && File.Exists(_filePath))
                _lastKnownWrite = File.GetLastWriteTimeUtc(_filePath);

            LastRefreshUtc = DateTime.UtcNow;
            TasksChanged?.Invoke();
        }
        catch (Exception)
        {
            // Swallow — don't crash timer thread from subscriber exception
        }
    }

    public void Dispose()
    {
        _disposed = true;
        _fsw?.Dispose();
        _debounce?.Dispose();
        _pollTimer.Dispose();
    }
}
