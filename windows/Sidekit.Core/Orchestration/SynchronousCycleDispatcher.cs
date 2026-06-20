namespace Sidekit.Core.Orchestration;

/// <summary>Default <see cref="ICycleDispatcher"/>: runs the cycle inline on the calling thread.
/// The orchestrator's fallback when no dispatcher is injected (keeps the existing synchronous
/// behaviour); the composition root replaces it with a background-thread dispatcher.</summary>
public sealed class SynchronousCycleDispatcher : ICycleDispatcher
{
    public void Run(Action cycle) => cycle();
}
