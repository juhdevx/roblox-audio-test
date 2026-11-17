# Voice models (Engine B)

**No voice model ships with VoiceShift VR.** The neural engine is complete for one well-defined
contract (`stream-v1`) and refuses everything else with an explanation.

## The `stream-v1` contract

A model is **compatible** when ONNX Runtime can load it and all of these hold:

| Requirement | Detail |
|---|---|
| One float32 input | shape `[N]`, `[1, N]` or `[1, 1, N]`; `N` fixed or dynamic |
| One float32 output | same rank family; length = chunk **or** context + chunk |
| `voiceshift.contract` | `stream-v1` |
| `voiceshift.sample_rate` | model audio rate, 8000–96000 |
| `voiceshift.chunk_samples` | optional if `N` is fixed (then `N - context`); otherwise defaults to 100 ms with a warning |
| `voiceshift.context_samples` | optional, default 0. Past audio prepended to every chunk |
| Smoke test | two inferences on silence must return finite samples of the right length |

Optional metadata: `voiceshift.name`, `voiceshift.version`, `voiceshift.license`,
`voiceshift.description`, `voiceshift.voice_owner`, `voiceshift.voice_owner_consent`
(`true`/`documented`). Metadata goes in the ONNX `metadata_props` (see
`tools/onnx/make_test_models.py` for a working example).

Runtime behaviour: the engine downsamples the conditioned mic signal (after low cut, gate, AGC) to the
model rate, the worker feeds `context + chunk` windows, the output chunk is upsampled, crossfaded in
and then passed through the EQ/compressor/limiter. Latency ≈ chunk + inference time + 25 ms margin.

## Import, validation and storage

1. Models tab → **Import .onnx file** (Android file picker; nothing is downloaded).
2. Consent dialog: generic/synthetic voice, or a real person's voice. Real voices need your
   confirmation that you own the voice or have the speaker's documented permission. Models whose
   metadata declares a voice owner cannot be imported without it.
3. The file is copied to private storage while its SHA-256 is computed (512 MB limit), validated with
   ONNX Runtime, and indexed. Duplicates (same hash) are detected; re-importing a model with the same
   name increments its **revision**.
4. **Load** checks free memory (about 3× file size + 128 MB) and low-RAM devices before opening the
   session. Loading restarts the audio engine once to size the native queues for the model.
5. **Delete** erases the file; presets that used it fall back to DSP.

## Verifying the AI pipeline without a voice model

CI publishes an artifact **diagnostic-onnx-models** (or run
`python3 tools/onnx/make_test_models.py --diagnostic`):

* `voiceshift_diagnostic_passthrough_16k.onnx` — returns its input (16 kHz, 100 ms chunks)
* `voiceshift_diagnostic_passthrough_48k.onnx` — same at 48 kHz, 50 ms chunks
* `voiceshift_diagnostic_smoothing_16k.onnx` — 3-tap low-pass with 25 ms context

Import one, load it, switch the engine to **AI**: you should hear your conditioned (unshifted) voice
with extra delay, and the Models tab shows real-time factor and chunk counts. These are pipeline
tests, not voice conversion.

## RVC status

RVC exports (inputs `phone`, `phone_lengths`, `pitch`, `pitchf`, `ds`/`sid`, `rnd`) are recognised and
marked **unsupported**. Running RVC needs, per chunk:

1. a HuBERT/ContentVec feature encoder (~90–360 MB ONNX),
2. an F0 estimator (RMVPE or CREPE),
3. feature retrieval/indexing (optional), and
4. the synthesizer itself,

with all four validated for tensor shapes, hop sizes and sample rates. That is a substantial, separate
milestone (see ROADMAP). Until it exists, the app does not claim RVC support.

Practical path today: export or distil a voice-conversion network into a single waveform-to-waveform
ONNX graph (e.g. by wrapping encoder + F0 + synthesizer in one exported module with a fixed
context window) and add the `stream-v1` metadata.

## Training a custom voice (outside the app)

Training is separate from the mobile runtime and is not performed on the phone. A future custom
feminine voice should be trained only from recordings of a consenting speaker, with written
permission stored alongside the dataset, and its ONNX export should carry `voiceshift.voice_owner`
and `voiceshift.voice_owner_consent=documented`. Never train on recordings of people who did not
agree, and never use a model to impersonate someone.
