# Modern-Light UI Restyle — Implementation Plan

> **For agentic workers:** This project ships via the `/ship` flow (CLAUDE.md §2a/§2b + `BRICKS.md`). Each task below is one brick. Steps use checkbox (`- [ ]`) syntax. **Verification is non-standard:** WinForms is Windows-only and cannot build/run on the dev Mac, and these UI controls have no unit-test surface — so each task verifies by **(a) CI compile-green on windows-latest** and **(b) a laptop screenshot compared to mockup B**. The Core test suite (179) must stay green (no Core changes).

**Goal:** Restyle SpeakType's Settings window, Welcome/download window, and tray menu to a modern "Win11 Fluent light" look (mockup B) — in-place WinForms, light-only, no new dependencies, no behavior changes.

**Architecture:** Two new foundation pieces — `UiTheme` (central light palette + style helpers) and `ToggleSwitch` (custom on/off control) — then apply them to the two windows and give the tray menu a flat renderer. All in `SpeakType.App`.

**Tech Stack:** C# / .NET 8, WinForms (`net8.0-windows`), GDI+ (`System.Drawing`) for owner-drawing. `TreatWarningsAsErrors=true`, `Nullable=enable`.

**Spec:** `docs/superpowers/specs/2026-06-03-ui-modern-light-restyle-design.md`

---

## File structure

- **Create** `SpeakType.App/Theme/UiTheme.cs` — palette tokens + `StyleWindow`/`StyleField`/`StyleButton` + `FlatMenuColorTable`. Single source of truth for the look.
- **Create** `SpeakType.App/Controls/ToggleSwitch.cs` — owner-drawn on/off switch (`Checked` + `CheckedChanged`).
- **Modify** `SpeakType.App/Settings/SettingsForm.cs` — apply theme, checkboxes → toggles, flat fields.
- **Modify** `SpeakType.App/Startup/WelcomeForm.cs` — apply theme, accent Retry button.
- **Modify** `SpeakType.App/Tray/TrayIcon.cs` — flat menu renderer.

---

## Task 1 (Brick UI-1): `UiTheme` tokens + helpers

**Files:**
- Create: `SpeakType.App/Theme/UiTheme.cs`

- [ ] **Step 1: Create the theme class**

```csharp
using System.Drawing;
using System.Windows.Forms;

namespace SpeakType.App.Theme;

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
```

- [ ] **Step 2: Verify it compiles (local Core build is unaffected; App is Windows-only)**

