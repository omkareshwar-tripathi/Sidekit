# Mobile keyboard (iOS + Android) — Sidekit's sibling

**Status:** 🔵 Vision · **Platforms:** iOS + Android · **In Sidekit:** ❌ — separate sibling, reuses the shared dictation + correction core · **Explicitly NOT:** a local LLM / agent

## What it is

The **mobile form** of SpeakType: a **custom keyboard** (a system keyboard extension) you enable in
iOS/Android settings and then use in *any* app. Its job is **voice typing** — tap the mic, speak, and
clean text lands at the cursor in Messages, Mail, WhatsApp, a browser, anywhere.

It runs the exact same two-part core as the desktop dictation MVP:

1. **Whisper** — on-device speech-to-text.
2. The [**text-correction pipeline**](../text-correction-pipeline.md) — SymSpell (typos) →
   CNN-BiLSTM (punctuation + casing) → GECToR (grammar).

**No LLM.** The generative drafting from [Pillar 2](2-desktop-local-llm.md) stays on desktop. Phones
get *accurate voice typing*, not *"write my email."* This is a deliberate scope line, set by mobile
constraints.

## Why a keyboard, not an app

On desktop, SpeakType types into any app from the outside via a global hotkey + paste. **Mobile OSes
forbid that.** The only sanctioned way to put text into arbitrary apps on a phone is to **be the
keyboard**. So mobile ships as a keyboard extension while desktop stays a standalone app — same
Whisper + correction core, different shell.

## Why it's third (after desktop)

Mobile reuses the **proven** Whisper + correction core from Pillars 1–2, so it's best built once that
core is solid. It introduces a whole new platform (store review, OS sandboxing, a real memory risk),
so it follows the lower-risk desktop work rather than leading. It does **not** depend on the LLM (the
agent isn't on mobile), so it doesn't wait on Pillar 2's quality.

## Dependencies

- Reuses the **portable text-correction pipeline** — the strongest reason that core must be portable.
- An on-device **Whisper** runtime per platform (Core ML on iOS; ONNX/TFLite-class on Android).
- Forces (or strongly benefits from) deciding **how code is shared** across desktop and mobile — the
  cross-platform architecture call, folded into this step.

## Open questions & risks

- **iOS keyboard-extension memory limit (the big risk + the gating spike).** iOS gives keyboard
  extensions a tight memory budget — historically too small to load Whisper *inside the extension*.
  Likely needs the **containing app + App Group** to run inference and hand text back, or a very small
  model. **Validate this with a spike before committing** — it shapes the whole iOS design.
- **"Full access" permission** — both OSes require granting the keyboard extra access; explain why and
  keep it fully offline.
- **Whisper size vs. speed** on a mid-range phone.
- **Layout scope** — a full typing keyboard, or a mic-first minimal keyboard that defers to the system
  keyboard for regular typing? (Smaller scope = faster first version.)

## What "done" looks like

You switch to the SpeakType keyboard in any app on your phone, tap the mic, speak, and clean,
correctly-punctuated, grammatical text appears at the cursor — processed entirely on the device, no
LLM needed, the same trustworthy voice typing your laptop gives you.
