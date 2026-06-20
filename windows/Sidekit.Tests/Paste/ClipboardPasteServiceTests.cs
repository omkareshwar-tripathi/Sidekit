using Sidekit.Core.Paste;

namespace Sidekit.Tests.Paste;

public sealed class ClipboardPasteServiceTests
{
    /// <summary>
    /// Records every clipboard operation (and the injected delay) into one ordered log
    /// so tests can assert the save→set→paste→delay→restore sequence.
    /// </summary>
    private sealed class FakeClipboard : IClipboard
    {
        public List<string> Ops { get; } = new();
        public string? CurrentText { get; set; }
        public bool PasteSucceeds { get; set; } = true;

        public string? GetText()
        {
            Ops.Add("GetText");
            return CurrentText;
        }

        public void SetText(string text) => Ops.Add($"SetText:{text}");

        public void Clear() => Ops.Add("Clear");

        public bool SendPaste()
        {
            Ops.Add("SendPaste");
            return PasteSucceeds;
        }
    }

    private readonly FakeClipboard _clipboard = new();

    private ClipboardPasteService CreateSut() =>
        new(_clipboard, _ => _clipboard.Ops.Add("Delay")); // no-op delay that logs its ordering

    [Fact]
    public void Successful_paste_runs_the_full_sequence_in_order()
    {
        _clipboard.CurrentText = "ORIGINAL";

        var outcome = CreateSut().Paste("OURTEXT");

        Assert.Equal(PasteOutcome.Pasted, outcome);
        Assert.Equal(
            new[] { "GetText", "SetText:OURTEXT", "SendPaste", "Delay", "SetText:ORIGINAL" },
            _clipboard.Ops);
    }

    [Fact]
    public void Restore_happens_after_the_delay()
    {
        _clipboard.CurrentText = "ORIGINAL";

        CreateSut().Paste("OURTEXT");

        var paste = _clipboard.Ops.IndexOf("SendPaste");
        var delay = _clipboard.Ops.IndexOf("Delay");
        var restore = _clipboard.Ops.IndexOf("SetText:ORIGINAL");
        Assert.True(paste < delay && delay < restore); // spec Feature 5 step 4: wait, then restore
    }

    [Fact]
    public void Original_was_null_clears_on_restore()
    {
        _clipboard.CurrentText = null;

        var outcome = CreateSut().Paste("OURTEXT");

        Assert.Equal(PasteOutcome.Pasted, outcome);
        Assert.Equal("Clear", _clipboard.Ops[^1]); // restore empties rather than re-setting text
        Assert.Single(_clipboard.Ops, op => op.StartsWith("SetText:")); // only our text was set; restore used Clear, not a re-set
    }

    [Fact]
    public void Blocked_paste_leaves_our_text_on_the_clipboard()
    {
        _clipboard.CurrentText = "ORIGINAL";
        _clipboard.PasteSucceeds = false; // OS blocked SendInput (e.g. elevated foreground window)

        var outcome = CreateSut().Paste("OURTEXT");

        Assert.Equal(PasteOutcome.LeftOnClipboard, outcome);
        Assert.Contains("SetText:OURTEXT", _clipboard.Ops); // our words are still safe on the clipboard
        Assert.DoesNotContain("Delay", _clipboard.Ops);
        Assert.DoesNotContain("SetText:ORIGINAL", _clipboard.Ops); // never restored over our text
        Assert.DoesNotContain("Clear", _clipboard.Ops);
    }

    [Fact]
    public void Null_text_throws()
    {
        Assert.Throws<ArgumentNullException>(() => CreateSut().Paste(null!));
    }

    [Fact]
    public void Null_clipboard_throws()
    {
        Assert.Throws<ArgumentNullException>(() => new ClipboardPasteService(null!));
    }
}
