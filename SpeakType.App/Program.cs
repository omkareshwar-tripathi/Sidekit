using System.Drawing;
using System.Net.Http;
using System.Windows.Forms;
using SpeakType.App.Startup;
using SpeakType.App.Tray;
using SpeakType.Core;
using SpeakType.Core.Models;
using SpeakType.Core.Orchestration;
using SpeakType.Core.Settings;

namespace SpeakType.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // Single-instance: the first launch owns the mutex; a second launch sees
        // createdNew == false, tells the user, and exits. Brick 12/14 may replace this
        // with signalling the running instance instead of a transient balloon.
        using var mutex = new Mutex(initiallyOwned: true, AppInfo.SingleInstanceMutexName, out var createdNew);
        ApplicationConfiguration.Initialize();
        if (!createdNew)
        {
            // Tell the user we're already running, then exit. A balloon needs a running message
            // loop to render, so pump briefly and quit on a timer. (Brick 12/14 may instead
            // signal the existing instance.)
            using var notice = new NotifyIcon { Visible = true, Icon = SystemIcons.Application };
            using var timer = new System.Windows.Forms.Timer { Interval = 4000 };
            timer.Tick += (_, _) => Application.ExitThread();
            timer.Start();
            notice.ShowBalloonTip(3000, AppInfo.Name, "SpeakType is already running", ToolTipIcon.Info);
            Application.Run();
            return;
        }

        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);

        var tray = new TrayIcon();
        // UI-thread exceptions are recoverable: log, tell the user, and return to Idle so the
        // message loop keeps running. Background-thread fatals can only be last-chance logged —
        // AppDomain.UnhandledException cannot stop termination and runs off the UI thread, so it
        // must not touch the NotifyIcon. The full threading/recovery model is Brick 14's.
        Application.ThreadException += (_, e) => RecoverFromUiException(tray, e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => System.Diagnostics.Trace.WriteLine(e.ExceptionObject);
        tray.QuitRequested += (_, _) => Application.ExitThread();

        // Start-with-Windows: the tray toggle writes/removes the per-user Run key.
        var autostart = new WinAutostart();
        tray.StartWithWindowsToggled += (_, enabled) =>
        {
            if (enabled)
            {
                autostart.Enable();
            }
            else
            {
                autostart.Disable();
            }
        };

        // First-run: download the default model via the Welcome window before the app is usable.
        // The HttpClient lives until Run() returns (Application.Run blocks), covering the modal flow.
        using var httpClient = new HttpClient();
        var modelStore = new ModelStore(new HttpModelDownloader(httpClient), ModelStore.DefaultModelsDirectory);
        var modelName = AppSettings.DefaultModelSize;
        if (modelStore.GetInstalledModelPath(modelName) is null)
        {
            using var welcome = new WelcomeForm(modelStore, modelName);
            if (welcome.ShowDialog() != DialogResult.OK)
            {
                // Setup didn't complete (download failed, or the user closed/quit the window).
                // Don't register autostart or enter the tray loop with no usable model — exit cleanly
                // so we don't auto-launch into the same broken first-run on every login.
                tray.Dispose();
                return;
            }

            // Setup succeeded: apply the spec default (autostart ON) and tell the user we're ready.
            autostart.Enable();
            tray.ShowBalloon(AppInfo.Name, "Ready!");
        }

        // Reflect the real Run-key state in the menu (the user may have toggled it off on a prior run).
        tray.SetStartWithWindowsChecked(autostart.IsEnabled());

        // This brick builds only the tray + lifecycle shell. Wiring the tray's state and
        // Pause to the real DictationOrchestrator is Brick 14 (the composition root).
        Application.Run();
        tray.Dispose();
    }

    // Surface a recoverable UI-thread failure as a balloon and return to Idle rather than crash.
    // Trace is a placeholder until the Brick 13 logger lands.
    private static void RecoverFromUiException(TrayIcon tray, Exception ex)
    {
        System.Diagnostics.Trace.WriteLine(ex);
        tray.ShowBalloon(AppInfo.Name, "Something went wrong — recovered.");
        tray.SetState(TrayState.Idle);
    }
}
