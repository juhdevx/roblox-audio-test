# DSP engine (Engine A)

All code: `core-dsp/cpp` (portable C++17, no platform dependencies). Tests: `tests/native`.

## Chain

| Stage | Class | Notes |
|---|---|---|
| Low cut | `Biquad` (RBJ high-pass, Q 0.707) | 20–300 Hz, removes rumble and proximity bass |
| Noise gate | `NoiseGate` | downward expander, 4 dB hysteresis, 60 ms hold, -30 dB range; ≤ -80 dB = off |
| AGC | `AutomaticGainControl` | 300 ms RMS, adapts only while the gate is open; -20 dB/s down, +4 dB/s up, -12…+18 dB |
| Voice transform | `SpectralVoiceShifter` | see below |
| Tone EQ | 3 × `Biquad` | body (peaking 220 Hz), presence (peaking 3 kHz), air (high shelf 8 kHz) |
| Compressor | `Compressor` | one "amount" control: threshold -10…-30 dB, ratio 1…6, 6 dB soft knee, auto make-up |
| Output gain | ramped per block | -24…+12 dB |
| Limiter | `Limiter` | instantaneous attack, 60 ms release, ceiling -1 dBFS (guaranteed by construction) |

Bypass replaces the processed signal with the dry input (same output gain, own limiter), crossfaded.

## Spectral voice shifter

Per STFT frame (periodic Hann, 75 % overlap, N = 2048 or 1024 at 48 kHz):

1. **Analysis FFT** (radix-2, `Fft`).
2. **Noise suppression** (optional): smoothed power per bin, minimum tracking with +4 dB/s rise,
   minimum-statistics bias ×2, over-subtraction 2…5 × noise, gain floor -6…-24 dB, temporal gain
   smoothing against musical noise. Runs inside the same frame → no extra latency.
3. **Spectral envelope** by cepstral smoothing: log-magnitude → IFFT → Hann lifter reaching zero at
   4 ms quefrency → FFT → exp. Removes the harmonic structure of voices below ~250 Hz, keeps formants.
4. **Excitation** = spectrum / envelope (envelope floored at -80 dB re. its maximum).
5. **Pitch shift** with a peak-locked phase vocoder (Laroche & Dolson, 1999): local maxima define
   regions; each region is moved by an integer number of bins to ratio × (instantaneous frequency of
   its peak) and rotated by one phase so all its bins stay coherent; the peak's phase advances at the
   shifted frequency, so the output frequency is exact even though bins move in integer steps.
6. **Formant shift:** multiply by the envelope resampled at k / formantRatio.
7. **Breathiness:** envelope-shaped random-phase noise faded in from 1 to 3.5 kHz.
8. **Synthesis:** Hermitian spectrum → IFFT → window → overlap-add (gain = hop / Σw²).

At ratio 1 the phase recursion reproduces the analysis phases exactly, so with all extras off the
shifter is an identity system (tested: > 60 dB SNR).

### Measured by the unit tests (host build)

| Check | Result required by test |
|---|---|
| Identity reconstruction (1024 and 2048) | SNR > 60 dB |
| Sine 220 Hz shifted +4, +7, -3, +12 st | frequency within 1 % |
| Synthetic vowel f0 105/140/150 Hz, +5 st | f0 within 3 %, formant peak within 15 % |
| Formant +4 st on a vowel | F2 moves by 2^(4/12) ± 8 %; pitch unchanged |
| Noise reduction on "syllables" over noise | > 12 dB less noise in pauses, voiced level within 3 dB |
| Extreme settings on noise + vowel | always finite, bounded |
| Full chain driven hot | peak ≤ -1 dBFS, finite |

CPU: the whole chain with all features on processes 10 s of audio in ~0.27 s on one x86 host core
(≈ 2.7 % of a core). Phone cores are slower; the app reports the real audio-thread load.

## Pitch tracking and calibration

`PitchDetector` (YIN, de Cheveigné & Kawahara 2002) runs on the raw microphone signal after
anti-alias filtering and decimation to ~12 kHz: 32 ms window, 16 ms hop, 60–600 Hz, threshold 0.15,
parabolic refinement, median of the last five voiced frames, held across short consonant gaps.
Cost ≈ 80k multiply-adds per 16 ms. Tests: sines 85–520 Hz within 1 %, synthetic vowels within 2–3 Hz,
noise and silence reported as unvoiced.

The Voice tab's calibration listens for 10 s, keeps voiced readings with confidence ≥ 0.6, takes the
median and suggests `pitch = 12·log2(target / median)` (0…+9 st, rounded to 0.5) and
`formant ≈ 0.35 × pitch` (0…+3 st). Targets: 175, 200 (default) or 225 Hz — mid-range adult
feminine speaking pitches. Home shows "input Hz → output Hz" live.

## Latency budget

| Part | Typical | Source |
|---|---|---|
| Voice transform | 42.7 ms (quality) / 21.3 ms (low latency) | algorithmic, exact |
| Platform input + output | ~10–40 ms on good devices, more over Bluetooth | `calculateLatencyMillis()` when the device supports timestamps |
| Neural engine | chunk duration + inference time + resampling | measured live (`AI latency`) |

The dashboard shows the estimate; the **round-trip probe** (Devices tab) measures real
output→input delay through a loopback. Targets (<100 ms ideal, ≤200 ms acceptable) are engineering
targets, not guarantees. Bluetooth headsets typically add 100–200 ms; prefer wired or USB.

## Parameters

Ranges (shared C++/Kotlin, enforced by tests): pitch -12…+12 st, formant -6…+6 st, noise reduction
0–1, gate -80…-20 dB, AGC on/off and target -30…-10 dB, low cut 20–300 Hz, body -12…+6 dB, presence
-6…+9 dB, air -6…+9 dB, compression 0–1, breathiness 0–1, output -24…+12 dB. Pitch/formant/noise/
breath glide with a 30 ms time constant; EQ coefficients update when values change.

## Feminine presets (built-in)

| Preset | Pitch | Formant | Notes |
|---|---|---|---|
| Soft feminine (default) | +5 st | +2 st | low cut 120 Hz, body -3, presence +2, air +3, breath 15 % |
| Bright feminine | +7 st | +3 st | thinner, brighter |
| Warm feminine | +4 st | +1.5 st | more breath, less brightness |
| Subtle / androgynous | +3 st | +1 st | minimal processing |
| Natural | 0 | 0 | clean-up only, for comparison |

These are starting points; voices differ. Moderate shifts sound more natural than large ones.
