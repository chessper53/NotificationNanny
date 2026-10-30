"""Side by side: the real banner in each state (left) and ours (right).

    python3 scripts/banner-lab/states_sheet.py [appearance] [backdrop]

Reads the captures of lab real-states and prod-states; writes states-sheet.png.
"""
import sys
from PIL import Image

appearance = sys.argv[1] if len(sys.argv) > 1 else "dark"
bd = sys.argv[2] if len(sys.argv) > 2 else "gray"
d = f"build/banner-lab/cap/{appearance}/"
rows = []
for st in ["collapsed", "hover", "expanded", "reply", "typed"]:
    try:
        a = Image.open(f"{d}real-state-{st}-{bd}.png").convert("RGB")
        b = Image.open(f"{d}ours-state-{st}-{bd}.png").convert("RGB")
    except FileNotFoundError:
        continue
    rows.append((a, b))
W = max(a.width + b.width + 12 for a, b in rows)
H = sum(max(a.height, b.height) + 8 for a, b in rows)
sheet = Image.new("RGB", (W, H), (255, 0, 255))
y = 0
for a, b in rows:
    sheet.paste(a, (0, y))
    sheet.paste(b, (a.width + 12, y))
    y += max(a.height, b.height) + 8
sheet.save("build/banner-lab/states-sheet.png")
print("wrote build/banner-lab/states-sheet.png")
