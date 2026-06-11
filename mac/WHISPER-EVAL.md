# Whisper dictation quality eval — adversarial battery

Purpose: find out **how** dictation fails per model, not just whether — so each error points at the
right fix. Run it in the lab (`lab/whisper-compare/`, three models side by side) **or** by dictating
into the shipping app. Today the app runs **`base.en`** + the regex `TranscriptCleaner` (filler/whitespace
only — no spelling, grammar, or dictionary).

## How to score (be strict)

For each line, compare each model's output to **Reference** and count errors:

- **1 error per** wrong/missing/extra word, wrong casing, or wrong/missing punctuation that changes meaning.
- Tag every error with a **bucket** (below). A line can score several errors across buckets.
- Put the **error count** in that model's column (0 = perfect). Lower total = better.
- Also note each model's **seconds** (the lab shows it). The winner is the *smallest/fastest model whose
  score and latency are both acceptable* — not necessarily the most accurate.

### Buckets → fix

| Code | Meaning | Likely fix |
|---|---|---|
| **W** | Wrong word / homophone (real word, wrong one) | **Bigger Whisper model.** Pipeline barely helps. |
| **N** | Proper noun / name / jargon mangled | **Custom dictionary** (decode-bias or post-step). |
| **P** | Missing/wrong punctuation | Bigger model first; punctuation model only if needed. |
| **C** | Bad casing | Bigger model first; else a casing pass. |
| **F** | Filler / false-start / self-correction left in | Cleaner; self-corrections need the **LLM**. |
| **X** | Formatting/symbol intent missed | **A feature** (voice formatting), not correction. |
| **H** | Hallucinated text on silence/noise, or dropped speech | Silence gate / hallucination filter. |

---

## The battery

Score columns: **b** = base.en (current), **s** = small.en, **L** = large-v3-turbo. Enter an error count.

### A · Homophone traps (bucket W)
| # | Say this | Reference | b | s | L |
|---|----------|-----------|--|--|--|
|A1| Whether or not the weather clears, wear the gear, and we'll see where we are. | Whether or not the weather clears, wear the gear, and we'll see where we are. | | | |
|A2| It's not its fault that they're parking their car over there. | It's not its fault that they're parking their car over there. | | | |
|A3| I accept your point, except for the part about the dessert in the desert. | I accept your point, except for the part about the dessert in the desert. | | | |
|A4| He read the red book, and tomorrow we'll read the manual aloud. | He read the red book, and tomorrow we'll read the manual aloud. | | | |

### B · Hard multicultural names (bucket N)
| # | Say this | Reference | b | s | L |
|---|----------|-----------|--|--|--|
|B1| Loop in Siobhan, Saoirse, Xóchitl, Nguyen, and Rajesh before the standup. | Loop in Siobhan, Saoirse, Xóchitl, Nguyen, and Rajesh before the standup. | | | |
|B2| Dr. Onyekwere and Ms. Dvořák reviewed Zhang's manuscript. | Dr. Onyekwere and Ms. Dvořák reviewed Zhang's manuscript. | | | |
|B3| Forward Joaquín and Mai-Linh's notes to Przemysław. | Forward Joaquín and Mai-Linh's notes to Przemysław. | | | |

### C · Dense technical jargon (bucket N, some W)
| # | Say this | Reference | b | s | L |
|---|----------|-----------|--|--|--|
|C1| SSH into the Kubernetes node, restart nginx, flush the Redis cache, and tail the kubectl logs. | SSH into the Kubernetes node, restart nginx, flush the Redis cache, and tail the kubectl logs. | | | |
|C2| The OAuth JWT expired, so PostgreSQL rejected the gRPC call from the Kafka consumer. | The OAuth JWT expired, so PostgreSQL rejected the gRPC call from the Kafka consumer. | | | |
|C3| Refactor the async await in the TypeScript SDK and bump the npm semver to 4.8.1. | Refactor the async/await in the TypeScript SDK and bump the npm semver to 4.8.1. | | | |

### D · Acronyms vs. real words (buckets C, W)
| # | Say this | Reference | b | s | L |
|---|----------|-----------|--|--|--|
|D1| The US needs us to send the IT team an ETA as soon as possible. | The US needs us to send the IT team an ETA as soon as possible. | | | |
|D2| Read the API docs, then read them to the QA lead. | Read the API docs, then read them to the QA lead. | | | |
|D3| The CEO, CFO, and CTO signed the NDA at 9 AM EST. | The CEO, CFO, and CTO signed the NDA at 9 AM EST. | | | |

### E · Numbers, money, dates, versions (buckets X, P)
| # | Say this | Reference (ideal) | b | s | L |
|---|----------|-----------|--|--|--|
|E1| Transfer one thousand two hundred fifty dollars and seventy five cents by March 3rd. | Transfer $1,250.75 by March 3rd. *(digits/`$` are X — likely missed)* | | | |
|E2| Upgrade from version 3.9.18 to 4.8.1 and set the timeout to 250 milliseconds. | Upgrade from version 3.9.18 to 4.8.1 and set the timeout to 250 milliseconds. | | | |
|E3| The package weighs 2.5 kilograms and ships 7,500 kilometers. | The package weighs 2.5 kilograms and ships 7,500 kilometers. | | | |
|E4| Call me at four one five, five five five, zero one four two, at half past two. | Call me at 415-555-0142 at half past two. *(formatting is X)* | | | |

