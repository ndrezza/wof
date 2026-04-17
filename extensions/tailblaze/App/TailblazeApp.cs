using Terminal.Gui.App;

namespace Tailblaze.App;

/// <summary>
/// Manages Terminal.Gui application lifecycle.
/// </summary>
public static class TailblazeApp
{
    public static void Run(string dataDir)
    {
        Application.Init();

        try
        {
            var mainWindow = new MainWindow(dataDir);
            Application.Run(mainWindow);
            mainWindow.Dispose();
        }
        finally
        {
            Application.Shutdown();
            Console.Clear();
        }
    }
}
