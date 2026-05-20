using System;
using System.Collections.Generic;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI;
using WorklogCalendar.Models;
using WorklogCalendar.Services;

namespace WorklogCalendar.Controls;

/// <summary>
/// Week-view calendar grid. C# port of <c>WorklogCalendar.qml</c>.
/// Renders 7 day columns × N rows of 30-min slots, with Jira / Clockify
/// blocks drawn as absolutely-positioned cards on each day's Canvas.
/// Supports drag-to-create on any day; in jira-clockify combined mode
/// each day is split vertically (Jira left / Clockify right).
/// </summary>
public sealed partial class WeekCalendarControl : UserControl
{
    public event Action<long /*dayMs*/, long /*startMs*/, long /*endMs*/>? CreateJiraRequested;
    public event Action<long, long, long>? CreateClockifyRequested;
    public event Action<JiraWorklog>? EditJiraRequested;
    public event Action<ClockifyEntry>? EditClockifyRequested;

    public AppSettings? Settings { get; set; }
    public JiraWorklogStore? JiraStore { get; set; }
    public ClockifyStore? ClockifyStore { get; set; }
    public DateTime WeekStart { get; set; } = DateTime.Today;
    public string Source => Settings?.Source ?? "jira";
    public bool IsCombined => Source == "jira-clockify";
    public bool ShowJira => Source is "jira" or "jira-clockify";
    public bool ShowClockify => Source is "clockify" or "jira-clockify";

    private const double RowHeight = 22;
    private const double HourColWidth = 64;
    private const double HeaderRowHeight = 26;
    private const double TotalsRowHeight = 24;

    private readonly List<Canvas> _dayCanvases = new();
    private readonly List<Border> _totalsCells = new();
    private readonly Dictionary<Canvas, Rectangle> _dragOverlays = new();

    public WeekCalendarControl()
    {
        this.InitializeComponent();
    }

    public int StartHour => (Settings?.ViewMode ?? "9h") == "24h" ? 0 : 9;
    public int EndHour => (Settings?.ViewMode ?? "9h") == "24h" ? 24 : 18;
    public int SlotsPerDay => (EndHour - StartHour) * 2;

