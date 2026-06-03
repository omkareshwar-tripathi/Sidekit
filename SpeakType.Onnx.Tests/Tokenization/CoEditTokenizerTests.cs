using SpeakType.Onnx.Tokenization;
using Xunit;

namespace SpeakType.Onnx.Tests.Tokenization;

public sealed class CoEditTokenizerTests
{
    // Golden vectors generated from the reference HuggingFace tokenizer
    // (tokenizers==latest, tokenizer.json from grammarly/coedit-large).
    // These pin exact agreement with the Python reference — any drift fails here.
    public static IEnumerable<object[]> GoldenVectors() => new[]
    {
        new object[] { "Fix the grammar: he go to school every days.",
            new[] { 14269, 8, 19519, 10, 3, 88, 281, 12, 496, 334, 477, 5, 1 } },
        new object[] { "Fix the grammar: i has went to the store yesterday.",
            new[] { 14269, 8, 19519, 10, 3, 23, 65, 877, 12, 8, 1078, 4981, 5, 1 } },
        new object[] { "Fix the grammar: she dont like apples.",
            new[] { 14269, 8, 19519, 10, 255, 2483, 114, 16981, 5, 1 } },
        new object[] { "Hello world.",
            new[] { 8774, 296, 5, 1 } },
        new object[] { "Fix the grammar: ",
            new[] { 14269, 8, 19519, 10, 3, 1 } },
    };

    private static CoEditTokenizer NewTokenizer() =>
        new(CoEditTokenizer.DefaultTokenizerPath);

    [Theory]
    [MemberData(nameof(GoldenVectors))]
    public void Encode_matches_reference_token_ids(string text, int[] expected)
    {
        var ids = NewTokenizer().Encode(text);
        Assert.Equal(expected, ids);
    }

    [Fact]
    public void Encode_appends_eos_token()
    {
        var ids = NewTokenizer().Encode("Hello world.");
        Assert.Equal(1, ids[^1]); // T5 EOS = id 1
    }

    [Theory]
    [MemberData(nameof(GoldenVectors))]
    public void Decode_round_trips_and_strips_special_tokens(string text, int[] ids)
    {
        var decoded = NewTokenizer().Decode(ids);
        Assert.Equal(text, decoded); // EOS (id 1) is stripped, original text restored
    }

    [Fact]
    public void Constructor_throws_when_file_missing()
    {
        Assert.Throws<FileNotFoundException>(() => new CoEditTokenizer("/no/such/tokenizer.json"));
    }

    [Fact]
    public void Encode_throws_on_null_text()
    {
        Assert.Throws<ArgumentNullException>(() => NewTokenizer().Encode(null!));
    }
}
