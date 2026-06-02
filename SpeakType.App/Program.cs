using System.Drawing;
using System.Net.Http;
using System.Windows.Forms;
using SpeakType.App.Audio;
using SpeakType.App.Input;
using SpeakType.App.Overlay;
using SpeakType.App.Paste;
using SpeakType.App.Startup;
using SpeakType.App.Threading;
using SpeakType.App.Tray;
using SpeakType.Core;
using SpeakType.Core.Cleanup;
using SpeakType.Core.Input;
using SpeakType.Core.Logging;
using SpeakType.Core.Models;
using SpeakType.Core.Orchestration;
using SpeakType.Core.Overlay;
using SpeakType.Core.Paste;
using SpeakType.Core.Settings;
using SpeakType.Core.Time;
using SpeakType.Core.Transcription;
using SpeakType.Whisper;

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

        // Build the dictation pipeline now that a usable model is present. The hotkey hook is installed
        // LAST — after the model loads — so it stays inert until SpeakType is actually ready (spec Feature 2).
        var settingsStore = new JsonSettingsStore(JsonSettingsStore.DefaultFilePath);
        var settings = settingsStore.Load();

        var transcriber = LoadTranscriber(modelStore, modelName, tray);
        if (transcriber is null)
        {
            return; // corrupt-on-load re-download was abandoned; tray already disposed
        }

        using var uiMarshaller = new UiMarshaller();
        using var overlay = new RecordingOverlay();
        using var capture = new NAudioCapture();
        using var autoStopTimer = new SystemAutoStopTimer();
        using var hotkey = new Win32HotkeyListener(Hotkey.Resolve(settings.Hotkey, AppSettings.DefaultHotkey));

        // Paste runs inside the background cycle, but WinForms Clipboard needs the STA UI thread, so it
        // is marshalled there. The cycle itself runs off the UI thread so transcription never freezes it.
        var pasteService = new ClipboardPasteService(new MarshallingClipboard(new WinClipboard(), uiMarshaller));

        // On a background-cycle failure: recover the tray to Idle and clear any overlay the cycle left
        // up — it threw before StateChanged(Idle)/Completed could fire, so nothing else fades it.
        var dispatcher = new BackgroundCycleDispatcher(ex => uiMarshaller.Post(() =>
        {
            RecoverFromUiException(tray, ex);
            overlay.FadeOut();
        }));

        // Diagnostic log (spec Logging & Privacy): metadata always; the transcript only when Debug
        // logging is on — read live via the Func so the Settings toggle applies without a restart.
        var logger = new AppLogger(new FileLogSink(FileLogSink.DefaultLogPath), () => settings.DebugLogging);

        var orchestrator = new DictationOrchestrator(
            hotkey, capture, transcriber, pasteService, new TranscriptCleaner(), settings,
            new SystemClock(), autoStopTimer, dispatcher, logger);

        // Drive the tray colour + overlay from the cycle. The events can fire on the background cycle
        // thread, so every UI touch is marshalled to the UI thread. Invariant: SHOWING the overlay is
        // gated on settings.Overlay, but CLEARING it (FadeOut) is unconditional — so toggling Overlay
        // off mid-cycle (Brick 14e) can never leave a stale overlay stuck on screen.
        orchestrator.StateChanged += (_, state) => uiMarshaller.Post(() =>
        {
            tray.SetState(TrayStatus.From(state));

            if (state == RecordingState.Idle)
            {
                overlay.FadeOut();
                return;
            }

            if (!settings.Overlay)
            {
                return;
            }

            switch (state)
            {
                case RecordingState.Recording:
                    overlay.ShowStatus(OverlayStatus.Listening);
                    break;
                case RecordingState.Transcribing:
                    overlay.ShowStatus(OverlayStatus.Transcribing);
                    break;

                // Pasting keeps the "Transcribing…" overlay up; the tray already reads Busy via SetState.
            }
        });

        orchestrator.Completed += (_, outcome) => uiMarshaller.Post(() =>
        {
            // Flash the outcome text (only if the overlay is enabled), then always fade so nothing is
            // left on screen. A clean paste shows no text — it just clears the lingering "Transcribing…".
            if (settings.Overlay)
            {
                switch (outcome)
                {
                    case DictationOutcome.NoSpeech:
                        overlay.ShowStatus(OverlayStatus.NoSpeech);
                        break;
                    case DictationOutcome.LeftOnClipboard:
                        overlay.ShowStatus(OverlayStatus.CopiedManually);
                        break;
                }
            }

            overlay.FadeOut();
        });

        Application.Run();
        tray.Dispose();

        // Dispose the model last. Guard against the rare quit-during-transcription: WhisperTranscriber
        // throws if disposed mid-run, and the process is exiting anyway.
        try
        {
            (transcriber as IDisposable)?.Dispose();
        }
        catch
        {
            // Ignore — a cycle was still in flight at quit; the OS reclaims native resources on exit.
        }
    }

    // Loads the Whisper model into a transcriber. Implements spec Feature 2 "corrupt-on-load": the
    // first-run gate only checks the file exists, so a truncated/stale cached model is detected here
    // (Whisper fails to load it) and re-downloaded via the Welcome flow. Returns null if that
    // re-download is abandoned (in which case the tray has been disposed and the app should exit).
    private static ITranscriber? LoadTranscriber(ModelStore modelStore, string modelName, TrayIcon tray)
    {
        var modelPath = modelStore.GetInstalledModelPath(modelName)!; // guaranteed present by the first-run gate
        try
        {
            return new WhisperTranscriber(modelPath);
        }
        catch (Exception)
        {
            using var redownload = new WelcomeForm(modelStore, modelName);
            if (redownload.ShowDialog() != DialogResult.OK)
            {
                tray.Dispose();
                return null;
            }

            return new WhisperTranscriber(modelStore.GetInstalledModelPath(modelName)!);
        }
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
