using SpeakType.Core.Orchestration;

namespace SpeakType.App.Threading;

/// <summary>
/// <see cref="ICycleDispatcher"/> that runs each dictation cycle on a thread-pool thread, so the
/// transcription (which blocks for ~1 s) never freezes the UI (spec Feature 2). A cycle that throws
/// is reported through <c>onError</c> rather than faulting an unobserved <see cref="Task"/>; the
/// orchestrator has already reset its own state to Idle by then.
/// </summary>
internal sealed class BackgroundCycleDispatcher : ICycleDispatcher
{
    private readonly Action<Exception> _onError;

    public BackgroundCycleDispatcher(Action<Exception> onError)
    {
        ArgumentNullException.ThrowIfNull(onError);
        _onError = onError;
    }

    public void Run(Action cycle)
    {
        ArgumentNullException.ThrowIfNull(cycle);
        Task.Run(() =>
        {
            try
            {
                cycle();
            }
            catch (Exception ex)
            {
                _onError(ex);
            }
        });
    }
}
