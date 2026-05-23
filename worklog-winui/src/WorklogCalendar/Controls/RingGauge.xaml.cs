using System;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI;

namespace WorklogCalendar.Controls;

/// <summary>
/// Port of <c>RingGauge.qml</c> — circular donut gauge with center
/// percentage label. Supports a fill-in animation (0 → value on
/// <see cref="StartFill"/>) and an optional color fade-loop between
/// <see cref="BaseColor"/> and <see cref="PaleColor"/>.
/// </summary>
public sealed partial class RingGauge : UserControl
{
    public RingGauge()
    {
        this.InitializeComponent();
        UpdateLabel();
        Loaded += (s, e) => Redraw();
    }

    // -------- Dependency properties -----------------------------------------

    public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(
        nameof(Value), typeof(double), typeof(RingGauge),
        new PropertyMetadata(0.0, (d, e) => ((RingGauge)d).OnValueChanged()));
    public double Value { get => (double)GetValue(ValueProperty); set => SetValue(ValueProperty, value); }

    public static readonly DependencyProperty BaseColorProperty = DependencyProperty.Register(
        nameof(BaseColor), typeof(Color), typeof(RingGauge),
        new PropertyMetadata(Color.FromArgb(0xFF, 0x81, 0xC7, 0x84), (d, e) => ((RingGauge)d).OnBaseColorChanged()));
    public Color BaseColor { get => (Color)GetValue(BaseColorProperty); set => SetValue(BaseColorProperty, value); }

    public static readonly DependencyProperty PaleColorProperty = DependencyProperty.Register(
        nameof(PaleColor), typeof(Color), typeof(RingGauge),
        new PropertyMetadata(Color.FromArgb(0xFF, 0xC8, 0xE6, 0xC9)));
    public Color PaleColor { get => (Color)GetValue(PaleColorProperty); set => SetValue(PaleColorProperty, value); }

    public static readonly DependencyProperty DiameterProperty = DependencyProperty.Register(
        nameof(Diameter), typeof(double), typeof(RingGauge),
        new PropertyMetadata(110.0, (d, e) => ((RingGauge)d).OnDiameterChanged()));
    public double Diameter { get => (double)GetValue(DiameterProperty); set => SetValue(DiameterProperty, value); }

    public static readonly DependencyProperty ThicknessProperty = DependencyProperty.Register(
        nameof(Thickness), typeof(double), typeof(RingGauge),
        new PropertyMetadata(12.0, (d, e) => ((RingGauge)d).Redraw()));
    public double Thickness { get => (double)GetValue(ThicknessProperty); set => SetValue(ThicknessProperty, value); }

    public static readonly DependencyProperty UseFadeLoopProperty = DependencyProperty.Register(
        nameof(UseFadeLoop), typeof(bool), typeof(RingGauge),
        new PropertyMetadata(false, (d, e) => ((RingGauge)d).RestartFadeLoop()));
    public bool UseFadeLoop { get => (bool)GetValue(UseFadeLoopProperty); set => SetValue(UseFadeLoopProperty, value); }

    public static readonly DependencyProperty IntermittentProperty = DependencyProperty.Register(
        nameof(Intermittent), typeof(bool), typeof(RingGauge),
        new PropertyMetadata(false, (d, e) => ((RingGauge)d).RestartFadeLoop()));
    public bool Intermittent { get => (bool)GetValue(IntermittentProperty); set => SetValue(IntermittentProperty, value); }

    public double RingDiameter => Math.Max(0, Diameter);

    // Internal animated value (drives the arc + center label during fill).
    public static readonly DependencyProperty DisplayValueProperty = DependencyProperty.Register(
        nameof(DisplayValue), typeof(double), typeof(RingGauge),
        new PropertyMetadata(0.0, (d, e) => { var r = (RingGauge)d; r.Redraw(); r.UpdateLabel(); }));
    public double DisplayValue { get => (double)GetValue(DisplayValueProperty); set => SetValue(DisplayValueProperty, value); }

    // Internal animated stroke color (drives the arc during fade-loop).
    public static readonly DependencyProperty AnimatedColorProperty = DependencyProperty.Register(
        nameof(AnimatedColor), typeof(Color), typeof(RingGauge),
        new PropertyMetadata(Color.FromArgb(0xFF, 0x81, 0xC7, 0x84), (d, e) => ((RingGauge)d).Redraw()));
    public Color AnimatedColor { get => (Color)GetValue(AnimatedColorProperty); set => SetValue(AnimatedColorProperty, value); }

