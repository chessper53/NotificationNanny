"""Measure native panel visibility by comparing recording frames with the initial baseline.
Print numbers only and retain no frames containing personal notifications."""
import json, subprocess, sys, tempfile, os
import numpy as np
from PIL import Image

path = sys.argv[1]
probe = json.loads(subprocess.run(
    ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=avg_frame_rate",
     "-of", "json", path], capture_output=True, text=True, check=True).stdout)
num, den = probe["streams"][0]["avg_frame_rate"].split("/")
fps = float(num) / float(den or 1)

with tempfile.TemporaryDirectory() as d:
    # Small greyscale frames are plenty to tell "panel there" from "not there".
    subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", "scale=190:-1,format=gray",
                    os.path.join(d, "f%05d.png")], check=True)
    names = sorted(os.listdir(d))
    frames = [np.asarray(Image.open(os.path.join(d, n)), dtype=np.float32) for n in names]

base = frames[0]
# Count strongly changed pixels because text changes are clearer than the glass's mean brightness.
changed = [float((np.abs(f - base) > 30).mean() * 100) for f in frames]
step = max(1, round(fps / 10))
timeline = " ".join(f"{max(changed[i:i + step]):.0f}" for i in range(0, len(changed), step))
print(f"changed % per 100 ms: {timeline}")
visible = [i for i, v in enumerate(changed) if v > 2.0]
if not visible:
    print(f"flash: panel never visible ({len(frames)} frames at {fps:.0f} fps, max {max(changed):.1f}% changed)")
else:
    print(f"flash: something visible in {len(visible)} of {len(frames)} frames at {fps:.0f} fps "
          f"(~{len(visible) / fps * 1000:.0f} ms, max {max(changed):.1f}% changed)")
