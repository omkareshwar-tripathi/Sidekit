using System.Reflection;
using System.Text.RegularExpressions;

namespace SpeakType.Core.Correction;

/// <summary>
/// Conservative spelling correction (spec §3). Operates token-by-token via regex so
/// all surrounding punctuation and the cleaner's trailing space survive. A word is
/// only changed when it is all-lowercase, longer than two letters, unknown to the
/// dictionary, and a single-edit suggestion clears a frequency floor — this protects
/// names, ACRONYMS, jargon, and rare-but-valid words. Fail-open: any internal error
/// returns the input unchanged so the user never loses text.
/// </summary>
public sealed partial class SymSpellCorrector : ITextCorrector
{
    private const int MaxEdit = 1;
    // Frequency floor: reject a suggestion whose corpus count is below this, so a real
    // but rare word isn't swapped for a common near-match. Pinned conservatively; the
    // skip rules above are the primary safety net. Tune against the dictionary if needed.
    private const long FrequencyFloor = 1_000_000;

    private readonly global::SymSpell _symSpell =
        new(initialCapacity: 82_765, maxDictionaryEditDistance: MaxEdit);

    [GeneratedRegex("[A-Za-z]+")]
    private static partial Regex WordToken();

    public SymSpellCorrector()
    {
        using var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("frequency_dictionary_en_82_765.txt")
            ?? throw new InvalidOperationException(
                "Embedded SymSpell dictionary 'frequency_dictionary_en_82_765.txt' not found.");
        // SymSpell 6.7.3: LoadDictionary(Stream, termIndex, countIndex) — separatorChars is optional.
        if (!_symSpell.LoadDictionary(stream, termIndex: 0, countIndex: 1))
        {
            throw new InvalidOperationException("Failed to load embedded SymSpell dictionary.");
        }
    }

    public string Correct(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text;
        }

        try
        {
            return WordToken().Replace(text, m => CorrectToken(m.Value));
        }
        catch
        {
            return text; // fail-open: never lose the user's text
        }
    }

    private string CorrectToken(string token)
    {
        if (token.Length <= 2 || !IsAllLower(token))
        {
            return token;
        }

        var suggestions = _symSpell.Lookup(token, global::SymSpell.Verbosity.Top, MaxEdit);
        if (suggestions.Count == 0)
        {
            return token;
        }

        var top = suggestions[0];
        if (top.distance == 0) return token;            // exact match: word is already valid
        if (top.count < FrequencyFloor) return token;   // suggestion too rare to trust

        return top.term;
    }

    private static bool IsAllLower(string token)
    {
        foreach (var c in token)
        {
            if (char.IsUpper(c))
            {
                return false;
            }
        }
        return true;
    }
}
