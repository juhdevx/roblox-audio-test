"""Sound design / mix for the meme edit. Writes a 48 kHz stereo WAV (pre-loudnorm)."""
import sys, wave, math
import numpy as np
sys.path.insert(0, sys.argv[3])
import compose as C

SR = 48000
A = sys.argv[1]           # dir with onda.wav awkward.wav outro.wav gs.wav
OUT = sys.argv[2]
N = int(math.ceil(C.DUR * SR))
mix = np.zeros((N, 2), np.float64)


def load(name):
    w = wave.open(f"{A}/{name}.wav")
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).astype(np.float64) / 32768
    return x


def rms_db(x):
    return 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-12)


def place(x, t_edit, src_t0=0.0, src_t1=None, gain_db=0.0, fade_in=0.004, fade_out=0.012):
    s0 = int(src_t0 * SR)
    s1 = len(x) if src_t1 is None else min(len(x), int(src_t1 * SR))
    seg = x[s0:s1].copy()
    fi, fo = int(fade_in * SR), int(fade_out * SR)
    if fi:
        seg[:fi] *= np.linspace(0, 1, fi)[:, None]
    if fo:
        seg[-fo:] *= np.linspace(1, 0, fo)[:, None]
    seg *= 10 ** (gain_db / 20)
    d0 = int(round(t_edit * SR))
    if d0 < 0:
        seg = seg[-d0:]; d0 = 0
    n = min(len(seg), N - d0)
    if n > 0:
        mix[d0:d0 + n] += seg[:n]


onda, awk, outro, gs = load("onda"), load("awkward"), load("outro"), load("gs")
TARGET = -17.0
# 1) funk under the dance, hard cut on the beat when the chest is spotted
g = TARGET - rms_db(onda[: int(C.T_NOTICE * SR)])
place(onda, 0.0, 0.0, C.T_NOTICE, g, fade_in=0.002, fade_out=0.010)
# 2) awkward-moment sting on the punch-in (normalise its peak)
g = -3.0 - 20 * np.log10(np.abs(awk).max())
place(awk, C.T_NOTICE + 0.01, gain_db=g, fade_out=0.05)

# 3) rumble + riser while the chest shakes (synthesised support SFX)
rng = np.random.default_rng(5)
t0, t1 = C.T_NOTICE_END + 0.2, C.T_BURST
n = int((t1 - t0) * SR)
tt = np.arange(n) / SR
e = np.clip((tt - (C.T_SHAKE - t0)) / (C.T_BURST - C.T_SHAKE), 0, 1)
brown = np.cumsum(rng.normal(0, 1, n)); brown -= np.convolve(brown, np.ones(2400) / 2400, "same"); brown /= np.abs(brown).max()
lp = np.convolve(brown, np.ones(160) / 160, "same")
lp /= np.abs(lp).max() + 1e-9
trem = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * (9 + 9 * e) * tt))
sub = np.sin(2 * np.pi * (38 + 10 * e) * tt)
rumble = (lp * 0.8 + sub * 0.35) * trem * (0.035 * np.clip(tt / 0.6, 0, 1) + 0.6 * e ** 1.6)
noise = rng.normal(0, 1, n)
# riser: noise through a rising resonant band (crude one-pole cascade)
fc = 300 + 5000 * e ** 2
y = np.zeros(n); y1 = 0.0
for i in range(n):
    a = math.exp(-2 * math.pi * fc[i] / SR)
    y1 = (1 - a) * noise[i] + a * y1
    y[i] = y1
hp = y - np.convolve(y, np.ones(48) / 48, "same")
riser = hp / (np.abs(hp).max() + 1e-9) * (e ** 2.2) * 0.22
sig = rumble + riser
sig[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
place(np.stack([sig, sig * 0.97], 1), t0, gain_db=0.0, fade_in=0.05, fade_out=0.0)

# 4) impact at the burst: sub drop + noise crack
n = int(1.4 * SR); tt = np.arange(n) / SR
f = 32 + 85 * np.exp(-tt / 0.09)
ph = 2 * np.pi * np.cumsum(f) / SR
boom = np.sin(ph) * np.exp(-tt / 0.42) * 0.9
crack = rng.normal(0, 1, n) * np.exp(-tt / 0.05) * 0.45
crack = np.convolve(crack, np.ones(6) / 6, "same")
imp = boom + crack
place(np.stack([imp, imp], 1), C.T_BURST, gain_db=-7.0, fade_in=0.0, fade_out=0.05)

# 5) the token UI's own sound, in sync with its animation (GS t = 0.2 at the burst)
seg = gs[int(0.2 * SR): int(6.8 * SR)]
g = -16.5 - rms_db(seg[: int(4.5 * SR)])
end_t = C.T_FINAL + 0.35
place(gs, C.T_BURST, 0.2, 0.2 + (end_t - C.T_BURST), g, fade_in=0.002, fade_out=0.35)

# 6) whoosh into the golden flash
n = int(0.45 * SR); tt = np.arange(n) / SR
wn = rng.normal(0, 1, n)
env = (tt / tt[-1]) ** 2.5
wh = (wn - np.convolve(wn, np.ones(24) / 24, "same")) * env * 0.25
place(np.stack([wh, wh], 1), C.T_FINAL - 0.45, fade_in=0.0, fade_out=0.004)

# 7) outro song: its first beat lands on the flash, fade at the end
g = TARGET - rms_db(outro[: int(5 * SR)])
place(outro, C.OUTRO_START, 0.0, C.DUR - C.OUTRO_START, g, fade_in=0.003, fade_out=0.7)

peak = np.abs(mix).max()
# soft-knee bus limiter
ax = np.abs(mix)
knee = 0.72
over = ax > knee
mix[over] = np.sign(mix[over]) * (knee + (1 - knee) * np.tanh((ax[over] - knee) / (1 - knee)))
pcm = (np.clip(mix, -1, 1) * 32767).astype(np.int16)
w = wave.open(OUT, "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes()); w.close()
print("mix written", OUT, f"{N / SR:.3f}s peak={peak:.3f}")
