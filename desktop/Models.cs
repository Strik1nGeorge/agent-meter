using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace AgentHud
{
    public class Snapshot
    {
        public List<Provider> providers { get; set; }
        public double? collectedAt { get; set; }
        public bool loading { get; set; }
    }
    public class Provider
    {
        public string id { get; set; }
        public string name { get; set; }
        public bool connected { get; set; }
        public bool bridgeConnected { get; set; }
        public string quotaStatus { get; set; }
        public string quotaMessage { get; set; }
        public Limits limits { get; set; }
        public Activity activity { get; set; }
    }
    // What the platform's agents are doing now (from lib/activity.mjs): drives the pets and the hover card.
    public class Activity
    {
        public bool working { get; set; }
        public int activeSessions { get; set; }
        public double todayTokens { get; set; }
        public int todayRequests { get; set; }
        public double? lastActiveAt { get; set; }
        public string model { get; set; }
        public string effort { get; set; }
    }
    public class Limits
    {
        public string plan { get; set; }
        public List<QuotaWindow> windows { get; set; }
        public double? collectedAt { get; set; }
        public string source { get; set; }
        public double? staleAfterMs { get; set; }
        public bool stale { get; set; }
    }
    public class QuotaWindow
    {
        public string id { get; set; }
        public string name { get; set; }
        public double? remainingPercent { get; set; }
        public double? windowMinutes { get; set; }
        public double? resetsAt { get; set; }
    }
    public class WidgetState
    {
        public double? left { get; set; }
        public double? top { get; set; }
        public string monitor { get; set; }
        public double? offsetX { get; set; }
        public double? offsetY { get; set; }
        public bool pinned { get; set; }
        // "auto" (follow Windows), "zh" or "en".
        public string language { get; set; }
        // "left" / "right" when docked to that side of the screen (vertical layout); null otherwise.
        public string dock { get; set; }
        public WidgetState() { pinned = true; language = "auto"; }
    }
    // One platform's rings. The outer ring is its shortest window (5 hours on most plans); the thinner inner
    // ring is the account-wide window after it (7 days), when the plan has one. The middle of the ring shows
    // whichever has less left, since that is the one that runs out first.
    public class RingSet
    {
        public RingValue Outer, Inner;
        public bool CenterInner;
        public RingValue Center { get { return CenterInner ? Inner : Outer; } }
    }
    public static class RingStatus
    {
        // Language-independent states; the label picks its words from these, never from Caption.
        public const string Waiting = "waiting", Setup = "setup", NotLinked = "not-linked", Unavailable = "unavailable", Expired = "expired", Live = "live";
    }
    public class RingValue
    {
        public double? Percent;
        public double? ResetsAt;
        public bool Stale;
        public string Status = RingStatus.Waiting;
        // The window's name ("5 小时" / "5 hours"), when there is one.
        public string Name;
        public string Caption;
        public string Detail;
        public static double Now() { return (DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalMilliseconds; }
        static readonly DateTime Epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        static readonly string[] WeekDaysZh = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" };
        static readonly string[] WeekDaysEn = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

        public static RingSet Rings(Provider provider, double now, bool online)
        {
            var windows = provider == null || provider.limits == null ? null : provider.limits.windows;
            var outer = OuterWindow(windows);
            var inner = InnerWindow(windows, outer);
            var set = new RingSet { Outer = ForWindow(provider, outer, now, online), Inner = inner == null ? null : ForWindow(provider, inner, now, online) };
            // A number beats a status word in the middle; between two numbers the lower one goes there.
            set.CenterInner = set.Inner != null && set.Inner.Percent.HasValue && (!set.Outer.Percent.HasValue || set.Inner.Percent.Value < set.Outer.Percent.Value);
            return set;
        }

        static RingValue ForWindow(Provider provider, QuotaWindow win, double now, bool online)
        {
            var result = new RingValue { Caption = Lang.T("等待数据", "Waiting for data"), Detail = Lang.T("等待平台提供额度，未将未知值当作零。", "Waiting for the platform to report its quota; an unknown value is never treated as zero.") };
            if (provider == null) return result;
            var limits = provider.limits;
            if (win == null)
            {
                result.Status = provider.quotaStatus == "desktop-connection-disabled" ? RingStatus.Setup : provider.quotaStatus == "desktop-not-connected" ? RingStatus.NotLinked : RingStatus.Unavailable;
                result.Caption = result.Status == RingStatus.Setup ? Lang.T("等待连接", "Connection not enabled") : result.Status == RingStatus.NotLinked ? Lang.T("桌面版未接入", "Desktop app not linked") : Lang.T("额度未提供", "Quota not provided");
                result.Detail = Lang.Server(provider.quotaMessage) ?? Lang.T("这个平台还没有提供额度。可打开完整面板查看接入状态。", "This platform hasn't reported a quota yet. Open the dashboard to check the connection.");
                result.Detail += "\n" + UpdatedText(limits == null ? null : limits.collectedAt, now);
                result.Detail += provider.id == "claude" ? Lang.T("\n点 ⋯ → Claude 官方用量，查看当前账户额度。", "\n⋯ → Claude usage shows this account's quota.") : Lang.T("\n点 ⋯ → Codex 官方用量，查看当前账户额度。", "\n⋯ → Codex usage shows this account's quota.");
                return result;
            }
            result.Name = WindowName(win);
            var weekly = WeeklyBlocker(limits, win, now);
            if (weekly == null && win.resetsAt.HasValue && win.resetsAt.Value <= now)
            {
                result.Status = RingStatus.Expired;
                result.Caption = Lang.T("等待额度重置", "Waiting for reset");
                result.Detail = Lang.T("上次快照的重置时间已过，等待新数据；不会自动显示 100%。\n", "The last snapshot's reset time has passed; waiting for new data instead of assuming 100%.\n") + UpdatedText(limits.collectedAt, now);
                return result;
            }
            result.Status = RingStatus.Live;
            result.Percent = weekly == null ? Math.Max(0, Math.Min(100, win.remainingPercent.Value)) : 0;
            result.ResetsAt = EffectiveReset(win, weekly, now);
            result.Stale = limits.stale || !online || !limits.collectedAt.HasValue || now - limits.collectedAt.Value > (limits.staleAfterMs ?? 120000);
            result.Caption = result.ResetsAt.HasValue ? ResetText(result.ResetsAt.Value - now) : Lang.T("重置时间未提供", "Reset time not provided");
            var resetDate = result.ResetsAt.HasValue ? LocalTime(result.ResetsAt.Value) : null;
            var resetStamp = resetDate.HasValue ? Lang.T("（" + resetDate.Value.ToString("MM-dd HH:mm") + "）", " (" + resetDate.Value.ToString("MM-dd HH:mm") + ")") : "";
            result.Detail = (Lang.Server(limits.source) ?? Lang.T("平台额度", "Platform quota")) + "\n" + UpdatedText(limits.collectedAt, now) + "\n" + (result.Stale ? Lang.T("历史快照 · ", "Snapshot · ") : "") + result.Caption + resetStamp;
            if (limits.source == "Codex 官方额度接口") result.Detail += Lang.T("\n正常约每 1 分钟查询，连接失败时可能延迟。", "\nNormally queried about once a minute; may lag when the connection fails.");
            else if (limits.source == "Claude 桌面账户额度") result.Detail += Lang.T("\n正常约每 5 分钟查询，连接失败时可能延迟。", "\nNormally queried about every 5 minutes; may lag when the connection fails.");
            result.Detail += Lang.T("\n同一平台账户内共享，非单个 agent 的独立额度。", "\nShared across the platform account, not a per-agent quota.");
            if (weekly != null) result.Detail += "\n" + WeeklyBlockedText(win);
            if (!String.IsNullOrEmpty(provider.quotaMessage)) result.Detail += "\n" + Lang.Server(provider.quotaMessage);
            if (result.Stale) result.Caption = Lang.T("快照 · ", "Snapshot · ") + result.Caption;
            return result;
        }
        // Only the account-wide weekly window blocks its 5-hour allowance. Model-specific
        // windows (for example Opus) and snapshots past their reset cannot block the account.
        public static QuotaWindow WeeklyBlocker(Limits limits, QuotaWindow window, double now)
        {
            if (window == null || window.windowMinutes != 300 || limits == null || limits.windows == null) return null;
            return limits.windows.FirstOrDefault(w => w != null && w.windowMinutes == 10080 && AccountWide(w)
                && w.remainingPercent.HasValue && !Double.IsInfinity(w.remainingPercent.Value) && w.remainingPercent.Value <= 0
                && (!w.resetsAt.HasValue || w.resetsAt.Value > now));
        }
        // Windows for the whole account, not one model's (Claude's "Opus · 7 天", Codex's per-model buckets).
        static bool AccountWide(QuotaWindow w)
        {
            return (String.IsNullOrEmpty(w.id) || w.id == "five_hour" || w.id == "seven_day") && (String.IsNullOrEmpty(w.name) || !w.name.Contains("·"));
        }
        public static double? EffectiveReset(QuotaWindow window, QuotaWindow weekly, double now)
        {
            if (weekly == null) return window.resetsAt;
            if (window.remainingPercent <= 0 && (!window.resetsAt.HasValue || window.resetsAt > now))
                return window.resetsAt.HasValue && weekly.resetsAt.HasValue ? Math.Max(window.resetsAt.Value, weekly.resetsAt.Value) : (double?)null;
            return weekly.resetsAt;
        }
        public static string WeeklyBlockedText(QuotaWindow window)
        {
            var note = Lang.T("周额度已用尽，5 小时可用额度为 0%。", "Weekly quota exhausted; available 5-hour quota is 0%.");
            if (window.remainingPercent.HasValue)
            {
                var raw = Math.Max(0, Math.Min(100, window.remainingPercent.Value)).ToString("0.#", CultureInfo.InvariantCulture);
                note += Lang.T("平台 5 小时原始剩余：" + raw + "%（未计入周限制）。", " Platform-reported 5-hour remaining: " + raw + "% (before the weekly limit).");
            }
            return note;
        }
        // Plans differ: most report 5 h and 7 d, the free plan one 30-day window. The outer ring takes the
        // shortest account-wide window (any window, if the plan only has model-specific ones), the inner ring
        // the next longer account-wide one.
        public static QuotaWindow OuterWindow(List<QuotaWindow> windows)
        {
            var usable = Usable(windows);
            return usable.Where(AccountWide).OrderBy(w => w.windowMinutes).FirstOrDefault() ?? usable.OrderBy(w => w.windowMinutes).FirstOrDefault();
        }
        public static QuotaWindow InnerWindow(List<QuotaWindow> windows, QuotaWindow outer)
        {
            if (outer == null) return null;
            return Usable(windows).Where(w => AccountWide(w) && w.windowMinutes > outer.windowMinutes).OrderBy(w => w.windowMinutes).FirstOrDefault();
        }
        // A window can go in a ring once it has a real percentage and a length.
        static List<QuotaWindow> Usable(List<QuotaWindow> windows)
        {
            if (windows == null) return new List<QuotaWindow>();
            return windows.Where(w => w != null && w.remainingPercent.HasValue && !Double.IsNaN(w.remainingPercent.Value) && !Double.IsInfinity(w.remainingPercent.Value) && w.windowMinutes > 0).ToList();
        }
        // The service's name for a window, or one made from its length.
        public static string WindowName(QuotaWindow window)
        {
            var name = Lang.Server(window.name);
            if (name != null) return name;
            if (!window.windowMinutes.HasValue || window.windowMinutes.Value <= 0) return Lang.T("额度", "Quota");
            var m = window.windowMinutes.Value;
            if (m % 1440 == 0) return Lang.T(m / 1440 + " 天", m / 1440 + (m == 1440 ? " day" : " days"));
            if (m % 60 == 0) return Lang.T(m / 60 + " 小时", m / 60 + (m == 60 ? " hour" : " hours"));
            return Lang.T(m + " 分钟", m + " min");
        }
        public static string UpdatedText(double? collectedAt, double now)
        {
            if (!collectedAt.HasValue) return Lang.T("额度更新时间未知", "Quota update time unknown");
            var stamp = collectedAt.Value;
            if (Double.IsNaN(stamp) || Double.IsInfinity(stamp) || stamp > now + 60000) return Lang.T("额度更新时间异常，请检查系统时间", "Quota update time looks wrong; check the system clock");
            try
            {
                var date = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(stamp).ToLocalTime();
                var minutes = Math.Floor(Math.Max(0, now - stamp) / 60000);
                var age = minutes < 1 ? Lang.T("刚刚", "just now")
                    : minutes < 60 ? Lang.T(minutes + " 分钟前", minutes + " min ago")
                    : minutes < 1440 ? Lang.T(Math.Floor(minutes / 60) + " 小时前", Math.Floor(minutes / 60) + " h ago")
                    : Lang.T(Math.Floor(minutes / 1440) + " 天前", Math.Floor(minutes / 1440) + " d ago");
                return Lang.T("额度更新：" + age + "（" + date.ToString("MM-dd HH:mm") + "）", "Quota updated " + age + " (" + date.ToString("MM-dd HH:mm") + ")");
            }
            catch (ArgumentOutOfRangeException) { return Lang.T("额度更新时间未知", "Quota update time unknown"); }
        }
        static DateTime? LocalTime(double stamp)
        {
            if (Double.IsNaN(stamp) || Double.IsInfinity(stamp)) return null;
            try { return Epoch.AddMilliseconds(stamp).ToLocalTime(); }
            catch (ArgumentOutOfRangeException) { return null; }
        }
        // Shortest form, for inside the ring (about 30 DIP across): the clock time within a day, the weekday
        // within the coming week, otherwise the date. The countdown and full date are in the hover card.
        public static string RingBadge(double resetsAt, double now)
        {
            var reset = LocalTime(resetsAt);
            if (!reset.HasValue || resetsAt <= now) return null;
            if (resetsAt - now < 86400000) return reset.Value.ToString("HH:mm", CultureInfo.InvariantCulture);
            // A weekday is only unambiguous within the next six days; a 7-day window's same-weekday reset gets its date.
            if ((reset.Value.Date - LocalTime(now).Value.Date).TotalDays < 7) { var day = (int)reset.Value.DayOfWeek; return Lang.T(WeekDaysZh[day], WeekDaysEn[day]); }
            return reset.Value.ToString("M/d", CultureInfo.InvariantCulture);
        }
        public static string Stamp(double time)
        {
            var date = LocalTime(time);
            return date.HasValue ? date.Value.ToString("MM-dd HH:mm", CultureInfo.InvariantCulture) : "";
        }
        public static string ResetText(double milliseconds)
        {
            var minutes = (long)Math.Ceiling(Math.Max(0, milliseconds) / 60000);
            if (minutes >= 1440) return Lang.T(String.Format("{0}天 {1}小时后重置", minutes / 1440, (minutes % 1440) / 60), String.Format("Resets in {0}d {1}h", minutes / 1440, (minutes % 1440) / 60));
            if (minutes >= 60) return Lang.T(String.Format("{0}小时 {1}分后重置", minutes / 60, minutes % 60), String.Format("Resets in {0}h {1}m", minutes / 60, minutes % 60));
            return Lang.T(String.Format("{0}分钟后重置", minutes), String.Format("Resets in {0} min", minutes));
        }
    }
}
