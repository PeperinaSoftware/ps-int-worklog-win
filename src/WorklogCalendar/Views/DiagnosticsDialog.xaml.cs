using Microsoft.UI.Xaml.Controls;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

public sealed partial class DiagnosticsDialog : ContentDialog
{
    private readonly JiraWorklogStore _jira;
    private readonly ClockifyStore _clockify;

    public DiagnosticsDialog(JiraWorklogStore jira, ClockifyStore clockify)
    {
        this.InitializeComponent();
        _jira = jira;
        _clockify = clockify;
        Refresh();
        SecondaryButtonClick += (s, e) =>
        {
            e.Cancel = true; // don't close
            _jira.ClearDebugLog();
            _clockify.ClearDebugLog();
            Refresh();
        };
    }

    private void Refresh()
    {
        var j = _jira.HasDebugLog ? _jira.DebugLog : "(vacío)";
        var c = _clockify.HasDebugLog ? _clockify.DebugLog : "(vacío)";
        if (!_jira.HasDebugLog && !_clockify.HasDebugLog)
            LogBox.Text = "Sin datos. Pulsá Sincronizar para empezar.";
        else
            LogBox.Text = $"---- JIRA ----\n{j}\n\n---- CLOCKIFY ----\n{c}";
    }
}
