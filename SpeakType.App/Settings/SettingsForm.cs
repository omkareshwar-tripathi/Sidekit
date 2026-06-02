using System.Windows.Forms;
using SpeakType.App.Controls;
using SpeakType.App.Theme;
using SpeakType.Core.Input;
using SpeakType.Core.Models;
using SpeakType.Core.Settings;

namespace SpeakType.App.Settings;

/// <summary>
/// The settings window (spec Feature 7): a small fixed dialog over the shared, live
/// <see cref="AppSettings"/>. There is no Save button — every edit mutates that instance,
/// persists via <see cref="ISettingsStore.Save"/>, and applies live. Toggles the orchestrator/
/// logger read (filler/overlay/debug) take effect because the form edits the same object they
/// hold; the side-effects the form can't do itself (re-registering the hook, downloading a model,
/// writing the Run key) are raised as events for the composition root (Brick 14) to wire — which
/// also owns rolling a change back if its side-effect fails (e.g. a model download error). Closing
/// the window hides it so that single instance can be reshown.
/// </summary>
public sealed class SettingsForm : Form
{
    private readonly AppSettings _settings;
    private readonly ISettingsStore _store;
    private readonly ErrorProvider _errorProvider = new();
    private readonly TextBox _hotkeyBox = new();
    private readonly ComboBox _modelBox = new();
    private bool _loading = true;

    public SettingsForm(AppSettings settings, ISettingsStore store)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(store);
        _settings = settings;
        _store = store;

        Text = "SpeakType Settings";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        UiTheme.StyleWindow(this);

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 2,
            Padding = new Padding(12),
            BackColor = UiTheme.Background,
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

        _hotkeyBox.Text = _settings.Hotkey;
        UiTheme.StyleField(_hotkeyBox);
        _hotkeyBox.Leave += (_, _) => CommitHotkey();
        AddRow(layout, "Hotkey", _hotkeyBox);

        AddRow(layout, "Model size", BuildModelBox());

        AddRow(layout, "Remove filler words", MakeToggle(_settings.FillerRemoval, v => _settings.FillerRemoval = v));
        AddRow(layout, "Show recording overlay", MakeToggle(_settings.Overlay, v => _settings.Overlay = v));
        AddRow(layout, "Start with Windows", MakeToggle(_settings.Autostart, v =>
        {
            _settings.Autostart = v;
            AutostartChanged?.Invoke(this, v);
        }));
        AddRow(layout, "Debug logging", MakeToggle(_settings.DebugLogging, v => _settings.DebugLogging = v));

        Controls.Add(layout);
        _loading = false;
    }

    /// <summary>Raised after a valid hotkey rebind so the composition root re-registers the global hook.</summary>
    public event EventHandler<Hotkey>? HotkeyRebound;

    /// <summary>Raised when the selected model changes so the composition root downloads/switches it.</summary>
    public event EventHandler<string>? ModelChangeRequested;

    /// <summary>Raised when Start with Windows is toggled so the composition root writes/removes the Run key.</summary>
    public event EventHandler<bool>? AutostartChanged;

    // Closing the window hides it instead of disposing, so the single instance can be reshown.
    // Commit a typed-but-not-yet-defocused valid hotkey first; discard any still-invalid edit so
    // the reshown form starts clean and consistent with the persisted settings.
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing)
        {
            CommitHotkey();
            _hotkeyBox.Text = _settings.Hotkey;
            _errorProvider.SetError(_hotkeyBox, string.Empty);
            e.Cancel = true;
            Hide();
            return;
        }

        base.OnFormClosing(e);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _errorProvider.Dispose();
        }

        base.Dispose(disposing);
    }

    private ComboBox BuildModelBox()
    {
        // Reconcile a stored model name that isn't in the catalog (Normalize only null-checks it)
        // to the default, so the dropdown is never blank and the in-memory setting is consistent.
        var selectedName = ModelCatalog.Resolve(_settings.ModelSize);
        _settings.ModelSize = selectedName;

        _modelBox.DropDownStyle = ComboBoxStyle.DropDownList;
        _modelBox.DisplayMember = nameof(ModelInfo.Name);
        UiTheme.StyleField(_modelBox);

        foreach (var model in ModelCatalog.All.Values.OrderBy(m => m.SizeBytes))
        {
            _modelBox.Items.Add(model);
            if (string.Equals(model.Name, selectedName, StringComparison.OrdinalIgnoreCase))
            {
                _modelBox.SelectedIndex = _modelBox.Items.Count - 1;
            }
        }

        _modelBox.SelectedIndexChanged += (_, _) =>
        {
            if (_loading || _modelBox.SelectedItem is not ModelInfo model)
            {
                return;
            }

            _settings.ModelSize = model.Name;
            _store.Save(_settings);
            ModelChangeRequested?.Invoke(this, model.Name);
        };

        return _modelBox;
    }

    /// <summary>
    /// Reselects the model dropdown to <paramref name="modelName"/> without raising
    /// <see cref="ModelChangeRequested"/>. The composition root calls this when a requested model
    /// switch fails or is cancelled, so the dropdown stays in sync with the still-active model.
    /// </summary>
    public void RevertModelSelection(string modelName)
    {
        _loading = true; // suppress the SelectedIndexChanged handler for this programmatic change
        try
        {
            for (var i = 0; i < _modelBox.Items.Count; i++)
            {
                if (_modelBox.Items[i] is ModelInfo model &&
                    string.Equals(model.Name, modelName, StringComparison.OrdinalIgnoreCase))
                {
                    _modelBox.SelectedIndex = i;
                    break;
                }
            }
        }
        finally
        {
            _loading = false;
        }
    }

    // Validates and applies the hotkey box on focus-loss / window-close. No-ops when unchanged
    // (so re-focusing the box doesn't needlessly re-save or re-register the hook). On a valid
    // edit it writes the canonical form, persists, and raises HotkeyRebound; on an invalid edit
    // it flags the error and leaves the text for the user to fix (the close path discards it).
    private void CommitHotkey()
    {
        if (string.Equals(_hotkeyBox.Text, _settings.Hotkey, StringComparison.Ordinal))
        {
            return;
        }

        if (Hotkey.TryParse(_hotkeyBox.Text, out var hotkey, out var error))
        {
            _errorProvider.SetError(_hotkeyBox, string.Empty);
            _settings.Hotkey = hotkey!.ToString();
            _hotkeyBox.Text = _settings.Hotkey;
            _store.Save(_settings);
            HotkeyRebound?.Invoke(this, hotkey);
        }
        else
        {
            _errorProvider.SetError(_hotkeyBox, error);
        }
    }

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

    // Adds a label + control pair as the next row of the layout.
    private static void AddRow(TableLayoutPanel layout, string label, Control control)
    {
        var row = layout.RowCount;
        layout.RowCount = row + 1;
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(
            new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(3, 6, 12, 6) },
            0,
            row);
        layout.Controls.Add(control, 1, row);
    }
}
