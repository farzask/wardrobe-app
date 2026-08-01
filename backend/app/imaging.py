"""Image preprocessing and thumbnail generation — TRD §4.

The guarantee this module exists to keep (PRD §4.2, TRD §4.8): **the original image is never
written anywhere.** Every function here takes and returns bytes or in-memory PIL images. Nothing
opens a file for writing, nothing uses a temp directory, and no image data is ever passed to a
logger. `tests/test_no_persistence.py` asserts this against the filesystem after a real call
rather than trusting the code to be read correctly.

Note the scope of that guarantee, per decision #5 in skills/README.md: it covers FitCheck's own
systems. The image is still sent to Google Gemini, and on the free tier Google may retain it.
"""

from __future__ import annotations

import io

import numpy as np
from PIL import Image, ImageOps

# Pillow will happily decompress a small file into gigabytes of RAM. This is a real DoS vector on
# an endpoint that accepts arbitrary uploads.
Image.MAX_IMAGE_PIXELS = 50_000_000


class ImageError(ValueError):
    pass


def load_image(data: bytes) -> Image.Image:
    """Decode upload bytes into an RGB image, dropping all metadata.

    EXIF is stripped rather than preserved: phone photos carry GPS coordinates, and there is no
    reason for a wardrobe app to hold the location where a shirt was photographed. `exif_transpose`
    is applied first so the orientation tag is honoured before it is discarded — skipping that step
    is why so many uploaded photos come out sideways.
    """
    try:
        image = Image.open(io.BytesIO(data))
        image = ImageOps.exif_transpose(image)
        image.load()
    except Exception as exc:  # Pillow raises a wide variety for malformed input
        raise ImageError(f"could not decode image: {exc}") from exc

    if image.mode not in ("RGB", "RGBA"):
        image = image.convert("RGBA" if "A" in image.mode else "RGB")
    return image


def downscale_for_inference(image: Image.Image, max_edge: int) -> Image.Image:
    """Shrink to the working resolution the vision model actually reads.

    Attribute reading gains nothing above ~1024px, and PRD §6 cares about perceived speed more than
    about exact accuracy. The client downscales too; this is the server-side floor for clients that
    don't.
    """
    if max(image.size) <= max_edge:
        return image
    scale = max_edge / max(image.size)
    new_size = (max(1, int(image.width * scale)), max(1, int(image.height * scale)))
    return image.resize(new_size, Image.Resampling.LANCZOS)


def crop_to_box(image: Image.Image, box: tuple[float, float, float, float]) -> Image.Image:
    """Crop to a normalised (x0, y0, x1, y1) bounding box, clamped to the image.

    Clamping is not defensive padding — a model returning a box that runs slightly outside the
    frame is normal, and an unclamped crop raises rather than degrading.
    """
    x0, y0, x1, y1 = box
    w, h = image.size
    left = max(0, min(w - 1, int(x0 * w)))
    top = max(0, min(h - 1, int(y0 * h)))
    right = max(left + 1, min(w, int(x1 * w)))
    bottom = max(top + 1, min(h, int(y1 * h)))
    return image.crop((left, top, right, bottom))


def garment_pixels(image: Image.Image, centre_fraction: float = 0.6) -> np.ndarray:
    """Return an (N, 3) uint8 array of pixels that are probably garment, not background.

    HONEST LIMITATION: this is not segmentation. TRD §12 names background removal as a real risk
    needing a dedicated preprocessing step, and this is not that step — it samples the central
    region of the crop and, if the image has an alpha channel, respects it.

    Central sampling works because the caller has already cropped to the garment's bounding box, so
    the middle of that crop is overwhelmingly garment. It will still be wrong for a garment held at
    arm's length against a busy background. Replacing this with real segmentation (rembg/U2-Net, or
    the model's own mask) is the highest-value accuracy improvement available to the colour
    pipeline, and it is not done here.
    """
    if image.mode == "RGBA":
        rgba = np.asarray(image, dtype=np.uint8)
        opaque = rgba[..., 3] > 200
        if opaque.any():
            return rgba[..., :3][opaque]
        image = image.convert("RGB")

    rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
    h, w = rgb.shape[:2]
    margin = (1.0 - centre_fraction) / 2.0
    y0, y1 = int(h * margin), max(int(h * (1 - margin)), int(h * margin) + 1)
    x0, x1 = int(w * margin), max(int(w * (1 - margin)), int(w * margin) + 1)
    return rgb[y0:y1, x0:x1].reshape(-1, 3)


def make_thumbnail(
    image: Image.Image,
    width: int,
    quality: int,
    target_bytes: int,
) -> bytes:
    """Encode a WebP thumbnail to TRD §4.4's spec: ~320px wide, quality 65–75, target ≤30 KB.

    Quality is stepped down only if the target is missed, and never below 50 — a garment thumbnail
    that has been crushed into artefacts is worse than one slightly over budget, because the user
    identifies items by them.
    """
    if image.mode == "RGBA":
        background = Image.new("RGB", image.size, (255, 255, 255))
        background.paste(image, mask=image.split()[3])
        image = background
    else:
        image = image.convert("RGB")

    if image.width > width:
        height = max(1, round(image.height * width / image.width))
        image = image.resize((width, height), Image.Resampling.LANCZOS)

    for q in (quality, quality - 10, quality - 20):
        if q < 50:
            break
        buffer = io.BytesIO()
        image.save(buffer, format="WEBP", quality=q, method=6)
        data = buffer.getvalue()
        if len(data) <= target_bytes:
            return data

    return data