    /// <summary>Rebuild the whole grid. Cheap enough to call on every store change.</summary>
    public void Refresh()
    {
        if (Settings == null) return;
        RootGrid.Children.Clear();
        RootGrid.RowDefinitions.Clear();
        RootGrid.ColumnDefinitions.Clear();
        _dayCanvases.Clear();
        _totalsCells.Clear();
        _dragOverlays.Clear();

        // Columns: 0 = hour labels, 1..7 = day columns
        RootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(HourColWidth) });
        for (int i = 0; i < 7; i++)
            RootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // Rows: 0 = header, 1 = totals, 2 = body
        RootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(HeaderRowHeight) });
        RootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(TotalsRowHeight) });
        RootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(SlotsPerDay * RowHeight) });

        BuildCornerAndHeaders();
        BuildHourColumn();
        BuildDayColumns();
        UpdateTotalsCells();
        RenderEntries();
    }

    private void BuildCornerAndHeaders()
    {
        var corner = new Border
        {
            Background = NeutralBrush(0.06),
            BorderBrush = NeutralBrush(0.16),
            BorderThickness = new Thickness(1),
            Child = new TextBlock
            {
                Text = "total",
                FontSize = 11,
                Opacity = 0.6,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        Grid.SetRow(corner, 0); Grid.SetRowSpan(corner, 2); Grid.SetColumn(corner, 0);
        RootGrid.Children.Add(corner);

        for (int i = 0; i < 7; i++)
        {
            var dayDate = WeekStart.AddDays(i);
            var header = new Border
            {
                Background = NeutralBrush(0.06),
                BorderBrush = NeutralBrush(0.16),
                BorderThickness = new Thickness(1),
                Child = new TextBlock
                {
                    Text = FormatDayHeader(i, dayDate),
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    FontSize = 12,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                }
            };
            Grid.SetRow(header, 0); Grid.SetColumn(header, i + 1);
            RootGrid.Children.Add(header);

            var totalsCell = new Border
            {
                BorderBrush = NeutralBrush(0.16),
                BorderThickness = new Thickness(1)
            };
            Grid.SetRow(totalsCell, 1); Grid.SetColumn(totalsCell, i + 1);
            RootGrid.Children.Add(totalsCell);
            _totalsCells.Add(totalsCell);
        }
    }

    private void BuildHourColumn()
    {
        var stack = new Canvas { Width = HourColWidth };
        for (int slot = 0; slot < SlotsPerDay; slot++)
        {
            var bg = new Rectangle
            {
                Width = HourColWidth,
                Height = RowHeight,
                Fill = (slot % 2 == 0) ? NeutralBrush(0.02) : new SolidColorBrush(Colors.Transparent)
            };
            Canvas.SetLeft(bg, 0); Canvas.SetTop(bg, slot * RowHeight);
            stack.Children.Add(bg);

            var tb = new TextBlock
            {
                Text = SlotLabel(slot),
                FontSize = 10,
                Opacity = slot % 2 == 0 ? 0.85 : 0.45,
                TextAlignment = TextAlignment.Right,
                Width = HourColWidth - 6
            };
            Canvas.SetLeft(tb, 0); Canvas.SetTop(tb, slot * RowHeight + 4);
            stack.Children.Add(tb);
        }
        Grid.SetRow(stack, 2); Grid.SetColumn(stack, 0);
        RootGrid.Children.Add(stack);
    }

    private void BuildDayColumns()
    {
        for (int day = 0; day < 7; day++)
        {
            var canvas = new Canvas
            {
                Background = NeutralBrush(0.0),
                Height = SlotsPerDay * RowHeight,
                HorizontalAlignment = HorizontalAlignment.Stretch
            };
            // Background slot stripes & borders.
            for (int slot = 0; slot < SlotsPerDay; slot++)
            {
                var row = new Rectangle
                {
                    Fill = (slot % 2 == 0) ? NeutralBrush(0.03) : NeutralBrush(0.0),
                    Stroke = NeutralBrush(0.08),
                    StrokeThickness = 0.5,
                    Height = RowHeight,
                    HorizontalAlignment = HorizontalAlignment.Stretch
                };
                // We don't know width until layout; bind via SizeChanged.
                Canvas.SetTop(row, slot * RowHeight);
                Canvas.SetLeft(row, 0);
                canvas.Children.Add(row);
            }

            // The drag-overlay rectangle (hidden until a drag starts).
            var drag = new Rectangle
            {
                Fill = AccentBrush(0.30),
                Stroke = AccentBrush(1.0),
                StrokeThickness = 1,
                IsHitTestVisible = false,
                Visibility = Visibility.Collapsed
            };
            Canvas.SetZIndex(drag, 9999);
            canvas.Children.Add(drag);
            _dragOverlays[canvas] = drag;

            // Combined-mode vertical divider.
            if (IsCombined)
            {
                var div = new Rectangle
                {
                    Fill = NeutralBrush(0.18),
                    Width = 1,
                    Height = SlotsPerDay * RowHeight
                };
                Canvas.SetTop(div, 0);
                Canvas.SetLeft(div, 0); // updated in SizeChanged
                Canvas.SetZIndex(div, 5);
                canvas.Children.Add(div);
                canvas.SizeChanged += (s, e) => Canvas.SetLeft(div, e.NewSize.Width / 2 - 0.5);
            }

            // Resize the background row rectangles when width changes.
            canvas.SizeChanged += (s, e) =>
            {
                foreach (var child in canvas.Children)
                {
                    if (child is Rectangle rc && rc.Height == RowHeight && rc.Width == 0)
                    {
                        // (these are the slot stripes — set width to canvas.)
                    }
                }
                // simpler: any Rectangle whose Stroke is the slot-stripe stroke gets full width.
                foreach (var child in canvas.Children)
                {
                    if (child is Rectangle r && r.Height == RowHeight && r != drag)
                        r.Width = e.NewSize.Width;
                }
                // Reposition entry blocks (they cache their width fraction in Tag).
                LayoutEntryBlocks(canvas, e.NewSize.Width);
            };

            int dayIdx = day;
            canvas.PointerPressed += (s, e) => OnDayPressed(canvas, dayIdx, e);
            canvas.PointerMoved += (s, e) => OnDayMoved(canvas, dayIdx, e);
            canvas.PointerReleased += (s, e) => OnDayReleased(canvas, dayIdx, e);
            canvas.PointerCaptureLost += (s, e) => HideDragOverlay(canvas);

            Grid.SetRow(canvas, 2); Grid.SetColumn(canvas, day + 1);
            RootGrid.Children.Add(canvas);
            _dayCanvases.Add(canvas);
        }
    }

    private void UpdateTotalsCells()
    {
        for (int i = 0; i < 7 && i < _totalsCells.Count; i++)
        {
            var s = TotalSecForDay(i);
            var cell = _totalsCells[i];
            if (s <= 0)
            {
                cell.Background = NeutralBrush(0.02);
                cell.Child = MakeText("—", 11);
            }
            else
            {
                var target = (Settings?.DailyTargetHours ?? 8) * 3600;
                cell.Background = s >= target
                    ? new SolidColorBrush(Color.FromArgb(0x2E, 0x2E, 0xCC, 0x71)) // green
                    : new SolidColorBrush(Color.FromArgb(0x2E, 0xF1, 0xC4, 0x0F)); // yellow
                cell.Child = MakeText($"Logged: {FormatTotal(s)} {FormatDiff(s)}", 11);
            }
        }
    }

    private TextBlock MakeText(string s, double sz) => new TextBlock
    {
        Text = s, FontSize = sz,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center
    };

    private int TotalSecForDay(int idx)
    {
        // Prefer Jira when shown (mirrors the QML logic).
        int s = 0;
        if (ShowJira && JiraStore != null)
        {
            long startMs = ToMs(WeekStart.AddDays(idx)), endMs = ToMs(WeekStart.AddDays(idx + 1));
            foreach (var w in JiraStore.Worklogs)
                if (w.StartedUnixMs >= startMs && w.StartedUnixMs < endMs) s += w.DurationSec;
            if (s > 0 || !ShowClockify) return s;
        }
        if (ShowClockify && ClockifyStore != null)
        {
            long startMs = ToMs(WeekStart.AddDays(idx)), endMs = ToMs(WeekStart.AddDays(idx + 1));
            foreach (var w in ClockifyStore.Entries)
                if (w.StartedUnixMs >= startMs && w.StartedUnixMs < endMs) s += w.DurationSec;
        }
        return s;
    }

    private void RenderEntries()
    {
        foreach (var canvas in _dayCanvases) ClearEntryBlocks(canvas);
        for (int day = 0; day < 7 && day < _dayCanvases.Count; day++)
        {
            var canvas = _dayCanvases[day];
            long dayStart = ToMs(WeekStart.AddDays(day));
            long dayEnd = ToMs(WeekStart.AddDays(day + 1));
            if (ShowJira && JiraStore != null)
            {
                foreach (var w in JiraStore.Worklogs)
                    if (w.StartedUnixMs >= dayStart && w.StartedUnixMs < dayEnd)
                        canvas.Children.Add(BuildBlock(w, isJira: true));
            }
            if (ShowClockify && ClockifyStore != null)
            {
                foreach (var e in ClockifyStore.Entries)
                    if (e.StartedUnixMs >= dayStart && e.StartedUnixMs < dayEnd)
                        canvas.Children.Add(BuildBlock(e, isJira: false));
            }
            if (canvas.ActualWidth > 0)
                LayoutEntryBlocks(canvas, canvas.ActualWidth);
        }
    }

    private void ClearEntryBlocks(Canvas canvas)
    {
        for (int i = canvas.Children.Count - 1; i >= 0; i--)
            if (canvas.Children[i] is Border) canvas.Children.RemoveAt(i);
    }

    private Border BuildBlock(object entry, bool isJira)
    {
        long startedMs; int durSec; string title; string subtitle; SolidColorBrush fill; SolidColorBrush border;
        if (isJira)
        {
            var w = (JiraWorklog)entry;
            startedMs = w.StartedUnixMs; durSec = w.DurationSec;
            title = FormatTimeRange(w.StartedUnixMs, w.DurationSec);
            bool showSummary = Settings?.ShowJiraSummary ?? false;
            subtitle = showSummary && !string.IsNullOrEmpty(w.IssueSummary) ? $"{w.IssueKey}: {w.IssueSummary}" : w.IssueKey;
            fill = (SolidColorBrush)Application.Current.Resources["JiraFillBrush"];
            border = (SolidColorBrush)Application.Current.Resources["JiraBorderBrush"];
        }
        else
        {
            var c = (ClockifyEntry)entry;
            startedMs = c.StartedUnixMs; durSec = c.DurationSec;
            title = FormatTimeRange(c.StartedUnixMs, c.DurationSec);
            var desc = string.IsNullOrEmpty(c.Description) ? "(sin descripción)" : c.Description;
            subtitle = !string.IsNullOrEmpty(c.ProjectName) ? $"[{c.ProjectName}] {desc}" : desc;
            // In pure clockify mode use the project's color if available.
            if (!IsCombined && !string.IsNullOrEmpty(c.ProjectColor) && TryParseHex(c.ProjectColor, out var col))
            {
                fill = new SolidColorBrush(Color.FromArgb(0x8C, col.R, col.G, col.B));
                border = new SolidColorBrush(col);
            }
            else
            {
                fill = (SolidColorBrush)Application.Current.Resources["ClockifyFillBrush"];
                border = (SolidColorBrush)Application.Current.Resources["ClockifyBorderBrush"];
            }
        }

        bool isShort = durSec <= 30 * 60;
        var stack = new StackPanel { Orientation = Orientation.Vertical, Spacing = 0 };
        stack.Children.Add(new TextBlock
        {
            Text = isShort ? FormatTimeShort(startedMs) + "  " + subtitle : title,
            Foreground = new SolidColorBrush(Colors.White),
            FontSize = isShort || IsCombined ? 10 : 11,
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = TextWrapping.NoWrap
        });
        if (!isShort)
        {
            stack.Children.Add(new TextBlock
            {
                Text = subtitle,
                Foreground = new SolidColorBrush(Colors.White),
                FontSize = IsCombined ? 10 : 11,
                TextTrimming = TextTrimming.CharacterEllipsis,
                TextWrapping = TextWrapping.NoWrap
            });
        }

        var card = new Border
        {
            Background = fill,
            BorderBrush = border,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(3),
            Padding = new Thickness(3),
            Child = stack
        };
        // Tag holds metadata used at layout: side (jira/clockify), startedMs, durationSec, entry.
        card.Tag = new BlockTag(isJira, startedMs, durSec, entry);

        // Click to edit.
        card.PointerPressed += (s, e) =>
        {
            e.Handled = true; // don't let canvas start a drag
        };
        card.Tapped += (s, e) =>
        {
            if (isJira) EditJiraRequested?.Invoke((JiraWorklog)entry);
            else EditClockifyRequested?.Invoke((ClockifyEntry)entry);
        };

        return card;
    }

    private record BlockTag(bool IsJira, long StartedMs, int DurationSec, object Entry);

    private void LayoutEntryBlocks(Canvas canvas, double width)
    {
        int day = _dayCanvases.IndexOf(canvas);
        if (day < 0) return;
        foreach (var child in canvas.Children)
        {
            if (child is not Border b || b.Tag is not BlockTag t) continue;
            int slotsTop = SlotOfMs(t.StartedMs, day);
            int slotsLen = Math.Max(1, (int)Math.Round(t.DurationSec / 1800.0));
            double y = slotsTop * RowHeight;
            double h = slotsLen * RowHeight - 2;
            double left, w;
            if (IsCombined)
            {
                if (t.IsJira) { left = 2; w = width / 2 - 4; }
                else { left = width / 2 + 1; w = width / 2 - 3; }
            }
            else { left = 2; w = width - 4; }
            Canvas.SetLeft(b, left);
            Canvas.SetTop(b, y);
            b.Width = Math.Max(0, w);
            b.Height = Math.Max(0, h);
        }
    }

    // -------- Drag-to-create -------------------------------------------------

    private record DragState(double PressY, bool PressLeft);
    private readonly Dictionary<Canvas, DragState> _drag = new();

    private void OnDayPressed(Canvas canvas, int day, PointerRoutedEventArgs e)
    {
        var pt = e.GetCurrentPoint(canvas);
        if (!pt.Properties.IsLeftButtonPressed) return;
        if (e.OriginalSource is FrameworkElement fe && fe.Parent is Border) return; // clicked an entry
        canvas.CapturePointer(e.Pointer);
        bool left = !IsCombined || pt.Position.X < canvas.ActualWidth / 2;
        _drag[canvas] = new DragState(pt.Position.Y, left);
        var overlay = _dragOverlays[canvas];
        overlay.Visibility = Visibility.Visible;
        UpdateDragOverlay(canvas, pt.Position.Y);
    }

    private void OnDayMoved(Canvas canvas, int day, PointerRoutedEventArgs e)
    {
        if (!_drag.TryGetValue(canvas, out _)) return;
        var pt = e.GetCurrentPoint(canvas);
        UpdateDragOverlay(canvas, pt.Position.Y);
    }

    private void OnDayReleased(Canvas canvas, int day, PointerRoutedEventArgs e)
    {
        if (!_drag.TryGetValue(canvas, out var st)) return;
        canvas.ReleasePointerCapture(e.Pointer);
        var pt = e.GetCurrentPoint(canvas);
        _drag.Remove(canvas);
        HideDragOverlay(canvas);

        int topSlot = SnapSlot(Math.Min(st.PressY, pt.Position.Y));
        int botSlot = SnapSlot(Math.Max(st.PressY, pt.Position.Y)) + 1;
        var dayDate = WeekStart.AddDays(day);
        var startMs = ToMsAtSlot(dayDate, topSlot);
        var endMs = ToMsAtSlot(dayDate, botSlot);
        if (endMs <= startMs) endMs = startMs + 30 * 60_000;
        long dayMs = ToMs(dayDate);

        if (IsCombined)
        {
            if (st.PressLeft) CreateJiraRequested?.Invoke(dayMs, startMs, endMs);
            else CreateClockifyRequested?.Invoke(dayMs, startMs, endMs);
        }
        else if (Source == "jira") CreateJiraRequested?.Invoke(dayMs, startMs, endMs);
        else CreateClockifyRequested?.Invoke(dayMs, startMs, endMs);
    }

    private void HideDragOverlay(Canvas canvas)
    {
        if (_dragOverlays.TryGetValue(canvas, out var ov)) ov.Visibility = Visibility.Collapsed;
    }

    private void UpdateDragOverlay(Canvas canvas, double curY)
    {
        if (!_drag.TryGetValue(canvas, out var st)) return;
        var overlay = _dragOverlays[canvas];
        double top = SnapSlot(Math.Min(st.PressY, curY)) * RowHeight;
        double bot = (SnapSlot(Math.Max(st.PressY, curY)) + 1) * RowHeight;
        double left = IsCombined ? (st.PressLeft ? 0 : canvas.ActualWidth / 2) : 0;
        double w = IsCombined ? canvas.ActualWidth / 2 : canvas.ActualWidth;
        Canvas.SetTop(overlay, top);
        Canvas.SetLeft(overlay, left);
        overlay.Width = w;
        overlay.Height = Math.Max(RowHeight, bot - top);
    }

    private int SnapSlot(double y)
    {
        int s = (int)Math.Round(y / RowHeight);
        return Math.Clamp(s, 0, SlotsPerDay);
    }

    // -------- Helpers --------------------------------------------------------

    private long ToMsAtSlot(DateTime day, int slot)
    {
        var dt = day.Date.AddHours(StartHour).AddMinutes(slot * 30);
        return new DateTimeOffset(DateTime.SpecifyKind(dt, DateTimeKind.Local)).ToUnixTimeMilliseconds();
    }

    private int SlotOfMs(long ms, int day)
    {
        var local = DateTimeOffset.FromUnixTimeMilliseconds(ms).LocalDateTime;
        var dayStart = WeekStart.AddDays(day).Date;
        var minutes = (int)Math.Floor((local - dayStart).TotalMinutes);
        return minutes / 30 - StartHour * 2;
    }

    private static long ToMs(DateTime d) =>
        new DateTimeOffset(DateTime.SpecifyKind(d.Date, DateTimeKind.Local)).ToUnixTimeMilliseconds();

    private static string FormatDayHeader(int idx, DateTime d)
    {
        var names = new[] { "Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb" };
        var months = new[] { "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic" };
        // Use the actual day-of-week of d so a Monday-start week labels correctly.
        return $"{names[(int)d.DayOfWeek]} {d.Day}/{months[d.Month - 1]}";
    }

    private string SlotLabel(int slot)
    {
        int totalMin = StartHour * 60 + slot * 30;
        return $"{totalMin / 60:00}:{totalMin % 60:00}";
    }

    private static string FormatTotal(int sec)
    {
        if (sec <= 0) return "—";
        int h = sec / 3600, m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return $"{h}h {m}m";
        if (h > 0) return $"{h}h";
        return $"{m}m";
    }

    private string FormatDiff(int sec)
    {
        var target = (Settings?.DailyTargetHours ?? 8) * 3600;
        var diff = sec - target;
        if (Math.Abs(diff) < 1) return "";
        var sign = diff > 0 ? "+" : "-";
        int abs = (int)Math.Abs(diff);
        int h = abs / 3600, m = (abs % 3600) / 60;
        string body = (h > 0 ? $"{h}h" : "") + (m > 0 ? (h > 0 ? " " : "") + $"{m}m" : "");
        return $"({sign}{body})";
    }

    private static string FormatTimeRange(long startMs, int durationSec)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var e = s.AddSeconds(durationSec);
        return $"{s:HH:mm} - {e:HH:mm} ({FormatTotal(durationSec)})";
    }

    private static string FormatTimeShort(long ms) =>
        DateTimeOffset.FromUnixTimeMilliseconds(ms).LocalDateTime.ToString("HH:mm");

    private static SolidColorBrush NeutralBrush(double alpha) =>
        new(Color.FromArgb((byte)Math.Clamp(alpha * 255, 0, 255), 255, 255, 255));

    private static SolidColorBrush AccentBrush(double alpha)
    {
        var c = (Color)Application.Current.Resources["SystemAccentColor"];
        return new SolidColorBrush(Color.FromArgb((byte)Math.Clamp(alpha * 255, 0, 255), c.R, c.G, c.B));
    }

    private static bool TryParseHex(string hex, out Color col)
    {
        col = Colors.Transparent;
        if (string.IsNullOrEmpty(hex)) return false;
        var s = hex.StartsWith("#") ? hex.Substring(1) : hex;
        if (s.Length == 6 && byte.TryParse(s.Substring(0, 2), System.Globalization.NumberStyles.HexNumber, null, out var r)
                          && byte.TryParse(s.Substring(2, 2), System.Globalization.NumberStyles.HexNumber, null, out var g)
                          && byte.TryParse(s.Substring(4, 2), System.Globalization.NumberStyles.HexNumber, null, out var b))
        { col = Color.FromArgb(255, r, g, b); return true; }
        return false;
    }
}
