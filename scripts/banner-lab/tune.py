"""Tries values for the replica's look against the real banner, in one appearance.

    python3 scripts/banner-lab/tune.py light 'LIGHT_WASH=0.05' 'LIGHT_WASH=0.15 RIM=0.2' ...

Each candidate is a set of NN_LOOK_ overrides (see BannerLook in CustomOverlay.swift),
rendered by the lab build of the app's own view (run.sh builds it) on white, black and
gray, and compared with the real banner captured on the same backdrops by run.sh.
Prints, per candidate, how far the inside and the edge are off; lower is closer.
Switches the system to the given appearance for the run and back afterwards.
"""
import os, subprocess, sys, time
import numpy as np
from PIL import Image

OUT = "build/banner-lab"
LAB = f"{OUT}/lab"
BACKDROPS = ["white", "black", "gray"]
M = 30  # capture margin, see lab.swift

appearance, candidates = sys.argv[1], sys.argv[2:]
current = "dark" if "Dark" in subprocess.run(["defaults", "read", "-g", "AppleInterfaceStyle"],
                                             capture_output=True, text=True).stdout else "light"


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(float)


def measure(img):
    h, w, _ = img.shape
    s = w / (344 + 2 * M)
    m = int(M * s)
    inside = img[m + int(12 * s):m + int(46 * s), m + int(250 * s):m + int(330 * s)].mean()
    # Down through the top edge at the middle: two rows outside, four inside.
    edge = np.array([img[m + k, w // 2].mean() for k in range(-2, 4)])
    return inside, edge


try:
    subprocess.run([LAB, "theme", appearance], check=True)
    # The switch takes a moment, and the lab files its captures by the appearance it sees.
    time.sleep(2.5)
    run = int(time.time())
    real = {bd: measure(load(f"{OUT}/cap/{appearance}/real-{bd}.png")) for bd in BACKDROPS}
    for i, cand in enumerate(candidates):
        env = dict(os.environ)
        for kv in cand.split():
            k, v = kv.split("=")
            env["NN_LOOK_" + k] = v
        # Unique per run, so a capture that went missing can't be read from an older one.
        name = f"tune{run}x{i}"
        subprocess.run([LAB, "prod", name, "--", *BACKDROPS], env=env, check=True, capture_output=True)
        di, de, parts = 0.0, 0.0, []
        for bd in BACKDROPS:
            ri, re_ = real[bd]
            path = f"{OUT}/cap/{appearance}/cand-{name}-{bd}.png"
            if not os.path.exists(path):
                sys.exit(f"no capture {path}: was the system really in {appearance} mode?")
            oi, oe = measure(load(path))
            di += abs(oi - ri) / len(BACKDROPS)
            de += np.abs(oe - re_).mean() / len(BACKDROPS)
            parts.append(f"{bd} {oi - ri:+5.1f}")
        print(f"{cand:45s} inside {di:5.2f}  edge {de:5.2f}   ({', '.join(parts)})", flush=True)
finally:
    subprocess.run([LAB, "theme", current])
