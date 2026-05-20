using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using WorklogCalendar.Models;

namespace WorklogCalendar.Services;

/// <summary>
/// Port of <c>JiraWorklogStore.qml</c>. Talks to Jira Cloud REST v3:
///   - GET    /rest/api/3/myself                 (resolve accountId)
///   - GET    /rest/api/3/search/jql             (week worklogs + picker)
///   - POST/PUT/DELETE /rest/api/3/issue/&lt;key&gt;/worklog[/&lt;id&gt;]
/// Auth: HTTP Basic with email + API token.
/// </summary>
public sealed class JiraWorklogStore : INotifyPropertyChanged
{
    private readonly AppSettings _settings;
    private readonly HttpClient _http;

    public JiraWorklogStore(AppSettings settings)
    {
        _settings = settings;
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    }

    // ----- Public state ----------------------------------------------------

    public IReadOnlyList<JiraWorklog> Worklogs { get; private set; } = Array.Empty<JiraWorklog>();
    public IReadOnlyList<JiraIssue> AssignableIssues { get; private set; } = Array.Empty<JiraIssue>();
    public string MyAccountId { get; private set; } = "";

    private bool _loading;
    public bool Loading { get => _loading; private set { _loading = value; Raise(); } }

    private string _lastError = "";
    public string LastError { get => _lastError; private set { _lastError = value; Raise(); } }

    public DateTime LastFetchedAt { get; private set; } = DateTime.MinValue;
    public DateTime CurrentWeekStart { get; private set; }

    private readonly StringBuilder _log = new();
    public string DebugLog => _log.ToString();
    public bool HasDebugLog => _log.Length > 0;

    public int TotalCount => Worklogs.Count;

    // ----- Public API ------------------------------------------------------

