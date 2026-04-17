using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;

namespace Tailblaze.Views;

/// <summary>
/// Right pane: read-only text view that shows log content with auto-scroll (tail mode).
/// Content is capped to prevent unbounded memory growth and UI lag.
/// </summary>
public sealed class LogViewerView : FrameView
{
    private readonly TextView _textView;
    private string _content = "";
    private bool _tailMode = true;

    /// <summary>Max characters to retain. ~200KB keeps the UI responsive.</summary>
    private const int MaxContentLength = 200_000;
    private const string TruncationMarker = "\n--- (older content trimmed) ---\n";

    public LogViewerView()
    {
        Title = "Log";
        _textView = new TextView
        {
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = Dim.Fill(),
            ReadOnly = true,
            WordWrap = true,
            Text = "(select a task to view its log)"
        };
        Add(_textView);
    }

    public bool TailMode
    {
        get => _tailMode;
        set => _tailMode = value;
    }

    public void SetTitle(string title) => Title = $"Log: {title}";

    public void Clear()
    {
        _content = "";
        _textView.Text = "(select a task to view its log)";
        Title = "Log";
    }

    public void SetContent(string content)
    {
        _content = TrimContent(content);
        _textView.Text = _content;
        if (_tailMode)
            ScrollToEnd();
    }

    public void AppendContent(string newContent)
    {
        _content += newContent;
        _content = TrimContent(_content);
        _textView.Text = _content;
        if (_tailMode)
            ScrollToEnd();
    }

    private static string TrimContent(string content)
    {
        if (content.Length <= MaxContentLength)
            return content;

        // Find next newline after the trim point to avoid cutting mid-line
        var trimFrom = content.Length - MaxContentLength;
        var nextNewline = content.IndexOf('\n', trimFrom);
        if (nextNewline >= 0 && nextNewline < trimFrom + 500)
            trimFrom = nextNewline + 1;

        return TruncationMarker + content[trimFrom..];
    }

    private void ScrollToEnd()
    {
        _textView.MoveEnd();
    }
}
