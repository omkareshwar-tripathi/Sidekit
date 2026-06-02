using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using SpeakType.Core.Overlay;

namespace SpeakType.App.Overlay;

/// <summary>
/// The recording overlay (spec Feature 6): a small, always-on-top, click-through window that
/// NEVER steals focus (no-activate + transparent/layered ex-styles), so the paste target keeps
/// its caret. It appears near the bottom-center of the active monitor, shows the status text for
/// each <see cref="OverlayStatus"/>, and fades out on completion. The composition root (Brick 14)
/// drives <see cref="ShowStatus"/>/<see cref="FadeOut"/> from the orchestrator and gates the whole
/// thing on <c>AppSettings.Overlay</c>; the overlay itself reads no settings.
/// </summary>
public sealed partial class RecordingOverlay : Form
{
    private const int WsExNoActivate = 0x08000000;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExTransparent = 0x00000020;
    private const int WsExLayered = 0x00080000;
    private const uint LwaAlpha = 0x2;

    private readonly Label _label;
    private readonly Font _font;
    private readonly Timer _fadeTimer;
    private int _fadeAlpha;

    public RecordingOverlay()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.FromArgb(32, 32, 32);

        _font = new Font(Font.FontFamily, 14f);
        _label = new Label
        {
            AutoSize = true,
            ForeColor = Color.White,
            Font = _font,
            Padding = new Padding(16, 10, 16, 10),
        };
        Controls.Add(_label);

        _fadeTimer = new Timer { Interval = 30 };
        _fadeTimer.Tick += FadeTick;
    }

    // No-activate + keep the window from taking focus when shown.
    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            // Layered + transparent = a click-through window; no-activate keeps it from ever taking
            // focus; tool-window keeps it off Alt-Tab. (TopMost is applied via the TopMost property.)
            cp.ExStyle |= WsExNoActivate | WsExToolWindow | WsExTransparent | WsExLayered;
            return cp;
        }
    }

    /// <summary>Shows the given status: cancels any pending fade, sets the text, resizes to fit,
    /// repositions to the bottom-center of the active monitor, and shows without taking focus.</summary>
    public void ShowStatus(OverlayStatus status)
    {
        _fadeTimer.Stop();

        _label.Text = OverlayText.For(status);
        ClientSize = _label.PreferredSize;

        // "Active monitor" is approximated by the cursor's screen — a reasonable v1 heuristic;
        // resolving the foreground window's screen is a later refinement.
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(area.Left + (area.Width - Width) / 2, area.Bottom - Height - 80);

        if (!Visible)
        {
            Show(); // creates the HWND; the layered window stays invisible until alpha is set below
        }

        SetAlpha(255);
    }

    /// <summary>Starts a timed fade; when fully transparent the form is hidden (kept alive for reuse).</summary>
    public void FadeOut()
    {
        _fadeAlpha = 255;
        _fadeTimer.Start();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _fadeTimer.Dispose();
            _font.Dispose();
            // _label is owned by the Controls collection and disposed by base.Dispose.
        }

        base.Dispose(disposing);
    }

    // Sets the layered window's uniform alpha directly (rather than Form.Opacity, which manages
    // WS_EX_LAYERED itself and conflicts with setting that style in CreateParams).
    private void SetAlpha(byte alpha)
    {
        if (IsHandleCreated)
        {
            SetLayeredWindowAttributes(Handle, 0, alpha, LwaAlpha);
        }
    }

    private void FadeTick(object? sender, EventArgs e)
    {
        _fadeAlpha -= 24;
        if (_fadeAlpha <= 0)
        {
            _fadeTimer.Stop();
            Hide();
        }
        else
        {
            SetAlpha((byte)_fadeAlpha);
        }
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetLayeredWindowAttributes(nint hwnd, uint crKey, byte bAlpha, uint dwFlags);
}
