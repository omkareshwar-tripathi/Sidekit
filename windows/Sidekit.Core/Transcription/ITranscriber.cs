namespace Sidekit.Core.Transcription;

/// <summary>Turns 16 kHz mono samples into a raw transcript string.</summary>
public interface ITranscriber
{
    string Transcribe(float[] samples);
}