Run (Mac): `/opt/homebrew/bin/dotnet build SpeakType.Core/SpeakType.Core.csproj -c Release --nologo`
Expected: PASS (sanity; this file isn't in Core but confirms nothing else broke). The App compile is proven by CI in Step 4.

- [ ] **Step 3: Commit**

```bash
git add SpeakType.App/Theme/UiTheme.cs
git commit -m "feat(app): add UiTheme light tokens + style helpers"
```

- [ ] **Step 4: Push and confirm CI compile-green** (the real App-build check)

```bash
git push origin main
gh run watch <id> --exit-status   # windows-latest build must pass
```

*No visual change yet (foundation only — precedent: brick 14g built a Core piece before wiring).*

---

## Task 2 (Brick UI-2): `ToggleSwitch` control

**Files:**
- Create: `SpeakType.App/Controls/ToggleSwitch.cs`

- [ ] **Step 1: Create the control**

```csharp
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
        using (var knobBrush = new SolidBrush(Color.White))
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
```

- [ ] **Step 2: Commit**

```bash
git add SpeakType.App/Controls/ToggleSwitch.cs
git commit -m "feat(app): add ToggleSwitch control for the modern restyle"
```

- [ ] **Step 3: Push and confirm CI compile-green**

```bash
git push origin main
gh run watch <id> --exit-status
```

*Foundation only; wired into SettingsForm in Task 3.*

---

## Task 3 (Brick UI-3): Restyle `SettingsForm`

**Files:**
- Modify: `SpeakType.App/Settings/SettingsForm.cs`

- [ ] **Step 1: Add usings**

At the top with the other usings, add:

```csharp
using SpeakType.App.Controls;
using SpeakType.App.Theme;
```

- [ ] **Step 2: Theme the window in the constructor**

Immediately after the `Text = "SpeakType Settings";` block (the property assignments), add:

```csharp
        UiTheme.StyleWindow(this);
```

And on the `layout` `TableLayoutPanel` initializer, add `BackColor = UiTheme.Background,` so the panel matches the window.

- [ ] **Step 3: Flatten the hotkey field and model dropdown**

After `_hotkeyBox.Text = _settings.Hotkey;` add `UiTheme.StyleField(_hotkeyBox);`.
In `BuildModelBox`, after `_modelBox.DisplayMember = nameof(ModelInfo.Name);` add `UiTheme.StyleField(_modelBox);`.

- [ ] **Step 4: Replace `MakeCheck` (CheckBox) with `MakeToggle` (ToggleSwitch)**

Replace the `MakeCheck` method:

```csharp
    private CheckBox MakeCheck(bool value, Action<bool> apply)
    {
        var check = new CheckBox { AutoSize = true, Checked = value };
        check.CheckedChanged += (_, _) =>
        {
            if (_loading)
            {
                return;
            }

            apply(check.Checked);
            _store.Save(_settings);
        };
        return check;
    }
```

with:

```csharp
    private ToggleSwitch MakeToggle(bool value, Action<bool> apply)
    {
        // Checked is set in the initializer BEFORE the handler is attached, so the initial
        // value never triggers a save. The _loading guard then matches the old checkbox behavior.
        var toggle = new ToggleSwitch { Checked = value };
        toggle.CheckedChanged += (_, _) =>
        {
            if (_loading)
            {
                return;
            }

            apply(toggle.Checked);
            _store.Save(_settings);
        };
        return toggle;
    }
```

Then update the four call sites in the constructor from `MakeCheck(...)` to `MakeToggle(...)` (the arguments are unchanged):

```csharp
        AddRow(layout, "Remove filler words", MakeToggle(_settings.FillerRemoval, v => _settings.FillerRemoval = v));
        AddRow(layout, "Show recording overlay", MakeToggle(_settings.Overlay, v => _settings.Overlay = v));
        AddRow(layout, "Start with Windows", MakeToggle(_settings.Autostart, v =>
        {
            _settings.Autostart = v;
            AutostartChanged?.Invoke(this, v);
        }));
        AddRow(layout, "Debug logging", MakeToggle(_settings.DebugLogging, v => _settings.DebugLogging = v));
```

- [ ] **Step 5: Commit, push, confirm CI compile-green**

```bash
git add SpeakType.App/Settings/SettingsForm.cs
git commit -m "feat(app): restyle SettingsForm (modern light + toggles)"
git push origin main
gh run watch <id> --exit-status
```

- [ ] **Step 6: Visual verification (laptop)**

On the Windows laptop: `git pull`, run `dotnet run --project SpeakType.App`, open Settings from the tray, and **send a screenshot**. Compare to mockup B (white surface, Segoe UI, accent toggles, flat fields, roomy spacing). Iterate if it diverges. All existing Settings behavior (hotkey rebind, model switch, autostart, live toggles) must still work — re-check M6.

---

## Task 4 (Brick UI-4): Restyle `WelcomeForm`

**Files:**
- Modify: `SpeakType.App/Startup/WelcomeForm.cs`

- [ ] **Step 1: Add using**

```csharp
using SpeakType.App.Theme;
```

- [ ] **Step 2: Theme the window + labels + Retry button**

In the constructor, after the `Text = windowTitle;` block, add `UiTheme.StyleWindow(this);`.
Change the heading label to use the heading font, and the status label to the secondary colour:

```csharp
        var heading = new Label { Text = headingText, AutoSize = true, Font = UiTheme.Heading, Margin = new Padding(3, 3, 3, 12) };
        _status = new Label { Text = "Downloading speech model…", AutoSize = true, ForeColor = UiTheme.TextSecondary, Margin = new Padding(3, 3, 3, 6) };
```

After the `_retry` button is constructed, add:

```csharp
        UiTheme.StyleButton(_retry, primary: true);
```

(The system `ProgressBar` is already accent-coloured on Win11 — leave it.)

- [ ] **Step 3: Commit, push, confirm CI compile-green**

```bash
git add SpeakType.App/Startup/WelcomeForm.cs
git commit -m "feat(app): restyle WelcomeForm (modern light + accent Retry)"
git push origin main
gh run watch <id> --exit-status
```

- [ ] **Step 4: Visual verification (laptop)**

On the laptop, trigger first-run (or a model switch from Settings) and **screenshot** the download window. Confirm the heading is Semibold, status is muted grey, Retry is an accent button, window is light. The download + Retry flow must still work (M2).

---

## Task 5 (Brick UI-5): Flat tray menu

**Files:**
- Modify: `SpeakType.App/Tray/TrayIcon.cs`

- [ ] **Step 1: Add using**

```csharp
using SpeakType.App.Theme;
```

- [ ] **Step 2: Apply the flat renderer in `BuildMenu`**

In `BuildMenu()`, right after `var menu = new ContextMenuStrip();`, add:

```csharp
        menu.Renderer = new ToolStripProfessionalRenderer(new FlatMenuColorTable()) { RoundedEdges = false };
        menu.Font = UiTheme.Body;
        menu.ForeColor = UiTheme.TextPrimary;
        menu.BackColor = UiTheme.Surface;
```

- [ ] **Step 3: Commit, push, confirm CI compile-green**

```bash
git add SpeakType.App/Tray/TrayIcon.cs
git commit -m "feat(app): flat modern tray context menu"
git push origin main
gh run watch <id> --exit-status
```

- [ ] **Step 4: Visual verification (laptop)**

Right-click the tray icon and **screenshot** the menu. Confirm it's a flat white menu with accent hover and a thin grey separator (no legacy gray gradient). The menu actions (Settings/Pause/Start-with-Windows/About/Quit) must still work.

---

## Self-review notes

- **Spec coverage:** UiTheme (token table) → Task 1; ToggleSwitch → Task 2; SettingsForm restyle + toggles + flat fields → Task 3; WelcomeForm + accent Retry → Task 4; tray menu renderer → Task 5. All spec surfaces covered; overlay intentionally untouched.
- **No behavior change:** Task 3 preserves the `_loading` guard and all four event wirings; `MakeToggle` sets `Checked` before attaching the handler (no spurious save). No Core edits → 179 tests stay green.
- **Type consistency:** `ToggleSwitch.Checked`/`CheckedChanged` match the CheckBox members the form used. `FlatMenuColorTable` lives in `UiTheme.cs` (Task 1) and is consumed in Task 5.
- **Verification caveat is intrinsic:** UI cannot be unit-tested or rendered on the dev Mac; CI proves compile, screenshots prove looks. Expect 1–2 screenshot iterations per window.
