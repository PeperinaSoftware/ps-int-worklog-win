using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using WinRT.Interop;
using WorklogCalendar.Models;
using WorklogCalendar.Services;
using WorklogCalendar.Views;

namespace WorklogCalendar;

/// <summary>
/// Desktop window. Owns the two stores, the current week, and dispatches
/// to the WeekCalendarControl + dialogs. Equivalent to
/// FullRepresentation.qml + main.qml on the KDE side.
/// </summary>
public sealed partial class MainWindow : Window
{
    private readonly AppSettings _settings;
    private readonly JiraWorklogStore _jira;
    private readonly ClockifyStore _clockify;
    private DateTime _weekStart;

    public MainWindow()
    {
        this.InitializeComponent();
        _settings = SettingsService.Load();
        _jira = new JiraWorklogStore(_settings);
        _clockify = new ClockifyStore(_settings);
        _clockify.Init();

        Calendar.Settings = _settings;
        Calendar.JiraStore = _jira;
        Calendar.ClockifyStore = _clockify;

        Title = "Worklog Calendar";
        ApplyWindowGeometry();

        _weekStart = WeekStartOf(DateTime.Today);
        Calendar.WeekStart = _weekStart;

        // Wire events
        Calendar.CreateJiraRequested += (dayMs, sMs, eMs) => _ = OpenJiraEditAsync(null, sMs, eMs);
        Calendar.EditJiraRequested += w => _ = OpenJiraEditAsync(w, w.StartedUnixMs, w.StartedUnixMs + w.DurationSec * 1000L);
        Calendar.CreateClockifyRequested += (dayMs, sMs, eMs) => _ = OpenClockifyEditAsync(null, sMs, eMs);
        Calendar.EditClockifyRequested += c => _ = OpenClockifyEditAsync(c, c.StartedUnixMs, c.StartedUnixMs + c.DurationSec * 1000L);

        PrevBtn.Click += async (s, e) => { _weekStart = _weekStart.AddDays(-7); await RefreshAsync(); };
        NextBtn.Click += async (s, e) => { _weekStart = _weekStart.AddDays(7); await RefreshAsync(); };
        TodayBtn.Click += async (s, e) => { _weekStart = WeekStartOf(DateTime.Today); await RefreshAsync(); };
        RefreshBtn.Click += async (s, e) => await RefreshAsync();
        ViewModeBtn.Click += async (s, e) =>
        {
            _settings.ViewMode = _settings.ViewMode == "24h" ? "9h" : "24h";
            SettingsService.Save(_settings);
            UpdateHeaderLabels();
            Calendar.Refresh();
            await RefreshAsync();
        };
        DiagBtn.Click += async (s, e) =>
        {
            var d = new DiagnosticsDialog(_jira, _clockify) { XamlRoot = Content.XamlRoot };
            await d.ShowAsync();
        };
        SettingsBtn.Click += async (s, e) => await OpenSettingsAsync();

        SyncJiraToClockifyBtn.Click += async (s, e) => await SyncJiraToClockify();
        SyncProjectCombo.SelectionChanged += (s, e) =>
        {
            var p = SyncProjectCombo.SelectedItem as ClockifyProject;
            _settings.ClockifyDefaultProjectId = p?.Id ?? "";
            SettingsService.Save(_settings);
            UpdateSyncProjectSwatch();
        };

        // Store change notifications: rebuild calendar on each property change.
        _jira.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName is nameof(JiraWorklogStore.Worklogs)
                or nameof(JiraWorklogStore.Loading)
                or nameof(JiraWorklogStore.LastError))
            { UpdateStatus(); Calendar.Refresh(); UpdateTotals(); }
        };
        _clockify.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName is nameof(ClockifyStore.Entries)
                or nameof(ClockifyStore.Loading)
                or nameof(ClockifyStore.LastError)
                or nameof(ClockifyStore.Projects))
            {
                UpdateStatus();
                RefillSyncProjectCombo();
                Calendar.Refresh();
                UpdateTotals();
            }
        };

        UpdateHeaderLabels();
        // Run initial fetch once the visual tree is up.
        DispatcherQueue.TryEnqueue(() => { _ = InitialFetchAsync(); });
    }

    private async Task InitialFetchAsync()
    {
        Calendar.Refresh();
        await RefreshAsync();
    }

    // -------- Window geometry & always-on-top -------------------------------

    private void ApplyWindowGeometry()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw == null) return;
        aw.Resize(new Windows.Graphics.SizeInt32(_settings.WindowWidth, _settings.WindowHeight));
        if (aw.Presenter is OverlappedPresenter op)
        {
            op.IsAlwaysOnTop = _settings.AlwaysOnTop;
            op.IsResizable = true;
        }
    }

    private void ReapplyAlwaysOnTop()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw?.Presenter is OverlappedPresenter op) op.IsAlwaysOnTop = _settings.AlwaysOnTop;
    }

    // -------- Refresh / fetch -----------------------------------------------

    private async Task RefreshAsync()
    {
        UpdateHeaderLabels();
        Calendar.WeekStart = _weekStart;
        Calendar.Refresh();
        var tasks = new List<Task>();
        if (Calendar.ShowJira) tasks.Add(_jira.FetchWeekAsync(_weekStart));
        if (Calendar.ShowClockify) tasks.Add(_clockify.FetchWeekAsync(_weekStart));
        try { await Task.WhenAll(tasks); }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine("Refresh error: " + ex); }
    }

    private void UpdateHeaderLabels()
    {
        TitleText.Text = _settings.Source switch
        {
            "clockify" => "Clockify",
            "jira-clockify" => "Jira / Clockify",
            _ => "Jira Worklog"
        };
        SourceBtn.Content = TitleText.Text;
        ViewModeBtn.Content = _settings.ViewMode == "9h" ? "Modo 9h" : "Modo 24h";
        WeekLabel.Text = FormatWeekLabel(_weekStart);

        bool combined = _settings.Source == "jira-clockify";
        SyncProjectCombo.Visibility = combined ? Visibility.Visible : Visibility.Collapsed;
        SyncProjectSwatch.Visibility = combined ? Visibility.Visible : Visibility.Collapsed;
        SyncJiraToClockifyBtn.Visibility = combined ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateStatus()
    {
        var parts = new List<string>();
        if (_jira.Loading) parts.Add("Jira: cargando…");
        else if (!string.IsNullOrEmpty(_jira.LastError)) parts.Add($"Jira: {_jira.LastError}");
        if (_clockify.Loading) parts.Add("Clockify: cargando…");
        else if (!string.IsNullOrEmpty(_clockify.LastError)) parts.Add($"Clockify: {_clockify.LastError}");

        StatusLabel.Text = string.Join("   ·   ", parts);
        StatusLabel.Visibility = parts.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        bool isError = !string.IsNullOrEmpty(_jira.LastError) || !string.IsNullOrEmpty(_clockify.LastError);
        StatusLabel.Foreground = isError
            ? new SolidColorBrush(Color.FromArgb(255, 234, 90, 84))
            : new SolidColorBrush(Color.FromArgb(255, 120, 200, 130));
    }

    private void UpdateTotals()
    {
        var parts = new List<string>();
        if (Calendar.ShowJira)
        {
            int s = 0; foreach (var w in _jira.Worklogs) s += w.DurationSec;
            parts.Add($"Jira: {s / 3600}h {(s % 3600) / 60}m");
        }
        if (Calendar.ShowClockify)
        {
            int s = 0; foreach (var w in _clockify.Entries) s += w.DurationSec;
            parts.Add($"Clockify: {s / 3600}h {(s % 3600) / 60}m");
        }
        TotalsLabel.Text = string.Join("   ·   ", parts);
    }

    // -------- Source picker --------------------------------------------------

    private async void OnSourceChanged(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuFlyoutItem mi || mi.Tag is not string src) return;
        _settings.Source = src;
        SettingsService.Save(_settings);
        UpdateHeaderLabels();
        await RefreshAsync();
    }

    // -------- Dialogs --------------------------------------------------------

    private async Task OpenJiraEditAsync(JiraWorklog? existing, long startMs, long endMs)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var en = DateTimeOffset.FromUnixTimeMilliseconds(endMs).LocalDateTime;
        var dlg = new JiraEditDialog(_jira, s, en, existing) { XamlRoot = Content.XamlRoot };
        await dlg.ShowAsync();
        if (dlg.Mutated) await RefreshAsync();
    }

    private async Task OpenClockifyEditAsync(ClockifyEntry? existing, long startMs, long endMs)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var en = DateTimeOffset.FromUnixTimeMilliseconds(endMs).LocalDateTime;
        var dlg = new ClockifyEditDialog(_clockify, _settings, s, en, existing) { XamlRoot = Content.XamlRoot };
        await dlg.ShowAsync();
        if (dlg.Mutated) await RefreshAsync();
    }

    private async Task OpenSettingsAsync()
    {
        var dlg = new SettingsDialog(_settings) { XamlRoot = Content.XamlRoot };
        var r = await dlg.ShowAsync();
        if (r == ContentDialogResult.Primary)
        {
            UpdateHeaderLabels();
            ApplyWindowGeometry();
            ReapplyAlwaysOnTop();
            _clockify.Init();
            Calendar.Refresh();
            await RefreshAsync();
        }
    }

    // -------- Combined sync --------------------------------------------------

    private void RefillSyncProjectCombo()
    {
        var list = new List<ClockifyProject> { new() { Id = "", Name = "(sin proyecto)" } };
        list.AddRange(_clockify.Projects);
        SyncProjectCombo.ItemsSource = list;
        int idx = 0;
        for (int i = 0; i < list.Count; i++)
            if (list[i].Id == _settings.ClockifyDefaultProjectId) { idx = i; break; }
        SyncProjectCombo.SelectedIndex = idx;
        UpdateSyncProjectSwatch();
    }

    private void UpdateSyncProjectSwatch()
    {
        var p = SyncProjectCombo.SelectedItem as ClockifyProject;
        SolidColorBrush brush = new(Colors.Transparent);
        if (p != null && !string.IsNullOrEmpty(p.Color) && TryParseHex(p.Color, out var col))
            brush = new SolidColorBrush(col);
        SyncProjectSwatch.Background = brush;
    }

    private async Task SyncJiraToClockify()
    {
        SyncJiraToClockifyBtn.IsEnabled = false;
        StatusLabel.Visibility = Visibility.Visible;
        StatusLabel.Text = "Copiando Jira → Clockify…";
        StatusLabel.Foreground = new SolidColorBrush(Color.FromArgb(255, 180, 200, 220));
        try
        {
            var projectId = string.IsNullOrEmpty(_settings.ClockifyDefaultProjectId) ? null : _settings.ClockifyDefaultProjectId;
            var (created, skipped, failed) = await _clockify.SyncFromJiraAsync(_jira.Worklogs, projectId, _settings.ClockifyBillableDefault);
            StatusLabel.Text = $"Sync terminado: {created} creadas, {skipped} ya existían, {failed} fallaron.";
            StatusLabel.Foreground = failed > 0
                ? new SolidColorBrush(Color.FromArgb(255, 234, 90, 84))
                : new SolidColorBrush(Color.FromArgb(255, 120, 200, 130));
            await _clockify.FetchWeekAsync(_weekStart);
        }
        finally { SyncJiraToClockifyBtn.IsEnabled = true; }
    }

    // -------- Helpers --------------------------------------------------------

    private DateTime WeekStartOf(DateTime d)
    {
        int dow = (int)d.DayOfWeek; // Sunday=0
        int offset = _settings.FirstDayOfWeek == 1
            ? (dow == 0 ? 6 : dow - 1)  // Monday-start
            : dow;                       // Sunday-start
        return d.Date.AddDays(-offset);
    }

    private string FormatWeekLabel(DateTime start)
    {
        var end = start.AddDays(6);
        var months = new[] { "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic" };
        return $"{start.Day} {months[start.Month - 1]} — {end.Day} {months[end.Month - 1]} {end.Year}";
    }

    private static bool TryParseHex(string hex, out Color col)
    {
        col = Colors.Transparent;
        if (string.IsNullOrEmpty(hex)) return false;
        var s = hex.StartsWith("#") ? hex.Substring(1) : hex;
        if (s.Length == 6 &&
            byte.TryParse(s.Substring(0, 2), System.Globalization.NumberStyles.HexNumber, null, out var r) &&
            byte.TryParse(s.Substring(2, 2), System.Globalization.NumberStyles.HexNumber, null, out var g) &&
            byte.TryParse(s.Substring(4, 2), System.Globalization.NumberStyles.HexNumber, null, out var b))
        { col = Color.FromArgb(255, r, g, b); return true; }
        return false;
    }
}
