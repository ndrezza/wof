using Terminal.Gui.App;
using Terminal.Gui.Drawing;
using Terminal.Gui.Drivers;
using Terminal.Gui.Input;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;
using Tailblaze.Models;
using Tailblaze.Services;
using Tailblaze.Views;

namespace Tailblaze.App;

/// <summary>
/// Split-pane layout: task list (left) + log viewer (right) + status bar (bottom).
/// Extends Runnable so Application.Run() can host it.
/// </summary>
public sealed class MainWindow : Runnable
{
    private readonly string _dataDir;
    private readonly TaskStore _taskStore;
    private readonly TaskWatcher _taskWatcher;
    private readonly LogWatcher _logWatcher;
    private readonly System.Timers.Timer _statusRefreshTimer;

    private readonly TaskListView _taskListView;
    private readonly LogViewerView _logViewerView;
    private readonly StatusBarView _statusBarView;

    private CoworkTask? _selectedTask;
    private string? _lastTopTaskKey; // tracks id+status of first task to detect changes
    private volatile bool _disposed;

    public MainWindow(string dataDir)
    {
        _dataDir = dataDir;
        Title = "Tailblaze";
        BorderStyle = LineStyle.Single;

        _taskStore = new TaskStore(dataDir);
        _taskWatcher = new TaskWatcher(_taskStore.TasksJsonPath);
        _logWatcher = new LogWatcher();

        // Views
        _taskListView = new TaskListView
        {
            X = 0,
            Y = 0,
            Width = Dim.Percent(30),
            Height = Dim.Fill(1) // leave 1 row for status bar
        };

        _logViewerView = new LogViewerView
        {
            X = Pos.Right(_taskListView),
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(1)
        };

        _statusBarView = new StatusBarView
        {
            X = 0,
            Y = Pos.Bottom(_taskListView)
        };

        Add(_taskListView, _logViewerView, _statusBarView);

        // Wire events
        _taskListView.TaskSelected += OnTaskSelected;
        _taskWatcher.TasksChanged += () => SafeInvoke(RefreshTasks);
        _logWatcher.NewContent += text => SafeInvoke(() => _logViewerView.AppendContent(text));

        // Global keybindings — Application.KeyDown fires before views consume keys
        Application.KeyDown += OnAppKeyDown;

        // Periodic status bar refresh (shows "Xs ago" / "Xm ago" updating live)
        _statusRefreshTimer = new System.Timers.Timer(5000) { AutoReset = true };
        _statusRefreshTimer.Elapsed += (_, _) => SafeInvoke(() =>
            _statusBarView.SetLastRefresh(_taskWatcher.LastRefreshUtc));
        _statusRefreshTimer.Start();

        // Load initial data
        RefreshTasks();
        _taskListView.FocusList();
    }

    private void OnAppKeyDown(object? sender, Key keyEvent)
    {
        switch (keyEvent.KeyCode)
        {
            case KeyCode.Q | KeyCode.CtrlMask:
            case KeyCode.Esc:
                keyEvent.Handled = true;
                RequestStop();
                return;

            case KeyCode.P | KeyCode.CtrlMask:
                keyEvent.Handled = true;
                _logWatcher.TogglePause();
                _statusBarView.SetTailStatus(
                    _selectedTask is not null,
                    _logWatcher.IsPaused);
                return;

            case KeyCode.R | KeyCode.CtrlMask:
                keyEvent.Handled = true;
                RefreshTasks();
                return;
        }
    }

    private void OnTaskSelected(CoworkTask task)
    {
        _selectedTask = task;
        _logViewerView.SetTitle(task.Title);

        // Build log header
        var header = $"=== Task: {task.Title} ===\n"
                   + $"ID: {task.Id}\n"
                   + $"Status: {task.Status}\n"
                   + $"Created: {task.CreatedAt:yyyy-MM-dd HH:mm:ss}\n";

        if (!string.IsNullOrWhiteSpace(task.Description))
        {
            header += "\n--- Assignment ---\n";
            var descLines = task.Description.Split('\n');
            if (descLines.Length > 50)
                header += string.Join('\n', descLines[..40]) + "\n\n[truncated — showing 40 of " + descLines.Length + " lines]\n";
            else
                header += task.Description + "\n";
        }

        if (task.Result is not null)
            header += $"\n--- Result ---\n{task.Result}\n";

        header += "\n--- Log ---\n";

        _logViewerView.SetContent(header);

        // Try to tail the log file
        var logPath = _taskStore.GetLogPath(task.Id, _dataDir);
        if (logPath is not null)
        {
            _logWatcher.Watch(logPath);
            _statusBarView.SetTailStatus(true, false);
        }
        else
        {
            _logWatcher.Stop();
            _logViewerView.AppendContent("(no log file found)\n");
            _statusBarView.SetTailStatus(false, false);
        }
    }

    private void RefreshTasks()
    {
        var tasks = _taskStore.Load();

        // Sort: running/pending pinned to top, then everything by most recent update
        tasks = [.. tasks
            .OrderBy(t => t.Status is "running" or "pending" ? 0 : 1)
            .ThenByDescending(t => t.UpdatedAt ?? t.CreatedAt)];

        // Auto-select first task when the top entry changes (new task or status change)
        var topKey = tasks.Count > 0 ? $"{tasks[0].Id}:{tasks[0].Status}" : null;
        var autoSelect = topKey != _lastTopTaskKey;
        _lastTopTaskKey = topKey;

        // Preserve selection by task ID across data source replacement
        var selectedId = _selectedTask?.Id;
        _taskListView.UpdateTasks(tasks, autoSelect, selectedId);

        // If the selected task's status or result changed, re-render the detail pane
        if (_selectedTask is not null && !autoSelect)
        {
            var updated = tasks.FirstOrDefault(t => t.Id == _selectedTask.Id);
            if (updated is not null &&
                (updated.Status != _selectedTask.Status || updated.Result != _selectedTask.Result))
            {
                OnTaskSelected(updated);
            }
        }

        // Update status bar refresh indicator
        _statusBarView.SetLastRefresh(_taskWatcher.LastRefreshUtc);
    }

    private void SafeInvoke(Action action)
    {
        if (_disposed) return;
        try
        {
            Application.Invoke(() =>
            {
                try { action(); }
                catch (Exception) { /* swallow — don't crash from UI update failure */ }
            });
        }
        catch (Exception) { /* swallow — Application may be shutting down */ }
    }

    protected override void Dispose(bool disposing)
    {
        _disposed = true;
        if (disposing)
        {
            Application.KeyDown -= OnAppKeyDown;
            _statusRefreshTimer.Dispose();
            _taskWatcher.Dispose();
            _logWatcher.Dispose();
        }
        base.Dispose(disposing);
    }
}