### F · Punctuation changes meaning (bucket P)
| # | Say this | Reference | b | s | L |
|---|----------|-----------|--|--|--|
|F1| Let's eat, Grandma, before we leave. | Let's eat, Grandma, before we leave. | | | |
|F2| I'd like to thank my parents, Ayn Rand, and God. | I'd like to thank my parents, Ayn Rand, and God. | | | |
|F3| Is it ready, or should we wait | Is it ready, or should we wait? | | | |

### G · Casing-sensitive brands (bucket C)
| # | Say this | Reference | b | s | L |
|---|----------|-----------|--|--|--|
|G1| I use macOS, iOS, iPadOS, GitHub, npm, and eBay daily. | I use macOS, iOS, iPadOS, GitHub, npm, and eBay daily. | | | |
|G2| Open VS Code, push to GitHub, and deploy on Vercel. | Open VS Code, push to GitHub, and deploy on Vercel. | | | |

### H · Disfluencies & self-corrections (bucket F)
| # | Say this | Reference (ideal) | b | s | L |
|---|----------|-----------|--|--|--|
|H1| So I— wait, no— I mean, send it to, uh, Sarah, not John. | Send it to Sarah, not John. *(resolving the correction needs the LLM)* | | | |
|H2| Um, basically, like, you know, we should sort of ship today. | We should ship today. | | | |
|H3| The deadline is Tues— sorry, Wednesday, the 14th. | The deadline is Wednesday, the 14th. | | | |

### I · Spoken symbols — expected to fail (bucket X)
| # | Say this | Reference (what a *feature* would do) | b | s | L |
|---|----------|-----------|--|--|--|
|I1| Email me at john dot smith underscore dev at gmail dot com. | Email me at john.smith_dev@gmail.com *(no model does this from audio)* | | | |
|I2| New paragraph. Next point: open parenthesis draft only close parenthesis. | ⏎⏎ Next point: (draft only) *(voice-formatting feature)* | | | |

### J · Long run-on — segmentation stress (buckets P, C)
| # | Say this | Reference | b | s | L |
|---|----------|-----------|--|--|--|
|J1| the migration finished overnight so staging is current we still need to verify the OAuth flow rotate the keys and email the team before we promote to production let me know if Thursday works | The migration finished overnight, so staging is current. We still need to verify the OAuth flow, rotate the keys, and email the team before we promote to production. Let me know if Thursday works. | | | |

### K · Foreign / loanwords (buckets N, W)
| # | Say this | Reference | b | s | L |
|---|----------|-----------|--|--|--|
|K1| She ordered an açaí bowl, a jalapeño quesadilla, and a croissant. | She ordered an açaí bowl, a jalapeño quesadilla, and a croissant. | | | |
|K2| The rendezvous is at the café on the boulevard near the fjord. | The rendezvous is at the café on the boulevard near the fjord. | | | |

### L · Silence / noise (bucket H) — do, don't read
| # | Do this | Expected | b | s | L |
|---|---------|----------|--|--|--|
|L1| Record ~2s of silence. | empty (nothing) | | | |
|L2| Record background noise / music, don't speak. | empty, or note any hallucinated "you"/"Thank you." | | | |

---

## Scorecard

| | base.en | small.en | large-v3-turbo |
|---|--:|--:|--:|
| **Total errors** (lower = better) | | | |
| W (wrong word) | | | |
| N (names/jargon) | | | |
| P (punctuation) | | | |
| C (casing) | | | |
| F (fillers/corrections) | | | |
| X (formatting — expected) | | | |
| H (silence/noise) | | | |
| **Avg seconds** (2nd run on) | | | |

## Decision rule

1. **Look at W + P + C across the three columns.** If a bigger model collapses these toward zero →
   the "bad output" is **model tier**, and most of the three-model correction pipeline is unjustified.
2. **Pick the knee of the curve.** If `small` ≈ `large` on your traps, ship `small` (smaller/faster,
   and it matters hugely for the future mobile keyboard's memory budget). If `large` clearly rescues
   names/words `small` misses, that quantifies the upgrade's worth.
3. **Whatever's left after the best model:**
   - residual **N** → build the **custom dictionary** (the one piece of "spell correction" worth keeping).
   - residual **F** self-corrections → **LLM** path, not the pipeline.
   - **X** → decide separately whether voice-formatting is in scope.
4. SymSpell-style generic spell-check should fix **almost nothing here** — Whisper emits real,
   correctly-spelled words. If the data shows that, the vision's pipeline shrinks to "bigger model +
   small dictionary," which is the whole point of running this.
