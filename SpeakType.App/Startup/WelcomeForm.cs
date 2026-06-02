using System.Windows.Forms;
using SpeakType.Core.Models;

namespace SpeakType.App.Startup;

/// <summary>
/// The first-run Welcome window (spec Feature 2 "first run"): shows the one-line how-to and
/// downloads the default speech model with a progress bar, offering Retry on failure. The
/// composition root shows this modally on first run, then a "Ready!" tray balloon on success;
/// gating the hotkey on model readiness is Brick 14.
/// </summary>
public sealed class WelcomeForm : Form
{
    private readonly IModelStore _modelStore;
    private readonly string _modelName;
    private readonly Label _status;
    private readonly ProgressBar _bar;
    private readonly Button _retry;
    private readonly CancellationTokenSource _cts = new();
    private bool _downloading;

    public WelcomeForm(IModelStore modelStore, string modelName)
    {
        ArgumentNullException.ThrowIfNull(modelStore);
        ArgumentNullException.ThrowIfNull(modelName);
        _modelStore = modelStore;
        _modelName = modelName;

        Text = "Welcome to SpeakType";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 1,
            Padding = new Padding(16),
        };

        var heading = new Label { Text = "Hold Right Ctrl, speak, release.", AutoSize = true, Margin = new Padding(3, 3, 3, 12) };
        _status = new Label { Text = "Downloading speech model…", AutoSize = true, Margin = new Padding(3, 3, 3, 6) };
        _bar = new ProgressBar { Style = ProgressBarStyle.Continuous, Minimum = 0, Maximum = 100, Width = 280 };
        _retry = new Button { Text = "Retry", AutoSize = true, Visible = false, Margin = new Padding(3, 12, 3, 3) };
        _retry.Click += (_, _) => StartDownload();

        layout.Controls.Add(heading);
        layout.Controls.Add(_status);
        layout.Controls.Add(_bar);
        layout.Controls.Add(_retry);
        Controls.Add(layout);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        StartDownload();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // Stop any in-flight download as the window closes.
        _cts.Cancel();
        base.OnFormClosing(e);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _cts.Dispose();
        }

        base.Dispose(disposing);
    }

    // Standard WinForms async-void event handler. The Progress<double> is created on the UI
    // thread, so its callbacks marshal back to update the bar without manual Invoke.
    private async void StartDownload()
    {
        // Guard re-entrancy: a queued double-click on Retry must not start a second concurrent
        // EnsureAsync (they would race the same temp file and the shared, soon-disposed CTS).
        if (_downloading)
        {
            return;
        }

        _downloading = true;
        _retry.Visible = false;
        _status.Text = "Downloading speech model…";
        _bar.Value = 0;

        var progress = new Progress<double>(f => _bar.Value = Math.Clamp((int)(f * 100), 0, 100));
        try
        {
            await _modelStore.EnsureAsync(_modelName, progress, _cts.Token);
            DialogResult = DialogResult.OK;
            Close();
        }
        catch (OperationCanceledException)
        {
            // The form is closing; nothing to do.
        }
        catch (Exception)
        {
            _status.Text = "Download failed — Retry";
            _bar.Value = 0;
            _retry.Visible = true;
        }
        finally
        {
            _downloading = false;
        }
    }
}
