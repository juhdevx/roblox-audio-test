"""Experimental bounded amplitude fitting with each partial's phase and pan fixed."""
import math
import numpy as np


def refine_amplitudes(samples, rate, fps, data, window_size=2048, ridge=.01):
    """Fit nonnegative gains; preserve all frequency, phase, pan and quiet slots.

    This optional method improves waveform fit on the comparison clips but has
    mixed unnormalized spectral results. The source-fit method remains default.
    """
    if (rate != 24000 or type(fps) is not int or not 20 <= fps <= 90
            or type(window_size) is not int or not 128 <= window_size <= 8192
            or window_size % 2 or not math.isfinite(ridge) or ridge <= 0):
        raise ValueError('Invalid phase/pan fitting settings')
    if samples.ndim != 2 or samples.shape[1] != 2 or data.ndim != 3 or data.shape[2] != 4:
        raise ValueError('Phase/pan fitting requires stereo PCM and four-field trajectories')
    if (not len(samples) or data.shape[0] != math.ceil(len(samples) * fps / rate)
            or not 16 <= data.shape[1] <= 128 or data.dtype != np.dtype('<u2')):
        raise ValueError('Source PCM and uint16 partial timelines do not match')
    if not np.all(np.isfinite(samples)):
        raise ValueError('Source PCM contains non-finite samples')
    result = data.copy()
    frequency = np.where(data[:, :, 0] > 0, 20 * 440 ** ((data[:, :, 0].astype(float)-1)/65534), 0)
    encoded = data[:, :, 1].astype(float)
    gains = np.where(encoded > 0, 10 ** (((encoded-1)/65534*100-100)/20), 0)
    phases = data[:, :, 3].astype(float) / 65535
    pans = data[:, :, 2].astype(float) / 32767.5 - 1
    times = (np.arange(window_size) - window_size // 2) / rate
    weights = np.hanning(window_size)
    for frame in range(len(data)):
        active = np.flatnonzero((gains[frame] > 1e-5) & (frequency[frame] > 0))
        if not len(active):
            continue
        first = round(frame * rate / fps) - window_size // 2
        source = np.zeros((window_size, 2))
        low, high = max(0, first), min(len(samples), first + window_size)
        if high > low:
            source[low-first:high-first] = samples[low:high]
        wave = np.sin(2*np.pi*(times[:, None]*frequency[frame, active] + phases[frame, active]))
        angle = (pans[frame, active]+1)*np.pi/4
        left, right = np.cos(angle), np.sin(angle)
        weighted = wave*weights[:, None]
        gram = (wave.T @ weighted)*(left[:, None]*left + right[:, None]*right)
        projection = (weighted.T @ source[:, 0])*left + (weighted.T @ source[:, 1])*right
        original = gains[frame, active]
        regularizer = ridge*np.maximum(np.diag(gram).copy(), 1)
        gram.flat[::len(gram)+1] += regularizer
        projection += regularizer*original
        upper = np.maximum(original*3, .0005)
        lipschitz = max(float(np.max(np.sum(np.abs(gram), axis=1))), 1e-8)
        gain, accelerated, momentum = original.copy(), original.copy(), 1.
        for _ in range(100):
            next_gain = np.clip(accelerated-(gram @ accelerated-projection)/lipschitz, 0, upper)
            next_momentum = (1+np.sqrt(1+4*momentum*momentum))/2
            accelerated = next_gain + ((momentum-1)/next_momentum)*(next_gain-gain)
            gain, momentum = next_gain, next_momentum
        objective = lambda value: float(.5*value @ gram @ value-projection @ value)
        if not np.all(np.isfinite(gain)) or objective(gain) > objective(original)+1e-8:
            continue
        db = 20*np.log10(np.maximum(gain, 1e-8))
        quantized = np.where(gain > 1e-5,
            np.clip(np.rint((db+100)/100*65534)+1, 1, 65535), 0).astype('<u2')
        # The serialized gain must also preserve the bounded local objective.
        decoded = np.where(quantized > 0, 10 ** (((quantized.astype(float)-1)/65534*100-100)/20), 0)
        if objective(decoded) <= objective(original)+1e-8:
            result[frame, active, 1] = quantized
        if frame % (fps*10) == 0:
            print(f'Fitted phase/pan amplitudes {frame/fps:.0f}/{len(data)/fps:.0f}s', flush=True)
    return result
