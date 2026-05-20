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
        MainWindow = new MainWindow();
        MainWindow.Activate();
    }
}
