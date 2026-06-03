using SpeakType.Core.Correction;

namespace SpeakType.Tests.Correction;

public sealed class SymSpellCorrectorFixture
{
    public SymSpellCorrector Sut { get; } = new();
}

public sealed class SymSpellCorrectorTests(SymSpellCorrectorFixture fixture)
    : IClassFixture<SymSpellCorrectorFixture>
{
    private readonly SymSpellCorrector _sut = fixture.Sut;

    [Fact]
    public void Fixes_a_clear_lowercase_typo()
    {
        // "recieve" is a classic misspelling; edit-distance 1 to "receive".
        Assert.Equal("please receive it", _sut.Correct("please recieve it"));
    }

    [Fact]
    public void Leaves_known_words_unchanged()
    {
        Assert.Equal("the quick brown fox", _sut.Correct("the quick brown fox"));
    }

    [Fact]
    public void Skips_capitalized_tokens_protecting_proper_nouns()
    {
        Assert.Equal("Kubernetes and Omkareshwar", _sut.Correct("Kubernetes and Omkareshwar"));
    }

    [Fact]
    public void Skips_allcaps_acronyms()
    {
        Assert.Equal("the HTTP API", _sut.Correct("the HTTP API"));
    }

    [Fact]
    public void Skips_short_tokens()
    {
        Assert.Equal("go to ok", _sut.Correct("go to ok"));
    }

    [Fact]
    public void Preserves_punctuation_and_trailing_space()
    {
        var result = _sut.Correct("Hello, freind. ");
        Assert.Equal("Hello, friend. ", result);
    }

    [Fact]
    public void Empty_string_returns_empty()
    {
        Assert.Equal("", _sut.Correct(""));
    }

    [Fact]
    public void Leaves_unknown_lowercase_word_with_no_suggestion_unchanged()
    {
        // No dictionary word is within edit-distance 1, so it must pass through.
        Assert.Equal("xyzzyx", _sut.Correct("xyzzyx"));
    }

    [Fact]
    public void Skips_mixed_case_tokens()
    {
        // Mid-word capitals (camelCase / brand spellings) are not all-lowercase ⇒ skipped.
        Assert.Equal("iPhone and WiFi", _sut.Correct("iPhone and WiFi"));
    }
}
