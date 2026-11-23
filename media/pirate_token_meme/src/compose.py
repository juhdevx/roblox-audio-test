"""Meme edit compositor: 1080x1920 @ 60 fps.

python compose.py OUT.mp4 [t0 t1]   (t0/t1 optional: render a sub-range for previews)
Env: PREVIEW_PNG=dir  -> write PNGs of the given times instead of a video.
"""
import os, sys, json, math, random, subprocess
from functools import lru_cache
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont, ImageFilter

cv2.setNumThreads(1)

S = "/tmp/claude-0/-home-user-roblox-audio-test/12f87363-e15b-5a02-b8dd-9c1989d7812c/scratchpad"
U = "/root/.claude/uploads/12f87363-e15b-5a02-b8dd-9c1989d7812c"
SRC_DIR = f"{S}/src"
GS_DIR = f"{S}/gs"
CHEST_DIR = f"{S}/chest"
PHOTO = f"{U}/93b884e5-image.jpg"
TRACK = f"{S}/work/track_full.npz"

W, H = 1080, 1920
FPS = 60
DUR = 16.0

# ------------------------------------------------------------------ timeline
T_S2 = 1.00            # punch-in face cut
T_S3 = 1.80            # continuous run into the bushes
SRC_S1, SRC_S2, SRC_S3 = 3.00, 5.45, 7.30
T_SHAKE = 6.20         # chest starts rumbling (src 11.70)
T_BURST = 7.80         # lid bursts (src 13.30)
T_FINAL = 12.60        # golden flash -> static image (GS t = 5.0)
GS_T0 = 0.20           # green-screen time at burst
GS_FPS = 30000 / 1001
GS_HOLD_IDX = 151      # banner fully open (GS t ~ 5.0 s)
FREEZE_SRC = 13.30

REF_ANCHOR = np.array([460.0, 1310.0])   # chest ground anchor in reference frame 313
CHEST_W_REF = 355.0                      # px between base corners in ref frame

GOLD = np.array([0.32, 0.74, 1.0], np.float32)     # BGR
GOLD_DEEP = np.array([0.12, 0.55, 1.0], np.float32)
WARM_WHITE = np.array([0.80, 0.95, 1.0], np.float32)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def smoothstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)


def ease_out(x):
    x = clamp(x)
    return 1 - (1 - x) ** 3


# ------------------------------------------------------------------ source mapping

def src_time(t):
    if t < T_S2:
        return SRC_S1 + t
    if t < T_S3:
        return SRC_S2 + (t - T_S2)
    if t < T_BURST:
        return SRC_S3 + (t - T_S3)
    return FREEZE_SRC


def src_index(ts):
    return int(min(353, max(1, math.floor(ts * 24 + 1e-6) + 1)))


def chest_frame(t):
    if t < T_SHAKE:
        return 0
    if t < T_BURST:
        return int(clamp(round((t - T_SHAKE) * 60) + 1, 1, 96))
    cf = 97 + int(round((t - T_BURST) * 60))
    if cf > 224:
        cf = 161 + (cf - 161) % 64
    return cf


# ------------------------------------------------------------------ tracking -> similarity per src frame
_trk = np.load(TRACK)
TRK_FRAMES = [int(x) for x in _trk["frames"]]
TRK_H = _trk["H"]


def _persp(Hm, p):
    v = Hm @ np.array([p[0], p[1], 1.0])
    return v[:2] / v[2]


_sims = {}
for k, fidx in enumerate(TRK_FRAMES):
    Hm = TRK_H[k]
    p = _persp(Hm, REF_ANCHOR)
    a = _persp(Hm, REF_ANCHOR + [-60, 0])
    b = _persp(Hm, REF_ANCHOR + [60, 0])
    v = b - a
    _sims[fidx] = (p, np.linalg.norm(v) / 120.0, math.atan2(v[1], v[0]))
# smooth scale & angle (slowly varying); keep position raw
_fr = sorted(_sims)
_sc = np.array([_sims[f][1] for f in _fr])
_an = np.array([_sims[f][2] for f in _fr])
_k = np.exp(-0.5 * (np.arange(-4, 5) / 2.0) ** 2); _k /= _k.sum()
_scs = np.convolve(np.pad(_sc, 4, mode="edge"), _k, "valid")
_ans = np.convolve(np.pad(_an, 4, mode="edge"), _k, "valid")
SIM = {f: (_sims[f][0], float(_scs[i]), float(np.clip(_ans[i] * 0.6, math.radians(-6), math.radians(6))))
       for i, f in enumerate(_fr)}


def sim_for(fidx):
    fidx = min(max(fidx, _fr[0]), _fr[-1])
    return SIM[fidx]


# ------------------------------------------------------------------ chest sprites
with open(f"{CHEST_DIR}/chest_info.json") as fh:
    CINFO = json.load(fh)
C_ANCH = np.array(CINFO["anchor"])
C_WPX = np.linalg.norm(np.array(CINFO["right"]) - np.array(CINFO["left"]))
S0 = CHEST_W_REF / C_WPX           # sprite px -> ref-frame px
C_MOUTH = {int(k): np.array(v) for k, v in CINFO["mouth_per_frame"].items()}


@lru_cache(maxsize=48)
def load_sprite(cf):
    im = cv2.imread(f"{CHEST_DIR}/c_{cf:04d}.png", cv2.IMREAD_UNCHANGED).astype(np.float32) / 65535.0
    a = im[..., 3:4]
    rgb = im[..., :3]
    lum = rgb.max(axis=2, keepdims=True)
    obj = a * (lum > 0.004)            # object (no shadow)
    # match footage: slightly lower contrast/brightness, lifted blacks
    lum_s = rgb[..., 0:1] * 0.114 + rgb[..., 1:2] * 0.587 + rgb[..., 2:3] * 0.299
    rgb = lum_s + (rgb - lum_s) * 0.84
    # keep the hot treasure golden instead of clipping to white
    hl = np.clip((lum_s - 0.62) / 0.38, 0, 1)
    rgb = rgb * (1 - 0.55 * hl) + hl * 0.55 * np.array([0.30, 0.74, 1.0], np.float32) * np.minimum(lum_s * 1.15, 1.0)
    rgb = rgb * 0.66 + 0.018
    rgb[..., 0] += 0.012   # slight cool/magenta night cast in the blacks
    rgb[..., 2] += 0.006
    prem = rgb * obj                   # premultiplied object colour (shadow pixels -> 0 colour)
    shadow_a = np.clip((a - obj) * 1.15, 0, 1)        # shadow-catcher alpha
    alpha = obj + shadow_a
    out = np.concatenate([prem, alpha, obj], axis=2)   # 5 channels: B G R A OBJ
    return out


