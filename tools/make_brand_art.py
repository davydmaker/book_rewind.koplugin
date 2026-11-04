"""Draws the icon, the README banner and the GitHub social preview from the rendered cards.

Usage: KOREADER_DIR=<desktop KOReader> python3 -I tools/make_brand_art.py
Run tools/koreader/render_readme_screens.lua first. Needs Pillow, and the Noto fonts that ship with KOReader.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BLACK, WHITE = 0, 255
ICON_SIZE = 1024
SUPERSAMPLE = 3
TAGLINE = "Your year of reading, rewound."
DETAILS = ["A yearly reading recap for KOReader,", "in illustrated cards made for e-ink.", "Offline, on your device."]


def draw_icon():
    k = SUPERSAMPLE
    size = ICON_SIZE
    image = Image.new("L", (size * k, size * k), BLACK)
    d = ImageDraw.Draw(image)

    def scaled(points):
        return [(x * k, y * k) for x, y in points]

    d.polygon(scaled([(262, 0), (762, 0), (762, 930), (512, 730), (262, 930)]), fill=WHITE)
    width, gap, height, center_y = 190, 18, 330, 350
    left = 512 - (2 * width + gap) / 2
    for start in (left, left + width + gap):
        d.polygon(scaled([(start + width, center_y - height / 2), (start + width, center_y + height / 2), (start, center_y)]), fill=BLACK)
    final = image.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=190 * 4, fill=255)
    icon = Image.new("LA", (size, size))
    icon.paste(final)
    icon.putalpha(mask.resize((size, size), Image.LANCZOS))
    return icon


def halftone(image, cx, cy, radius, spacing):
    d = ImageDraw.Draw(image)
    row, y = 0, cy - radius
    while y <= cy + radius:
        x = cx - radius + (spacing / 2 if row % 2 else 0)
        while x <= cx + radius:
            distance = math.hypot(x - cx, y - cy) / radius
            if distance <= 1:
                dot = spacing * 0.34 * (1 - distance * 0.72)
                d.ellipse([x - dot, y - dot, x + dot, y + dot], fill=88)
            x += spacing
        y += spacing * 0.87
        row += 1


def place_card(image, name, center, card_height, angle):
    card = Image.open(os.path.join(ROOT, "docs", "screenshots", name + ".png")).convert("L")
    card = card.resize((round(card_height * card.width / card.height), card_height), Image.LANCZOS)
    border = max(4, card_height // 90)
    framed = Image.new("LA", (card.width + 2 * border, card.height + 2 * border), (WHITE, 255))
    framed.paste(card, (border, border))
    rotated = framed.rotate(angle, resample=Image.BICUBIC, expand=True)
    image.paste(rotated.getchannel("L"), (center[0] - rotated.width // 2, center[1] - rotated.height // 2), rotated.getchannel("A"))


def draw_header(width, height, fonts, icon, layout):
    k = 2
    image = Image.new("L", (width * k, height * k), BLACK)
    middle, card_height, offset, text = layout["middle"], layout["card_height"], layout["offset"], layout["text"]
    halftone(image, middle * k, height // 2 * k, round(layout["halftone"] * k), 26 * k)
    drop = round(card_height * 0.05)
    place_card(image, "hours", ((middle - offset) * k, (height // 2 + drop) * k), card_height * k, 8)
    place_card(image, "profiles/marathoner", ((middle + offset) * k, (height // 2 + drop) * k), card_height * k, -8)
    place_card(image, "cover", (middle * k, height // 2 * k), card_height * k, 0)

    margin = 58
    icon_size = round(96 * text)
    title_size = round(72 * text)
    tagline_size = round(27 * text)
    details_size = round(19 * text)
    details = layout.get("details")
    block = icon_size + title_size + tagline_size + round(44 * text)
    if details:
        block += round(details_size * 1.45 * len(details)) + round(22 * text)
    y = (height - block) // 2
    small = icon.resize((icon_size * k, icon_size * k), Image.LANCZOS)
    # The ribbon starts inside the icon's black square, which disappears on this background.
    ribbon_inset = round(icon_size * 262 / ICON_SIZE)
    image.paste(small.getchannel("L"), ((margin - ribbon_inset) * k, y * k), small.getchannel("A"))
    y += icon_size + round(6 * text)
    d = ImageDraw.Draw(image)
    d.text((margin * k, y * k), "Book Rewind", font=ImageFont.truetype(fonts["bold"], title_size * k), fill=WHITE)
    y += title_size + round(26 * text)
    d.text((margin * k, y * k), TAGLINE, font=ImageFont.truetype(fonts["italic"], tagline_size * k), fill=WHITE)
    y += tagline_size + round(30 * text)
    if details:
        font = ImageFont.truetype(fonts["regular"], details_size * k)
        for line in details:
            d.text((margin * k, y * k), line, font=font, fill=205)
            y += round(details_size * 1.45)
    return image.resize((width, height), Image.LANCZOS)


def main():
    koreader = os.environ.get("KOREADER_DIR")
    if not koreader:
        sys.exit("Set KOREADER_DIR to the KOReader folder, which has the Noto fonts.")
    noto = os.path.join(koreader, "fonts", "noto")
    fonts = {
        "bold": os.path.join(noto, "NotoSerif-Bold.ttf"),
        "italic": os.path.join(noto, "NotoSerif-Italic.ttf"),
        "regular": os.path.join(noto, "NotoSerif-Regular.ttf"),
    }
    brand = os.path.join(ROOT, "docs", "brand")
    os.makedirs(brand, exist_ok=True)
    icon = draw_icon()
    icon.save(os.path.join(brand, "icon.png"), optimize=True)
    draw_header(1280, 400, fonts, icon, {"middle": 945, "card_height": 330, "offset": 170, "text": 1, "halftone": 296}).save(os.path.join(brand, "banner.png"), optimize=True)
    draw_header(1280, 640, fonts, icon, {"middle": 950, "card_height": 440, "offset": 118, "text": 1.2, "halftone": 380, "details": DETAILS}).save(os.path.join(ROOT, "docs", "social-preview.png"), optimize=True)
    print("Images generated in docs/brand and docs/social-preview.png")


main()
