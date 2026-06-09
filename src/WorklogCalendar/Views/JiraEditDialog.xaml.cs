using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WorklogCalendar.Models;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

/// <summary>
/// Modal that creates or edits a Jira worklog. Mirrors WorklogEditDialog.qml:
/// the issue picker is shown only when creating; when editing the issue is
/// locked (Jira's API doesn't let you move a worklog between issues).
/// </summary>
public sealed partial class JiraEditDialog : ContentDialog
{
    private readonly JiraWorklogStore _store;
    private List<JiraIssue> _allIssues = new();
    public bool IsEdit { get; }
    public JiraWorklog? EditingEntry { get; }

    /// <summary>True if the dialog completed a save/delete and the caller should refresh.</summary>
    public bool Mutated { get; private set; }

    public JiraEditDialog(JiraWorklogStore store, AppSettings settings, DateTime start, DateTime end, JiraWorklog? existing)
    {
        this.InitializeComponent();
        _store = store;
        IsEdit = existing != null;
        EditingEntry = existing;
        Title = IsEdit ? "Editar worklog Jira" : "Nuevo worklog Jira";
        // Apply configurable modal size, clamped to the window so the
        // dialog never overflows on small screens.
        ApplyModalSize(settings);

        DayPicker.Date = new DateTimeOffset(start.Date);
        StartPicker.Time = start.TimeOfDay;
        EndPicker.Time = end.TimeOfDay;
        UpdateDuration();
        StartPicker.TimeChanged += (s, e) => UpdateDuration();
        EndPicker.TimeChanged += (s, e) => UpdateDuration();

        if (IsEdit && existing != null)
        {
            PickerSearchRow.Visibility = Visibility.Collapsed;
            IssueList.Visibility = Visibility.Collapsed;
            LockedIssue.Visibility = Visibility.Visible;
            LockedIssue.Text = $"[{existing.IssueKey}] {existing.IssueSummary}";
            CommentBox.Text = existing.Comment ?? "";
        }
        else
        {
            SecondaryButtonText = ""; // hide delete on create
        }

        IssueSearch.TextChanged += (s, e) => ApplyFilter();
        ReloadBtn.Click += async (s, e) => await ReloadIssues();

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
                var (ok, err) = await _store.DeleteWorklogAsync(EditingEntry!.IssueKey, EditingEntry.Id);
                if (!ok) { e.Cancel = true; await ShowError($"Error al eliminar: {err}"); }
                else Mutated = true;
            }
            finally { def.Complete(); }
        };

        if (!IsEdit) _ = ReloadIssues();
    }

    private void UpdateDuration()
    {
        var s = StartPicker.Time;
        var en = EndPicker.Time;
        var dur = en - s;
        if (dur.Ticks <= 0) { DurationLabel.Text = "(duración inválida)"; return; }
        DurationLabel.Text = $"({FormatDur((int)dur.TotalSeconds)})";
    }

    private async Task ReloadIssues()
    {
        IsPrimaryButtonEnabled = false;
        await _store.FetchAssignableIssuesAsync();
        _allIssues = new List<JiraIssue>(_store.AssignableIssues);
        ApplyFilter();
        IsPrimaryButtonEnabled = true;
    }

    private void ApplyFilter()
    {
        var q = (IssueSearch.Text ?? "").Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(q)) { IssueList.ItemsSource = _allIssues; return; }
        var filtered = new List<JiraIssue>();
        foreach (var it in _allIssues)
        {
            var hay = $"{it.Key} {it.Summary} {it.IssueType} {it.Status}".ToLowerInvariant();
            if (hay.Contains(q)) filtered.Add(it);
        }
        IssueList.ItemsSource = filtered;
    }

    private async Task<bool> SaveAsync()
    {
        var day = DayPicker.Date.DateTime.Date;
        var start = day + StartPicker.Time;
        var end = day + EndPicker.Time;
        if (end <= start) { await ShowError("La hora de fin debe ser posterior al inicio."); return false; }
        int durSec = (int)(end - start).TotalSeconds;

        if (IsEdit && EditingEntry != null)
        {
            var (ok, err) = await _store.UpdateWorklogAsync(EditingEntry.IssueKey, EditingEntry.Id, start, durSec, CommentBox.Text ?? "");
            if (!ok) { await ShowError("Error: " + err); return false; }
        }
        else
        {
            if (IssueList.SelectedItem is not JiraIssue selected)
            {
                await ShowError("Seleccioná un issue.");
                return false;
            }
            var (ok, err) = await _store.CreateWorklogAsync(selected.Key, start, durSec, CommentBox.Text ?? "");
            if (!ok) { await ShowError("Error: " + err); return false; }
        }
        Mutated = true;
        return true;
    }

    private async Task ShowError(string msg)
    {
        var dlg = new ContentDialog
        {
            Title = "Worklog",
            Content = msg,
            CloseButtonText = "OK",
            XamlRoot = this.XamlRoot
        };
        await dlg.ShowAsync();
    }

    private static string FormatDur(int sec)
    {
        int h = sec / 3600, m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return $"{h}h {m}m";
        if (h > 0) return $"{h}h";
        return $"{m}m";
    }

    private void ApplyModalSize(AppSettings s)
    {
        // Clamp to the configured window size − margin so the dialog
        // never overflows on small screens.
        const int margin = 80;
        BodyGrid.Width = Math.Clamp(s.ModalWidth, 360, Math.Max(360, s.WindowWidth - margin));
        BodyGrid.Height = Math.Clamp(s.ModalHeight, 280, Math.Max(280, s.WindowHeight - margin));
    }
}
