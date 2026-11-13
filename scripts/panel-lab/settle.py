"""Measure frame differences from the final settled frame to reveal panels reappearing during exit.
Print differences and frame rate only; retain no captured frames."""
import json, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image

path = sys.argv[1]
probe = json.loads(subprocess.run(
    ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=avg_frame_rate",
     "-of", "json", path], capture_output=True, text=True, check=True).stdout)
num, den = probe["streams"][0]["avg_frame_rate"].split("/")
fps = float(num) / float(den or 1)
with tempfile.TemporaryDirectory() as d:
    subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", "scale=190:-1,format=gray",
                    os.path.join(d, "f%05d.png")], check=True)
    frames = [np.asarray(Image.open(os.path.join(d, n)), dtype=np.float32) for n in sorted(os.listdir(d))]
last = frames[-1]
print(f"{fps:.1f} fps:", " ".join(str(int(round(float((np.abs(f - last) > 20).mean() * 100)))) for f in frames))