def local_to_frame(sim, pts_local):
    """chest-local (ref px, origin=anchor) -> frame coords"""
    p, s, th = sim
    c, si = math.cos(th), math.sin(th)
    x = pts_local[..., 0] * s
    y = pts_local[..., 1] * s
    return np.stack([p[0] + c * x - si * y, p[1] + si * x + c * y], axis=-1)


def chest_affine(sim):
    p, s, th = sim
    sc = s * S0
    c, si = math.cos(th) * sc, math.sin(th) * sc
    M = np.array([[c, -si, 0.0], [si, c, 0.0]])
    M[:, 2] = p - M[:, :2] @ C_ANCH + np.array([0.0, 5.0 * s])
    return M


def mouth_local(cf):
    return (C_MOUTH.get(cf, C_MOUTH[0]) - C_ANCH) * S0


# ------------------------------------------------------------------ particles (chest-local coordinates)
class P:
    __slots__ = ("t0", "life", "x", "y", "vx", "vy", "drag", "g", "size", "kind", "ph", "tw")


def _mk(rng, t0, life, x, y, vx, vy, drag, g, size, kind):
    p = P(); p.t0, p.life, p.x, p.y, p.vx, p.vy, p.drag, p.g, p.size, p.kind = t0, life, x, y, vx, vy, drag, g, size, kind
    p.ph = rng.uniform(0, 6.28); p.tw = rng.uniform(8, 22)
    return p


def build_particles():
    rng = random.Random(42)
    ps = []
    # idle Fortnite-chest shimmer: sparkles on/around chest
    t = 0.0
    while t < T_SHAKE:
        t += rng.expovariate(7.0)
        ps.append(_mk(rng, t, rng.uniform(0.5, 1.0), rng.uniform(-200, 200), rng.uniform(-330, -30),
                      rng.uniform(-15, 15), rng.uniform(-90, -30), 0.0, 0.0, rng.uniform(7, 15), "star"))
    # rumble: motes leaking from the lid seam + ground dust
    t = T_SHAKE
    while t < T_BURST:
        e = (t - T_SHAKE) / (T_BURST - T_SHAKE)
        t += rng.expovariate(12 + 70 * e)
        kind = "star" if rng.random() < 0.35 else "dust"
        ps.append(_mk(rng, t, rng.uniform(0.6, 1.3), rng.uniform(-190, 190), rng.uniform(-300, -230),
                      rng.uniform(-80, 80), rng.uniform(-420, -120), 0.6, -60.0, rng.uniform(4, 12), kind))
        if rng.random() < 0.5:
            ps.append(_mk(rng, t, rng.uniform(0.35, 0.7), rng.uniform(-230, 230), rng.uniform(-10, 15),
                          rng.uniform(-260, 260), rng.uniform(-380, -120), 0.0, 1500.0, rng.uniform(2.5, 5.5), "debris"))
    # burst explosion
    for _ in range(520):
        ang = rng.uniform(-math.pi * 0.92, -math.pi * 0.08)
        spd = rng.uniform(500, 2600)
        kind = "star" if rng.random() < 0.3 else "dust"
        ps.append(_mk(rng, T_BURST + rng.uniform(0, 0.08), rng.uniform(0.8, 2.3), rng.uniform(-150, 150), rng.uniform(-20, 20),
                      math.cos(ang) * spd * 0.75, math.sin(ang) * spd, 2.2, 240.0, rng.uniform(4, 15), kind))
    # continuous fountain while the token animation plays
    t = T_BURST + 0.05
    while t < T_FINAL:
        t += rng.expovariate(90.0)
        kind = "star" if rng.random() < 0.3 else "dust"
        ps.append(_mk(rng, t, rng.uniform(1.0, 2.2), rng.uniform(-140, 140), rng.uniform(-15, 15),
                      rng.uniform(-260, 260), rng.uniform(-1150, -380), 1.1, 120.0, rng.uniform(3.5, 12), kind))
    return ps


PARTS = build_particles()

# final-card sparkles (screen space)
def build_final_sparkles():
    rng = random.Random(7)
    ps = []
    t = T_FINAL - 0.2
    while t < DUR:
        t += rng.expovariate(40.0)
        ps.append(_mk(rng, t, rng.uniform(0.8, 1.8), rng.uniform(60, 1020), rng.uniform(150, 1750),
                      rng.uniform(-30, 30), rng.uniform(-160, -50), 0.0, 0.0, rng.uniform(5, 16),
                      "star" if rng.random() < 0.45 else "dust"))
    return ps


FINAL_PARTS = build_final_sparkles()


def particle_state(p, t):
    tau = t - p.t0
    if tau < 0 or tau > p.life:
        return None
    if p.drag > 0:
        f = (1 - math.exp(-p.drag * tau)) / p.drag
    else:
        f = tau
    x = p.x + p.vx * f
    y = p.y + p.vy * f + 0.5 * p.g * tau * tau
    life_f = math.sin(math.pi * tau / p.life) ** 0.6
    tw = 0.55 + 0.45 * math.sin(p.tw * tau + p.ph)
    return x, y, life_f * (tw if p.kind == "star" else 0.7 + 0.3 * tw)


def draw_particles(core, dust, debris, items):
    """items: list of (x, y, intensity, size, kind) in frame coords"""
    for x, y, a, sz, kind in items:
        if a <= 0.01 or x < -50 or y < -50 or x > W + 50 or y > H + 50:
            continue
        xi, yi = int(round(x)), int(round(y))
        if kind == "star":
            L = int(sz * (0.7 + 0.6 * a))
            cv2.line(core, (xi - L, yi), (xi + L, yi), a, 2, cv2.LINE_AA)
            cv2.line(core, (xi, yi - L), (xi, yi + L), a, 2, cv2.LINE_AA)
            cv2.circle(core, (xi, yi), max(2, int(sz * 0.22)), a, -1, cv2.LINE_AA)
        elif kind == "dust":
            cv2.circle(dust, (xi, yi), max(1, int(sz * 0.35)), a, -1, cv2.LINE_AA)
        else:
            cv2.circle(debris, (xi, yi), max(1, int(sz * 0.5)), a, -1, cv2.LINE_AA)


