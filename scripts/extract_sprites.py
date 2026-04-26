#!/usr/bin/env python3
"""
extract_sprites.py — extract individual sprites from reference-sheet images.

Each sprite is saved as a separate PNG with a transparent background.
The dark sheet background is detected automatically by sampling image corners.

Usage:
    python tools/extract_sprites.py [options] <image1> [image2 ...]

Options:
    --out-dir DIR      Root output directory  (default: assets/sprites)
    --tolerance INT    Background color tolerance 0-255  (default: 35)
    --merge INT        Dilation px to merge nearby regions into one sprite (default: 8)
    --min-area INT     Minimum sprite area in px² to keep (default: 500)
    --preview          Save a _preview.jpg showing detected bounding boxes

Examples:
    # Extract with defaults, enable debug preview
    python tools/extract_sprites.py --preview sheet1.png sheet2.png

    # Looser merging (groups animation frames together)
    python tools/extract_sprites.py --merge 20 sheet1.png

    # Stricter background removal
    python tools/extract_sprites.py --tolerance 20 sheet1.png
"""

import argparse
import os
import sys
from pathlib import Path

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def sample_bg_color(img: np.ndarray, sample: int = 40) -> np.ndarray:
    """Estimate background colour by taking the median of all four corners."""
    h, w = img.shape[:2]
    corners = [
        img[:sample, :sample],
        img[:sample, w - sample:],
        img[h - sample:, :sample],
        img[h - sample:, w - sample:],
    ]
    pixels = np.concatenate([c.reshape(-1, 3) for c in corners], axis=0)
    return np.median(pixels, axis=0)


def make_fg_mask(img: np.ndarray, bg: np.ndarray, tol: int) -> np.ndarray:
    """Return a binary mask: 255 = foreground, 0 = background."""
    diff = np.abs(img.astype(np.float32) - bg.astype(np.float32))
    dist = np.max(diff, axis=2)
    _, mask = cv2.threshold(dist.astype(np.uint8), tol, 255, cv2.THRESH_BINARY)
    return mask


def remove_bg(crop: np.ndarray, bg: np.ndarray, tol: int) -> np.ndarray:
    """Return the crop as BGRA with background pixels set to alpha=0."""
    mask = make_fg_mask(crop, bg, tol)
    # Soften mask edges slightly, then re-binarize
    blurred = cv2.GaussianBlur(mask, (3, 3), 0)
    _, alpha = cv2.threshold(blurred, 128, 255, cv2.THRESH_BINARY)
    out = cv2.cvtColor(crop, cv2.COLOR_BGR2BGRA)
    out[:, :, 3] = alpha
    return out


def tight_bounds(sprite_bgra: np.ndarray):
    """Return (x1, y1, x2, y2) of the non-transparent region."""
    alpha = sprite_bgra[:, :, 3]
    cols = np.any(alpha > 0, axis=0)
    rows = np.any(alpha > 0, axis=1)
    if not cols.any():
        return None
    x1, x2 = np.where(cols)[0][[0, -1]]
    y1, y2 = np.where(rows)[0][[0, -1]]
    return int(x1), int(y1), int(x2) + 1, int(y2) + 1


# ---------------------------------------------------------------------------
# Core extraction
# ---------------------------------------------------------------------------

def extract(image_path: str, out_dir: str, tol: int, merge: int,
            min_area: int, preview: bool) -> int:
    img = cv2.imread(image_path)
    if img is None:
        print(f"  ERROR: cannot read '{image_path}'", file=sys.stderr)
        return 0

    h, w = img.shape[:2]
    bg = sample_bg_color(img)
    print(f"  Background colour: B={bg[0]:.0f}  G={bg[1]:.0f}  R={bg[2]:.0f}")

    # --- Foreground mask -------------------------------------------------
    fg = make_fg_mask(img, bg, tol)

    # Dilate to merge nearby pixels belonging to the same sprite
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (merge, merge))
    merged = cv2.dilate(fg, kernel)

    # --- Connected components on the merged mask -------------------------
    n_labels, labels, stats, _ = cv2.connectedComponentsWithStats(
        merged, connectivity=8
    )

    os.makedirs(out_dir, exist_ok=True)
    pad = 5
    saved = 0
    boxes = []

    for i in range(1, n_labels):          # label 0 = background
        x, y, cw, ch, area = stats[i]
        if area < min_area:
            continue

        # Expand bounding box
        x1 = max(0, x - pad)
        y1 = max(0, y - pad)
        x2 = min(w, x + cw + pad)
        y2 = min(h, y + ch + pad)

        crop = img[y1:y2, x1:x2]
        sprite = remove_bg(crop, bg, tol)

        # Trim to tight transparent bounds so files aren't padded with empty alpha
        tb = tight_bounds(sprite)
        if tb is not None:
            tx1, ty1, tx2, ty2 = tb
            sprite = sprite[ty1:ty2, tx1:tx2]

        if sprite.size == 0:
            continue

        out_path = os.path.join(out_dir, f"sprite_{saved:03d}.png")
        cv2.imwrite(out_path, sprite)
        boxes.append((x1, y1, x2, y2))
        saved += 1

    # --- Optional debug preview ------------------------------------------
    if preview and boxes:
        dbg = img.copy()
        for idx, (bx1, by1, bx2, by2) in enumerate(boxes):
            cv2.rectangle(dbg, (bx1, by1), (bx2, by2), (0, 255, 0), 2)
            cv2.putText(dbg, str(idx), (bx1 + 2, by1 + 14),
                        cv2.FONT_HERSHEY_PLAIN, 0.9, (0, 255, 255), 1)
        preview_path = os.path.join(out_dir, "_preview.jpg")
        cv2.imwrite(preview_path, dbg)
        print(f"  Preview → {preview_path}")

    print(f"  Extracted {saved} sprites → {out_dir}/")
    return saved


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("images", nargs="+", help="Input sprite-sheet PNG/JPG files")
    parser.add_argument(
        "--out-dir", default="assets/sprites",
        help="Root output directory (default: assets/sprites)",
    )
    parser.add_argument(
        "--tolerance", type=int, default=35,
        help="Background colour tolerance 0-255 (default: 35)",
    )
    parser.add_argument(
        "--merge", type=int, default=8,
        help="Dilation size in px to group nearby regions (default: 8)",
    )
    parser.add_argument(
        "--min-area", type=int, default=500,
        help="Minimum region area in px² to keep (default: 500)",
    )
    parser.add_argument(
        "--preview", action="store_true",
        help="Save a _preview.jpg with bounding boxes drawn",
    )
    args = parser.parse_args()

    total = 0
    for path in args.images:
        name = Path(path).stem
        # Sanitize: replace spaces with underscores
        name = name.replace(" ", "_")
        out = os.path.join(args.out_dir, name)
        print(f"\nProcessing: {path}")
        total += extract(path, out, args.tolerance, args.merge, args.min_area, args.preview)

    print(f"\nDone — {total} sprites extracted in total.")


if __name__ == "__main__":
    main()