    // -------- Public API ----------------------------------------------------

    private Storyboard? _fillSb;
    private Storyboard? _fadeSb;

    public void StartFill()
    {
        _fillSb?.Stop();
        DisplayValue = 0;
        var anim = new DoubleAnimation
        {
            From = 0,
            To = Math.Max(0, Math.Min(100, Value)),
            Duration = TimeSpan.FromMilliseconds(1500),
            EasingFunction = new QuarticEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(anim, this);
        Storyboard.SetTargetProperty(anim, "DisplayValue");
        _fillSb = new Storyboard();
        _fillSb.Children.Add(anim);
        _fillSb.Begin();
    }

    // -------- Reactions to property changes ---------------------------------

    private void OnValueChanged()
    {
        if (_fillSb == null || _fillSb.GetCurrentState() != ClockState.Active)
        {
            DisplayValue = Math.Max(0, Math.Min(100, Value));
        }
    }

    private void OnBaseColorChanged()
    {
        // Keep AnimatedColor in sync when no fade-loop is active.
        if (_fadeSb == null || _fadeSb.GetCurrentState() != ClockState.Active)
            AnimatedColor = BaseColor;
    }

    private void OnDiameterChanged()
    {
        RootGrid.Width = Diameter;
        RootGrid.Height = Diameter;
        if (CenterLabel != null) CenterLabel.FontSize = Math.Round(Diameter * 0.22);
        Redraw();
    }

    private void RestartFadeLoop()
    {
        _fadeSb?.Stop();
        if (!UseFadeLoop) { AnimatedColor = BaseColor; return; }

        int pause = Intermittent ? 1000 : 3000;
        int colorMs = Intermittent ? 1000 : 1500;

        var toPale = new ColorAnimation { From = BaseColor, To = PaleColor, Duration = TimeSpan.FromMilliseconds(colorMs), BeginTime = TimeSpan.FromMilliseconds(pause) };
        Storyboard.SetTarget(toPale, this);
        Storyboard.SetTargetProperty(toPale, "AnimatedColor");
        var toBase = new ColorAnimation { From = PaleColor, To = BaseColor, Duration = TimeSpan.FromMilliseconds(colorMs), BeginTime = TimeSpan.FromMilliseconds(pause + colorMs) };
        Storyboard.SetTarget(toBase, this);
        Storyboard.SetTargetProperty(toBase, "AnimatedColor");

        _fadeSb = new Storyboard { RepeatBehavior = RepeatBehavior.Forever };
        _fadeSb.Children.Add(toPale);
        _fadeSb.Children.Add(toBase);
        _fadeSb.Begin();
    }

    // -------- Drawing -------------------------------------------------------

    private void UpdateLabel()
    {
        if (CenterLabel != null) CenterLabel.Text = $"{Math.Round(DisplayValue)}%";
    }

    private void Redraw()
    {
        if (ArcPath == null) return;
        ArcPath.Width = Diameter;
        ArcPath.Height = Diameter;
        ArcPath.Stroke = new SolidColorBrush(AnimatedColor);

        double v = Math.Max(0, Math.Min(100, DisplayValue));
        if (v <= 0)
        {
            ArcPath.Data = null;
            return;
        }

        // Drawing area: an inset circle inside the Diameter×Diameter Path
        // (so the rounded stroke caps don't clip on the edges).
        double r = (Diameter - Thickness) / 2;
        double cx = Diameter / 2;
        double cy = Diameter / 2;
        double startAngle = -Math.PI / 2;
        double endAngle = startAngle + (v / 100.0) * Math.PI * 2;
        var p0 = new Point(cx + r * Math.Cos(startAngle), cy + r * Math.Sin(startAngle));
        var p1 = new Point(cx + r * Math.Cos(endAngle), cy + r * Math.Sin(endAngle));

        // 100% would put p0==p1 and the arc would render as a point; bias
        // the end a hair off so the full circle still draws.
        if (v >= 100)
        {
            endAngle -= 0.001;
            p1 = new Point(cx + r * Math.Cos(endAngle), cy + r * Math.Sin(endAngle));
        }

        var fig = new PathFigure { StartPoint = p0, IsClosed = false };
        fig.Segments.Add(new ArcSegment
        {
            Point = p1,
            Size = new Size(r, r),
            IsLargeArc = v > 50,
            SweepDirection = SweepDirection.Clockwise
        });
        var geo = new PathGeometry();
        geo.Figures.Add(fig);
        ArcPath.Data = geo;
    }
}
