using System;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace AgentHud
{
    // Remaining quota in the platform's own colours. The outer ring is the platform's shortest window
    // (5 hours on most plans); a longer account-wide window (7 days) is a thinner ring inside it. The middle
    // shows whichever has less left, with its reset time under it. The pet beside the ring names the platform.
    public class QuotaRing : FrameworkElement
    {
        // Animated stand-ins for the two percentages, so the arcs move to new values instead of jumping.
        public static readonly DependencyProperty DisplayProperty = DependencyProperty.Register("Display", typeof(double), typeof(QuotaRing), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));
        public static readonly DependencyProperty DisplayInnerProperty = DependencyProperty.Register("DisplayInner", typeof(double), typeof(QuotaRing), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));
        public double Display { get { return (double)GetValue(DisplayProperty); } set { SetValue(DisplayProperty, value); } }
        public double DisplayInner { get { return (double)GetValue(DisplayInnerProperty); } set { SetValue(DisplayInnerProperty, value); } }
        public const double Diameter = 44;
        // The outer stroke, the gap between the rings, and the thinner inner stroke.
        const double OuterThickness = 3, Gap = 1.2, InnerThickness = 2;
        const double OuterRadius = Diameter / 2 - OuterThickness / 2 - 0.4;
        const double InnerRadius = OuterRadius - OuterThickness / 2 - Gap - InnerThickness / 2;
        public Brush ArcBrush { get; set; }
        public Color Track { get; set; }
        // Text on glass stays in the primary colour (grey on glass measures as low as 2.3 : 1);
        // hierarchy comes from size and weight. Red only for a nearly used-up quota, on the number itself.
        public Brush TextBrush { get; set; }
        public Brush LowBrush { get; set; }
        // The outer ring's value, and the inner ring's when there is one.
        public double? Percent { get; private set; }
        public bool Stale { get; private set; }
        public bool HasInner { get; private set; }
        public double? InnerPercent { get; private set; }
        bool innerStale, centerStale;
        double? centerPercent;
        public string Platform { get; set; }
        // What the middle says: "62%" or a status word, and under it the reset time, "离线" or "剩余".
        public string Primary { get; private set; }
        public string Secondary { get; private set; }
        sealed class Stroke { public Pen Track, Arc; public Color TrackColor; public Brush ArcBrush; public bool Unknown; public Geometry Shape; public double Value = Double.NaN; }
        readonly Stroke outer = new Stroke(), inner = new Stroke();
        static readonly Typeface FaceBold = new Typeface(new FontFamily("Segoe UI Variable Display, Segoe UI, Microsoft YaHei UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
        static readonly Typeface FaceRegular = new Typeface(new FontFamily("Segoe UI Variable Display, Segoe UI, Microsoft YaHei UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        static readonly Typeface FaceSmall = new Typeface(new FontFamily("Segoe UI Variable Small, Segoe UI, Microsoft YaHei UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        public QuotaRing() { Width = Diameter; Height = Diameter; }
        // The numbers are drawn, not text elements, so screen readers get them from the ring's own name.
        protected override System.Windows.Automation.Peers.AutomationPeer OnCreateAutomationPeer() { return new RingPeer(this); }
        sealed class RingPeer : System.Windows.Automation.Peers.FrameworkElementAutomationPeer
        {
            public RingPeer(FrameworkElement owner) : base(owner) { }
            protected override System.Windows.Automation.Peers.AutomationControlType GetAutomationControlTypeCore() { return System.Windows.Automation.Peers.AutomationControlType.Text; }
            protected override string GetClassNameCore() { return "QuotaRing"; }
        }

        public void PauseAnimation()
        {
            BeginAnimation(DisplayProperty, null); BeginAnimation(DisplayInnerProperty, null);
            Display = Percent ?? 0; DisplayInner = InnerPercent ?? 0;
        }

        // A single window: one ring.
        public void Update(RingValue value, bool offline) { Update(new RingSet { Outer = value }, offline); }

        public void Update(RingSet set, bool offline)
        {
            var outerValue = set.Outer ?? new RingValue();
            var innerValue = set.Inner;
            var center = set.Center ?? outerValue;
            var innerPercent = innerValue == null ? null : innerValue.Percent;
            var changed = Percent != outerValue.Percent;
            var innerChanged = HasInner != (innerValue != null) || InnerPercent != innerPercent;
            var styleChanged = Stale != outerValue.Stale || innerStale != (innerValue != null && innerValue.Stale) || centerStale != center.Stale || centerPercent != center.Percent;
            Percent = outerValue.Percent; Stale = outerValue.Stale;
            HasInner = innerValue != null; InnerPercent = innerPercent; innerStale = innerValue != null && innerValue.Stale;
            centerPercent = center.Percent; centerStale = center.Stale;
            string primary, secondary;
            if (center.Percent.HasValue)
            {
                primary = Math.Round(center.Percent.Value).ToString(CultureInfo.InvariantCulture) + "%";
                var badge = center.ResetsAt.HasValue ? RingValue.RingBadge(center.ResetsAt.Value, RingValue.Now()) : null;
                // Offline keeps its word; without a reset time the ring just says what the number is.
                secondary = offline ? Lang.T("离线", "Offline") : badge ?? (center.Stale ? Lang.T("快照", "Snapshot") : Lang.T("剩余", "left"));
            }
            else
            {
                primary = offline ? Lang.T("离线", "Offline")
                    : center.Status == RingStatus.Setup ? Lang.T("待连接", "Setup")
                    : center.Status == RingStatus.NotLinked ? Lang.T("未接入", "No link")
                    : center.Status == RingStatus.Expired ? Lang.T("待更新", "Pending")
                    : center.Status == RingStatus.Waiting ? Lang.T("等待", "Waiting")
                    : Lang.T("未提供", "N/A");
                secondary = null;
            }
            var textChanged = primary != Primary || secondary != Secondary;
            Primary = primary; Secondary = secondary;
            // What the middle says, then each ring by name.
            var name = Platform + Lang.T(" 剩余额度 " + primary + (secondary != null ? "，" + secondary : ""), " quota remaining " + primary + (secondary != null ? ", " + secondary : ""));
            if (HasInner) name += Lang.T("；外圈 " + Describe(outerValue) + "，内圈 " + Describe(innerValue), "; outer ring " + Describe(outerValue) + ", inner ring " + Describe(innerValue));
            if (AutomationProperties.GetName(this) != name) AutomationProperties.SetName(this, name);
            if (changed) Animate(DisplayProperty, Percent);
            if (innerChanged) Animate(DisplayInnerProperty, InnerPercent);
            if (changed || innerChanged || styleChanged || textChanged) InvalidateVisual();
        }
        static string Describe(RingValue value)
        {
            var amount = value.Percent.HasValue ? Math.Round(value.Percent.Value).ToString(CultureInfo.InvariantCulture) + "%" : Lang.T("未知", "unknown");
            return String.IsNullOrEmpty(value.Name) ? amount : value.Name + " " + amount;
        }
        // Critically damped: a strong ease-out, no overshoot.
        void Animate(DependencyProperty property, double? target)
        {
            if (IsVisible && target.HasValue && SystemParameters.ClientAreaAnimation)
                BeginAnimation(property, new DoubleAnimation(target.Value, TimeSpan.FromMilliseconds(600)) { EasingFunction = new QuarticEase { EasingMode = EasingMode.EaseOut } });
            else { BeginAnimation(property, null); SetValue(property, target ?? 0); }
        }

        FormattedText Text(string text, Typeface face, double size, Brush brush)
        {
            return new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, size, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        }

        protected override void OnRender(DrawingContext dc)
        {
            base.OnRender(dc);
            const double half = Diameter / 2;
            var middle = new Point(half, half);
            DrawRing(dc, outer, middle, OuterRadius, OuterThickness, Percent, Stale, Display, 1);
            // The inner ring sits a step back, so the two read as one gauge with a secondary scale.
            if (HasInner) DrawRing(dc, inner, middle, InnerRadius, InnerThickness, InnerPercent, innerStale, DisplayInner, 0.8);

            if (TextBrush == null || Primary == null) return;
            // Inside the inner ring everything is a size smaller, to stay clear of it.
            var nested = HasInner;
            if (centerPercent.HasValue)
            {
                // "62" large with a small "%" on the same baseline, the reset time underneath.
                var number = Text(Primary.TrimEnd('%'), centerStale ? FaceRegular : FaceBold, nested ? 11 : 13, centerPercent.Value < 20 && LowBrush != null ? LowBrush : TextBrush);
                var sign = Text("%", FaceRegular, nested ? 6.5 : 7.5, TextBrush);
                var width = number.WidthIncludingTrailingWhitespace + sign.WidthIncludingTrailingWhitespace;
                var top = half - (nested ? 1.2 : 1.5) - number.Height / 2 - (Secondary != null ? (nested ? 3 : 3.5) : 0);
                var left = half - width / 2;
                dc.DrawText(number, new Point(left, top));
                dc.DrawText(sign, new Point(left + number.WidthIncludingTrailingWhitespace, top + number.Baseline - sign.Baseline));
                if (Secondary != null)
                {
                    double room = nested ? 20 : Diameter - 10, size = nested ? 6.6 : 7.2;
                    var under = Text(Secondary, FaceSmall, size, TextBrush);
                    // A long word shrinks a little before it is cut short.
                    if (nested && under.Width > room) under = Text(Secondary, FaceSmall, Math.Max(5.6, size * room / under.Width), TextBrush);
                    under.MaxTextWidth = room; under.MaxLineCount = 1; under.Trimming = TextTrimming.CharacterEllipsis;
                    dc.PushOpacity(0.86);
                    dc.DrawText(under, new Point(half - Math.Min(under.Width, room) / 2, half + (nested ? 3.4 : 4.6)));
                    dc.Pop();
                }
            }
            else
            {
                double room = nested ? 28 : Diameter - 8;
                var status = Text(Primary, FaceRegular, nested ? 7.5 : 8.5, TextBrush);
                status.MaxTextWidth = room; status.MaxLineCount = 1; status.Trimming = TextTrimming.CharacterEllipsis;
                dc.DrawText(status, new Point(half - Math.Min(status.Width, room) / 2, half - status.Height / 2));
            }
        }

        // Track all the way round (dotted while the value is unknown), the arc clockwise from 12 o'clock.
        void DrawRing(DrawingContext dc, Stroke stroke, Point middle, double radius, double thickness, double? percent, bool stale, double display, double emphasis)
        {
            var unknown = !percent.HasValue;
            if (stroke.Track == null || stroke.TrackColor != Track || stroke.Unknown != unknown)
            {
                stroke.Track = new Pen(new SolidColorBrush(Track), thickness);
                if (unknown) { stroke.Track.DashStyle = new DashStyle(new double[] { 0, 1.8 }, 0); stroke.Track.DashCap = PenLineCap.Round; }
                stroke.Track.Freeze(); stroke.TrackColor = Track; stroke.Unknown = unknown;
            }
            dc.DrawEllipse(null, stroke.Track, middle, radius, radius);

            var value = Math.Max(0, Math.Min(100, display));
            if (unknown || value <= 0.05 || ArcBrush == null) return;
            if (stroke.Shape == null || stroke.Value != value)
            {
                if (value >= 99.95) stroke.Shape = new EllipseGeometry(middle, radius, radius);
                else
                {
                    var angle = value / 100 * 2 * Math.PI;
                    var end = new Point(middle.X + radius * Math.Sin(angle), middle.Y - radius * Math.Cos(angle));
                    var geometry = new StreamGeometry();
                    using (var ctx = geometry.Open())
                    {
                        ctx.BeginFigure(new Point(middle.X, middle.Y - radius), false, false);
                        ctx.ArcTo(end, new Size(radius, radius), 0, value > 50, SweepDirection.Clockwise, true, false);
                    }
                    stroke.Shape = geometry;
                }
                stroke.Shape.Freeze(); stroke.Value = value;
            }
            if (stroke.Arc == null || stroke.ArcBrush != ArcBrush)
            {
                stroke.Arc = new Pen(ArcBrush, thickness) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                if (stroke.Arc.CanFreeze) stroke.Arc.Freeze(); stroke.ArcBrush = ArcBrush;
            }
            dc.PushOpacity((stale ? 0.5 : 1) * emphasis);
            dc.DrawGeometry(null, stroke.Arc, stroke.Shape);
            dc.Pop();
        }
    }
}
