using System.Collections;
using System.Collections.Specialized;
using Terminal.Gui.Drawing;
using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;
using Tailblaze.Models;
using TGAttribute = Terminal.Gui.Drawing.Attribute;

namespace Tailblaze.Views;

/// <summary>
/// Left pane: color-coded task list with RowRender coloring.
/// </summary>
public sealed class TaskListView : FrameView
{
    private readonly ListView _listView;
    private List<CoworkTask> _tasks = [];
    private TaskListDataSource _dataSource;

    public event Action<CoworkTask>? TaskSelected;

    public TaskListView()
    {
        Title = "Tasks";
        _dataSource = new TaskListDataSource([]);
        _listView = new ListView
        {
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(),
            Source = _dataSource
        };

        // Color rows by status
        _listView.RowRender += (_, args) =>
        {
            if (args.Row >= 0 && args.Row < _tasks.Count)
            {
                var task = _tasks[args.Row];
                args.RowAttribute = task.Status switch
                {
                    "pending" => new TGAttribute(ColorName16.Gray, ColorName16.Black),
                    "running" => new TGAttribute(ColorName16.BrightYellow, ColorName16.Black),
                    "completed" => new TGAttribute(ColorName16.Green, ColorName16.Black),
                    "failed" => new TGAttribute(ColorName16.Red, ColorName16.Black),
                    _ => null
                };
            }
        };

        // Selection events
        _listView.ValueChanged += (_, _) =>
        {
            var idx = _listView.SelectedItem;
            if (idx is >= 0 && idx < _tasks.Count)
                TaskSelected?.Invoke(_tasks[idx.Value]);
        };

        Add(_listView);
    }

    public void UpdateTasks(List<CoworkTask> tasks, bool autoSelect = false, string? preserveSelectedId = null)
    {
        _tasks = tasks;
        _dataSource = new TaskListDataSource(tasks);
        _listView.Source = _dataSource;

        if (autoSelect && _tasks.Count > 0)
        {
            SelectIndex(0);
        }
        else if (preserveSelectedId is not null)
        {
            // Restore selection to the same task after data source replacement
            var idx = _tasks.FindIndex(t => t.Id == preserveSelectedId);
            if (idx >= 0)
                _listView.SelectedItem = idx; // restore position without re-firing TaskSelected
        }
    }

    public void SelectIndex(int index)
    {
        if (index >= 0 && index < _tasks.Count)
        {
            _listView.SelectedItem = index;
            TaskSelected?.Invoke(_tasks[index]);
        }
    }

    public void FocusList() => _listView.SetFocus();
}

/// <summary>
/// Simple data source that provides display strings for the ListView.
/// </summary>
internal sealed class TaskListDataSource : IListDataSource
{
    private readonly List<CoworkTask> _tasks;

    public TaskListDataSource(List<CoworkTask> tasks) => _tasks = tasks;

    public int Count => _tasks.Count;
    public int MaxItemLength => _tasks.Count > 0 ? _tasks.Max(t => t.DisplayLine.Length) : 0;
    public bool SuspendCollectionChangedEvent { get; set; }

#pragma warning disable CS0067 // Required by IListDataSource but not used directly
    public event NotifyCollectionChangedEventHandler? CollectionChanged;
#pragma warning restore CS0067

    public void Render(ListView listView, bool selected, int item, int col, int row, int width, int viewportX = 0)
    {
        if (item < 0 || item >= _tasks.Count) return;

        var text = _tasks[item].DisplayLine;
        if (text.Length - viewportX > width)
            text = text.Substring(viewportX, width);
        else if (viewportX > 0 && viewportX < text.Length)
            text = text[viewportX..].PadRight(width);
        else if (viewportX == 0)
            text = text.PadRight(width);
        else
            text = new string(' ', width);

        listView.Move(col, row);
        listView.AddStr(text);
    }

    public bool IsMarked(int item) => false;
    public void SetMark(int item, bool value) { }
    public IList ToList() => _tasks.Select(t => (object)t.DisplayLine).ToList();
    public void Dispose() { }
}
