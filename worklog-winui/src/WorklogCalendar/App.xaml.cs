using Microsoft.UI.Xaml;

namespace WorklogCalendar;

public partial class App : Application
{
    public static Window? MainWindow { get; private set; }

    public App()
    {
        this.InitializeComponent();
        this.UnhandledException += (s, e) =>
        {
            System.Diagnostics.Debug.WriteLine($"[Unhandled] {e.Exception}");
            e.Handled = true;
        };
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        try
        {
            MainWindow = new MainWindow();
            MainWindow.Activate();
        }
        catch (System.Exception ex)
        {
            // Persist startup failures so we can read them after the
            // crash. The native heap-corruption error code we sometimes
            // see in Event Viewer is only the symptom; this catches the
            // managed exception that triggered it.
            var path = System.IO.Path.Combine(
                System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData),
                "WorklogCalendar-crash.txt");
            try { System.IO.File.WriteAllText(path, ex.ToString()); }
            catch { /* nothing else to do */ }
            throw;
        }
    }
}
