#!/usr/bin/env python3
"""Builds the README screenshots from raw captures (see scripts/make-screenshots.sh).

Usage: scripts/compose-screenshots.py RAW_DIR OUT_DIR
RAW_DIR holds camera.png, simulator.png, settings.png (SimCamLite window) and iphone.png (simctl screenshot).
Needs Pillow.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
FRAME = ROOT / "assets/frames/iphone.png"
PAD, GAP = 60, 60


def framed_iphone(screen: Image.Image) -> Image.Image:
    """Puts a simulator screenshot inside the transparent screen of the iPhone frame."""
    frame = Image.open(FRAME).convert("RGBA")
    # The screen is the transparent area connected to the center, separated from the outside by the bezel.
    mask = frame.getchannel("A").point(lambda a: 0 if a < 128 else 255)
    ImageDraw.floodfill(mask, (frame.width // 2, frame.height // 2), 128)
    mask = mask.point(lambda v: 255 if v == 128 else 0)
    left, top, right, bottom = mask.getbbox()
    screen = screen.convert("RGBA").resize((right - left, bottom - top), Image.LANCZOS)
    phone = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    phone.paste(screen, (left, top), mask.crop((left, top, right, bottom)))
    phone.alpha_composite(frame)
    return phone


def row(images: list[Image.Image]) -> Image.Image:
    width = sum(i.width for i in images) + GAP * (len(images) - 1) + PAD * 2
    height = max(i.height for i in images) + PAD * 2
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    x = PAD
    for image in images:
        canvas.alpha_composite(image, (x, (height - image.height) // 2))
        x += image.width + GAP
    return canvas


def main() -> None:
    raw, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    load = lambda name: Image.open(raw / name).convert("RGBA")
    camera = load("camera.png")
    phone = framed_iphone(load("iphone.png"))
    phone = phone.resize((round(phone.width * camera.height / phone.height), camera.height), Image.LANCZOS)
    row([camera, phone]).save(out / "camera-and-simulator.png", optimize=True)
    row([load("simulator.png"), load("settings.png")]).save(out / "simulator-and-settings.png", optimize=True)


if __name__ == "__main__":
    main()
