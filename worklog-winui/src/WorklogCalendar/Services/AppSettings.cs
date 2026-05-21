using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace WorklogCalendar.Services;

/// <summary>
/// Strongly-typed user settings. Persisted as JSON under
/// %LOCALAPPDATA%\WorklogCalendar\settings.json. Equivalent of the kcfg file
/// (categorizedtodorc) in the KDE plasmoid.
/// </summary>
public sealed class AppSettings : INotifyPropertyChanged
{
    // -------- Jira --------
    public string JiraSite { get; set; } = "";
    public string JiraEmail { get; set; } = "";
    public string JiraToken { get; set; } = "";
    public string JiraIssueJql { get; set; } =
        "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC";
    public int JiraIssueMax { get; set; } = 50;
    public bool ShowJiraSummary { get; set; } = false;
    public bool JiraDebug { get; set; } = true;

    // -------- Clockify --------
    public string ClockifyApiKey { get; set; } = "";
    public string ClockifyWorkspaceId { get; set; } = "";
    public string ClockifyUserId { get; set; } = "";
    public string ClockifyDefaultProjectId { get; set; } = "";
    public bool ClockifyBillableDefault { get; set; } = true;
    public bool ClockifyDebug { get; set; } = true;

    // -------- View / behaviour --------
    /// <summary>"9h" (09:00-18:00) or "24h" (00:00-24:00).</summary>
    public string ViewMode { get; set; } = "9h";
    /// <summary>"jira", "clockify" or "jira-clockify" (split).</summary>
    public string Source { get; set; } = "jira";
    public double DailyTargetHours { get; set; } = 8;
    public int WindowWidth { get; set; } = 1280;
    public int WindowHeight { get; set; } = 760;
    public bool AlwaysOnTop { get; set; } = false;
    /// <summary>Week start day. 0 = Sunday, 1 = Monday. Default 0 to match the plasmoid.</summary>
    public int FirstDayOfWeek { get; set; } = 0;

    // Events aren't serialized by System.Text.Json — no [JsonIgnore] needed
    // (and [JsonIgnore] would fail to compile on an event anyway).
    public event PropertyChangedEventHandler? PropertyChanged;
    public void Raise([CallerMemberName] string name = "") =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public static class SettingsService
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static string ConfigDir
    {
        get
        {
            var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(root, "WorklogCalendar");
        }
    }

    public static string SettingsPath => Path.Combine(ConfigDir, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                var loaded = JsonSerializer.Deserialize<AppSettings>(json, JsonOpts);
                if (loaded != null) return loaded;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Settings] load failed: {ex.Message}");
        }
        return new AppSettings();
    }

    public static void Save(AppSettings s)
    {
        try
        {
            Directory.CreateDirectory(ConfigDir);
            File.WriteAllText(SettingsPath, JsonSerializer.Serialize(s, JsonOpts));
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Settings] save failed: {ex.Message}");
        }
    }
}
