"""Fit oscillator amplitudes to source PCM while retaining tracked pitch, stereo pan and phase."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import ctypes
from functools import lru_cache
import math
import os
from pathlib import Path
import threading
import numpy as np


_BLAS_LOCK = threading.Lock()


@lru_cache(maxsize=1)
def _blas_control():
    """Recognize only the OpenBLAS shipped in this NumPy installation."""
    base = Path(np.__file__).resolve().parent
    for directory in (base.parent / 'numpy.libs', base / '.libs'):
        if not directory.is_dir():
            continue
        for path in directory.glob('*openblas*'):
            if not path.is_file():
                continue
            try:
                library = ctypes.CDLL(str(path))
            except OSError:
                continue
            for prefix in ('scipy_openblas_', 'openblas_'):
                for suffix in ('64_', ''):
                    get = getattr(library, prefix + 'get_num_threads' + suffix, None)
                    set_ = getattr(library, prefix + 'set_num_threads' + suffix, None)
                    if get is not None and set_ is not None:
                        get.argtypes, get.restype = [], ctypes.c_int
                        set_.argtypes, set_.restype = [ctypes.c_int], None
                        return get, set_
    return None


@contextmanager
def _single_threaded_blas():
    controller = _blas_control()
    if controller is None:
        yield False
        return
    # The converter has its own process; serialize changes for concurrent callers.
    with _BLAS_LOCK:
        get, set_ = controller
        previous = get()
        if not 1 <= previous <= 1024:
            yield False
            return
        try:
            set_(1)
            yield get() == 1
        finally:
            set_(previous)


def _fit_frames(samples, rate, fps, frequencies, gains, times, weights, result,
                window_size, ridge, first_frame, last_frame, progress):
    for frame in range(first_frame, last_frame):
        active = np.flatnonzero((gains[frame] > 1e-5) & (frequencies[frame] > 0))
        if not len(active):
            progress()
            continue
        angles = 2 * np.pi * times[:, None] * frequencies[frame, active][None, :]
        basis = np.concatenate((np.sin(angles), np.cos(angles)), axis=1)
        first = round(frame * rate / fps) - window_size // 2
        source = np.zeros((window_size, 2))
        low, high = max(0, first), min(len(samples), first + window_size)
        if high > low:
            source[low - first:high - first] = samples[low:high]
        weighted = basis * weights[:, None]
        gram = basis.T @ weighted
        diagonal = np.diag(gram).copy()
        gram.flat[::len(gram) + 1] += ridge * np.maximum(diagonal, 1)
        try:
            coefficients = np.linalg.solve(gram, weighted.T @ source)
        except np.linalg.LinAlgError:
            progress()
            continue
        count = len(active)
        amplitude = np.sqrt(np.sum(coefficients[:count] ** 2 + coefficients[count:] ** 2, axis=1))
        # Bound near-duplicate frequencies instead of amplifying an unstable fit.
        amplitude = np.minimum(amplitude, np.maximum(gains[frame, active] * 3, .0005))
        finite = np.isfinite(amplitude)
        amplitude = np.where(finite, amplitude, gains[frame, active])
        db = 20 * np.log10(np.maximum(amplitude, 1e-8))
        result[frame, active, 1] = np.where(amplitude > 1e-5,
            np.clip(np.rint((db + 100) / 100 * 65534) + 1, 1, 65535), 0).astype('<u2')
        progress()


def refine_amplitudes(samples, rate, fps, data, window_size=2048, ridge=.01):
    if (rate != 24000 or not 20 <= fps <= 90 or window_size < 128
            or window_size > 8192 or window_size % 2 or not math.isfinite(ridge) or ridge <= 0):
        raise ValueError('Invalid source-fitting settings')
    if samples.ndim != 2 or samples.shape[1] != 2 or data.ndim != 3 or data.shape[2] != 4:
        raise ValueError('Source fitting requires stereo PCM and four-field partial trajectories')
    if data.shape[0] != math.ceil(len(samples) * fps / rate) or not 16 <= data.shape[1] <= 128:
        raise ValueError('Source PCM and partial timelines do not match')
    result = data.copy()
    frequencies = np.where(data[:, :, 0] > 0, 20 * 440 ** ((data[:, :, 0].astype(float) - 1) / 65534), 0)
    gains = np.where(data[:, :, 1] > 0, 10 ** (((data[:, :, 1].astype(float) - 1) / 65534 * 100 - 100) / 20), 0)
    times = (np.arange(window_size) - window_size // 2) / rate
    weights = np.hanning(window_size)
    completed, next_report = 0, fps * 10
    progress_lock = threading.Lock()

    def progress():
        nonlocal completed, next_report
        with progress_lock:
            completed += 1
            if completed == 1 or completed >= next_report:
                print(f'Fitted source amplitudes {completed / fps:.0f}/{len(data) / fps:.0f}s', flush=True)
                if completed >= next_report:
                    next_report += fps * 10

    arguments = (samples, rate, fps, frequencies, gains, times, weights, result, window_size, ridge)
    workers = min(8, os.cpu_count() or 1, len(data))
    if workers > 1 and len(data) >= fps:
        with _single_threaded_blas() as limited:
            if limited:
                # Frames are independent and workers write disjoint rows of result.
                chunk = math.ceil(len(data) / workers)
                with ThreadPoolExecutor(max_workers=workers) as executor:
                    jobs = [executor.submit(_fit_frames, *arguments, first,
                            min(first + chunk, len(data)), progress)
                            for first in range(0, len(data), chunk)]
                    for job in jobs:
                        job.result()
                return result
    # Unknown BLAS backends retain the original serial execution.
    _fit_frames(*arguments, 0, len(data), progress)
    return result
