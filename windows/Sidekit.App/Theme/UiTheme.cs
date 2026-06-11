using System.Drawing;
using System.Windows.Forms;

namespace Sidekit.App.Theme;

/// <summary>
/// Central light-theme tokens and small styling helpers for the modern-light UI restyle
/// (spec 2026-06-03). One place to change the look — a future dark mode swaps this palette.
/// </summary>
internal static class UiTheme
{
    // Palette — Win11 "Fluent" light.
    public static readonly Color Background = Color.FromArgb(0xF3, 0xF3, 0xF3);
    public static readonly Color Surface = Color.White;
    public static readonly Color Border = Color.FromArgb(0xD9, 0xD9, 0xD9);
    public static readonly Color TextPrimary = Color.FromArgb(0x1A, 0x1A, 0x1A);
    public static readonly Color TextSecondary = Color.FromArgb(0x61, 0x61, 0x61);
    public static readonly Color Accent = Color.FromArgb(0x00, 0x67, 0xC0);
    public static readonly Color AccentHover = Color.FromArgb(0x1A, 0x75, 0xC7);
    public static readonly Color AccentPressed = Color.FromArgb(0x00, 0x5B, 0xA1);
    public static readonly Color ToggleOff = Color.FromArgb(0x8A, 0x8A, 0x8A);
    public static readonly Color OnAccent = Color.White;

    // Fonts — created once and held for the process lifetime (small fixed set; the app is a singleton).
    public static readonly Font Body = new("Segoe UI", 9.75f);
    public static readonly Font Heading = new("Segoe UI Semibold", 12f);

    public const int WindowPadding = 20;
    public const int RowGap = 12;

    public static void StyleWindow(Form form)
    {
        form.BackColor = Background;
        form.ForeColor = TextPrimary;
        form.Font = Body;
    }

    /// <summary>Flattens a text box or combo box onto the light surface.</summary>
    public static void StyleField(Control field)
    {
        field.BackColor = Surface;
        field.ForeColor = TextPrimary;
        switch (field)
        {
            case TextBox tb: tb.BorderStyle = BorderStyle.FixedSingle; break;
            case ComboBox cb: cb.FlatStyle = FlatStyle.Flat; break;
        }
    }

    /// <summary>Styles a button: accent fill when <paramref name="primary"/>, otherwise a bordered light button.</summary>
    public static void StyleButton(Button button, bool primary)
    {
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 1;
        button.FlatAppearance.BorderColor = primary ? Accent : Border;
        button.BackColor = primary ? Accent : Surface;
        button.ForeColor = primary ? OnAccent : TextPrimary;
        button.FlatAppearance.MouseOverBackColor = primary ? AccentHover : Background;
        button.FlatAppearance.MouseDownBackColor = primary ? AccentPressed : Border;
    }
}

/// <summary>Flat white context-menu colours for the tray menu (used in Task 5).</summary>
internal sealed class FlatMenuColorTable : ProfessionalColorTable
{
    public override Color ToolStripDropDownBackground => UiTheme.Surface;
    public override Color ImageMarginGradientBegin => UiTheme.Surface;
    public override Color ImageMarginGradientMiddle => UiTheme.Surface;
    public override Color ImageMarginGradientEnd => UiTheme.Surface;
    public override Color MenuBorder => UiTheme.Border;
    public override Color MenuItemBorder => UiTheme.Accent;
    public override Color MenuItemSelected => UiTheme.Background;
    public override Color MenuItemSelectedGradientBegin => UiTheme.Background;
    public override Color MenuItemSelectedGradientEnd => UiTheme.Background;
    public override Color SeparatorDark => UiTheme.Border;
    public override Color SeparatorLight => UiTheme.Border;
}