def add_glow_layers(img, core, dust, glow_gain=1.0, scale=1.0):
    small = cv2.resize(core + dust, (W // 4, H // 4), interpolation=cv2.INTER_AREA)
    g1 = cv2.GaussianBlur(small, (0, 0), 2.5 * scale)
    g2 = cv2.GaussianBlur(small, (0, 0), 9 * scale)
    glow = cv2.resize(g1 * 2.2 + g2 * 3.0, (W, H), interpolation=cv2.INTER_LINEAR)
    img += core[..., None] * WARM_WHITE + dust[..., None] * GOLD * 1.1 + glow[..., None] * GOLD * 0.9 * glow_gain


# ------------------------------------------------------------------ god rays
RAYS = []
_rr = random.Random(11)
for i in range(13):
    RAYS.append(dict(ang=math.radians(-48 + 96 * i / 12 + _rr.uniform(-4, 4)), w=_rr.uniform(0.05, 0.13),
                     L=_rr.uniform(0.7, 1.15), sp=_rr.uniform(0.6, 1.8), ph=_rr.uniform(0, 6.28), I=_rr.uniform(0.55, 1.0)))
_YY, _XX = np.mgrid[0:H // 2, 0:W // 2].astype(np.float32)


def draw_rays(origin, t, strength, length_px, spread=1.0, rot=0.0):
    """returns half-res single-channel ray layer"""
    lay = np.zeros((H // 2, W // 2), np.float32)
    if strength <= 0.002:
        return lay
    ox, oy = origin[0] / 2, origin[1] / 2
    Lh = length_px / 2
    for r in RAYS:
        a = r["ang"] * spread + rot + 0.06 * math.sin(r["sp"] * t + r["ph"])
        inten = r["I"] * (0.65 + 0.35 * math.sin(r["sp"] * 2.3 * t + r["ph"] * 2))
        L = Lh * r["L"]
        dx, dy = math.sin(a), -math.cos(a)
        px, py = -dy, dx
        w0, w1 = 6, L * r["w"]
        pts = np.array([[ox + px * w0, oy + py * w0], [ox - px * w0, oy - py * w0],
                        [ox + dx * L - px * w1, oy + dy * L - py * w1], [ox + dx * L + px * w1, oy + dy * L + py * w1]], np.int32)
        cv2.fillConvexPoly(lay, pts, float(inten), cv2.LINE_AA)
    d = np.sqrt((_XX - ox) ** 2 + (_YY - oy) ** 2)
    fall = np.exp(-d / (Lh * 0.42))
    lay = cv2.GaussianBlur(lay, (0, 0), 4) * fall * strength * 0.8
    # central pillar
    col = np.exp(-((_XX - ox) ** 2) / (2 * (18 + 10 * strength) ** 2)) * np.clip(1 - (oy - _YY) / (Lh * 1.2), 0, 1) * (_YY < oy)
    lay += col * strength * 0.9
    return lay


def add_rays(img, lay, color=GOLD, gain=1.0):
    full = cv2.resize(lay, (W, H), interpolation=cv2.INTER_LINEAR)
    img += full[..., None] * (color * 0.75 + WARM_WHITE * 0.45) * gain


# ------------------------------------------------------------------ green-screen matte (triangulation matting)

def _ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


_gy, _gx = np.mgrid[0:360, 0:640].astype(np.float32)
GS_EDGE = (_ss(0, 34, _gx) * _ss(0, 34, 639 - _gx) * _ss(-4, 46, _gy) * _ss(0, 90, 359 - _gy)).astype(np.float32)


@lru_cache(maxsize=8)
def gs_layer(idx, scale):
    idx = int(clamp(idx, 1, 300))
    cg = cv2.imread(f"{GS_DIR}/g_{idx:04d}.png").astype(np.float32)
    cb = cv2.imread(f"{GS_DIR}/g_{idx + 300:04d}.png").astype(np.float32)
    one_minus_a = np.clip((cg[..., 1] - cb[..., 1]) / 199.0, 0, 1)
    a = 1 - one_minus_a
    a = np.clip((a - 0.04) / 0.96, 0, 1)
    fg = np.clip(cb - 3.0, 0, None) / 252.0          # premultiplied foreground (black-bg version)
    fg = cv2.GaussianBlur(fg, (0, 0), 0.6)
    a = cv2.GaussianBlur(a, (0, 0), 0.6)
    fg *= GS_EDGE[..., None]
    a *= GS_EDGE
    sw, sh = int(round(640 * scale)), int(round(360 * scale))
    fg = np.clip(cv2.resize(fg, (sw, sh), interpolation=cv2.INTER_CUBIC), 0, None)
    a = np.clip(cv2.resize(a, (sw, sh), interpolation=cv2.INTER_CUBIC), 0, 1)
    if scale > 1.8:   # crisp up the upscaled token art
        amt = min(1.0, (scale - 1.8) * 1.2)
        fg = np.clip(fg + (fg - cv2.GaussianBlur(fg, (0, 0), 1.8)) * amt, 0, None)
        a = np.clip(a + (a - cv2.GaussianBlur(a, (0, 0), 1.8)) * amt, 0, 1)
    # bloom
    small = cv2.resize(fg, (sw // 4, sh // 4), interpolation=cv2.INTER_AREA)
    bl = cv2.resize(cv2.GaussianBlur(small, (0, 0), 4), (sw, sh))
    return fg, a, bl


GS_CENTER = np.array([320.0, 108.0])    # content centre inside the GS frame
GS_SCALE = 1.6875


def comp_gs(img, idx, center, scale=GS_SCALE, opacity=1.0, bloom=0.35):
    fg, a, bl = gs_layer(idx, scale)
    sh, sw = a.shape
    x0 = int(round(center[0] - GS_CENTER[0] * scale))
    y0 = int(round(center[1] - GS_CENTER[1] * scale))
    # clip to frame
    fx0, fy0 = max(0, x0), max(0, y0)
    fx1, fy1 = min(W, x0 + sw), min(H, y0 + sh)
    if fx1 <= fx0 or fy1 <= fy0:
        return
    sx0, sy0 = fx0 - x0, fy0 - y0
    sl = (slice(sy0, sy0 + fy1 - fy0), slice(sx0, sx0 + fx1 - fx0))
    roi = img[fy0:fy1, fx0:fx1]
    aa = a[sl][..., None] * opacity
    roi[:] = roi * (1 - aa) + fg[sl] * 1.06 * opacity + bl[sl] * bloom * opacity


# ------------------------------------------------------------------ captions
FONT = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
EMOJI = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"
WHITE = (255, 255, 255)
YELLOW = (255, 224, 0)


def _is_emoji(ch):
    cp = ord(ch)
    return cp >= 0x1F000 or 0x2600 <= cp <= 0x27BF or cp in (0x200D, 0xFE0F)


def _runs(s):
    out = []
    for ch in s:
        k = "e" if _is_emoji(ch) else "t"
        if out and out[-1][0] == k:
            out[-1][1] += ch
        else:
            out.append([k, ch])
    return out


def render_line(text, size, fill, stroke):
    font = ImageFont.truetype(FONT, size)
    efont = ImageFont.truetype(EMOJI, 109, layout_engine=ImageFont.Layout.RAQM)
    pieces = []
    for kind, s in _runs(text):
        if kind == "t":
            l, t_, r, b = font.getbbox(s, stroke_width=stroke, anchor="ls")
            im = Image.new("RGBA", (r - l + 4, int(size * 1.6)), (0, 0, 0, 0))
            d = ImageDraw.Draw(im)
            d.text((-l + 2, int(size * 1.2)), s, font=font, fill=fill + (255,), stroke_width=stroke,
                   stroke_fill=(0, 0, 0, 255), anchor="ls")
            pieces.append(im)
        else:
            im = Image.new("RGBA", (140 * len(s) + 40, 160), (0, 0, 0, 0))
            d = ImageDraw.Draw(im)
            d.text((10, 10), s, font=efont, embedded_color=True)
            bb = im.getbbox()
            if bb is None:
                continue
            im = im.crop(bb)
            eh = int(size * 1.05)
            im = im.resize((max(1, int(im.width * eh / im.height)), eh), Image.LANCZOS)
            # stroke-like dark outline around emoji for legibility
            a = im.split()[3].filter(ImageFilter.MaxFilter(9))
            back = Image.new("RGBA", (im.width + 16, im.height + 16), (0, 0, 0, 0))
            sh = Image.new("RGBA", back.size, (0, 0, 0, 0))
            sh.paste((0, 0, 0, 255), (8, 8), a)
            back.alpha_composite(sh)
            back.alpha_composite(im, (8, 8))
            canvas = Image.new("RGBA", (back.width + 8, int(size * 1.6)), (0, 0, 0, 0))
            canvas.alpha_composite(back, (4, int(size * 1.2) - back.height + int(size * 0.14) + 8))
            pieces.append(canvas)
    wtot = sum(p.width for p in pieces) + 6 * (len(pieces) - 1)
    line = Image.new("RGBA", (max(1, wtot), int(size * 1.6)), (0, 0, 0, 0))
    x = 0
    for p in pieces:
        line.alpha_composite(p, (x, 0))
        x += p.width + 6
    bb = line.getbbox()
    return line.crop((0, max(0, bb[1] - 4), line.width, min(line.height, bb[3] + 4))) if bb else line


@lru_cache(maxsize=32)
def render_caption(key):
    lines, glow = CAPTION_DEFS[key]
    ims = [render_line(txt, size, col, max(8, size // 9)) for txt, col, size in lines]
    gap = 6
    wmax = max(i.width for i in ims)
    htot = sum(i.height for i in ims) + gap * (len(ims) - 1)
    pad = 40
    cap = Image.new("RGBA", (wmax + 2 * pad, htot + 2 * pad), (0, 0, 0, 0))
    y = pad
    for i in ims:
        cap.alpha_composite(i, ((cap.width - i.width) // 2, y))
        y += i.height + gap
    max_w = 960
    if wmax > max_w:     # auto-fit inside the safe width
        f = max_w / wmax
        cap = cap.resize((int(cap.width * f), int(cap.height * f)), Image.LANCZOS)
    # drop shadow (+ optional gold glow)
    a = np.array(cap.split()[3]).astype(np.float32) / 255
    shadow = cv2.GaussianBlur(np.roll(a, 9, axis=0), (0, 0), 6) * 0.55
    rgba = np.array(cap).astype(np.float32) / 255
    bgr = rgba[..., [2, 1, 0]] * rgba[..., 3:4]
    alpha = rgba[..., 3:4]
    out_a = alpha + shadow[..., None] * (1 - alpha)
    glow_l = None
    if glow:
        glow_l = cv2.GaussianBlur(a, (0, 0), 14)[..., None] * GOLD * 0.9
    return bgr, out_a, glow_l


CAPTION_DEFS = {
    "c1": ([("QUANDO O PARÇA", WHITE, 92), ("ENTRA NO MATO...", YELLOW, 92)], False),
    "c3": ([("PERA... ISSO É", WHITE, 96), ("UM BAÚ?? 😳", YELLOW, 104)], False),
    "c3b": ([("O BAÚ PIRATA?! 🏴‍☠️", YELLOW, 96)], False),
    "c4": ([("TÁ TREMENDO!!! 😱", WHITE, 100)], False),
    "c5": ([("VAI ESTOURAR 🔥🔥", YELLOW, 108)], False),
    "c6": ([("LENDÁRIOOO!!!", YELLOW, 150)], True),
    "c7": ([("1 EM 137.500 😭", WHITE, 104)], False),
    "c8": ([("TOKEN PIRATA", WHITE, 112), ("NA CONTA 🏴‍☠️", YELLOW, 112)], True),
    "c9": ([("CHANCE DE 1 EM 137.500", YELLOW, 70)], False),
}
# key, t0, t1, center_y, tilt_deg
CAPTIONS = [
    ("c1", 0.05, T_S3 - 0.02, 360, -2.0),
    ("c3", 3.90, 4.75, 360, 2.0),
    ("c3b", 4.78, T_SHAKE, 360, -1.5),
    ("c4", T_SHAKE + 0.02, 7.00, 360, 1.5),
    ("c5", 7.02, T_BURST, 360, -2.0),
    ("c6", T_BURST + 0.03, 9.45, 330, -3.0),
    ("c7", 9.50, T_FINAL - 0.02, 1430, 1.5),
    ("c8", T_FINAL + 0.25, DUR, 1300, -2.0),
    ("c9", T_FINAL + 0.55, DUR, 1480, 1.5),
]


def comp_caption(img, key, t0, t, cy, tilt, extra=(0, 0)):
    bgr, a, glow = render_caption(key)
    tau = t - t0
    s = 1 - 0.45 * math.exp(-tau * 22) * math.cos(tau * 28)
    rot = tilt + 4.0 * math.exp(-tau * 15) * math.sin(tau * 35)
    if key == "c4":   # trembling text
        rot += 2.5 * math.sin(t * 70)
        extra = (extra[0] + 5 * math.sin(t * 93), extra[1] + 4 * math.cos(t * 81))
    h, w = a.shape[:2]
    M = cv2.getRotationMatrix2D((w / 2, h / 2), rot, s)
    cx, cyy = W / 2 + extra[0], cy + extra[1]
    M[:, 2] += [cx - w / 2, cyy - h / 2]
    # ROI
    corners = np.array([[0, 0, 1], [w, 0, 1], [0, h, 1], [w, h, 1]], np.float32) @ M.T
    x0, y0 = np.floor(corners.min(0)).astype(int)
    x1, y1 = np.ceil(corners.max(0)).astype(int)
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(W, x1), min(H, y1)
    if x1 <= x0 or y1 <= y0:
        return
    M2 = M.copy(); M2[:, 2] -= [x0, y0]
    sz = (x1 - x0, y1 - y0)
    cb = cv2.warpAffine(bgr, M2, sz, flags=cv2.INTER_LINEAR)
    ca = cv2.warpAffine(a, M2, sz, flags=cv2.INTER_LINEAR)
    if ca.ndim == 2:
        ca = ca[..., None]
    roi = img[y0:y1, x0:x1]
    if glow is not None:
        cg = cv2.warpAffine(glow, M2, sz, flags=cv2.INTER_LINEAR)
        roi += cg * (0.8 + 0.2 * math.sin(t * 9))
    roi[:] = roi * (1 - ca) + cb


# ------------------------------------------------------------------ grading

def _curve_lut():
    x = np.linspace(0, 1, 256)
    y = np.clip((x - 0.035) / 0.95, 0, 1)
    k = 6.2
    s = 1 / (1 + np.exp(-k * (y - 0.47)))
    s = (s - s[0]) / (s[-1] - s[0])
    y = 0.55 * y + 0.45 * s
    return np.clip(y * 255, 0, 255).astype(np.uint8)


LUT = _curve_lut()


def grade_pop(img, sat=1.32, sharpen=0.35):
    u8 = np.clip(img * 255, 0, 255).astype(np.uint8)
    u8 = cv2.LUT(u8, LUT)
    f = u8.astype(np.float32) / 255
    lum = f[..., 0:1] * 0.114 + f[..., 1:2] * 0.587 + f[..., 2:3] * 0.299
    f = lum + (f - lum) * sat
    # gentle warm push in highlights, teal-ish shadows (meme "pop")
    f[..., 2] += 0.025 * lum[..., 0]
    f[..., 0] += 0.02 * (1 - lum[..., 0]) - 0.01
    if sharpen:
        bl = cv2.GaussianBlur(f, (0, 0), 1.6)
        f = f + (f - bl) * sharpen
    return np.clip(f, 0, 1)


# ------------------------------------------------------------------ camera

def shake_noise(t, freq, seed):
    return (math.sin(t * freq * 1.0 + seed) * 0.5 + math.sin(t * freq * 1.73 + seed * 2.1) * 0.3
            + math.sin(t * freq * 2.91 + seed * 0.7) * 0.2)


def chest_center_frame(t):
    ts = src_time(t)
    sim = sim_for(src_index(ts))
    return local_to_frame(sim, np.array([0.0, -170.0]))


FACE_S2 = np.array([660.0, 600.0])
BURST_CENTER = np.array([520.0, 890.0])


def camera(t):
    """returns zoom, center(frame coords), rot(deg), shake(dx,dy)"""
    sx = sy = rot = 0.0
    z, c = 1.0, np.array([540.0, 960.0])

    def impulse(t0, amp, dec=0.16, freq=60, seed=1.0):
        if t < t0:
            return 0.0, 0.0
        e = amp * math.exp(-(t - t0) / dec)
        return e * shake_noise(t, freq, seed), e * shake_noise(t, freq, seed + 3.3)

    if t < T_S2:
        z = 1.0 + 0.14 * (1 - ease_out(t / 0.35))
    elif t < T_S3:
        z = 1.38 + 0.05 * (t - T_S2) / (T_S3 - T_S2)
        c = FACE_S2
        dx, dy = impulse(T_S2, 22); sx += dx; sy += dy
    elif t < 3.90:
        z = 1.0 + 0.03 * (t - T_S3) / 2.1
        dx, dy = impulse(T_S3, 16); sx += dx; sy += dy
    elif t < 4.75:
        z = 1.0 + 0.30 * ease_out((t - 3.90) / 0.08) + 0.04 * (t - 3.9)
        c = 0.45 * np.array([540.0, 960.0]) + 0.55 * chest_center_frame(t)
        dx, dy = impulse(3.90, 20); sx += dx; sy += dy
    elif t < T_SHAKE:
        z = 1.04 + 0.02 * (t - 4.75)
        dx, dy = impulse(4.75, 14); sx += dx; sy += dy
    elif t < T_BURST:
        e = (t - T_SHAKE) / (T_BURST - T_SHAKE)
        z = 1.07 + 0.16 * smoothstep(0, 1, e) + (0.07 if t >= 7.0 else 0.0)
        cc = chest_center_frame(t)
        c = 0.5 * np.array([540.0, 960.0]) + 0.5 * np.array([cc[0], cc[1] - 200])
        amp = 3 + 15 * e ** 1.5
        sx += amp * shake_noise(t, 55, 0.3)
        sy += amp * shake_noise(t, 61, 1.9)
        rot += 0.9 * e * shake_noise(t, 37, 2.2)
        if t >= 7.0:
            dx, dy = impulse(7.0, 18); sx += dx; sy += dy
    elif t < T_FINAL:
        tb = t - T_BURST
        z = 1.30 + 0.13 * ease_out(tb / 0.10) + 0.025 * tb
        c = BURST_CENTER
        e = math.exp(-tb / 0.22)
        sx += 55 * e * shake_noise(t, 48, 4.4) + 3 * shake_noise(t, 9, 1.0)
        sy += 55 * e * shake_noise(t, 53, 0.4) + 3 * shake_noise(t, 7, 2.0)
        rot += 3.5 * e * shake_noise(t, 31, 5.1)
    return z, c, rot, (sx, sy)


def camera_matrix(z, c, rot, sh):
    M = cv2.getRotationMatrix2D((float(c[0]), float(c[1])), rot, z)
    M[:, 2] += [540 - c[0] + sh[0], 960 - c[1] + sh[1]]
    return M


# ------------------------------------------------------------------ frame renderers
_YQ, _XQ = np.mgrid[0:H // 4, 0:W // 4].astype(np.float32)
VIGNETTE = None


def vignette():
    global VIGNETTE
    if VIGNETTE is None:
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        d = np.sqrt(((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H / 2) / (H * 0.62)) ** 2)
        VIGNETTE = np.clip(1 - 0.75 * np.clip(d - 0.45, 0, None) ** 1.4, 0, 1)[..., None].astype(np.float32)
    return VIGNETTE


@lru_cache(maxsize=4)
def load_src(idx):
    return cv2.imread(f"{SRC_DIR}/r_{idx:04d}.png").astype(np.float32) / 255.0


def fx_levels(t):
    """spill, aura, rays, flash"""
    if t < T_SHAKE:
        pulse = 0.5 + 0.5 * math.sin(t * 4.0)
        return 0.04 + 0.03 * pulse, 0.05 + 0.05 * pulse, 0.0, 0.0
    if t < T_BURST:
        e = (t - T_SHAKE) / (T_BURST - T_SHAKE)
        fl = 0.85 + 0.15 * math.sin(t * 47)
        return (0.08 + 0.9 * e ** 1.4) * fl, (0.10 + 1.2 * e ** 1.3) * fl, 0.0, 0.0
    tb = t - T_BURST
    spill = 0.55 + 0.9 * math.exp(-tb / 0.22)
    aura = 0.55 + 0.9 * math.exp(-tb / 0.25)
    rays = ease_out(tb / 0.12) * (0.55 + 0.45 * math.exp(-tb / 0.3)) * (0.9 + 0.1 * math.sin(t * 13))
    flash = 0.85 * math.exp(-tb / 0.05)
    return spill, aura, rays, flash


def render_scene(t):
    """real footage + chest + light FX, before camera transform"""
    ts = src_time(t)
    sidx = src_index(ts)
    bg = load_src(sidx).copy()
    sim = sim_for(sidx)
    cf = chest_frame(t)
    spr = load_sprite(cf)
    M = chest_affine(sim)
    spill, aura, rays, flash = fx_levels(t)

    # chest centre (frame coords) for lighting
    cc = local_to_frame(sim, np.array([0.0, -150.0]))
    s = sim[1]
    # --- light spill on environment (lights surfaces relative to albedo)
    r = 330 * s * (1 + 0.35 * min(spill, 1.5))
    d2 = ((_XQ * 4 - cc[0]) ** 2 + (_YQ * 4 - cc[1]) ** 2) / (2 * r * r)
    sp = cv2.resize(np.exp(-d2), (W, H), interpolation=cv2.INTER_LINEAR)[..., None]
    bg = bg * (1 + sp * spill * 1.3 * GOLD) + sp * spill * 0.08 * GOLD

    # --- contact shadow (height aware)
    lift = max(0.0, -(mouth_local(cf)[1] - mouth_local(0)[1])) * s
    cs_str = 0.85 * math.exp(-lift / (55 * s))
    if cs_str > 0.01:
        cs = np.zeros((H // 2, W // 2), np.float32)
        an = local_to_frame(sim, np.array([0.0, -6.0]))
        ax = (CHEST_W_REF * 0.56 * s * (1 + lift / (160 * s))) / 2
        ay = (CHEST_W_REF * 0.16 * s * (1 + lift / (160 * s))) / 2
        cv2.ellipse(cs, (int(an[0] / 2), int(an[1] / 2)), (int(max(ax, 2)), int(max(ay, 1))), math.degrees(sim[2]), 0, 360, 1.0, -1, cv2.LINE_AA)
        cs = cv2.GaussianBlur(cs, (0, 0), 7 * s + lift / 12)
        cs2 = cv2.GaussianBlur(cs, (0, 0), 16 * s)
        csf = cv2.resize(cs * 0.75 + cs2 * 0.5, (W, H), interpolation=cv2.INTER_LINEAR)[..., None]
        bg = bg * (1 - np.clip(csf, 0, 1) * cs_str)
    bg_clean = bg.copy()

    # --- chest layer (ROI warp)
    h0, w0 = spr.shape[:2]
    corners = np.array([[0, 0, 1], [w0, 0, 1], [0, h0, 1], [w0, h0, 1]], np.float32) @ M.T
    x0, y0 = np.floor(corners.min(0)).astype(int) - 12
    x1, y1 = np.ceil(corners.max(0)).astype(int) + 12
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(W, x1), min(H, y1)
    obj_full = None
    if x1 > x0 and y1 > y0:
        M2 = M.copy(); M2[:, 2] -= [x0, y0]
        sz = (x1 - x0, y1 - y0)
        lay = cv2.warpAffine(spr, M2, sz, flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        # match softness of the footage
        lay = cv2.GaussianBlur(lay, (0, 0), 0.9)
        # camera motion blur (velocity of the tracked anchor, 24 fps source)
        if t < T_BURST:
            p_prev = sim_for(sidx - 1)[0]
            v = (sim[0] - p_prev) * 0.5
            L = float(np.hypot(*v))
            if L > 2.0:
                ks = int(min(61, 2 * math.ceil(L / 2) + 1))
                kern = np.zeros((ks, ks), np.float32)
                c0 = ks // 2
                ang = math.atan2(v[1], v[0])
                cv2.line(kern, (int(round(c0 - math.cos(ang) * L / 2)), int(round(c0 - math.sin(ang) * L / 2))),
                         (int(round(c0 + math.cos(ang) * L / 2)), int(round(c0 + math.sin(ang) * L / 2))), 1.0, 1)
                kern /= max(kern.sum(), 1e-6)
                lay = cv2.filter2D(lay, -1, kern)
        prem, al, obj = lay[..., :3], lay[..., 3:4], lay[..., 4]
        # sensor grain on the CG
        rng = np.random.default_rng(int(t * 1000))
        grain = rng.normal(0, 0.016, prem.shape[:2]).astype(np.float32)[..., None]
        prem = prem + grain * obj[..., None]
        # gold glow from within during rumble (chest self-illumination boost)
        prem = prem * (1 + 0.08 * max(0.0, min(aura, 1.5) - 0.1) * obj[..., None])
        # ambient occlusion toward the chest base while grounded
        occ0 = clamp(1 - lift / (25 * s))
        if occ0 > 0:
            dd = max(4, int(70 * s))
            below2 = np.zeros_like(obj); below2[:-dd] = obj[dd:]
            ao = cv2.GaussianBlur(np.clip(obj - below2, 0, 1), (0, 0), 10 * s)
            prem = prem * (1 - 0.45 * occ0 * ao[..., None])
        roi = bg[y0:y1, x0:x1]
        roi[:] = prem + roi * (1 - al)
        # leaves in front of the chest base (only while it rests on the ground)
        occ = clamp(1 - lift / (10 * s))
        if occ > 0:
            d = max(3, int(30 * s))
            ob = obj.copy()
            below = np.zeros_like(ob); below[:-d] = ob[d:]
            band = np.clip(ob - below, 0, 1)
            band = cv2.GaussianBlur(band, (0, 0), 1.5)
            band = np.clip(band * 1.6, 0, 1)
            src = bg_clean[y0:y1, x0:x1]
            leaf = np.clip(((src[..., 2] + src[..., 0]) * 0.5 - src[..., 1] - 0.008) * 16, 0, 1)
            leaf = np.maximum(leaf, np.clip((0.16 - src.mean(axis=2)) * 9, 0, 1) * 0.8)
            leaf = cv2.GaussianBlur(leaf, (0, 0), 1.0)
            m = (band * leaf * occ)[..., None]
            roi[:] = roi * (1 - m) + src * m
        obj_full = np.zeros((H, W), np.float32)
        obj_full[y0:y1, x0:x1] = obj
        bright = np.zeros((H, W, 3), np.float32)
        bright[y0:y1, x0:x1] = np.clip(prem - 0.72, 0, None)

    img = grade_pop(bg)

    # --- aura + bloom (after grade)
    if obj_full is not None:
        small = cv2.resize(obj_full, (W // 4, H // 4), interpolation=cv2.INTER_AREA)
        a1 = cv2.GaussianBlur(small, (0, 0), 6 * max(s, 0.5))
        a2 = cv2.GaussianBlur(small, (0, 0), 22 * max(s, 0.5))
        au = cv2.resize(a1 * 1.2 + a2 * 1.9, (W, H), interpolation=cv2.INTER_LINEAR)
        au = au * (1 - 0.8 * obj_full)
        img += au[..., None] * GOLD * aura * 0.55
        bs = cv2.resize(bright, (W // 4, H // 4), interpolation=cv2.INTER_AREA)
        bb = cv2.resize(cv2.GaussianBlur(bs, (0, 0), 5), (W, H), interpolation=cv2.INTER_LINEAR)
        img += bb * (0.3 + 0.45 * min(aura, 2.0))

    # --- rays + shockwave
    mouth = local_to_frame(sim, mouth_local(cf))
    if rays > 0:
        tb = t - T_BURST
        lay = draw_rays(mouth, t, rays, 1700 * max(s, 0.6) * (0.6 + 0.4 * ease_out(tb / 0.25)), rot=0.05 * math.sin(t * 0.8))
        add_rays(img, lay, gain=0.75)
        if tb < 0.5:
            rr = 60 + 1500 * ease_out(tb / 0.5)
            ring = np.zeros((H // 2, W // 2), np.float32)
            cv2.ellipse(ring, (int(cc[0] / 2), int((cc[1] + 120 * s) / 2)), (int(rr / 2), int(rr / 2 * 0.42)), 0, 0, 360,
                        1.0, int(max(2, 18 * (1 - tb / 0.5))), cv2.LINE_AA)
            ring = cv2.GaussianBlur(ring, (0, 0), 4) * (1 - tb / 0.5) * 1.6
            img += cv2.resize(ring, (W, H))[..., None] * (GOLD + WARM_WHITE) * 0.6

    # --- particles (chest-local -> frame)
    core = np.zeros((H, W), np.float32)
    dust = np.zeros((H, W), np.float32)
    debris = np.zeros((H, W), np.float32)
    items = []
    mloc = mouth_local(cf)
    for p in PARTS:
        st = particle_state(p, t)
        if st is None:
            continue
        x, y, a = st
        if p.t0 >= T_BURST:
            x, y = x + mloc[0], y + mloc[1]
        fx, fy = local_to_frame(sim, np.array([x, y]))
        items.append((fx, fy, a, p.size * max(s, 0.6), p.kind))
    draw_particles(core, dust, debris, items)
    if debris.any():
        db = cv2.GaussianBlur(debris, (0, 0), 0.8)[..., None]
        img[:] = img * (1 - db * 0.85) + db * 0.85 * np.array([0.42, 0.50, 0.55], np.float32)
    add_glow_layers(img, core, dust)

    # --- flash
    if flash > 0.003:
        img += flash * WARM_WHITE
    return img, mouth


def render_frame(t):
    if t >= T_FINAL - 1e-9:
        return render_final(t)
    img, mouth = render_scene(t)
    z, c, rot, sh = camera(t)
    M = camera_matrix(z, c, rot, sh)
    out = cv2.warpAffine(img, M, (W, H), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT101)

    if t >= T_BURST:
        tb = t - T_BURST
        # chromatic aberration kick
        ca = int(round(14 * math.exp(-tb / 0.12)))
        if ca >= 1:
            out[..., 2] = np.roll(out[..., 2], ca, axis=1)
            out[..., 0] = np.roll(out[..., 0], -ca, axis=1)
        # dim + blur background for the token overlay
        dimf = smoothstep(0.25, 0.8, tb)
        if dimf > 0:
            bl = cv2.GaussianBlur(out, (0, 0), 1 + 5 * dimf)
            out = (out * (1 - dimf) + bl * dimf) * (1 - 0.40 * dimf)
            out *= 1 - (1 - vignette()) * dimf
        gs_idx = int(math.floor((GS_T0 + tb) * GS_FPS)) + 1
        shk = (sh[0] * 0.35, sh[1] * 0.35)
        comp_gs(out, gs_idx, (540 + shk[0], 880 + shk[1]))
        # pre-flash for the transition into the final card
        pre = smoothstep(T_FINAL - 0.16, T_FINAL, t) ** 2
        if pre > 0:
            out += pre * 1.1 * (WARM_WHITE * 0.7 + GOLD * 0.3)
    else:
        out = np.clip(out, 0, None)
    cap_shake = (sh[0] * 0.3, sh[1] * 0.3)
    for key, t0, t1, cy, tilt in CAPTIONS:
        if t0 <= t < t1:
            comp_caption(out, key, t0, t, cy, tilt, cap_shake)
    return out


@lru_cache(maxsize=1)
def load_photo():
    im = cv2.imread(PHOTO).astype(np.float32) / 255
    h, w = im.shape[:2]
    sc = max(W / w, H / h)
    im = cv2.resize(im, (int(round(w * sc)), int(round(h * sc))), interpolation=cv2.INTER_AREA)
    y0 = (im.shape[0] - H) // 2
    x0 = (im.shape[1] - W) // 2
    im = im[y0:y0 + H, x0:x0 + W]
    return grade_pop(im, sat=1.28, sharpen=0.25)


def render_final(t):
    tau = t - T_FINAL
    photo = load_photo()
    z = 1.045 + 0.035 * tau / 3.4 + 0.12 * math.exp(-tau / 0.14)
    rot = 0.45 * math.sin(2 * math.pi * tau / 3.2)
    dy = 9 * math.sin(2 * math.pi * tau / 2.4)
    dx = 5 * math.sin(2 * math.pi * tau / 3.7)
    M = cv2.getRotationMatrix2D((540, 900), rot, z)
    M[:, 2] += [dx, dy]
    img = cv2.warpAffine(photo, M, (W, H), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT101)
    # banner moves from overlay position up above his head, then floats
    k = ease_out(tau / 0.55)
    by = 880 * (1 - k) + 345 * k + 12 * math.sin(2 * math.pi * tau / 1.7) * k
    bx = 540 + 4 * math.sin(2 * math.pi * tau / 2.3)
    bs = GS_SCALE * (1.0 + 0.58 * k + 0.02 * math.sin(2 * math.pi * tau / 1.7))
    # rotating gold rays behind the token
    token = np.array([bx, by - 38 * bs])
    lay = np.zeros((H // 2, W // 2), np.float32)
    n = 16
    for i in range(n):
        a = 2 * math.pi * i / n + tau * 0.35
        L = 900
        w1 = L * 0.10
        ox, oy = token / 2
        dxr, dyr = math.cos(a), math.sin(a)
        px, py = -dyr, dxr
        pts = np.array([[ox, oy], [ox + dxr * L / 2 - px * w1 / 2, oy + dyr * L / 2 - py * w1 / 2],
                        [ox + dxr * L / 2 + px * w1 / 2, oy + dyr * L / 2 + py * w1 / 2]], np.int32)
        cv2.fillConvexPoly(lay, pts, 0.6 + 0.4 * (i % 2), cv2.LINE_AA)
    d = np.sqrt((_XX - token[0] / 2) ** 2 + (_YY - token[1] / 2) ** 2)
    lay = cv2.GaussianBlur(lay, (0, 0), 6) * np.exp(-d / 130) * 0.30 * (0.85 + 0.15 * math.sin(tau * 5))
    halo = np.exp(-(d ** 2) / (2 * 70 ** 2)) * 0.22
    img += cv2.resize(lay + halo, (W, H))[..., None] * (GOLD * 0.8 + WARM_WHITE * 0.3)
    plate = np.exp(-(((_XQ * 4 - bx) / 560) ** 2) - (((_YQ * 4 - by) / 190) ** 2))
    img *= 1 - 0.55 * k * cv2.resize(plate, (W, H))[..., None]
    comp_gs(img, GS_HOLD_IDX, (bx, by), scale=bs, bloom=0.45)
    # sparkles
    core = np.zeros((H, W), np.float32)
    dust = np.zeros((H, W), np.float32)
    items = []
    for p in FINAL_PARTS:
        st = particle_state(p, t)
        if st is None:
            continue
        items.append((st[0], st[1], st[2] * 0.8, p.size, p.kind))
    draw_particles(core, dust, dust, items)
    add_glow_layers(img, core, dust, glow_gain=0.8)
    # golden flash out of the transition
    fl = 1.1 * math.exp(-tau / 0.20)
    img += fl * (WARM_WHITE * 0.7 + GOLD * 0.3)
    for key, t0, t1, cy, tilt in CAPTIONS:
        if t0 <= t < t1:
            comp_caption(img, key, t0, t, cy, tilt)
    return img


def frame_bytes(i):
    t = i / FPS
    img = render_frame(t)
    # soft highlight roll-off then 8-bit RGB
    img = np.where(img > 0.85, 0.85 + (1 - np.exp(-(img - 0.85) * 5)) * 0.15, img)
    u8 = np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8)
    return cv2.cvtColor(u8, cv2.COLOR_BGR2RGB).tobytes()


if __name__ == "__main__":
    out = sys.argv[1]
    prev = os.environ.get("PREVIEW_PNG")
    if prev:
        os.makedirs(prev, exist_ok=True)
        for tt in [float(x) for x in sys.argv[2:]]:
            i = int(round(tt * FPS))
            b = frame_bytes(i)
            im = np.frombuffer(b, np.uint8).reshape(H, W, 3)
            cv2.imwrite(f"{prev}/p_{tt:06.2f}.png", cv2.cvtColor(im, cv2.COLOR_RGB2BGR))
        sys.exit(0)
    t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    t1 = float(sys.argv[3]) if len(sys.argv) > 3 else DUR
    crf = os.environ.get("CRF", "12")
    preset = os.environ.get("PRESET", "slow")
    frames = list(range(int(round(t0 * FPS)), int(round(t1 * FPS))))
    cmd = ["ffmpeg", "-v", "error", "-y",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
           "-map", "0:v", "-map", "1:a", "-shortest",
           "-c:v", "libx264", "-preset", preset, "-crf", crf, "-pix_fmt", "yuv420p",
           "-profile:v", "high", "-level", "5.2", "-x264-params", "aq-mode=3:deblock=-1,-1",
           "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
           "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    import multiprocessing as mp
    nproc = int(os.environ.get("NPROC", "4"))
    with mp.get_context("fork").Pool(nproc) as pool:
        for n, b in enumerate(pool.imap(frame_bytes, frames, chunksize=6)):
            proc.stdin.write(b)
            if n % 60 == 0:
                print(f"frame {frames[n]} / {frames[-1]}", flush=True)
    proc.stdin.close()
    proc.wait()
    print("done", out)
