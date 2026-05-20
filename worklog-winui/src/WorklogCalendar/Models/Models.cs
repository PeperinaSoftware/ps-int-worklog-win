using System.Collections.Generic;

namespace WorklogCalendar.Models;

/// <summary>One Jira worklog as rendered on the calendar.</summary>
public sealed class JiraWorklog
{
    public string Id { get; set; } = "";
    public string IssueId { get; set; } = "";
    public string IssueKey { get; set; } = "";
    public string IssueSummary { get; set; } = "";
    public long StartedUnixMs { get; set; }
    public int DurationSec { get; set; }
    public string Comment { get; set; } = "";
}

/// <summary>Issue in the picker shown by the Jira "new worklog" dialog.</summary>
public sealed class JiraIssue
{
    public string Key { get; set; } = "";
    public string Summary { get; set; } = "";
    public string IssueType { get; set; } = "";
    public string Status { get; set; } = "";
    public string Display => $"{Key} — {Summary}";
}

/// <summary>One Clockify time entry as rendered on the calendar.</summary>
public sealed class ClockifyEntry
{
    public string Id { get; set; } = "";
    public long StartedUnixMs { get; set; }
    public int DurationSec { get; set; }
    public string Description { get; set; } = "";
    public string ProjectId { get; set; } = "";
    public string ProjectName { get; set; } = "";
    public string ProjectColor { get; set; } = "";
    public List<string> TagIds { get; set; } = new();
    public List<string> TagNames { get; set; } = new();
    public bool Billable { get; set; }
}

public sealed class ClockifyProject
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Color { get; set; } = "";
    public bool Billable { get; set; }
    public string DisplayName => string.IsNullOrEmpty(Name) ? "(sin nombre)" : Name;
}

public sealed class ClockifyTag
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
}
