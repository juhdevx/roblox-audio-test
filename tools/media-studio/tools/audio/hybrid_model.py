"""Estimate stereo stochastic residual energy left by SPC1 sinusoidal tracks."""
import math
import numpy as np


def band_centers(count=12):
    """Log-spaced high-frequency bands; the native noise bank uses this layout."""
    if not 1 <= count <= 24:
        raise ValueError('Residual bank must have 1-24 bands')
    return np.geomspace(900.0, 11000.0, count)


def band_quality(centers):
    """Return center/bandwidth Q using geometric band boundaries."""
    centers = np.asarray(centers, dtype=float)
    if len(centers) < 2:
        return np.ones_like(centers)
    edges = np.sqrt(centers[:-1] * centers[1:])
    lo = np.r_[centers[0] ** 2 / edges[0], edges]
    hi = np.r_[edges, centers[-1] ** 2 / edges[-1]]
    return centers / (hi - lo)


def power_weights(centers, frequencies):
    """Crossfade adjacent logarithmic bands without counting shared energy twice."""
    centers = np.asarray(centers, dtype=float)
    frequencies = np.asarray(frequencies, dtype=float)
    if len(centers) == 1:
        width = np.array([math.log(2)])
    else:
        gaps = np.diff(np.log(centers))
        width = np.r_[gaps, gaps[-1]]
    weights = np.maximum(1 - np.abs(np.log(np.maximum(frequencies, 1))[None, :]
        - np.log(centers)[:, None]) / width[:, None], 0)
    weights /= np.maximum(weights.sum(axis=0, keepdims=True), 1)
    return weights


def extract_residual(samples, rate, fps, tracked_uint16, centers=None):
    """Return (frames, bands, 2) linear RMS before the runtime residual-mix gain.

    The estimate subtracts represented TONAL POWER, not waveforms: the Roblox
    oscillators do not preserve the original recording's phases. This avoids
    misidentifying phase differences as an extra copy of the same tone.
    Native filter RMS calibration remains the renderer's responsibility.
    """
    samples = np.asarray(samples)
    data = np.asarray(tracked_uint16)
    centers = band_centers() if centers is None else np.asarray(centers, dtype=float)
    if samples.ndim != 2 or samples.shape[1] != 2:
        raise ValueError('Stereo PCM is required')
    if data.ndim != 3 or data.shape[2] != 3:
        raise ValueError('Expected SPC1 (frame, voice, frequency/gain/pan) data')
    if len(data) != math.ceil(len(samples) * fps / rate):
        raise ValueError('PCM and trajectory frame counts do not match')
    if (len(centers) < 1 or len(centers) > 24 or not np.all(np.isfinite(centers))
            or np.any(centers <= 0) or np.any(centers >= rate / 2)
            or np.any(np.diff(centers) <= 0)):
        raise ValueError('Residual centers must be increasing below Nyquist')
    size = 2048
    window = np.hanning(size)
    frequencies = np.fft.rfftfreq(size, 1 / rate)
    weights = power_weights(centers, frequencies)
    scale = size / 2 * np.sum(window ** 2)
    result = np.zeros((len(data), len(centers), 2), dtype=np.float32)
    for index, frame_data in enumerate(data):
        center = round(index * rate / fps)
        first = center - size // 2
        frame = np.zeros((size, 2))
        lo, hi = max(first, 0), min(first + size, len(samples))
        frame[lo - first:hi - first] = samples[lo:hi]
        spectrum = np.fft.rfft(frame * window[:, None], axis=0)
        original = weights @ (np.abs(spectrum) ** 2) / scale
        f, a, p = frame_data.astype(float).T
        f = np.where(f > 0, 20 * 440 ** ((f - 1) / 65534), 0)
        a = np.where(a > 0, 10 ** (((a - 1) / 65534 * 100 - 100) / 20), 0)
        angle = (p / 32767.5) * np.pi / 4
        stereo_power = (a * a / 2)[:, None] * np.column_stack((np.cos(angle) ** 2, np.sin(angle) ** 2))
        allocation = np.array([np.interp(f, frequencies, band) for band in weights])
        represented = allocation @ stereo_power
        result[index] = np.sqrt(np.maximum(original - represented, 0))
    return result
