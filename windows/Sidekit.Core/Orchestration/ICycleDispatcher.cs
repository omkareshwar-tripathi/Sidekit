namespace Sidekit.Core.Orchestration;

/// <summary>
/// Runs one dictation cycle (capture → transcribe → clean → paste). The default
/// <see cref="SynchronousCycleDispatcher"/> runs it inline on the calling thread; the composition
/// root supplies an implementation that offloads it to a background thread so transcription never
/// blocks the UI (spec Feature 2). The orchestrator hands each cycle to <see cref="Run"/> exactly
/// once per dictation, fire-and-forget, after winning its atomic state claim.
/// </summary>
public interface ICycleDispatcher
{
    void Run(Action cycle);
}