    public async Task<bool> FetchWeekAsync(DateTime weekStart)
    {
        if (Loading) { Warn("[abort] ya hay un fetch en curso."); return false; }
        if (!HasCredentials(out var creds))
        {
            LastError = "Faltan credenciales (sitio, email o token). Configurá la pestaña Jira.";
            return false;
        }

        AppendDebug($"=== Worklog fetch {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===\n");
        CurrentWeekStart = weekStart.Date;
        var weekEnd = CurrentWeekStart.AddDays(7);

        Loading = true;
        LastError = "";
        try
        {
            if (string.IsNullOrEmpty(MyAccountId))
            {
                Log("GET /rest/api/3/myself (cacheamos accountId)");
                var (code, body) = await SendAsync("GET", $"{creds.Site}/rest/api/3/myself", null);
                if (code != 200)
                {
                    LastError = $"No se pudo obtener el usuario actual (HTTP {code}).";
                    Warn($"myself exit={code}: {Trim(body, 200)}");
                    return false;
                }
                try
                {
                    using var d = JsonDocument.Parse(body);
                    MyAccountId = d.RootElement.TryGetProperty("accountId", out var a) ? (a.GetString() ?? "") : "";
                    Log($"accountId = {MyAccountId}");
                }
                catch (Exception ex)
                {
                    LastError = "Respuesta inválida de /myself.";
                    Warn("parse myself: " + ex.Message);
                    return false;
                }
            }

            var jql = $"worklogAuthor = currentUser() AND worklogDate >= \"{FormatJqlDate(CurrentWeekStart)}\" AND worklogDate <= \"{FormatJqlDate(weekEnd.AddDays(-1))}\"";
            var url = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql)}&maxResults=200&fields=summary,worklog";
            Log("GET " + url);
            var (code2, body2) = await SendAsync("GET", url, null);
            if (code2 != 200)
            {
                LastError = $"HTTP {code2} al buscar issues con worklogs.";
                Warn($"search exit={code2}: {Trim(body2, 300)}");
                return false;
            }
            return ProcessWeekResponse(body2, CurrentWeekStart, weekEnd);
        }
        catch (Exception ex)
        {
            LastError = "Error de red: " + ex.Message;
            Warn("FetchWeek exception: " + ex);
            return false;
        }
        finally
        {
            Loading = false;
            LastFetchedAt = DateTime.Now;
        }
    }

    private bool ProcessWeekResponse(string body, DateTime weekStart, DateTime weekEnd)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var out_ = new List<JiraWorklog>();
            if (root.TryGetProperty("issues", out var issues) && issues.ValueKind == JsonValueKind.Array)
            {
                long startMs = ToUnixMs(weekStart);
                long endMs = ToUnixMs(weekEnd);
                foreach (var iss in issues.EnumerateArray())
                {
                    string issueId = iss.TryGetProperty("id", out var idE) ? idE.GetString() ?? "" : "";
                    string issueKey = iss.TryGetProperty("key", out var keyE) ? keyE.GetString() ?? "" : "";
                    string summary = "";
                    if (iss.TryGetProperty("fields", out var fields))
                    {
                        if (fields.TryGetProperty("summary", out var sE)) summary = sE.GetString() ?? "";
                        if (fields.TryGetProperty("worklog", out var wlC) &&
                            wlC.TryGetProperty("worklogs", out var wlA) &&
                            wlA.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var w in wlA.EnumerateArray())
                            {
                                long started = ParseJiraDate(w.TryGetProperty("started", out var stE) ? stE.GetString() ?? "" : "");
                                if (started < startMs || started >= endMs) continue;
                                if (!string.IsNullOrEmpty(MyAccountId) && w.TryGetProperty("author", out var au))
                                {
                                    var aid = au.TryGetProperty("accountId", out var aidE) ? aidE.GetString() ?? "" : "";
                                    if (!string.IsNullOrEmpty(aid) && aid != MyAccountId) continue;
                                }
                                int dur = w.TryGetProperty("timeSpentSeconds", out var dE) ? dE.GetInt32() : 0;
                                string wid = w.TryGetProperty("id", out var widE) ? widE.GetString() ?? "" : "";
                                string comment = "";
                                if (w.TryGetProperty("comment", out var cE)) comment = ExtractAdfText(cE);
                                out_.Add(new JiraWorklog
                                {
                                    Id = wid, IssueId = issueId, IssueKey = issueKey, IssueSummary = summary,
                                    StartedUnixMs = started, DurationSec = dur, Comment = comment
                                });
                            }
                        }
                    }
                }
            }
            out_.Sort((a, b) => a.StartedUnixMs.CompareTo(b.StartedUnixMs));
            Worklogs = out_;
            Log($"Recibí {out_.Count} worklog(s) propios en la semana.");
            Raise(nameof(Worklogs));
            Raise(nameof(TotalCount));
            return true;
        }
        catch (Exception ex)
        {
            LastError = "Error parseando la respuesta: " + ex.Message;
            Warn("parse: " + ex);
            return false;
        }
    }

    public async Task<bool> FetchAssignableIssuesAsync()
    {
        if (!HasCredentials(out var creds)) return false;
        var jql = string.IsNullOrWhiteSpace(_settings.JiraIssueJql)
            ? "assignee = currentUser() AND statusCategory != Done"
            : _settings.JiraIssueJql.Trim();
        var max = Math.Clamp(_settings.JiraIssueMax, 10, 200);
        var url = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql)}&maxResults={max}&fields=summary,status,issuetype";
        Log("Picker GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"Picker exit={code}: {Trim(body, 200)}"); return false; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            var list = new List<JiraIssue>();
            if (doc.RootElement.TryGetProperty("issues", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var r in arr.EnumerateArray())
                {
                    var it = new JiraIssue
                    {
                        Key = r.TryGetProperty("key", out var kE) ? kE.GetString() ?? "" : ""
                    };
                    if (r.TryGetProperty("fields", out var f))
                    {
                        it.Summary = f.TryGetProperty("summary", out var sE) ? sE.GetString() ?? "" : "";
                        if (f.TryGetProperty("issuetype", out var tE) &&
                            tE.TryGetProperty("name", out var tnE)) it.IssueType = tnE.GetString() ?? "";
                        if (f.TryGetProperty("status", out var stE) &&
                            stE.TryGetProperty("name", out var snE)) it.Status = snE.GetString() ?? "";
                    }
                    list.Add(it);
                }
            }
            AssignableIssues = list;
            Raise(nameof(AssignableIssues));
            Log($"Picker: {list.Count} issue(s).");
            return true;
        }
        catch (Exception ex)
        {
            Warn("Picker parse: " + ex);
            return false;
        }
    }

    public async Task<(bool ok, string err)> CreateWorklogAsync(string issueKey, DateTime started, int durationSec, string comment)
    {
        if (!HasCredentials(out var creds)) return (false, "Faltan credenciales.");
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}/worklog";
        var body = BuildWorklogBody(started, durationSec, comment);
        Log("POST " + url + " body=" + body);
        var (code, resp) = await SendAsync("POST", url, body);
        if (code is 200 or 201) { Log("create OK."); return (true, ""); }
        var msg = ExtractError(resp);
        Warn($"create exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    public async Task<(bool ok, string err)> UpdateWorklogAsync(string issueKey, string worklogId, DateTime started, int durationSec, string comment)
    {
        if (!HasCredentials(out var creds)) return (false, "Faltan credenciales.");
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}/worklog/{Uri.EscapeDataString(worklogId)}";
        var body = BuildWorklogBody(started, durationSec, comment);
        Log("PUT " + url + " body=" + body);
        var (code, resp) = await SendAsync("PUT", url, body);
        if (code == 200) { Log("update OK."); return (true, ""); }
        var msg = ExtractError(resp);
        Warn($"update exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    public async Task<(bool ok, string err)> DeleteWorklogAsync(string issueKey, string worklogId)
    {
        if (!HasCredentials(out var creds)) return (false, "Faltan credenciales.");
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}/worklog/{Uri.EscapeDataString(worklogId)}";
        Log("DELETE " + url);
        var (code, resp) = await SendAsync("DELETE", url, null);
        if (code is 200 or 204) { Log("delete OK."); return (true, ""); }
        var msg = ExtractError(resp);
        Warn($"delete exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    // ----- Helpers ---------------------------------------------------------

    private record Creds(string Site, string Email, string Token);

    private bool HasCredentials(out Creds creds)
    {
        var site = (_settings.JiraSite ?? "").Trim().TrimEnd('/');
        var email = (_settings.JiraEmail ?? "").Trim();
        var token = (_settings.JiraToken ?? "").Trim();
        if (site.Length == 0 || email.Length == 0 || token.Length == 0)
        {
            creds = new Creds("", "", "");
            return false;
        }
        creds = new Creds(site, email, token);
        return true;
    }

    private async Task<(int code, string body)> SendAsync(string method, string url, string? body)
    {
        if (!HasCredentials(out var creds)) return (0, "");
        using var req = new HttpRequestMessage(new HttpMethod(method), url);
        var auth = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{creds.Email}:{creds.Token}"));
        req.Headers.Authorization = new AuthenticationHeaderValue("Basic", auth);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (body != null) req.Content = new StringContent(body, Encoding.UTF8, "application/json");
        try
        {
            using var resp = await _http.SendAsync(req);
            var text = await resp.Content.ReadAsStringAsync();
            return ((int)resp.StatusCode, text);
        }
        catch (Exception ex)
        {
            Warn("http: " + ex.Message);
            return (0, "");
        }
    }

    private static string BuildWorklogBody(DateTime started, int durationSec, string comment)
    {
        // Jira wants "2026-05-12T15:00:00.000+0000".
        var off = TimeZoneInfo.Local.GetUtcOffset(started);
        string sign = off >= TimeSpan.Zero ? "+" : "-";
        int absMin = (int)Math.Abs(off.TotalMinutes);
        string startedIso = started.ToString("yyyy-MM-ddTHH:mm:ss.fff") + sign + (absMin / 60).ToString("00") + (absMin % 60).ToString("00");

        var obj = new Dictionary<string, object?>
        {
            ["started"] = startedIso,
            ["timeSpentSeconds"] = durationSec,
        };
        if (!string.IsNullOrEmpty(comment))
        {
            obj["comment"] = new
            {
                type = "doc",
                version = 1,
                content = new[]
                {
                    new { type = "paragraph", content = new[] { new { type = "text", text = comment } } }
                }
            };
        }
        return JsonSerializer.Serialize(obj);
    }

    private static string FormatJqlDate(DateTime d) => d.ToString("yyyy-MM-dd");

    private static long ParseJiraDate(string s)
    {
        if (string.IsNullOrEmpty(s)) return 0;
        if (DateTimeOffset.TryParse(s, out var dto)) return dto.ToUnixTimeMilliseconds();
        return 0;
    }

    private static long ToUnixMs(DateTime localDate)
    {
        var dt = DateTime.SpecifyKind(localDate, DateTimeKind.Local);
        return new DateTimeOffset(dt).ToUnixTimeMilliseconds();
    }

    private static string ExtractAdfText(JsonElement adf)
    {
        if (adf.ValueKind == JsonValueKind.String) return adf.GetString() ?? "";
        if (adf.ValueKind != JsonValueKind.Object) return "";
        if (adf.TryGetProperty("type", out var tE))
        {
            var type = tE.GetString();
            if (type == "text" && adf.TryGetProperty("text", out var txt)) return txt.GetString() ?? "";
        }
        if (adf.TryGetProperty("content", out var cArr) && cArr.ValueKind == JsonValueKind.Array)
        {
            var sb = new StringBuilder();
            foreach (var ch in cArr.EnumerateArray())
            {
                sb.Append(ExtractAdfText(ch));
                if (ch.TryGetProperty("type", out var ct) && ct.GetString() == "paragraph") sb.Append('\n');
            }
            return sb.ToString();
        }
        return "";
    }

    private static string ExtractError(string body)
    {
        if (string.IsNullOrEmpty(body)) return "";
        try
        {
            using var d = JsonDocument.Parse(body);
            if (d.RootElement.TryGetProperty("errorMessages", out var em) && em.ValueKind == JsonValueKind.Array)
            {
                var parts = new List<string>();
                foreach (var v in em.EnumerateArray()) parts.Add(v.GetString() ?? "");
                if (parts.Count > 0) return string.Join("; ", parts);
            }
            if (d.RootElement.TryGetProperty("errors", out var er) && er.ValueKind == JsonValueKind.Object)
            {
                var parts = new List<string>();
                foreach (var p in er.EnumerateObject()) parts.Add($"{p.Name}: {p.Value}");
                if (parts.Count > 0) return string.Join("; ", parts);
            }
            if (d.RootElement.TryGetProperty("message", out var msg)) return msg.GetString() ?? "";
        }
        catch { /* not json */ }
        return Trim(body, 240);
    }

    private static string Trim(string s, int n) => s.Length <= n ? s : s.Substring(0, n);

    // ----- Logging ---------------------------------------------------------

    public void ClearDebugLog() { _log.Clear(); Raise(nameof(DebugLog)); Raise(nameof(HasDebugLog)); }

    private void Log(string msg)
    {
        AppendDebug(msg + "\n");
        if (_settings.JiraDebug) System.Diagnostics.Debug.WriteLine("[JiraWorklog] " + msg);
    }
    private void Warn(string msg)
    {
        AppendDebug("[!] " + msg + "\n");
        System.Diagnostics.Debug.WriteLine("[JiraWorklog] " + msg);
    }
    private void AppendDebug(string s)
    {
        const int max = 80000;
        if (_log.Length + s.Length > max)
        {
            var keep = _log.ToString().Substring(_log.Length / 2);
            _log.Clear();
            _log.Append("[…log truncado…]\n").Append(keep);
        }
        _log.Append(s);
        Raise(nameof(DebugLog));
        Raise(nameof(HasDebugLog));
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string name = "") =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
