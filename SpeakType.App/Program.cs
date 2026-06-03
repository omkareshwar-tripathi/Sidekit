using System.Drawing;
using System.IO;
using System.Net.Http;
using System.Windows.Forms;
using SpeakType.App.Audio;
using SpeakType.App.Input;
using SpeakType.App.Overlay;
using SpeakType.App.Paste;
using SpeakType.App.Settings;
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
using SpeakType.Core.Polishing;
using SpeakType.Core.Settings;
using SpeakType.Core.Time;
using SpeakType.Core.Transcription;
using SpeakType.Onnx.Inference;
using SpeakType.Onnx.Tokenization;
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

        var settingsStore = new JsonSettingsStore(JsonSettingsStore.DefaultFilePath);
        var settings = settingsStore.Load();

        // Single funnel for both autostart entry points (tray menu + Settings checkbox) so the Run key,
        // the persisted AppSettings.Autostart, and the tray checkmark never diverge.
        void ApplyAutostart(bool enabled)
        {
            if (enabled)
            {
                autostart.Enable();
            }
            else
            {
                autostart.Disable();
            }

            settings.Autostart = enabled;
            settingsStore.Save(settings);
            tray.SetStartWithWindowsChecked(enabled);
        }

        tray.StartWithWindowsToggled += (_, enabled) => ApplyAutostart(enabled);

        // First-run: download the default model via the Welcome window before the app is usable.
        // The HttpClient lives until Run() returns (Application.Run blocks), covering the modal flow.
        using var httpClient = new HttpClient();
        var modelStore = new ModelStore(new HttpModelDownloader(httpClient), ModelStore.DefaultModelsDirectory);

        // Honor the persisted model (fall back to the default if it isn't a known catalog entry), so a
        // model chosen in Settings survives a restart instead of always reverting to the default.
        var modelName = ModelCatalog.Resolve(settings.ModelSize);
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
            ApplyAutostart(true);
            tray.ShowBalloon(AppInfo.Name, "Ready!");
        }

        // CoEdIT text-improvement model (multi-part, ~2.4 GB) is OPT-IN: NOT downloaded here, so the app
        // is usable immediately with no large download and the launch can never hang/crash on it. The
        // Settings "Improve text (CoEdIT)" toggle triggers the download + activation on demand (below).
        var coeditStore = new CoEditModelStore(new HttpModelDownloader(httpClient), CoEditModelStore.DefaultModelsDirectory);

        // Reflect the real Run-key state in the menu (the user may have toggled it off on a prior run).
        tray.SetStartWithWindowsChecked(autostart.IsEnabled());

        // Build the dictation pipeline now that a usable model is present. The hotkey hook is installed
        // LAST — after the model loads — so it stays inert until SpeakType is actually ready (spec Feature 2).
        var transcriber = LoadTranscriber(modelStore, modelName, tray);
        if (transcriber is null)
        {
            return; // corrupt-on-load re-download was abandoned; tray already disposed
        }

        // Wrap in a swappable so the Settings model dropdown can hot-swap the model at runtime
        // (spec Feature 4). activeModel tracks what's actually loaded, for the roll-back on a failed switch.
        var swappable = new SwappableTranscriber(transcriber);
        var activeModel = modelName;

        // Diagnostic log (spec Logging & Privacy): metadata always; the transcript only when Debug
        // logging is on — read live via the Func so the Settings toggle applies without a restart.
        // Built here (before CoEdIT activation) so a model-load failure is logged.
        var logger = new AppLogger(new FileLogSink(FileLogSink.DefaultLogPath), () => settings.DebugLogging);

        // CoEdIT polishing is opt-in and hot-swappable. The orchestrator always holds this pass-through
        // wrapper; it polishes only once a model is loaded into it (ActivateCoEdit). coeditModel keeps
        // the ~2.4 GB ONNX sessions referenced for disposal at shutdown.
        var coeditPolisher = new SwappableTextPolisher();
        OnnxCoEditModel? coeditModel = null;

        // Loads the installed CoEdIT model and switches polishing on. Fail-open: a load failure (e.g. a
        // missing Visual C++ runtime or a corrupt model) is logged and leaves CoEdIT inactive rather than
        // crashing dictation. Returns false if no model is installed or the load failed.
        bool ActivateCoEdit()
        {
            if (coeditPolisher.IsActive)
            {
                return true;
            }

            var dir = coeditStore.GetInstalledModelDirectory();
            if (dir is null)
            {
                return false;
            }

            try
            {
                var model = new OnnxCoEditModel(
                    Path.Combine(dir, "encoder_model.onnx"),
                    Path.Combine(dir, "decoder_model_merged.onnx"));
                coeditPolisher.Set(new CoEditPolisher(new CoEditTokenizer(), model));
                coeditModel = model;
                return true;
            }
            catch (Exception ex)
            {
                logger.Error($"coedit load failed: {ex.Message}");
                return false;
            }
        }

        // If the user enabled CoEdIT on a previous run and the model is present, load it now.
        if (settings.CoEditPolishing)
        {
            ActivateCoEdit();
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

        var orchestrator = new DictationOrchestrator(
            hotkey, capture, swappable, pasteService, new TranscriptCleaner(), settings,
            new SystemClock(), autoStopTimer, dispatcher, logger, coeditPolisher);

        // Settings window — single instance; Show/Activate on each request, it hides itself on close.
        using var settingsForm = new SettingsForm(settings, settingsStore);
        settingsForm.HotkeyRebound += (_, rebound) =>
        {
            hotkey.Rebind(rebound);
            orchestrator.Cancel(); // a rebind mid-hold won't fire Released — drop any active capture
        };
        settingsForm.AutostartChanged += (_, enabled) => ApplyAutostart(enabled);

        // Enabling CoEdIT downloads its ~2.4 GB model on demand (if not already present), then switches
        // polishing on live. On cancel/failure, revert the setting + toggle so the UI matches reality.
        settingsForm.CoEditEnableRequested += (_, _) =>
        {
            void Revert()
            {
                settings.CoEditPolishing = false;
                settingsStore.Save(settings);
                settingsForm.RevertCoEditToggle();
            }

            if (coeditPolisher.IsActive)
            {
                return; // already on
            }

            if (coeditStore.GetInstalledModelDirectory() is null)
            {
                // Need the model first. A modal keeps the message loop pumping, so dictation still works
                // while it downloads. The old, no-CoEdIT pipeline stays live throughout.
                using var download = new WelcomeForm(
                    (progress, ct) => coeditStore.EnsureAsync(progress, ct),
                    "Enable text improvement",
                    "Downloading the text-improvement model (~2.4 GB, one time).",
                    "Downloading text-improvement model…");
                if (download.ShowDialog() != DialogResult.OK)
                {
                    Revert(); // download cancelled/failed
                    return;
                }
            }

            if (!ActivateCoEdit())
            {
                // Model present but failed to load (e.g. missing Visual C++ runtime). Don't re-download.
                tray.ShowBalloon(AppInfo.Name, "Couldn't start text improvement — see the log.");
                Revert();
            }
        };
        settingsForm.ModelChangeRequested += (_, requested) =>
        {
            if (string.Equals(requested, activeModel, StringComparison.OrdinalIgnoreCase))
            {
                return; // already the live model
            }

            // Download + verify the new model behind a progress UI; the old model stays live throughout
            // (we only swap after a verified download). A modal keeps the message loop pumping, so a
            // background dictation cycle on the old model still works while this window is open.
            var switched = false;
            using (var download = new WelcomeForm(modelStore, requested, "Switch model", $"Switching to the {requested} model."))
            {
                if (download.ShowDialog() == DialogResult.OK)
                {
                    try
                    {
                        // Swap on the UI thread (SwappableTranscriber's contract); it disposes the old model.
                        swappable.Swap(new WhisperTranscriber(modelStore.GetInstalledModelPath(requested)!));
                        activeModel = requested;
                        switched = true;
                    }
                    catch
                    {
                        // The verified file still failed to load — keep the old model and roll back below.
                    }
                }
            }

            if (!switched)
            {
                // Download failed/cancelled (or load threw): keep the live model and undo both the
                // persisted choice and the dropdown selection so they match what's actually running.
                settings.ModelSize = activeModel;
                settingsStore.Save(settings);
                settingsForm.RevertModelSelection(activeModel);
            }
        };
        tray.SettingsRequested += (_, _) =>
        {
            if (!settingsForm.Visible)
            {
                settingsForm.Show();
            }

            settingsForm.Activate();
        };

        // Pause is session-only (spec Feature 6): stop/resume the hook; pausing mid-hold drops the capture.
        tray.PauseToggled += (_, paused) =>
        {
            if (paused)
            {
                hotkey.Pause();
                orchestrator.Cancel();
            }
            else
            {
                hotkey.Resume();
            }
        };

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
            swappable.Dispose(); // disposes whichever speech model is currently active
            coeditPolisher.Dispose();
            coeditModel?.Dispose(); // releases the ~2.4 GB CoEdIT ONNX sessions, if loaded
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
