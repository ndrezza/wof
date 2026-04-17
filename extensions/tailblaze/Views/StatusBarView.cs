using Terminal.Gui.ViewBase;
using Terminal.Gui.Views;

namespace Tailblaze.Views;

/// <summary>
/// Bottom bar showing keybinding hints, tail status, and last refresh timestamp.
/// </summary>
public sealed class StatusBarView : View
{
    private readonly Label _label;
    private bool _tailOn = true;
    private bool _paused;
    private DateTime? _lastRefreshUtc;

    public StatusBarView()
    {
        Height = 1;
        Width = Dim.Fill();

        _label = new Label
        {
            X = 0,
            Y = 0,
            Width = Dim.Fill(),
            Height = 1,
            Text = BuildText()
        };
        Add(_label);
    }

    public void SetTailStatus(bool tailOn, bool paused)
    {
        _tailOn = tailOn;
        _paused = paused;
        _label.Text = BuildText();
    }

    public void SetLastRefresh(DateTime utcTimestamp)
    {
        _lastRefreshUtc = utcTimestamp;
        _label.Text = BuildText();
    }

    private string BuildText()
    {
        var tail = _paused ? "PAUSED" : (_tailOn ? "ON" : "OFF");
        var refresh = _lastRefreshUtc.HasValue
            ? FormatAge(DateTime.UtcNow - _lastRefreshUtc.Value)
            : "—";
        return $" Ctrl+Q/Esc Quit | Ctrl+P Pause/Resume | Ctrl+R Refresh | PgUp/PgDn Scroll    TAIL: {tail}  |  Last refresh: {refresh}";
    }

    private static string FormatAge(TimeSpan age)
    {
        if (age.TotalSeconds < 5) return "just now";
        if (age.TotalSeconds < 60) return $"{(int)age.TotalSeconds}s ago";
        if (age.TotalMinutes < 60) return $"{(int)age.TotalMinutes}m ago";
        return $"{(int)age.TotalHours}h ago";
    }
}
