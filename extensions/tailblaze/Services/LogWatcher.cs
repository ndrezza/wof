namespace Tailblaze.Services;

/// <summary>
/// Watches a log file for new content using FSW + polling fallback.
/// Tracks read position so only new bytes are emitted.
/// Handles file truncation/replacement gracefully.
/// </summary>
public sealed class LogWatcher : IDisposable
{
    private FileSystemWatcher? _fsw;
    private readonly System.Timers.Timer _pollTimer;
    private readonly object _readLock = new();
    private string? _currentPath;
    private long _position;
    private bool _paused;
    private volatile bool _disposed;

    public event Action<string>? NewContent;

    public LogWatcher()
    {
        _pollTimer = new System.Timers.Timer(500) { AutoReset = true };
        _pollTimer.Elapsed += (_, _) => ReadNewContent();
    }

    public bool IsPaused => _paused;
    public bool IsDisposed => _disposed;

    public void Watch(string logPath)
    {
        Stop();

        _currentPath = logPath;
        _position = 0;

        // Read full file initially
        ReadNewContent();

        // Set up FSW
        SetupFsw(logPath);

        // Start polling fallback
        _pollTimer.Start();
    }

    private void SetupFsw(string logPath)
    {
        _fsw?.Dispose();
        _fsw = null;

        var dir = Path.GetDirectoryName(logPath);
        var file = Path.GetFileName(logPath);

        if (dir is null || !Directory.Exists(dir))
            return;

        try
        {
            _fsw = new FileSystemWatcher(dir, file)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size,
                InternalBufferSize = 16384,
                EnableRaisingEvents = true
            };
            _fsw.Changed += (_, _) => ReadNewContent();
            _fsw.Error += OnFswError;
        }
        catch (Exception)
        {
            _fsw?.Dispose();
            _fsw = null;
        }
    }

    private void OnFswError(object sender, ErrorEventArgs e)
    {
        if (_disposed || _currentPath is null) return;
        try { SetupFsw(_currentPath); }
        catch (Exception) { /* polling will cover us */ }
    }

    public void Stop()
    {
        _pollTimer.Stop();
        _fsw?.Dispose();
        _fsw = null;
        _currentPath = null;
        _position = 0;
    }

    public void TogglePause()
    {
        _paused = !_paused;
        if (!_paused)
            ReadNewContent(); // Catch up on missed content
    }

    private void ReadNewContent()
    {
        if (_disposed || _paused || _currentPath is null || !File.Exists(_currentPath))
            return;

        lock (_readLock)
        {
            try
            {
                if (_currentPath is null || !File.Exists(_currentPath))
                    return;

                using var stream = new FileStream(
                    _currentPath,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.ReadWrite);

                // Detect file truncation/replacement — reset position
                if (stream.Length < _position)
                {
                    _position = 0;
                    NewContent?.Invoke("\n--- (log file was replaced/truncated) ---\n");
                }

                if (stream.Length <= _position)
                    return;

                stream.Seek(_position, SeekOrigin.Begin);

                using var reader = new StreamReader(stream);
                var newText = reader.ReadToEnd();
                _position = stream.Position;

                if (!string.IsNullOrEmpty(newText))
                    NewContent?.Invoke(newText);
            }
            catch (Exception)
            {
                // File locked or subscriber error — next poll will catch it
            }
        }
    }

    public void Dispose()
    {
        _disposed = true;
        Stop();
        _pollTimer.Dispose();
    }
}
