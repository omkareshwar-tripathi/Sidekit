# SpeakType — "Modern light" UI restyle (design)

**Date:** 2026-06-03
**Status:** Approved (pending spec review)
**Approach:** Option 1 — restyle the existing WinForms windows in place. Light theme only (no dark mode yet). No new dependencies; stays a self-contained single-file exe; no architecture change.

## Goal

Make SpeakType's windows look modern and current ("Win11 Fluent light" — the mockup option **B**): white surfaces, Segoe UI, accent-blue highlights, generous spacing, and toggle switches instead of square checkboxes. Purely a visual change.

## Non-goals (YAGNI)

- **No dark mode** in this round (the palette is centralized so it can be added later as a one-place change).
- **No new UI toolkit / NuGet** (no WPF, no MaterialSkin/Guna). Restyle WinForms only.
- **No behavior changes.** Every event, the live-apply logic, the `_loading` guard, `RevertModelSelection`, the autostart funnel, hotkey rebind, model switch — all preserved exactly.
- **No toggle animation** in v1 (instant flip — lower risk; can add later).
- **Recording overlay left as-is** (already a clean dark pill).

## Surfaces in scope

1. **Settings window** (`SpeakType.App/Settings/SettingsForm.cs`)
2. **Welcome / model-download window** (`SpeakType.App/Startup/WelcomeForm.cs`)
3. **Tray right-click menu** (`SpeakType.App/Tray/TrayIcon.cs`)

Out of scope: `RecordingOverlay`, the tray *icon* glyphs (the colored state circles stay).

## Visual tokens (light palette)

A single source of truth so every surface is consistent.

| Token | Value |
|---|---|
| Window background | `#F3F3F3` |
| Field / surface background | `#FFFFFF` |
| Field border | `#D9D9D9` |
| Text — primary | `#1A1A1A` |
| Text — secondary | `#616161` |
| Accent | `#0067C0` |
| Accent — hover / pressed | `#1A75C7` / `#005BA1` |
| On-accent text | `#FFFFFF` |
| Body font | Segoe UI ~9.75pt |
| Heading font | Segoe UI Semibold ~11–12pt |
| Window padding | 20px |
| Row vertical gap | 12px |
| Label↔control gap | 16px |

Toggle switch: ~36×18 track, ~14 knob; accent track when on, gray (`#8A8A8A`) when off, white knob; instant (no animation).

## Components

### 1. `UiTheme` (new, `SpeakType.App/Theme/UiTheme.cs`)
Static class holding the tokens above (as `Color`/`Font`/int constants) plus small helper methods:
- `StyleWindow(Form)` — background, font, optional padding.
- `StyleField(Control)` — flat border, white background (text box / combo box).
- `StyleButton(Button, primary: bool)` — flat; accent fill + white text when primary, white + border otherwise.

Rationale: one place to change the look (and to add dark mode later). Fonts/brushes that are `IDisposable` are created once and owned by `UiTheme` for process lifetime (small fixed set), or handed to controls that dispose them — decided per helper during implementation.

### 2. `ToggleSwitch` (new, `SpeakType.App/Controls/ToggleSwitch.cs`)
A small owner-drawn `Control` that mirrors the slice of `CheckBox` the forms use:
- `bool Checked { get; set; }`
- `event EventHandler? CheckedChanged`
- Paints the pill track + knob using `UiTheme` colors; click (and Space/Enter) toggles `Checked` and raises `CheckedChanged`.
- Setting `Checked` programmatically updates the visual without re-raising during a suppressed/load phase — matches how `SettingsForm` drives checkboxes today (the form's `_loading` guard still gates the *handler*, exactly as now).

### 3. Restyled `SettingsForm`
- Apply `UiTheme` to the window + layout (padding, fonts, background).
- Replace the four `MakeCheck` checkboxes with `ToggleSwitch` (same `(value, apply)` wiring; `_loading` guard unchanged).
- Flatten the hotkey `TextBox` and the model `ComboBox` via `StyleField`.
- The `ErrorProvider` red-flag behavior on the hotkey field is kept.

### 4. Restyled `WelcomeForm`
- Apply `UiTheme` to the window + labels (heading Semibold, status secondary color).
- Style the **Retry** button as a primary accent button.
- Keep the system `ProgressBar` (already accent-colored on Win11).

### 5. Tray menu renderer
- Give `ContextMenuStrip` a custom `ToolStripRenderer` (a `ToolStripProfessionalRenderer` + custom `ProfessionalColorTable`, or a small flat renderer) for a flat white menu with accent hover, replacing the legacy gray gradient. Menu items, checkmarks, and the separator stay; only the chrome changes.

## Brick plan

All bricks are **Windows-only** (WinForms, `net8.0-windows`). Per CLAUDE.md §2a sizing.

1. **UI-1 — `UiTheme` tokens + helpers.** Foundation, no visible change yet (precedent: 14g built a Core piece before wiring). `Skill: dotnet-best-practices`
2. **UI-2 — `ToggleSwitch` control.** Foundation. `Skill: dotnet-best-practices`
3. **UI-3 — Restyle SettingsForm** (theme + toggles + flat fields). First visible change. `Skill: dotnet-best-practices`
4. **UI-4 — Restyle WelcomeForm** (theme + accent Retry). `Skill: dotnet-best-practices`
5. **UI-5 — Tray menu renderer.** `Skill: dotnet-best-practices`

## Verification ("build-blind" reality)

- **Core is untouched → the 179 existing tests still pass; no behavior regressions.**
- Each brick is verified by **CI compile-green** (windows-latest) — that's all CI can prove for UI.
- **Visual correctness is verified on the laptop by screenshot.** Loop per brick (or per batch): I ship → you build & send a screenshot → I adjust against mockup **B**. No automated visual test.
- No new packages; single-file publish still works (covered by the existing CI publish step).

## Risks / open points

- **Build-blind iteration.** The look will likely need 1–2 screenshot rounds to match B; the toggle and the flat combo box are the most likely to need tweaks.
- **WinForms ceiling.** This reaches ~85–90% of true Fluent. If the last 10% matters after seeing it, that's a later WPF decision (out of scope here).
- **ComboBox flattening** in WinForms is partial (the drop arrow keeps some native chrome); acceptable for v1.
