# The text-correction pipeline

The shared, on-device pipeline that turns a raw speech transcript into clean, properly written text.
It is **not** a language model — it's a chain of three small, fast, special-purpose models. This is
the quality engine behind dictation on **every** platform, so it must stay **portable** (desktop and
mobile both run it).

## The chain

```
Whisper:  "how are you i am fine thank you"
   ↓  SymSpell        — fixes typos / misspellings
   ↓  CNN-BiLSTM      — restores punctuation + casing
   ↓  GECToR          — fixes grammar
Result:   "How are you? I am fine, thank you."
```

| Stage | Model | Job |
|-------|-------|-----|
| 0 | **Whisper** | Speech → raw text (lowercase, no punctuation, occasional typos/homophones) |
| 1 | **SymSpell** | Fast dictionary-based spelling/typo correction |
| 2 | **CNN-BiLSTM** | Restores **punctuation** (. , ?) and **casing** (capitalization) |
| 3 | **GECToR** | **Grammatical error correction** — tag-based edits, *not* generative rewriting |

## Why these, and not an LLM

Each stage is a **small, fast, predictable** model that does one job well. Together they make
dictation read like written English **without** the cost, size, or unpredictability of a generative
LLM. That's what lets the same pipeline run inside a **phone keyboard** (tight memory) as well as on
a laptop. The generative LLM (drafting whole emails) is a **separate, desktop-only** capability —
see [Pillar 2](pillars/2-desktop-local-llm.md). This pipeline is about *cleaning what you said*, not
*writing something new*.

## Where it's used

- **[Pillar 1 — Desktop dictation MVP](pillars/1-mvp-desktop-dictation.md)** (Mac + Windows).
- **[Pillar 3 — Mobile keyboard](pillars/3-mobile-keyboard.md)** (iOS + Android) — same pipeline, no LLM.

Because two platforms share it, the pipeline is the **single strongest reason to keep a portable
core**: write/test it once, run it everywhere.

## Where we are today

The shipped desktop apps already do a **basic cleanup** (filler-word removal, simple
punctuation/spacing/formatting fixups). The **full three-model pipeline above (SymSpell → CNN-BiLSTM
→ GECToR) is the target** — maturing today's cleanup into it is part of finishing the MVP (Pillar 1).

## Open questions

- **Model sizes / quantization** — especially for the phone, where memory is tight (ties into the iOS
  keyboard-extension limit in [Pillar 3](pillars/3-mobile-keyboard.md)).
- **Stage ordering & interaction** — does GECToR after CNN-BiLSTM ever undo punctuation/casing? Needs
  evaluation on real dictation output.
- **Language scope** — English first; other languages are a later question (each stage is
  language-specific).
- **Runtime** — one portable inference stack across platforms vs. per-platform (Core ML / ONNX /
  TFLite). Same native-vs-shared tension that runs through the whole vision.
- **Latency budget** — three models in a row must still feel instant after you stop speaking.
