"""
File: render_teendrive_ad.py
Created: 2026-05-12
Creator: Vladimyr Merci

Purpose:
Renders a short TeenDrive promotional video ad as an animated GIF source that can be converted to video.

Developer Notes:
This script avoids private user data and uses stylized product scenes instead of real teen route screenshots.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
OUT_GIF = ROOT / "teendrive_ad_source.gif"
FRAMES_DIR = ROOT / "frames"
WIDTH = 1080
HEIGHT = 1920
FPS = 8
DURATION_SECONDS = 20
FRAME_COUNT = FPS * DURATION_SECONDS


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFCompact.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size, index=1 if bold and path.endswith(".ttc") else 0)
        except Exception:
            continue
    return ImageFont.load_default()


FONT_TITLE = font(88, bold=True)
FONT_HEAD = font(62, bold=True)
FONT_BODY = font(42)
FONT_SMALL = font(30)
FONT_BUTTON = font(44, bold=True)
FONT_NUMBER = font(76, bold=True)


def ease(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return 1 - pow(1 - value, 3)


def scene_progress(t: float, start: float, end: float) -> float:
    return ease((t - start) / (end - start))


def rounded(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], radius: int, fill, outline=None, width: int = 1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text_center(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, fnt, fill):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    draw.text((xy[0] - (bbox[2] - bbox[0]) / 2, xy[1] - (bbox[3] - bbox[1]) / 2), text, font=fnt, fill=fill)


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        test = word if not current else f"{current} {word}"
        if draw.textlength(test, font=fnt) <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_wrapped(draw: ImageDraw.ImageDraw, text: str, x: int, y: int, fnt, fill, max_width: int, line_gap: int = 10):
    for line in wrap(draw, text, fnt, max_width):
        draw.text((x, y), line, font=fnt, fill=fill)
        y += fnt.size + line_gap
    return y


def background(t: float) -> Image.Image:
    x = np.linspace(0, 1, WIDTH, dtype=np.float32)[None, :]
    y = np.linspace(0, 1, HEIGHT, dtype=np.float32)[:, None]
    glow = 0.22 + 0.14 * np.sin(t * 0.45 + x * 4.2) + 0.10 * np.cos(y * 5.0 - t * 0.25)
    red = 4 + 18 * (1 - y)
    green = 22 + 42 * (1 - y) + 42 * np.maximum(glow, 0)
    blue = 22 + 35 * x + 16 * glow
    arr = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)
    arr[..., 0] = np.clip(red, 0, 255).astype(np.uint8)
    arr[..., 1] = np.clip(green, 0, 112).astype(np.uint8)
    arr[..., 2] = np.clip(blue, 0, 92).astype(np.uint8)
    return Image.fromarray(arr, "RGB").filter(ImageFilter.GaussianBlur(1.2))


def glass_card(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], radius: int = 38):
    rounded(draw, box, radius, (255, 255, 255, 42), (255, 255, 255, 82), 2)


def draw_phone_scene(draw: ImageDraw.ImageDraw, t: float, alpha: float):
    ox = int(130 + 34 * math.sin(t * 0.8))
    oy = 250
    phone = (ox, oy, ox + 820, oy + 1180)
    rounded(draw, phone, 82, (7, 17, 16, int(230 * alpha)), (255, 255, 255, int(90 * alpha)), 3)
    draw.text((ox + 70, oy + 72), "Drive", font=FONT_TITLE, fill=(255, 255, 255, int(245 * alpha)))
    draw.text((ox + 70, oy + 170), "Ready to drive", font=FONT_SMALL, fill=(188, 198, 194, int(230 * alpha)))

    map_box = (ox + 56, oy + 240, ox + 764, oy + 900)
    rounded(draw, map_box, 28, (28, 78, 68, int(230 * alpha)), (255, 255, 255, int(80 * alpha)), 2)
    for i in range(7):
        yy = map_box[1] + 70 + i * 78
        draw.line((map_box[0] + 20, yy, map_box[2] - 20, yy + 30 * math.sin(i)), fill=(105, 134, 147, int(115 * alpha)), width=6)
    for i in range(6):
        xx = map_box[0] + 60 + i * 105
        draw.line((xx, map_box[1] + 30, xx + 35 * math.sin(i), map_box[3] - 40), fill=(30, 92, 84, int(150 * alpha)), width=18)

    route = [(map_box[0] + 140, map_box[3] - 120), (map_box[0] + 245, map_box[3] - 270), (map_box[0] + 390, map_box[3] - 330), (map_box[0] + 520, map_box[3] - 500)]
    draw.line(route, fill=(70, 230, 112, int(230 * alpha)), width=10)
    for p, color in zip(route, [(70, 230, 112), (255, 157, 74), (255, 91, 91), (70, 230, 112)]):
        draw.ellipse((p[0] - 24, p[1] - 24, p[0] + 24, p[1] + 24), fill=(*color, int(230 * alpha)), outline=(255, 255, 255, int(220 * alpha)), width=5)

    stats = (ox + 56, oy + 930, ox + 764, oy + 1060)
    glass_card(draw, stats, 26)
    draw.text((stats[0] + 42, stats[1] + 30), "Safety Score", font=FONT_SMALL, fill=(230, 236, 233, int(240 * alpha)))
    draw.text((stats[0] + 42, stats[1] + 66), "92 Good", font=FONT_BODY, fill=(70, 230, 112, int(245 * alpha)))
    draw.text((stats[0] + 380, stats[1] + 30), "Alerts", font=FONT_SMALL, fill=(230, 236, 233, int(240 * alpha)))
    draw.text((stats[0] + 380, stats[1] + 66), "On map", font=FONT_BODY, fill=(255, 255, 255, int(245 * alpha)))

    button = (ox + 56, oy + 1090, ox + 764, oy + 1190)
    rounded(draw, button, 50, (49, 210, 91, int(222 * alpha)), (140, 255, 171, int(170 * alpha)), 2)
    text_center(draw, ((button[0] + button[2]) // 2, (button[1] + button[3]) // 2), "Start Drive", FONT_BUTTON, (255, 255, 255, int(245 * alpha)))


def scene_intro(draw: ImageDraw.ImageDraw, t: float):
    p = scene_progress(t, 0, 4)
    y = int(305 - 60 * p)
    draw.text((76, y), "Teen Drive", font=FONT_TITLE, fill=(255, 255, 255, 255))
    draw_wrapped(draw, "A calmer way for families to review teen driving.", 80, y + 120, FONT_BODY, (220, 231, 226, 235), 850)
    rounded(draw, (80, y + 285, 520, y + 365), 40, (47, 210, 91, 215), (145, 255, 174, 160), 2)
    text_center(draw, (300, y + 325), "Built for awareness", FONT_SMALL, (255, 255, 255, 245))
    draw_phone_scene(draw, t, 0.78)


def scene_alerts(draw: ImageDraw.ImageDraw, t: float):
    draw.text((76, 200), "See what happened", font=FONT_HEAD, fill=(255, 255, 255, 255))
    draw_wrapped(draw, "Speeding, harsh stops, cornering, night driving, and phone unlocks appear where they occurred.", 80, 290, FONT_BODY, (220, 231, 226, 235), 900)
    card = (80, 600, 1000, 1360)
    glass_card(draw, card, 42)
    for i, label in enumerate(["Speed", "Stop", "Phone", "Night"]):
        x = 160 + i * 210
        y = 760 + int(28 * math.sin(t * 2 + i))
        color = [(255, 160, 74), (255, 88, 88), (82, 170, 255), (170, 140, 255)][i]
        draw.ellipse((x - 34, y - 34, x + 34, y + 34), fill=(*color, 235), outline=(255, 255, 255, 220), width=5)
        text_center(draw, (x, y + 72), label, FONT_SMALL, (255, 255, 255, 230))
    draw.line((180, 1180, 360, 980, 565, 1080, 810, 850), fill=(71, 230, 112, 210), width=12)
    draw.text((130, 1260), "Safety alerts on the map", font=FONT_BODY, fill=(255, 255, 255, 240))


def scene_parent(draw: ImageDraw.ImageDraw, t: float):
    draw.text((76, 205), "Parents stay connected", font=FONT_HEAD, fill=(255, 255, 255, 255))
    draw_wrapped(draw, "Private QR pairing links a teen and parent account without making reports public.", 80, 290, FONT_BODY, (220, 231, 226, 235), 900)
    glass_card(draw, (90, 570, 990, 1280), 42)
    draw.text((150, 650), "Parent Dashboard", font=FONT_BODY, fill=(255, 255, 255, 245))
    for i, (label, value) in enumerate([("Live Drive", "Active"), ("Recent Score", "92"), ("Distance", "8.4 mi")]):
        y = 760 + i * 145
        rounded(draw, (150, y, 930, y + 105), 28, (255, 255, 255, 38), (255, 255, 255, 70), 2)
        draw.text((185, y + 28), label, font=FONT_SMALL, fill=(210, 220, 216, 230))
        draw.text((680, y + 22), value, font=FONT_BODY, fill=(70, 230, 112, 245))
    qr = (405, 1120, 675, 1390)
    rounded(draw, qr, 24, (255, 255, 255, 245))
    for row in range(7):
        for col in range(7):
            if (row * col + row + col) % 3 != 0:
                draw.rectangle((qr[0] + 28 + col * 31, qr[1] + 28 + row * 31, qr[0] + 50 + col * 31, qr[1] + 50 + row * 31), fill=(10, 30, 24, 255))


def scene_privacy(draw: ImageDraw.ImageDraw, t: float):
    draw.text((76, 235), "Private by design", font=FONT_HEAD, fill=(255, 255, 255, 255))
    draw_wrapped(draw, "Family reports stay in paired accounts. Delete account and data from Profile.", 80, 320, FONT_BODY, (220, 231, 226, 235), 900)
    glass_card(draw, (90, 600, 990, 1250), 42)
    for i, (label, icon) in enumerate([("Privacy & Safety", "LOCK"), ("Account deletion", "DATA"), ("Safety disclaimer", "CARE")]):
        y = 700 + i * 160
        rounded(draw, (150, y, 930, y + 105), 28, (40, 120, 67, 145), (102, 255, 146, 95), 2)
        draw.text((190, y + 33), icon, font=FONT_SMALL, fill=(70, 230, 112, 245))
        draw.text((370, y + 27), label, font=FONT_BODY, fill=(255, 255, 255, 245))
    draw.text((96, 1430), "Teen Drive", font=FONT_TITLE, fill=(255, 255, 255, 255))
    draw_wrapped(draw, "Drive awareness for modern families.", 100, 1540, FONT_BODY, (220, 231, 226, 240), 840)


def render_frame(i: int) -> Image.Image:
    t = i / FPS
    img = background(t)
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")

    if t < 6:
        scene_intro(draw, t)
    elif t < 12:
        scene_alerts(draw, t)
    elif t < 18:
        scene_parent(draw, t)
    else:
        scene_privacy(draw, t)

    # Soft vignette to keep focus in the center.
    vignette = Image.new("L", (WIDTH, HEIGHT), 0)
    vd = ImageDraw.Draw(vignette)
    vd.ellipse((-260, -120, WIDTH + 260, HEIGHT + 160), fill=190)
    vignette = vignette.filter(ImageFilter.GaussianBlur(120))
    shade = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 80))
    img = Image.composite(Image.alpha_composite(img.convert("RGBA"), overlay), shade, vignette).convert("RGB")
    return img


def main():
    FRAMES_DIR.mkdir(parents=True, exist_ok=True)
    for old_frame in FRAMES_DIR.glob("frame_*.png"):
        old_frame.unlink()

    frames = []
    for i in range(FRAME_COUNT):
        frame = render_frame(i)
        frame.save(FRAMES_DIR / f"frame_{i:04d}.png")
        frames.append(frame)

    frames[0].save(
        OUT_GIF,
        save_all=True,
        append_images=frames[1:],
        duration=int(1000 / FPS),
        loop=0,
        optimize=False,
    )
    print(OUT_GIF)
    print(FRAMES_DIR)


if __name__ == "__main__":
    main()
