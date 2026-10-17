"""Export the approved Coco ERP artwork without redrawing it (Python + Pillow)."""
from pathlib import Path
from shutil import copyfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets" / "brand"
logo = Image.open(BRAND / "coco-erp-logo-approved-20261017.png").convert("RGB")
icon = Image.open(BRAND / "coco-erp-icon-approved-20261016.jpeg").convert("RGB")

# Trim only the white presentation margin; retain the approved blue relief.
mask = Image.new("L", logo.size)
mask.putdata([255 if max(p) - min(p) > 45 else 0 for p in logo.getdata()])
left, top, right, bottom = mask.getbbox()
cropped = logo.crop((max(0, left - 32), max(0, top - 24),
                     min(logo.width, right + 32), min(logo.height, bottom + 24)))
cropped.save(ROOT / "coco-erp-logo.png", optimize=True)
cropped.save(ROOT / "coco-gama-logo.jpg", quality=95, subsampling=0)
logo.save(ROOT / "coco-erp-logo-full.png", optimize=True)

# Keep the supplied white tile, shadows and padding. The C already fits the
# central safe area used by maskable icons; no additional drawing is applied.
for size in (180, 192, 512):
    image = icon.resize((size, size), Image.Resampling.LANCZOS)
    target = ROOT / f"coco-erp-icon-{size}.png"
    image.save(target, optimize=True)
    for name in (f"coco-gama-icon-{size}.png", f"icon-{size}.png"):
        copyfile(target, ROOT / name)
    if size != 180:
        for prefix in ("coco-erp", "coco-gama"):
            copyfile(target, ROOT / f"{prefix}-icon-maskable-{size}.png")

icon.resize((1024, 1024), Image.Resampling.LANCZOS).save(
    BRAND / "icon-arrondi-1024.png", optimize=True)
icon.save(ROOT / "favicon.ico", sizes=[(n, n) for n in (16, 32, 48, 64, 128, 256)])
print(f"Main logo: {cropped.width}x{cropped.height}; app icons: 180, 192, 512; favicon: 16–256.")
