# Getting the processed voice into the Quest 3S

**Status: experimental. None of the routes below has been verified end to end on real hardware by
the authors.** This document separates what is known, what the app implements, and what you must
check yourself.

## Facts and constraints

* Horizon OS (Android-based) does not offer third-party apps a public API to create a system-wide
  virtual microphone. Root access or OS modification is out of scope.
* An Android phone connected to the Quest with a USB-C cable does **not** become a USB microphone.
  Making a phone act as a USB Audio Class *device* (gadget mode) is not something a normal APK can do.
* What the Quest can use, where your Horizon OS version supports it, is a **USB audio input device**
  (a USB microphone or USB audio adapter with a capture channel) via its experimental external
  microphone support. Menu names and availability change between Horizon OS releases; check your
  headset's Settings (often under an *Experimental* section) and record the OS version you tested.

So the working idea is: **phone output → (cable/interface chain) → a USB audio input device plugged
into the Quest.**

## Route A — external USB microphone path (priority 1)

### What the phone app implements
* Output device selection (USB interfaces, USB/3.5 mm headsets, wired headphones) and automatic
  fallback/return when they are unplugged.
* 1 kHz / 440 Hz test tone at a chosen level (-40 … -6 dBFS) on the selected output.
* Route checks: USB host support, USB Audio Class detection (interfaces, streaming endpoints),
  whether Android exposes a USB/wired output, 48 kHz support, routing of the engine output, signal
  level/clipping while the tone plays.
* Round-trip latency probe for any output→input loopback.
* Output gain and limiter (protects a mic input from clipping).

### Candidate wiring (choose one; all unverified)

**A1 — analog, fewest parts**
```
Phone 3.5 mm out (or USB-C→3.5 mm DAC dongle)
  → attenuator (line/headphone level → mic level, ~20-40 dB pad, or a "TRS-to-TRRS mic" adapter cable)
  → TRRS microphone input of a USB-C audio adapter that supports headset microphones
  → Quest USB-C port
```
**A2 — USB interface on the phone**
```
Phone (USB host/OTG) → USB audio interface line out → cable/attenuator
  → input of a second USB audio adapter/interface → Quest USB-C port
```
**A3 — dual-USB audio devices**: some audio mixers/interfaces expose two USB ports and can pass
audio from one host to the other. If you own one, route the phone's USB output to the Quest's USB
input inside the device.

Practical notes:
* The adapter on the Quest side **must expose a capture (microphone) channel**; many cheap USB-C
  headphone adapters are playback-only.
* Start with the phone volume low and the 1 kHz tone at -18 dBFS; raise until the Quest probe reads
  roughly -30 to -12 dBFS. Line level into a mic input will distort.
* When both devices charge from different supplies a ground loop can add hum; try on battery first.
* The Quest's USB-C port is occupied, so it will not charge unless a hub with power pass-through
  works with your adapter (unverified).

### How to verify (stages are recorded separately in the app)
1. **Phone output** — Devices tab: select the output, run route checks with the tone on.
2. **Quest system recognition** — the headset lists/accepts the USB input (Horizon OS settings).
3. **Signal at the Quest** — install **VoiceShift Quest Lab** (`voiceshift-quest-lab-debug-apk`
   artifact), open *USB mic probe*, select the USB input, confirm "1 kHz tone DETECTED".
4. **Roblox in-game capture** — [ROBLOX_TESTING.md](ROBLOX_TESTING.md). Only this proves the goal.

Stage 3 passing while stage 4 fails means Roblox is not using that input — check Horizon OS
microphone selection and Roblox's own audio settings.

## Route B — native Quest app (research)

`app-quest-experimental` ("VoiceShift Quest Lab") runs the same native engine on the headset:
* *USB mic probe* — capture from any input with playback muted and a 1 kHz Goertzel detector.
* *Native DSP on the headset* — the full voice chain on the Quest CPU with load/latency/xrun readouts,
  to measure feasibility of processing on the Quest itself.
* It is a normal 2D app. It cannot install a virtual microphone or route its output into Roblox, and it
  does not attempt privilege escalation or OS modification. Feasibility findings belong in the
  validation log and ROADMAP.

## Route C — Wi-Fi audio bridge (experimental)

Phone (Devices → *Wi-Fi bridge*) streams the processed voice as 10 ms, 16-bit mono UDP packets
(format documented in `bridge-network/.../PcmPacket.kt`) to Quest Lab, which plays it through a
jitter buffer (reordering, loss concealment, re-buffering) and a low-latency `AudioTrack`.

**This does not create a microphone for Roblox or any other app.** It is useful for monitoring and for
measuring network latency/jitter. Use the same Wi-Fi network; the receiver shows its IP address.

## Summary

| Route | Phone side | Headset side | Gives Roblox a mic? |
|---|---|---|---|
| A | implemented | needs hardware + Horizon OS support | **possibly** — to be verified |
| B | — | research app | no (cannot inject) |
| C | implemented | receiver implemented | no |
