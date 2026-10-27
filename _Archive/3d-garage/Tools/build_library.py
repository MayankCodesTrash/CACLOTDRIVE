import json, os, subprocess, colorsys, shutil, sys
from collections import Counter
from PIL import Image

SRC = "kenney/src/Models/OBJ format"
OUT = "library"
os.makedirs(OUT, exist_ok=True)
img = Image.open(f"{SRC}/Textures/colormap.png").convert("RGB")
shutil.copy(f"{SRC}/Textures/colormap.png", f"{OUT}/lot-palette.png")
BLOCK_W, BLOCK_H = 64, 128   # each swatch is a 64x128 block (two shaded columns)

# (file, display name, body style)
MODELS = [
    ("sedan", "Sedan", "sedan"),
    ("sedan-sports", "Sports sedan", "coupe"),
    ("hatchback-sports", "Hatchback", "hatchback"),
    ("suv", "SUV", "suv"),
    ("suv-luxury", "Luxury SUV", "suv"),
    ("truck", "Pickup truck", "pickup"),
    ("taxi", "Taxi", "sedan"),
    ("van", "Van", "van"),
]

def paint_block(name):
    vts, counts, cur = [], Counter(), None
    for line in open(f"{SRC}/{name}.obj"):
        p = line.split()
        if not p: continue
        if p[0] == "vt": vts.append((float(p[1]), float(p[2])))
        elif p[0] in ("g", "o"): cur = p[1]
        elif p[0] == "f" and cur == "body":
            for v in p[1:]:
                u, vv = vts[int(v.split("/")[1]) - 1]
                x = min(img.width - 1, int(u * img.width)); y = min(img.height - 1, int((1 - vv) * img.height))
                counts[(x // BLOCK_W, y // BLOCK_H)] += 1
    best = None
    for (bx, by), n in counts.most_common():
        region = img.crop((bx * BLOCK_W, by * BLOCK_H, (bx + 1) * BLOCK_W, (by + 1) * BLOCK_H))
        px = list(region.getdata()); r = sum(p[0] for p in px) / len(px); g = sum(p[1] for p in px) / len(px); b = sum(p[2] for p in px) / len(px)
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s > 0.35 and v > 0.3:
            best = (bx, by, n, (round(r), round(g), round(b))); break
    return best, counts.most_common(4)

entries = []
for file, title, body in MODELS:
    out = f"{OUT}/kenney-{file}.usdz"
    subprocess.run(["tools/convert", f"{SRC}/{file}.obj", out], check=True, cwd=".", capture_output=True)
    best, top = paint_block(file)
    print(file, "paint block:", best, "| top blocks:", top)
    regions = [[best[0] * BLOCK_W, best[1] * BLOCK_H, BLOCK_W, BLOCK_H]] if best else []
    entries.append({
        "id": f"kenney-{file}", "name": title, "bodyStyle": body, "make": None, "model": None,
        "file": f"kenney-{file}.usdz", "texture": "lot-palette.png", "paintRegions": regions,
        "sizeBytes": os.path.getsize(out), "license": "CC0 1.0", "author": "Kenney (kenney.nl)",
        "sourceURL": "https://kenney.nl/assets/car-kit", "attributionRequired": False,
    })
json.dump({"version": 1, "name": "LOT starter library (Kenney Car Kit, CC0)", "models": entries}, open(f"{OUT}/lot-library-manifest.json", "w"), indent=2)
print("total KB:", sum(e["sizeBytes"] for e in entries) // 1024)
