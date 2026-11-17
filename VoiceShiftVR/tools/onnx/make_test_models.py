#!/usr/bin/env python3
"""Generates small ONNX files used by VoiceShift VR tests and on-device pipeline checks.

None of these are voice-conversion models. They are deterministic signal-processing graphs that
exercise the import -> validate -> load -> stream -> playback path of the neural engine (Engine B).

Usage (from VoiceShiftVR/):
    python3 -m pip install onnx==1.19.0
    python3 tools/onnx/make_test_models.py --tests        # writes core-inference/src/test/resources/models
    python3 tools/onnx/make_test_models.py --diagnostic   # writes tools/onnx/out/*.onnx to copy to a phone

Metadata keys follow the streaming contract documented in docs/MODELS.md.
"""
import argparse
import os

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

OPSET = 17


def _finish(graph, metadata, path):
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", OPSET)], producer_name="voiceshift-tools")
    model.ir_version = 8  # widely supported by ONNX Runtime releases
    for key, value in (metadata or {}).items():
        entry = model.metadata_props.add()
        entry.key = key
        entry.value = str(value)
    onnx.checker.check_model(model)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    onnx.save(model, path)
    print("wrote", path, os.path.getsize(path), "bytes")


def stream_metadata(sample_rate, chunk, context, name, extra=None):
    meta = {
        "voiceshift.contract": "stream-v1",
        "voiceshift.sample_rate": sample_rate,
        "voiceshift.chunk_samples": chunk,
        "voiceshift.context_samples": context,
        "voiceshift.name": name,
        "voiceshift.version": "1.0.0",
        "voiceshift.license": "Apache-2.0",
        "voiceshift.description": "Diagnostic DSP graph, not a voice model.",
    }
    meta.update(extra or {})
    return meta


def gain_model(path, gain, sample_rate=16000, chunk=1600, metadata=True, name="gain"):
    """[1, N] (N dynamic) -> [1, N], y = gain * x."""
    x = helper.make_tensor_value_info("audio", TensorProto.FLOAT, [1, "samples"])
    y = helper.make_tensor_value_info("audio_out", TensorProto.FLOAT, [1, "samples"])
    g = numpy_helper.from_array(np.array([gain], dtype=np.float32), name="gain")
    node = helper.make_node("Mul", ["audio", "gain"], ["audio_out"])
    graph = helper.make_graph([node], name, [x], [y], initializer=[g])
    _finish(graph, stream_metadata(sample_rate, chunk, 0, name) if metadata else None, path)


def fir_context_model(path, sample_rate=16000, chunk=1600, context=400, name="fir-context"):
    """[1, 1, context+chunk] fixed -> same shape; 3-tap smoothing FIR (Conv, zero padded)."""
    n = context + chunk
    x = helper.make_tensor_value_info("waveform", TensorProto.FLOAT, [1, 1, n])
    y = helper.make_tensor_value_info("waveform_out", TensorProto.FLOAT, [1, 1, n])
    w = numpy_helper.from_array(np.array([[[0.25, 0.5, 0.25]]], dtype=np.float32), name="kernel")
    node = helper.make_node("Conv", ["waveform", "kernel"], ["waveform_out"], pads=[1, 1])
    graph = helper.make_graph([node], name, [x], [y], initializer=[w])
    _finish(graph, stream_metadata(sample_rate, chunk, context, name), path)


def rvc_like_model(path):
    """Mimics the I/O signature of an RVC synthesizer export (no real weights)."""
    inputs = [
        helper.make_tensor_value_info("phone", TensorProto.FLOAT, [1, "frames", 768]),
        helper.make_tensor_value_info("phone_lengths", TensorProto.INT64, [1]),
        helper.make_tensor_value_info("pitch", TensorProto.INT64, [1, "frames"]),
        helper.make_tensor_value_info("pitchf", TensorProto.FLOAT, [1, "frames"]),
        helper.make_tensor_value_info("ds", TensorProto.INT64, [1]),
        helper.make_tensor_value_info("rnd", TensorProto.FLOAT, [1, 192, "frames"]),
    ]
    out = helper.make_tensor_value_info("audio", TensorProto.FLOAT, [1, "frames"])
    node = helper.make_node("Identity", ["pitchf"], ["audio"])
    graph = helper.make_graph([node], "rvc-like", inputs, [out])
    _finish(graph, None, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tests", action="store_true")
    parser.add_argument("--diagnostic", action="store_true")
    args = parser.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    if args.tests:
        d = os.path.join(root, "core-inference", "src", "test", "resources", "models")
        gain_model(os.path.join(d, "stream_gain_half.onnx"), 0.5, name="gain-half")
        gain_model(os.path.join(d, "stream_no_metadata.onnx"), 1.0, metadata=False, name="no-metadata")
        fir_context_model(os.path.join(d, "stream_fir_context.onnx"))
        rvc_like_model(os.path.join(d, "rvc_like_signature.onnx"))
        with open(os.path.join(d, "not_a_model.onnx"), "wb") as f:
            f.write(b"this is not an onnx protobuf \x00\x01\x02")

    if args.diagnostic:
        d = os.path.join(root, "tools", "onnx", "out")
        gain_model(os.path.join(d, "voiceshift_diagnostic_passthrough_16k.onnx"), 1.0, 16000, 1600,
                   name="Diagnostic passthrough 16 kHz")
        gain_model(os.path.join(d, "voiceshift_diagnostic_passthrough_48k.onnx"), 1.0, 48000, 2400,
                   name="Diagnostic passthrough 48 kHz")
        fir_context_model(os.path.join(d, "voiceshift_diagnostic_smoothing_16k.onnx"),
                          name="Diagnostic smoothing filter 16 kHz")

    if not (args.tests or args.diagnostic):
        parser.print_help()


if __name__ == "__main__":
    main()
