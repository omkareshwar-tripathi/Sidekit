using System.Text.RegularExpressions;

namespace Sidekit.Core.Cleanup;

/// <summary>
/// Pure, side-effect-free cleanup of a raw Whisper transcript. Stages run in a
/// fixed order: optional filler removal, always-on debris fixups, trimming, and
/// a hallucination/empty filter. A non-empty result always ends in a single
/// trailing space; terminal punctuation is never forced.
/// </summary>
public sealed class TranscriptCleaner
{
    // Always-removable disfluencies, even when bare (no surrounding commas).
    private const string Always = "um|uh|er|ah|hmm|mm";

    // Discourse-marker phrases — removed only at a comma/sentence boundary, so
    // genuine uses ("do you know the answer?", "I sort of like it") survive.
    private const string Phrase = @"you\ know|I\ mean|sort\ of|kind\ of";

    // ALWAYS ∪ PHRASE, used by the boundary-sensitive passes (1–3).
    private const string Any = Always + "|" + Phrase;

    // Interpreted (not Compiled): Clean() runs once per dictation, so the JIT
    // cost of Compiled would never pay back over so few invocations.
    private const RegexOptions Options = RegexOptions.IgnoreCase;

    // 1. Filler immediately before a sentence terminator: ", um." → "."
    private static readonly Regex SentenceEnd =
        new($@"\s*,\s*(?:{Any})\b\s*([.!?])", Options);

    // 2. Comma-bounded interior filler: "x, um, y" → "x y".
    private static readonly Regex CommaBounded =
        new($@"\s*,\s*(?:{Any})\b\s*,\s*", Options);

    // 3. Filler at the very start, with a required comma, re-capitalizing the
    //    next letter. "Um, i think" → "I think".
    private static readonly Regex StartComma =
        new($@"^\s*(?:{Any})\b\s*,\s*(\p{{L}})", Options);

    // 3b. Same, but after a terminal punctuation mark.
    private static readonly Regex AfterPunctComma =
        new($@"([.!?]\s+)(?:{Any})\b\s*,\s*(\p{{L}})", Options);

    // 4. ALWAYS-word at the start with an optional comma, re-capitalizing next.
    private static readonly Regex StartAlways =
        new($@"^\s*(?:{Always})\b,?\s*(\p{{L}})", Options);

    // 4b. Same, after terminal punctuation.
    private static readonly Regex AfterPunctAlways =
        new($@"([.!?]\s+)(?:{Always})\b,?\s*(\p{{L}})", Options);

    // 5. Bare interior ALWAYS-word: "I think um it" → "I think it".
    private static readonly Regex BareAlways =
        new($@"\s+(?:{Always})\b", Options);

    // 6. A string that is nothing but an ALWAYS word plus trailing punctuation
    //    ("Uh.") reduces to empty.
    private static readonly Regex WholeAlways =
        new($@"^\s*(?:{Always})\b[,.!?\s]*$", Options);

    // 6b. Pure-filler ALWAYS leftover at the start with no following letter,
    //    stripped so debris fixups can finish the job.
    private static readonly Regex StartAlwaysBare =
        new($@"^\s*(?:{Always})\b,?\s*", Options);

    // Fixups.
    private static readonly Regex MultipleCommas = new(@",(\s*,)+", Options);
    private static readonly Regex SpaceBeforeComma = new(@" +,", Options);
    private static readonly Regex MultipleSpaces = new(@" {2,}", Options);
    private static readonly Regex LeadingDebris = new(@"^[,\s]+", Options);
    private static readonly Regex LoneI = new(@"\bi\b", Options);

    // Exact tokens Whisper emits in place of non-speech audio.
    private static readonly string[] Sentinels = { "[BLANK_AUDIO]" };

    // Short courtesy/filler phrases Whisper hallucinates from a near-silent clip;
    // treated as noise only when one of them is the whole output (see IsHallucination).
    private static readonly string[] SilencePhrases = { "you", "Thank you." };

    /// <summary>
    /// Cleans <paramref name="raw"/>. When <paramref name="removeFillers"/> is
    /// true, disfluencies and boundary discourse markers are stripped. Returns an
    /// empty string for empty input or a known silence-hallucination; otherwise
    /// the trimmed text plus a single trailing space.
    /// </summary>
    public string Clean(string? raw, bool removeFillers = true)
    {
        var text = raw ?? "";

        if (removeFillers)
        {
            text = RemoveFillers(text);
        }

        text = Fixups(text);

        var trimmed = text.Trim();

        if (trimmed.Length == 0 || IsHallucination(trimmed))
        {
            return "";
        }

        return trimmed + " ";
    }

    private static string RemoveFillers(string text)
    {
        text = SentenceEnd.Replace(text, "$1");
        text = CommaBounded.Replace(text, " ");
        text = StartComma.Replace(text, m => m.Groups[1].Value.ToUpperInvariant());
        text = AfterPunctComma.Replace(
            text, m => m.Groups[1].Value + m.Groups[2].Value.ToUpperInvariant());
        text = StartAlways.Replace(text, m => m.Groups[1].Value.ToUpperInvariant());
        text = AfterPunctAlways.Replace(
            text, m => m.Groups[1].Value + m.Groups[2].Value.ToUpperInvariant());
        text = BareAlways.Replace(text, "");
        text = WholeAlways.Replace(text, "");
        text = StartAlwaysBare.Replace(text, "");
        return text;
    }

    private static string Fixups(string text)
    {
        text = MultipleCommas.Replace(text, ",");
        text = SpaceBeforeComma.Replace(text, ",");
        text = MultipleSpaces.Replace(text, " ");
        text = LeadingDebris.Replace(text, "");
        text = LoneI.Replace(text, "I");
        return text;
    }

    private static bool IsHallucination(string trimmed) =>
        Sentinels.Contains(trimmed, StringComparer.OrdinalIgnoreCase) ||
        SilencePhrases.Contains(trimmed, StringComparer.OrdinalIgnoreCase);
}
