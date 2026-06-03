namespace SpeakType.Core.Polishing;

/// <summary>
/// Improves a piece of transcribed text (grammar/clarity) on-device.
/// Synchronous: callers run it on a background thread, so no async is needed.
/// </summary>
public interface ITextPolisher
{
    string Polish(string text);
}
