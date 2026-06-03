using SpeakType.Core.Settings;

namespace SpeakType.Core.Correction;

/// <summary>
/// Runs an ordered list of <see cref="ITextCorrector"/> stages, applying each only
/// when its <c>isEnabled</c> predicate returns true for the current settings.
/// Predicates are evaluated per call, so a settings change (e.g. a Settings-form
/// toggle) takes effect on the next dictation with no re-wiring. Pure Core.
/// </summary>
public sealed class TextCorrectionPipeline
{
    private readonly IReadOnlyList<(ITextCorrector Corrector, Func<AppSettings, bool> IsEnabled)> _stages;

    public TextCorrectionPipeline(
        IReadOnlyList<(ITextCorrector corrector, Func<AppSettings, bool> isEnabled)> stages)
    {
        ArgumentNullException.ThrowIfNull(stages);
        _stages = stages;
    }

    public string Correct(string text, AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(settings);
        foreach (var (corrector, isEnabled) in _stages)
        {
            if (isEnabled(settings))
            {
                text = corrector.Correct(text);
            }
        }
        return text;
    }
}
