using SpeakType.Onnx.Inference;
using SpeakType.Onnx.Tokenization;
using Xunit;

namespace SpeakType.Onnx.Tests.Inference;

public sealed class CoEditPolisherTests
{
    private const int VocabSize = 32100; // CoEdIT/Flan-T5 vocab
    private const int EosTokenId = 1;

    private static CoEditTokenizer Tokenizer() => new();

    /// <summary>
    /// Fake model: emits a scripted sequence of next-tokens (one per decode step),
    /// records how it was called. When the script runs out, it emits a fixed non-EOS
    /// token forever (to exercise the runaway cap).
    /// </summary>
    private sealed class FakeModel : ICoEditModel
    {
        private readonly Queue<int> _script;
        private const int FillerToken = 700;

        public int EncodeCalls { get; private set; }
        public int DecodeCalls { get; private set; }
        public IReadOnlyList<int>? LastSourceIds { get; private set; }

        public FakeModel(IEnumerable<int> script) => _script = new Queue<int>(script);

        public IEncoderOutput Encode(IReadOnlyList<int> sourceIds)
        {
            EncodeCalls++;
            LastSourceIds = sourceIds;
            return new Output();
        }

        public float[] DecodeNextLogits(IEncoderOutput encoderOutput, IReadOnlyList<int> decodedSoFar)
        {
            DecodeCalls++;
            int token = _script.Count > 0 ? _script.Dequeue() : FillerToken;
            var logits = new float[VocabSize];
            logits[token] = 10f; // make `token` the argmax
            return logits;
        }

        private sealed class Output : IEncoderOutput { }
    }

    [Fact]
    public void Polish_decodes_scripted_tokens_into_text()
    {
        var tok = Tokenizer();
        // Script the model to emit exactly the tokens for the target sentence
        // (Encode() ends with EOS, which stops the loop).
        var script = tok.Encode("He goes to school every day.");
        var polisher = new CoEditPolisher(tok, new FakeModel(script));

        var result = polisher.Polish("he go to school every days.");

        Assert.Equal("He goes to school every day.", result);
    }

    [Fact]
    public void Polish_prepends_the_instruction_before_encoding()
    {
        var tok = Tokenizer();
        var model = new FakeModel(new[] { EosTokenId }); // stop immediately
        var polisher = new CoEditPolisher(tok, model, instruction: "Fix the grammar: ");

        polisher.Polish("hello there");

        Assert.Equal(tok.Encode("Fix the grammar: hello there"), model.LastSourceIds);
    }

    [Fact]
    public void Polish_runs_the_encoder_exactly_once()
    {
        var tok = Tokenizer();
        var model = new FakeModel(tok.Encode("Anything at all."));
        var polisher = new CoEditPolisher(tok, model);

        polisher.Polish("input text");

        Assert.Equal(1, model.EncodeCalls);
    }

    [Fact]
    public void Polish_stops_at_eos_without_decoding_further()
    {
        var tok = Tokenizer();
        // 3 real tokens then EOS → exactly 4 decode steps, stops at EOS.
        var script = new[] { 100, 200, 300, EosTokenId };
        var model = new FakeModel(script);
        var polisher = new CoEditPolisher(tok, model);

        polisher.Polish("x");

        Assert.Equal(4, model.DecodeCalls);
    }

    [Fact]
    public void Polish_caps_runaway_generation_at_max_new_tokens()
    {
        var tok = Tokenizer();
        var model = new FakeModel(Array.Empty<int>()); // never emits EOS
        var polisher = new CoEditPolisher(tok, model, maxNewTokens: 5);

        polisher.Polish("x");

        Assert.Equal(5, model.DecodeCalls); // bounded, does not hang
    }

    [Fact]
    public void Polish_throws_on_null_text()
    {
        var polisher = new CoEditPolisher(Tokenizer(), new FakeModel(Array.Empty<int>()));
        Assert.Throws<ArgumentNullException>(() => polisher.Polish(null!));
    }
}
