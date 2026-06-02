using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using SpeakType.Core;
using SpeakType.Core.Orchestration;

namespace SpeakType.App.Tray;

/// <summary>
/// The system-tray surface (spec Feature 6): a <see cref="NotifyIcon"/> whose icon and
/// tooltip reflect the four <see cref="TrayState"/>s, plus a right-click menu. State icons
/// are drawn programmatically (no .ico assets). The composition root (Brick 14) subscribes
/// to the events to wire Settings/Pause/Start-with-Windows/Quit; About is handled in place.
/// </summary>
public sealed partial class TrayIcon : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu;
    private readonly Dictionary<TrayState, Icon> _icons;
    private ToolStripMenuItem _startupItem = null!; // assigned in BuildMenu (called from the ctor)
    private bool _disposed;

    public TrayIcon()
    {
        _icons = new Dictionary<TrayState, Icon>
        {
            [TrayState.Idle] = MakeIcon(Color.SteelBlue),
            [TrayState.Recording] = MakeIcon(Color.Red),
            [TrayState.Busy] = MakeIcon(Color.Orange),
            [TrayState.Error] = MakeIcon(Color.DarkRed),
        };

        _menu = BuildMenu();
        _notifyIcon = new NotifyIcon
        {
            Icon = _icons[TrayState.Idle],
            Text = Tooltip(TrayState.Idle),
            ContextMenuStrip = _menu,
            Visible = true,
        };
    }

    /// <summary>Raised when the user clicks Settings… (Brick 11 will handle it).</summary>
    public event EventHandler? SettingsRequested;

    /// <summary>Raised when Pause listening is toggled; argument is the new Checked value.</summary>
    public event EventHandler<bool>? PauseToggled;

    /// <summary>Raised when Start with Windows is toggled; argument is the new Checked value.</summary>
    public event EventHandler<bool>? StartWithWindowsToggled;

    /// <summary>Raised when the user clicks Quit.</summary>
    public event EventHandler? QuitRequested;

    public void SetState(TrayState state)
    {
        _notifyIcon.Icon = _icons[state];
        _notifyIcon.Text = Tooltip(state);
    }

    public void ShowBalloon(string title, string text) =>
        _notifyIcon.ShowBalloonTip(3000, title, text, ToolTipIcon.Info);

    /// <summary>Reflects the actual autostart state in the menu checkmark. Sets the property
    /// directly (no <c>Click</c>), so it does not raise <see cref="StartWithWindowsToggled"/>.</summary>
    public void SetStartWithWindowsChecked(bool isChecked) => _startupItem.Checked = isChecked;

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
        foreach (var icon in _icons.Values)
        {
            icon.Dispose();
        }

        GC.SuppressFinalize(this);
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();

        var settings = new ToolStripMenuItem("Settings…");
        settings.Click += (_, _) => SettingsRequested?.Invoke(this, EventArgs.Empty);

        var pause = new ToolStripMenuItem("Pause listening") { CheckOnClick = true };
        pause.Click += (_, _) => PauseToggled?.Invoke(this, pause.Checked);

        var startup = new ToolStripMenuItem("Start with Windows") { CheckOnClick = true, Checked = true };
        startup.Click += (_, _) => StartWithWindowsToggled?.Invoke(this, startup.Checked);
        _startupItem = startup;

        var about = new ToolStripMenuItem("About");
        about.Click += (_, _) => MessageBox.Show(AppInfo.Name, $"About {AppInfo.Name}");

        var quit = new ToolStripMenuItem("Quit");
        quit.Click += (_, _) => QuitRequested?.Invoke(this, EventArgs.Empty);

        menu.Items.Add(settings);
        menu.Items.Add(pause);
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(about);
        menu.Items.Add(quit);
        return menu;
    }

    private static string Tooltip(TrayState state) => $"{AppInfo.Name} — {state}"; // ≤ 63 chars (Win32 limit)

    // Draw a filled circle on a 16×16 bitmap and turn it into an Icon — avoids shipping
    // binary .ico assets for the four states.
    private static Icon MakeIcon(Color color)
    {
        using var bitmap = new Bitmap(16, 16);
        using (var graphics = Graphics.FromImage(bitmap))
        using (var brush = new SolidBrush(color))
        {
            graphics.Clear(Color.Transparent);
            graphics.FillEllipse(brush, 1, 1, 14, 14);
        }

        // GetHicon returns an unmanaged HICON that Icon.FromHandle does NOT own (so disposing
        // that Icon would not free it). Clone an Icon that owns its own copy, then destroy the
        // original handle — keeping the Dispose() loop an honest, leak-free cleanup.
        var hicon = bitmap.GetHicon();
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

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DestroyIcon(nint handle);
}
