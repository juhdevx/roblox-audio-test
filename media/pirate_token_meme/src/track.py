"""Track the ground plane through the bushes segment.

Computes frame-to-frame homographies on the lower (ground) part of each frame,
chains them to a reference frame, and saves per-frame homography H_ref->frame.
"""
import sys, json
import numpy as np
import cv2

SRC = sys.argv[1]          # dir with r_%04d.png
OUT = sys.argv[2]          # output npz
F0, F1, REF = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])

sift = cv2.SIFT_create(nfeatures=6000, contrastThreshold=0.01)
bf = cv2.BFMatcher(cv2.NORM_L2)


def load(i):
    im = cv2.imread(f"{SRC}/r_{i:04d}.png")
    g = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
    return g


def feats(g):
    h, w = g.shape
    mask = np.zeros_like(g)
    mask[int(h * 0.50):, :] = 255   # ground region
    kp, des = sift.detectAndCompute(g, mask)
    return kp, des


def homog(a, b):
    """Homography mapping points in frame a -> frame b."""
    kpa, da = a
    kpb, db = b
    m = bf.knnMatch(da, db, k=2)
    good = [x for x, y in m if x.distance < 0.75 * y.distance]
    pa = np.float32([kpa[x.queryIdx].pt for x in good])
    pb = np.float32([kpb[x.trainIdx].pt for x in good])
    H, inl = cv2.findHomography(pa, pb, cv2.USAC_MAGSAC, 3.0, maxIters=10000, confidence=0.999)
    return H, int(inl.sum()), len(good)


frames = list(range(F0, F1 + 1))
F = {i: feats(load(i)) for i in frames}
# chain: H_ref_to[i]
H = {REF: np.eye(3)}
for i in range(REF + 1, F1 + 1):
    h, n, g = homog(F[i - 1], F[i])
    H[i] = h @ H[i - 1]
    print(i, n, g, flush=True)
for i in range(REF - 1, F0 - 1, -1):
    h, n, g = homog(F[i + 1], F[i])
    H[i] = h @ H[i + 1]
    print(i, n, g, flush=True)

np.savez(OUT, frames=np.array(frames), H=np.stack([H[i] for i in frames]))
