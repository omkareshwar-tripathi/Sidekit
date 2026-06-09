# Universal clipboard (inside Sidekit)

**Status:** 🔵 Vision · **Platforms:** Windows · macOS · iOS · Android (cross-ecosystem) · **In Sidekit:** ✅ — flows through the surface (alongside the shelf)

## What it is

Copy on **any** device, and it's **automatically available on all your other devices**. Copy a link
on a **Samsung** phone → it's on your **Windows** laptop's clipboard. Copy text on an **iPhone** →
paste it on a **Mac** or a PC. Apple already does this *within* its own walled garden; the vision is
to break the wall — **any device to any device, regardless of brand.**

## Why it's fourth ("once all four are ready")

This is the payoff of having all **four platform endpoints** live — Mac, Windows, iOS, Android (from
Pillars 1–3). It's only magic when your *phone* and your *laptop* are both in it, so it comes **after**
the apps that put SpeakType on those devices exist. Building it earlier would mean building
cross-device plumbing with nothing to connect.

## How it might work (high level — not a design)

- Each device watches its **local clipboard** and shares new contents over a **secure transport** to
  your other devices, which write it into *their* clipboards — automatically.
- **Transport is the key choice:** local-network peer-to-peer (most private) vs. an optional
  end-to-end-encrypted relay (works across any network). Text first; images/files later (files
  overlap with the [shelf](5-shelf.md)).

## Dependencies

- **Pillars 1–3** — needs SpeakType present on all four device types.
- A **device-pairing / identity** mechanism ("these are my devices").
- End-to-end encryption — clipboard contents are sensitive; this is non-negotiable.

## Open questions

- **Transport:** P2P-only vs. optional encrypted relay vs. both (privacy vs. "works anywhere").
- **Pairing:** no-account local pairing (QR/code) vs. an account.
- **Auto vs. manual:** does every copy sync automatically, or do you flick a clip across deliberately?
- **Mobile-OS limits:** iOS/Android restrict background clipboard access (esp. iOS reads) — shapes
  what's possible.
- **Sensitive content:** detect and skip passwords/OTPs?

## What "done" looks like

You copy something on your phone; by the time you glance at your laptop it's already on the laptop's
clipboard — encrypted in transit, no account, no cloud copy you didn't ask for — whether the phone is
an iPhone or a Samsung and the laptop a Mac or a PC.
