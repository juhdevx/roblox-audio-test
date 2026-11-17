# Roblox voice chat test procedure

**Result so far: NOT RUN.** Nobody has yet confirmed in-game capture with this project. Record your
results in the app (Devices → *Quest & Roblox validation*) and share the diagnostic report.

VoiceShift does not modify, inject into, or automate the Roblox client, and does not bypass Roblox's
voice eligibility rules. Use voice chat according to the Roblox Terms of Use and Community Standards.
Do not use a voice changer to impersonate another person.

## Prerequisites
* Roblox voice chat already enabled and permitted for the account (Roblox decides eligibility).
* A second account on another device, or a friend, to listen.
* Route A hardware connected (see [QUEST_BRIDGE.md](QUEST_BRIDGE.md)).
* Headphones on the phone are optional; the Quest's own speakers are the monitor for Roblox.

## Procedure

| # | Step | Expected | Record |
|---|---|---|---|
| 1 | Phone: start VoiceShift, select the external output, enable 1 kHz tone at -18 dBFS | Route checks PASS for output routing and level | `phone.tone` |
| 2 | Phone: tone off, speak | Output meter moves | `phone.voice` |
| 3 | Quest: plug the USB input; enable/choose the external microphone in Horizon OS if offered | Input appears/selected | `quest.listed` + OS version |
| 4 | Quest: Quest Lab → USB mic probe on that input, phone tone on | "1 kHz tone DETECTED" | `quest.probe` |
| 5 | Quest: Roblox → a voice-enabled experience; check the mic indicator above your avatar while the phone plays the tone, then while you speak | Indicator reacts | note in `roblox.capture` |
| 6 | Listener confirms they hear the **processed** voice, not the headset's built-in mic (cover the headset mic / speak quietly near it to tell them apart) | Processed voice heard | `roblox.capture` |
| 7 | Measure delay: listener notes lip/feel delay; on the phone run the latency probe for the phone-side round trip | Values noted | note |
| 8 | 30-minute session | No dropouts, no disconnect | note + diagnostic report |

## Interpreting failures
* **4 fails** → hardware/level issue before Roblox (adapter has no capture, wrong cable, too quiet).
* **4 passes, 5 fails** → Horizon OS/Roblox is not using that input. Re-check the headset's
  microphone selection; restart Roblox after plugging in; try the input before launching Roblox.
* **Robotic or echoing voice in game** → the built-in headset microphone may also be active, or Roblox's
  own processing interacts with the effect. Reduce pitch shift, disable phone noise reduction, compare
  with bypass.
* Always distinguish *system recognition* (step 3/4) from *successful in-game capture* (step 6).
