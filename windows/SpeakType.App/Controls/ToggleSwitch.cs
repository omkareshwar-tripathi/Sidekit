using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using SpeakType.App.Theme;

namespace SpeakType.App.Controls;

/// <summary>
/// A small owner-drawn on/off switch that replaces the square WinForms CheckBox in the
/// modern-light restyle. Exposes the slice of CheckBox the forms use — <see cref="Checked"/>
/// and <see cref="CheckedChanged"/>. A mouse click or Space/Enter toggles it; setting
/// <see cref="Checked"/> in code updates the visual and raises <see cref="CheckedChanged"/>
/// (callers that drive it programmatically suppress reactions with their own flag, as
/// <c>SettingsForm</c> already does via <c>_loading</c>).
/// </summary>
internal sealed class ToggleSwitch : Control
{
    private const int TrackW = 36;
    private const int TrackH = 18;
    private const int Knob = 14;
    private bool _checked;

    public ToggleSwitch()
    {
        SetStyle(
            ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint |
            ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor,
            true);
        Size = new Size(TrackW, TrackH);
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
        TabStop = true;
    }

    public event EventHandler? CheckedChanged;

    public bool Checked
    {
        get => _checked;
        set
        {
            if (_checked == value)
            {
                return;
            }

            _checked = value;
            Invalidate();
            CheckedChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    protected override void OnClick(EventArgs e)
    {
        Checked = !Checked;
        base.OnClick(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode is Keys.Space or Keys.Enter)
        {
            Checked = !Checked;
            e.Handled = true;
        }

        base.OnKeyDown(e);
    }

    protected override bool IsInputKey(Keys keyData) =>
        keyData is Keys.Space or Keys.Enter || base.IsInputKey(keyData);

    protected override void OnGotFocus(EventArgs e)
    {
        base.OnGotFocus(e);
        Invalidate();
    }

    protected override void OnLostFocus(EventArgs e)
    {
        base.OnLostFocus(e);
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        var track = new Rectangle(0, (Height - TrackH) / 2, TrackW - 1, TrackH - 1);
        using (var path = RoundedPill(track))
        using (var fill = new SolidBrush(_checked ? UiTheme.Accent : UiTheme.ToggleOff))
        {
            g.FillPath(fill, path);
        }

        var x = _checked ? track.Right - Knob - 1 : track.Left + 2;
        var knobRect = new Rectangle(x, track.Top + (track.Height - Knob) / 2, Knob, Knob);
        using (var knobBrush = new SolidBrush(UiTheme.OnAccent))
        {
            g.FillEllipse(knobBrush, knobRect);
        }

        if (Focused)
        {
            using var focusPath = RoundedPill(track);
            using var pen = new Pen(UiTheme.AccentPressed, 1) { DashStyle = DashStyle.Dot };
            g.DrawPath(pen, focusPath);
        }
    }

    private static GraphicsPath RoundedPill(Rectangle r)
    {
        var path = new GraphicsPath();
        var d = r.Height;
        path.AddArc(r.X, r.Y, d, d, 90, 180);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 180);
        path.CloseFigure();
        return path;
    }
}
