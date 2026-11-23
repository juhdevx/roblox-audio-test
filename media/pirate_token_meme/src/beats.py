import wave, numpy as np, sys
def load(p):
    w = wave.open(p); n = w.getnframes(); sr = w.getframerate()
    a = np.frombuffer(w.readframes(n), np.int16).reshape(-1, w.getnchannels()).astype(np.float32) / 32768
    return a.mean(1), sr
def flux_of(x, sr, hop_s=0.005):
    hop = int(sr * hop_s); win = 2048
    fr = np.lib.stride_tricks.sliding_window_view(np.pad(x, (win // 2, win)), win)[::hop]
    sp = np.log1p(np.abs(np.fft.rfft(fr * np.hanning(win), axis=1)) * 10)
    fl = np.maximum(np.diff(sp, axis=0), 0)[:, :200].sum(1)   # emphasise lows/mids (kick/snare)
    return np.concatenate([[0], fl]) / (fl.max() + 1e-9), hop_s
for name, lo, hi, span in [("onda", 0.30, 0.36, 4.2), ("outro", 0.38, 0.44, 6.0)]:
    x, sr = load(f"{sys.argv[1]}/{name}.wav")
    fl, hs = flux_of(x, sr)
    best = None
    for P in np.arange(lo, hi, 0.0005):
        for ph in np.arange(0, P, 0.002):
            idx = (np.arange(ph, span, P) / hs).astype(int)
            sc = fl[idx].sum() / len(idx)
            if best is None or sc > best[0]:
                best = (sc, P, ph)
    sc, P, ph = best
    # which of the two alternating beats is stronger (downbeat)
    idx = (np.arange(ph, span, P) / hs).astype(int)
    ev, od = fl[idx[0::2]].mean(), fl[idx[1::2]].mean()
    print(f"{name}: period={P:.4f}s ({60/P:.1f} bpm) phase={ph:.3f}s score={sc:.3f} even={ev:.3f} odd={od:.3f}")
    print("   beats:", [round(b, 3) for b in np.arange(ph, span, P)][:16])
