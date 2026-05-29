using System;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Graphics;
using WinRT.Interop;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

/// <summary>
/// Control-Center-style fly-out: frame-less window anchored to the
/// bottom-right of the primary monitor's work area, Mica backdrop, with
/// a slide-in + fade-in animation on first show. Clicking anywhere on
/// the body raises <see cref="OpenMainRequested"/>; deactivation
/// (clicking elsewhere) raises <see cref="HideRequested"/> so the
/// owning App can dispose the window cleanly.
/// </summary>
public sealed partial class TrayPopupWindow : Window
{
    private const int PopupWidth = 420;
    private const int PopupHeight = 360;

    public Action? OpenMainRequested;
    public Action? HideRequested;

    public TrayPopupWindow(JiraWorklogStore jira)
    {
        this.InitializeComponent();
        Gauges.Store = jira;

        // Frame-less, no taskbar entry, no min/max buttons.
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

        // Mica backdrop — gives the Control-Center translucent blur look.
        TrySetMicaBackdrop();

        // Click on the body opens the main window.
        Root.PointerPressed += (s, e) =>
        {
            OpenMainRequested?.Invoke();
            HideRequested?.Invoke();
        };

        // Auto-hide when the user clicks somewhere else.
        this.Activated += (s, e) =>
        {
            if (e.WindowActivationState == WindowActivationState.Deactivated)
            {
                HideRequested?.Invoke();
            }
        };
    }

    private void TrySetMicaBackdrop()
    {
        if (MicaController.IsSupported())
        {
            try
            {
                this.SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt };
                return;
            }
            catch { /* fall through to solid background */ }
        }
        // Mica unavailable (older Win11 build / VM) → solid dark fallback.
        Root.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0xF2, 0x1F, 0x1F, 0x1F));
    }

    /// <summary>Position near the bottom-right (above the tray) and animate in.</summary>
    public void ShowNearTray()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw != null)
        {
            var da = DisplayArea.GetFromWindowId(wid, DisplayAreaFallback.Primary);
            var work = da.WorkArea;
            const int margin = 12;
            int x = work.X + work.Width - PopupWidth - margin;
            int y = work.Y + work.Height - PopupHeight - margin;
            aw.MoveAndResize(new RectInt32(x, y, PopupWidth, PopupHeight));
        }

        Gauges.StartFillAnimation();
        this.Activate();
        AnimateSlideIn();
    }

    private void AnimateSlideIn()
    {
        // Fade + slide from below — short and snappy, like the Win11
        // Control Center.
        Root.Opacity = 0;
        RootTransform.TranslateY = 24;

        var sb = new Storyboard();

        var fade = new DoubleAnimation
        {
            From = 0, To = 1,
            Duration = TimeSpan.FromMilliseconds(180),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(fade, Root);
        Storyboard.SetTargetProperty(fade, "Opacity");
        sb.Children.Add(fade);

        var slide = new DoubleAnimation
        {
            From = 24, To = 0,
            Duration = TimeSpan.FromMilliseconds(240),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(slide, RootTransform);
        Storyboard.SetTargetProperty(slide, "TranslateY");
        sb.Children.Add(slide);

        sb.Begin();
    }
}
