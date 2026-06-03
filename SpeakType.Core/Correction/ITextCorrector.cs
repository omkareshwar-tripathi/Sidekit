namespace SpeakType.Core.Correction;

/// <summary>
/// One Fix-pipeline stage: a pure, synchronous string→string transform applied
/// to dictated text after <c>TranscriptCleaner</c> and before paste.
/// </summary>
public interface ITextCorrector
{
    string Correct(string text);
}
