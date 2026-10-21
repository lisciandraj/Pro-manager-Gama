"""Export the approved Coco ERP artwork without redrawing it (Python + Pillow)."""
from pathlib import Path
from shutil import copyfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets" / "brand"
logo = Image.open(BRAND / "coco-erp-logo-approved-20261020.png").convert("RGB")
icon = Image.open(BRAND / "coco-erp-icon-co-approved-20261018.png").convert("RGB")

# Trim only the white presentation margin; retain the approved satin-blue artwork.
mask = Image.new("L", logo.size)
mask.putdata([255 if max(p) - min(p) > 45 else 0 for p in logo.getdata()])
left, top, right, bottom = mask.getbbox()
cropped = logo.crop((max(0, left - 32), max(0, top - 24),
                     min(logo.width, right + 32), min(logo.height, bottom + 24)))
# A 1200px wordmark covers the largest UI slot at 3x without shipping the full source.
cropped.thumbnail((1200, 1200), Image.Resampling.LANCZOS)
cropped.save(ROOT / "coco-erp-logo.png", optimize=True)
cropped.save(ROOT / "coco-gama-logo.jpg", quality=95, subsampling=0)
logo.save(ROOT / "coco-erp-logo-full.png", optimize=True)

# Keep the approved CO unchanged and add white safety padding for app masks.
# The source remains intact; only the export canvas grows by 3% per edge.
padding = round(icon.width * 0.03)
padded_icon = Image.new("RGB", (icon.width + 2 * padding, icon.height + 2 * padding), "white")
padded_icon.paste(icon, (padding, padding))
icon = padded_icon
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
