"""Check a red-custom-panel recording over a gray lab backdrop for gray native rows.

Record the rightmost 460 x 600 points starting just below the menu bar. This is a
diagnostic for that controlled scene, not an arbitrary-video classifier. Print only
counts/timestamps; never extract notification text or persist captured frames.
Requires ffmpeg, ffprobe, and NumPy. Exit 1 for suspected native exposures.
"""
import argparse
import json
import subprocess

import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("recording")
args = parser.parse_args()
probe = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
    "frame=best_effort_timestamp_time", "-of", "json", args.recording,
]))
timestamps = [float(frame["best_effort_timestamp_time"]) for frame in probe["frames"]]
decoder = subprocess.Popen([
    "ffmpeg", "-v", "error", "-i", args.recording, "-vf", "scale=230:300",
    "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
], stdout=subprocess.PIPE)
suspects = []
count = 0
maximum = 0
while True:
    raw = decoder.stdout.read(230 * 300 * 3)
    if not raw:
        break
    if len(raw) != 230 * 300 * 3:
        raise RuntimeError("Incomplete decoded frame")
    frame = np.frombuffer(raw, dtype=np.uint8).reshape(300, 230, 3).astype(np.int16)
    # Card interiors, excluding the neutral toolbar/footer. White labels are small;
    # native gray card fills occupy hundreds more pixels than the red custom cards.
    cards = frame[35:120, 45:218]
    neutral = (cards.max(2) - cards.min(2) < 12) & (cards.mean(2) > 125) & (cards.mean(2) < 220)
    score = int(neutral.sum())
    maximum = max(maximum, score)
    if score > 450:
        suspects.append(timestamps[count])
    count += 1
if decoder.wait() != 0 or count == 0 or count != len(timestamps):
    raise RuntimeError("Recording did not decode completely")
print(f"{count} captured frames; {len(suspects)} suspected native exposures; maximum neutral score {maximum}")
if suspects:
    print("Suspect timestamps (seconds):", " ".join(f"{timestamp:.3f}" for timestamp in suspects))
raise SystemExit(1 if suspects else 0)
