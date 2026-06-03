using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace SpeakType.Onnx.Inference;

/// <summary>
/// Real <see cref="ICoEditModel"/> backed by two ONNX Runtime sessions — the
/// Flan-T5 encoder and the merged decoder (with KV cache). The encoder runs once
/// per <see cref="Encode"/>; each <see cref="DecodeNextLogits"/> runs the decoder
/// for one token, feeding the previous step's key/value cache so generation is
/// O(n) rather than O(n^2).
/// <para>All graph I/O is float32 (the encoder is fp16 internally but keeps fp32 I/O).</para>
/// </summary>
public sealed class OnnxCoEditModel : ICoEditModel, IDisposable
{
    // Flan-T5-large dims, from config.json.
    private const int NumLayers = 24;
    private const int NumHeads = 16;
    private const int HeadDim = 64;

    private static readonly string[] Kinds = { "decoder", "encoder" };
    private static readonly string[] KeyValue = { "key", "value" };

    private readonly InferenceSession _encoder;
    private readonly InferenceSession _decoder;

    public OnnxCoEditModel(string encoderPath, string decoderPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(encoderPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(decoderPath);
        if (!File.Exists(encoderPath))
            throw new FileNotFoundException("CoEdIT encoder model not found.", encoderPath);
        if (!File.Exists(decoderPath))
            throw new FileNotFoundException("CoEdIT decoder model not found.", decoderPath);

        _encoder = new InferenceSession(encoderPath);
        _decoder = new InferenceSession(decoderPath);
    }

    public IEncoderOutput Encode(IReadOnlyList<int> sourceIds)
    {
        ArgumentNullException.ThrowIfNull(sourceIds);
        int n = sourceIds.Count;

        var inputIds = new DenseTensor<long>(new[] { 1, n });
        var attention = new DenseTensor<long>(new[] { 1, n });
        for (int i = 0; i < n; i++)
        {
            inputIds[0, i] = sourceIds[i];
            attention[0, i] = 1;
        }

        using var results = _encoder.Run(new[]
        {
            NamedOnnxValue.CreateFromTensor("input_ids", inputIds),
            NamedOnnxValue.CreateFromTensor("attention_mask", attention),
        });

        var hidden = results.First(r => r.Name == "last_hidden_state").AsTensor<float>();
        var hiddenCopy = new DenseTensor<float>(hidden.ToArray(), hidden.Dimensions.ToArray());
        return new State(hiddenCopy, attention);
    }

    public float[] DecodeNextLogits(IEncoderOutput encoderOutput, IReadOnlyList<int> decodedSoFar)
    {
        ArgumentNullException.ThrowIfNull(encoderOutput);
        ArgumentNullException.ThrowIfNull(decodedSoFar);
        var state = (State)encoderOutput;
        bool firstStep = state.Cache is null;

        var inputIds = new DenseTensor<long>(new[] { 1, 1 });
        inputIds[0, 0] = decodedSoFar[^1];

        var inputs = new List<NamedOnnxValue>(4 + NumLayers * 4)
        {
            NamedOnnxValue.CreateFromTensor("encoder_attention_mask", state.AttentionMask),
            NamedOnnxValue.CreateFromTensor("input_ids", inputIds),
            NamedOnnxValue.CreateFromTensor("encoder_hidden_states", state.EncoderHidden),
            NamedOnnxValue.CreateFromTensor(
                "use_cache_branch", new DenseTensor<bool>(new[] { !firstStep }, new[] { 1 })),
        };

        ForEachKv((i, kind, kv) =>
        {
            var past = firstStep
                ? new DenseTensor<float>(new[] { 1, NumHeads, 0, HeadDim }) // empty on first step
                : state.Cache![Present(i, kind, kv)];
            inputs.Add(NamedOnnxValue.CreateFromTensor($"past_key_values.{i}.{kind}.{kv}", past));
        });

        using var results = _decoder.Run(inputs);
        var byName = results.ToDictionary(r => r.Name, r => r.AsTensor<float>());

        var logitsTensor = byName["logits"];                 // [1, 1, vocab]
        int vocab = logitsTensor.Dimensions[^1];
        var logits = new float[vocab];
        for (int v = 0; v < vocab; v++)
            logits[v] = logitsTensor[0, 0, v];

        var newCache = new Dictionary<string, DenseTensor<float>>(NumLayers * 4);
        ForEachKv((i, kind, kv) =>
        {
            string name = Present(i, kind, kv);
            var t = byName[name];
            newCache[name] = new DenseTensor<float>(t.ToArray(), t.Dimensions.ToArray());
        });
        state.Cache = newCache;

        return logits;
    }

    private static string Present(int layer, string kind, string kv) => $"present.{layer}.{kind}.{kv}";

    private static void ForEachKv(Action<int, string, string> action)
    {
        for (int i = 0; i < NumLayers; i++)
            foreach (var kind in Kinds)
                foreach (var kv in KeyValue)
                    action(i, kind, kv);
    }

    public void Dispose()
    {
        _encoder.Dispose();
        _decoder.Dispose();
    }

    private sealed class State : IEncoderOutput
    {
        public DenseTensor<float> EncoderHidden { get; }
        public DenseTensor<long> AttentionMask { get; }

        /// <summary>Present key/values from the previous decode step; null before the first step.</summary>
        public Dictionary<string, DenseTensor<float>>? Cache { get; set; }

        public State(DenseTensor<float> encoderHidden, DenseTensor<long> attentionMask)
        {
            EncoderHidden = encoderHidden;
            AttentionMask = attentionMask;
        }
    }
}
