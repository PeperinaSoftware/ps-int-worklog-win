using System;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Windows.Graphics;
using WinRT.Interop;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

/// <summary>
/// Small frame-less window that appears anchored to the tray icon.
/// Shows the Sprint + Horas ring gauges; clicking anywhere opens the
/// main app window. Hides itself when it loses focus.
/// </summary>
public sealed partial class TrayPopupWindow : Window
{
    private const int PopupWidth = 460;
    private const int PopupHeight = 320;

    public Action? OpenMainRequested;

    public TrayPopupWindow(JiraWorklogStore jira)
    {
        this.InitializeComponent();
        Gauges.Store = jira;

        // Frame-less, no taskbar entry, no titlebar buttons.
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw != null)
        {
            aw.Resize(new SizeInt32(PopupWidth, PopupHeight));
            if (aw.Presenter is OverlappedPresenter op)
            {
                op.IsResizable = false;
                op.IsMaximizable = false;
                op.IsMinimizable = false;
                op.SetBorderAndTitleBar(false, false);
                op.IsAlwaysOnTop = true;
            }
            aw.IsShownInSwitchers = false;
            aw.Title = "Worklog";
        }

        // A click anywhere on the body opens the main window.
        Root.PointerPressed += (s, e) => Hide(openMain: true);

        // Auto-hide when the window deactivates (user clicks elsewhere).
        this.Activated += (s, e) =>
        {
            if (e.WindowActivationState == WindowActivationState.Deactivated)
                Hide(openMain: false);
        };
    }

    /// <summary>Position near the bottom-right corner (above the tray) and show.</summary>
    public void ShowNearTray()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw != null)
        {
            // DisplayArea.Primary covers the primary monitor's working
            // area (excludes the taskbar). Bottom-right is where the
            // tray lives on default Win11 layouts.
            var da = DisplayArea.GetFromWindowId(wid, DisplayAreaFallback.Primary);
            var work = da.WorkArea;
            int margin = 8;
            int x = work.X + work.Width - PopupWidth - margin;
            int y = work.Y + work.Height - PopupHeight - margin;
            aw.Move(new PointInt32(x, y));
        }
        Gauges.StartFillAnimation();
        this.Activate();
    }

    public void Hide(bool openMain)
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        aw?.Hide();
        if (openMain) OpenMainRequested?.Invoke();
    }
}
