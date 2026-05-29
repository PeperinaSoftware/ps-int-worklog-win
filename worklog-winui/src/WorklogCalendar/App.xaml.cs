using System;
using System.IO;
using H.NotifyIcon;
using Microsoft.UI.Xaml;
using WorklogCalendar.Services;
using WorklogCalendar.Views;

namespace WorklogCalendar;

public partial class App : Application
{
    public static Window? MainWindow { get; private set; }

    // App-owned singletons. The main window and the tray popup share
    // the same stores so a fetch driven by either UI updates both.
    public static AppSettings Settings { get; private set; } = new();
    public static JiraWorklogStore? Jira { get; private set; }
    public static ClockifyStore? Clockify { get; private set; }

    private TaskbarIcon? _tray;
    private TrayPopupWindow? _trayPopup;

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
            Settings = SettingsService.Load();
            Jira = new JiraWorklogStore(Settings);
            Clockify = new ClockifyStore(Settings);
            Clockify.Init();

            MainWindow = new MainWindow();
            MainWindow.Activate();
            // Close button on the main window exits the whole app
            // (tray included). Use the tray menu's "Salir" otherwise.
            MainWindow.Closed += (s, e) => Exit();

            InitializeTrayIcon();
        }
        catch (System.Exception ex)
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WorklogCalendar-crash.txt");
            try { File.WriteAllText(path, ex.ToString()); }
            catch { /* nothing else to do */ }
            throw;
        }
    }

    /// <summary>
    /// Build the notification-area icon. Left-click toggles a small
    /// frame-less popup with the Sprint + Horas gauges; clicking the
    /// popup brings the main window forward. Right-click shows a menu
    /// with the same options plus Exit.
    /// </summary>
    private void InitializeTrayIcon()
    {
        _tray = new TaskbarIcon
        {
            ToolTipText = "Worklog Calendar"
        };
        // Unpackaged WinUI 3 doesn't honour ms-appx:/// URIs, so we load
        // the 32 px PNG from the app's install directory. BitmapImage
        // can't decode .ico, hence the PNG variant.
        try
        {
            var pngPath = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon-32.png");
            _tray.IconSource = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(pngPath));
        }
        catch (System.Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("[Tray] icon load failed: " + ex.Message);
        }

        _tray.LeftClickCommand = new RelayCommand(_ => ToggleTrayPopup());
        _tray.NoLeftClickDelay = true;

        // Right-click menu.
        var openItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Abrir Worklog Calendar" };
        openItem.Click += (s, e) => BringMainToFront();
        var sprintItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Ver sprint" };
        sprintItem.Click += (s, e) => ShowTrayPopup();
        var exitItem = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Salir" };
        exitItem.Click += (s, e) => Exit();
        var menu = new Microsoft.UI.Xaml.Controls.MenuFlyout();
        menu.Items.Add(openItem);
        menu.Items.Add(sprintItem);
        menu.Items.Add(new Microsoft.UI.Xaml.Controls.MenuFlyoutSeparator());
        menu.Items.Add(exitItem);
        _tray.ContextFlyout = menu;

        _tray.ForceCreate();
    }

    private void ToggleTrayPopup()
    {
        if (_trayPopup == null) ShowTrayPopup();
        else _trayPopup.Hide(openMain: false);
    }

    private void ShowTrayPopup()
    {
        if (Jira == null) return;
        if (_trayPopup == null)
        {
            _trayPopup = new TrayPopupWindow(Jira)
            {
                OpenMainRequested = BringMainToFront
            };
            _trayPopup.Closed += (s, e) => _trayPopup = null;
        }
        _trayPopup.ShowNearTray();
    }

    private void BringMainToFront()
    {
        if (MainWindow == null) return;
        _trayPopup?.Hide(openMain: false);
        MainWindow.Activate();
        // AppWindow.Show + reorder so it pops above other top-level windows.
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(MainWindow);
        var wid = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(wid);
        aw?.Show();
    }

    private bool _exiting;
    private new void Exit()
    {
        if (_exiting) return;
        _exiting = true;
        try { _tray?.Dispose(); } catch { /* tray already gone */ }
        try { MainWindow?.Close(); } catch { /* already closing */ }
        Application.Current.Exit();
    }

    // -------- Tiny ICommand impl for the tray button --------------------
    private sealed class RelayCommand : System.Windows.Input.ICommand
    {
        private readonly Action<object?> _exec;
        public RelayCommand(Action<object?> exec) { _exec = exec; }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => _exec(parameter);
        public event EventHandler? CanExecuteChanged { add { } remove { } }
    }
}
