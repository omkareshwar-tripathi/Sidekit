using System.Drawing;
using System.Windows.Forms;
using SpeakType.App.Tray;
using SpeakType.Core;
using SpeakType.Core.Orchestration;

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
