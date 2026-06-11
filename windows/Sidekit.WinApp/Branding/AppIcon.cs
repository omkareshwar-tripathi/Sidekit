using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace Sidekit.WinApp.Branding;

/// <summary>
/// The app's visual identity: a waveform/equalizer mark in the accent blue (the "C" logo).
/// <see cref="Brand"/> is the full brand icon (blue tile + white waveform) loaded from the
/// embedded <c>sidekit.ico</c> — used for the .exe and window title bars. <see cref="ForState"/>
/// draws just the waveform glyph in a given colour for the tray, so the four tray states keep
/// their colour signal (idle/recording/busy/error) while sharing the logo's shape.
/// </summary>
internal static partial class AppIcon
{
    // The tray glyph's waveform proportions, hand-matched to the brand .ico's shape.
    private static readonly double[] BarHeights = { 0.16, 0.30, 0.46, 0.30, 0.16 };

    private static Icon? _brand;

    /// <summary>The full brand icon (blue tile + white waveform). Loaded once and held for the
    /// process lifetime; shared across windows, so callers must NOT dispose it (Form keeps its own
    /// derived small icon and does not dispose an assigned <c>Icon</c>).</summary>
    public static Icon Brand => _brand ??= LoadBrand();

    private static Icon LoadBrand()
    {
        using var stream = typeof(AppIcon).Assembly.GetManifestResourceStream("sidekit.ico")
            ?? throw new InvalidOperationException("Embedded resource 'sidekit.ico' was not found.");
        return new Icon(stream);
    }

    /// <summary>Draws the waveform glyph in <paramref name="color"/> on a transparent square and
    /// returns an owned <see cref="Icon"/> (the caller disposes it). Used for the tray's per-state
    /// icons.</summary>
    public static Icon ForState(Color color)
    {
        const int size = 32;
        const int ss = 4; // supersample for a crisp downscale
        var w = size * ss;

        using var big = new Bitmap(w, w);
        using (var graphics = Graphics.FromImage(big))
        using (var brush = new SolidBrush(color))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.Clear(Color.Transparent);

            var cx = w / 2;
            var barW = (int)(w * 0.12);
            var gap = (int)(w * 0.07);
            var total = (BarHeights.Length * barW) + ((BarHeights.Length - 1) * gap);
            var startX = cx - (total / 2);
            var radius = barW / 2f;

            for (var i = 0; i < BarHeights.Length; i++)
            {
                var hh = (int)(w * BarHeights[i]);
                var x = startX + (i * (barW + gap));
                FillRoundedBar(graphics, brush, x, cx - hh, barW, hh * 2, radius);
            }
        }

        using var small = new Bitmap(big, new Size(size, size));

        // GetHicon returns an unmanaged HICON that Icon.FromHandle does NOT own; clone an Icon that
        // owns its own copy, then destroy the original handle so the caller's Dispose is leak-free.
        var hicon = small.GetHicon();
        try
        {
            using var unowned = Icon.FromHandle(hicon);
            return (Icon)unowned.Clone();
        }
        finally
        {
            DestroyIcon(hicon);
        }
    }

    private static void FillRoundedBar(Graphics g, Brush brush, int x, int y, int width, int height, float radius)
    {
        var d = radius * 2f;
        using var path = new GraphicsPath();
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + width - d, y, d, d, 270, 90);
        path.AddArc(x + width - d, y + height - d, d, d, 0, 90);
        path.AddArc(x, y + height - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(brush, path);
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DestroyIcon(nint handle);
}
