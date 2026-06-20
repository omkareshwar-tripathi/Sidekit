using Sidekit.Core.Cleanup;

namespace Sidekit.Tests.Cleanup;

public sealed class TranscriptCleanerTests
{
    [Theory]
    [InlineData("Um, I think, you know, we should ship it.", "I think we should ship it. ")]
    [InlineData("I mean it.", "I mean it. ")]
    [InlineData("do you know the answer?", "do you know the answer? ")]
    [InlineData("i like pizza", "I like pizza ")]
    [InlineData("Um, we should ship it.", "We should ship it. ")]
    [InlineData("Uh, you know, it works.", "It works. ")]
    [InlineData("We should ship it, you know.", "We should ship it. ")]
    [InlineData("You know, it works.", "It works. ")]
    [InlineData("I think um it works.", "I think it works. ")]
    [InlineData("I think, um, it works.", "I think it works. ")]
    [InlineData("I sort of like it.", "I sort of like it. ")]
    [InlineData("Uh.", "")]
    public void Clean_with_filler_removal_on(string raw, string expected)
    {
        var cleaner = new TranscriptCleaner();

        Assert.Equal(expected, cleaner.Clean(raw));
    }

    // Guards spec-defined behaviors that the primary corpus leaves unexercised:
    // sort-of/kind-of *removal* (not just the kept case), multi-sentence fillers
    // after terminal punctuation, a filler right before a terminator, a leading
    // filler followed by a non-letter, and stacked bare fillers.
    [Theory]
    [InlineData("It is, sort of, fine.", "It is fine. ")]            // comma-bounded "sort of" removed
    [InlineData("I get it, kind of.", "I get it. ")]                  // "kind of" before terminator
    [InlineData("Kind of, it works.", "It works. ")]                 // "kind of" at sentence start
    [InlineData("It works. Um, then we ship.", "It works. Then we ship. ")] // filler after a period (comma)
    [InlineData("It works. Um then we ship.", "It works. Then we ship. ")]  // bare filler after a period
    [InlineData("I think, um.", "I think. ")]                         // filler immediately before terminator
    [InlineData("Um 2024 was rough.", "2024 was rough. ")]            // leading filler before a digit
    [InlineData("I think um er it works.", "I think it works. ")]     // two stacked bare fillers
    public void Clean_guards_each_filler_pass(string raw, string expected)
    {
        var cleaner = new TranscriptCleaner();

        Assert.Equal(expected, cleaner.Clean(raw));
    }

    [Theory]
    [InlineData("Um, I think, you know, we should ship it.", "Um, I think, you know, we should ship it. ")]
    [InlineData("i like pizza", "I like pizza ")]
    public void Clean_with_filler_removal_off(string raw, string expected)
    {
        var cleaner = new TranscriptCleaner();

        Assert.Equal(expected, cleaner.Clean(raw, removeFillers: false));
    }

    [Theory]
    [InlineData("[BLANK_AUDIO]")]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("Thank you.")]
    [InlineData("you")]
    [InlineData("You")]
    public void Clean_drops_hallucinations_and_empty(string raw)
    {
        var cleaner = new TranscriptCleaner();

        Assert.Equal("", cleaner.Clean(raw));
    }
}
