using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using WorklogCalendar.Models;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

/// <summary>Create / edit / delete a Clockify time entry.</summary>
public sealed partial class ClockifyEditDialog : ContentDialog
{
    private readonly ClockifyStore _store;
    private readonly AppSettings _settings;
    public ClockifyEntry? EditingEntry { get; }
    public bool IsEdit { get; }
    public bool Mutated { get; private set; }

    private readonly HashSet<string> _selectedTagIds = new();

    public ClockifyEditDialog(ClockifyStore store, AppSettings settings, DateTime start, DateTime end, ClockifyEntry? existing)
    {
        this.InitializeComponent();
        _store = store;
        _settings = settings;
        IsEdit = existing != null;
        EditingEntry = existing;
        Title = IsEdit ? "Editar entrada Clockify" : "Nueva entrada Clockify";

        const int margin = 80;
        BodyGrid.Width = Math.Clamp(settings.ModalWidth, 360, Math.Max(360, settings.WindowWidth - margin));
        BodyGrid.Height = Math.Clamp(settings.ModalHeight, 280, Math.Max(280, settings.WindowHeight - margin));

        DayPicker.Date = new DateTimeOffset(start.Date);
        StartPicker.Time = start.TimeOfDay;
        EndPicker.Time = end.TimeOfDay;
        UpdateDuration();
        StartPicker.TimeChanged += (s, e) => UpdateDuration();
        EndPicker.TimeChanged += (s, e) => UpdateDuration();

        if (!IsEdit) SecondaryButtonText = ""; // hide delete on create
        BillableCheck.IsChecked = existing?.Billable ?? _settings.ClockifyBillableDefault;
        DescBox.Text = existing?.Description ?? "";
        if (existing != null)
            foreach (var t in existing.TagIds) _selectedTagIds.Add(t);

        Loaded += async (s, e) =>
        {
            IsPrimaryButtonEnabled = false;
            await _store.EnsureContextAsync();
            PopulateProjects(existing?.ProjectId ?? _settings.ClockifyDefaultProjectId);
            PopulateTags();
            IsPrimaryButtonEnabled = true;
        };

        ProjectCombo.SelectionChanged += (s, e) => UpdateProjectSwatch();

        this.PrimaryButtonClick += async (s, e) =>
        {
            var def = e.GetDeferral();
            try { e.Cancel = !await SaveAsync(); }
            finally { def.Complete(); }
        };
        this.SecondaryButtonClick += async (s, e) =>
        {
            if (!IsEdit) { e.Cancel = true; return; }
            var def = e.GetDeferral();
            try
            {
                var (ok, err) = await _store.DeleteEntryAsync(EditingEntry!.Id);
                if (!ok) { e.Cancel = true; await ShowError($"Error al eliminar: {err}"); }
                else Mutated = true;
            }
            finally { def.Complete(); }
        };
    }

    private void PopulateProjects(string preselectId)
    {
        var list = new List<ClockifyProject> { new() { Id = "", Name = "(sin proyecto)" } };
        list.AddRange(_store.Projects);
        ProjectCombo.ItemsSource = list;
        int selIdx = 0;
        for (int i = 0; i < list.Count; i++) if (list[i].Id == preselectId) { selIdx = i; break; }
        ProjectCombo.SelectedIndex = selIdx;
        UpdateProjectSwatch();
    }

    private void UpdateProjectSwatch()
    {
        var p = ProjectCombo.SelectedItem as ClockifyProject;
        if (p != null && !string.IsNullOrEmpty(p.Color) && TryParseHex(p.Color, out var col))
            ProjectSwatch.Background = new SolidColorBrush(col);
        else
            ProjectSwatch.Background = new SolidColorBrush(Colors.Transparent);
    }

    private void PopulateTags()
    {
        if (_store.Tags.Count == 0)
        {
            TagsRepeater.ItemsSource = new[] { new { Name = "(no hay tags)" } };
            return;
        }
        var items = new List<ToggleButton>();
        foreach (var t in _store.Tags)
        {
            var btn = new ToggleButton
            {
                Content = t.Name,
                IsChecked = _selectedTagIds.Contains(t.Id),
                Tag = t.Id,
                MinHeight = 28,
                Padding = new Thickness(10, 2, 10, 2)
            };
            btn.Checked += (s, e) => { if (btn.Tag is string id) _selectedTagIds.Add(id); };
            btn.Unchecked += (s, e) => { if (btn.Tag is string id) _selectedTagIds.Remove(id); };
            items.Add(btn);
        }
        TagsRepeater.ItemsSource = items;
    }

    private void UpdateDuration()
    {
        var dur = EndPicker.Time - StartPicker.Time;
        if (dur.Ticks <= 0) { DurationLabel.Text = "(duración inválida)"; return; }
        DurationLabel.Text = $"({FormatDur((int)dur.TotalSeconds)})";
    }

    private async Task<bool> SaveAsync()
    {
        var day = DayPicker.Date.DateTime.Date;
        var start = day + StartPicker.Time;
        var end = day + EndPicker.Time;
        if (end <= start) { await ShowError("La hora de fin debe ser posterior al inicio."); return false; }

        var projectId = (ProjectCombo.SelectedItem as ClockifyProject)?.Id ?? "";
        var billable = BillableCheck.IsChecked == true;
        var description = DescBox.Text ?? "";

        (bool ok, string err) result;
        if (IsEdit && EditingEntry != null)
            result = await _store.UpdateEntryAsync(EditingEntry.Id, start, end, description, projectId, _selectedTagIds, billable);
        else
            result = await _store.CreateEntryAsync(start, end, description, projectId, _selectedTagIds, billable);

        if (!result.ok) { await ShowError("Error: " + result.err); return false; }
        Mutated = true;
        return true;
    }

    private async Task ShowError(string msg)
    {
        var dlg = new ContentDialog { Title = "Clockify", Content = msg, CloseButtonText = "OK", XamlRoot = this.XamlRoot };
        await dlg.ShowAsync();
    }

    private static bool TryParseHex(string hex, out Color col)
    {
        col = Colors.Transparent;
        if (string.IsNullOrEmpty(hex)) return false;
        var s = hex.StartsWith("#") ? hex.Substring(1) : hex;
        if (s.Length == 6 &&
            byte.TryParse(s.Substring(0, 2), NumberStyles.HexNumber, null, out var r) &&
            byte.TryParse(s.Substring(2, 2), NumberStyles.HexNumber, null, out var g) &&
            byte.TryParse(s.Substring(4, 2), NumberStyles.HexNumber, null, out var b))
        { col = Color.FromArgb(255, r, g, b); return true; }
        return false;
    }

    private static string FormatDur(int sec)
    {
        int h = sec / 3600, m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return $"{h}h {m}m";
        if (h > 0) return $"{h}h";
        return $"{m}m";
    }
}
