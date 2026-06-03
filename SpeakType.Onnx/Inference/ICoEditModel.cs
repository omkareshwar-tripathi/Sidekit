namespace SpeakType.Onnx.Inference;

/// <summary>
/// The CoEdIT (T5 encoder-decoder) model, abstracted so the greedy-decode loop
/// in <see cref="CoEditPolisher"/> is pure, testable logic. The real implementation
/// (built later) wraps two ONNX Runtime sessions and manages the KV cache + tensor
/// dtype conversions internally; a fake drives the loop with canned logits in tests.
/// </summary>
public interface ICoEditModel
{
    /// <summary>Runs the encoder once over the source token ids.</summary>
    IEncoderOutput Encode(IReadOnlyList<int> sourceIds);

    /// <summary>
    /// Returns the next-token logits (over the full vocabulary) given the encoder
    /// output and the decoder tokens produced so far. Called once per generated token.
    /// </summary>
    float[] DecodeNextLogits(IEncoderOutput encoderOutput, IReadOnlyList<int> decodedSoFar);
}

/// <summary>
/// Opaque handle for the encoder's output, threaded from <see cref="ICoEditModel.Encode"/>
/// into each decode step so the encoder runs exactly once. Implementations carry their
/// own state (e.g. the encoder hidden-state tensor + attention mask).
/// </summary>
public interface IEncoderOutput
{
}
