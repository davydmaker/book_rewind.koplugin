"""Draws the fixed art of the cards, without any text so it works in every language.

Usage: python3 -I tools/make_card_art.py   writes assets/cards/600 and assets/cards/1200
"""
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
W, H = 600, 800
BLACK, DARK, MID, LIGHT, PALE, WHITE = 0, 68, 136, 187, 221, 255
SUPERSAMPLE = 3


class Art:
    def __init__(self, scale, background=WHITE):
        self.k = scale * SUPERSAMPLE
        self.scale = scale
        self.image = Image.new("L", (W * self.k, H * self.k), background)
        self.d = ImageDraw.Draw(self.image)

    def s(self, *values):
        return [v * self.k for v in values]

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=0):
        self.d.rectangle(self.s(x0, y0, x1, y1), fill=fill, outline=outline, width=int(width * self.k))

    def circle(self, cx, cy, r, fill=None, outline=None, width=0):
        self.d.ellipse(self.s(cx - r, cy - r, cx + r, cy + r), fill=fill, outline=outline, width=int(width * self.k))

    def poly(self, points, fill=None, outline=None, width=0):
        scaled = [(x * self.k, y * self.k) for x, y in points]
        self.d.polygon(scaled, fill=fill)
        if outline is not None:
            self.d.line(scaled + [scaled[0]], fill=outline, width=int(width * self.k), joint="curve")

    def line(self, points, fill=BLACK, width=2):
        self.d.line([(x * self.k, y * self.k) for x, y in points], fill=fill, width=int(width * self.k), joint="curve")

    def pattern(self, box, kind, ink=BLACK, spacing=7, size=None, mask=None):
        x0, y0, x1, y1 = box
        layer = Image.new("L", self.image.size, 0)
        ld = ImageDraw.Draw(layer)
        k = self.k
        if kind == "dots":
            r = (size or spacing * 0.28) * k
            row, y = 0, y0
            while y <= y1:
                x = x0 + (spacing / 2 if row % 2 else 0)
                while x <= x1:
                    ld.ellipse([x * k - r, y * k - r, x * k + r, y * k + r], fill=255)
                    x += spacing
                y += spacing * 0.87
                row += 1
        elif kind == "hatch":
            for offset in range(int(x0 - (y1 - y0)), int(x1), spacing):
                ld.line([(offset * k, y1 * k), ((offset + y1 - y0) * k, y0 * k)], fill=255, width=int((size or 1.4) * k))
        clip = Image.new("L", self.image.size, 0)
        cd = ImageDraw.Draw(clip)
        if mask:
            mask(cd)
        else:
            cd.rectangle(self.s(x0, y0, x1, y1), fill=255)
        self.image.paste(ink, mask=Image.composite(layer, Image.new("L", layer.size, 0), clip))

    def save(self, name):
        final = self.image.resize((W * self.scale, H * self.scale), Image.LANCZOS)
        final = final.point(lambda v: round(v / 17) * 17)
        directory = os.path.join(ROOT, "assets", "cards", str(W * self.scale))
        os.makedirs(directory, exist_ok=True)
        final.save(os.path.join(directory, name + ".png"), optimize=True)


def spine(a, x, base, w, h, tone):
    if tone in ("dots", "hatch"):
        a.rect(x, base - h, x + w, base, fill=WHITE, outline=BLACK, width=2)
        a.pattern((x + 2, base - h + 2, x + w - 2, base - 2), tone, spacing=6)
    else:
        a.rect(x, base - h, x + w, base, fill=tone, outline=BLACK, width=2)
    if w >= 16:
        ink = WHITE if tone in (BLACK, DARK) else BLACK
        a.rect(x + 3, base - h + 12, x + w - 3, base - h + 15, fill=ink)
        a.rect(x + 3, base - h + 20, x + w - 3, base - h + 22, fill=ink)


def cover(scale):
    a = Art(scale)
    a.pattern((220, 50, 620, 450), "dots", spacing=9, size=3.0, mask=lambda d: d.ellipse(a.s(230, 60, 610, 440), fill=255))
    random.seed(4)
    x, base = -8, 762
    tones = [BLACK, "dots", WHITE, DARK, "hatch", MID, BLACK, WHITE, "dots", DARK, "hatch", BLACK, MID, WHITE, "dots", BLACK]
    i = 0
    while x < W:
        w = random.randint(26, 54)
        spine(a, x, base, w, random.randint(110, 170), tones[i % len(tones)])
        x += w
        i += 1
    a.rect(0, base, W, base + 4, fill=BLACK)
    a.save("cover")


def time_art(scale):
    a = Art(scale, BLACK)
    cx, cy, h = 300, 240, 240
    w = h * 0.34
    a.rect(cx - w - 8, cy - h / 2 - 8, cx + w + 8, cy - h / 2, fill=WHITE)
    a.rect(cx - w - 8, cy + h / 2, cx + w + 8, cy + h / 2 + 8, fill=WHITE)
    outline = [(cx - w, cy - h / 2), (cx + w, cy - h / 2), (cx + 7, cy), (cx + w, cy + h / 2), (cx - w, cy + h / 2), (cx - 7, cy)]
    a.line(outline + [outline[0]], fill=WHITE, width=4)
    a.pattern((cx - w, cy + h * 0.12, cx + w, cy + h / 2), "dots", ink=WHITE, spacing=6, size=1.9, mask=lambda d: d.polygon(a.s(cx, cy + h * 0.12, cx + w - 5, cy + h / 2 - 2, cx - w + 5, cy + h / 2 - 2), fill=255))
    a.pattern((cx - w, cy - h / 2, cx + w, cy - h * 0.1), "dots", ink=WHITE, spacing=6, size=1.9, mask=lambda d: d.polygon(a.s(cx - w + 18, cy - h * 0.26, cx + w - 18, cy - h * 0.26, cx, cy - 6), fill=255))
    a.line([(cx, cy - 2), (cx, cy + h * 0.13)], fill=WHITE, width=2)
    a.save("time")


def pages(scale):
    a = Art(scale)
    cx, cy = 300, 800
    for i in range(37):
        angle = math.radians(180 + i * 5)
        r = 470 + (i % 3) * 8
        a.line([(cx, cy), (cx + r * math.cos(angle), cy + r * math.sin(angle))], fill=BLACK if i % 6 == 0 else DARK, width=2.6 if i % 6 == 0 else 1.2)
    a.circle(cx, cy, 300, fill=WHITE)
    a.rect(120, 120, 480, 330, fill=WHITE)
    a.save("pages")


def author(scale):
    a = Art(scale)
    # A pair of opening quotes, drawn as shapes so no font is needed.
    for x in (64, 132):
        a.circle(x + 26, 150, 26, fill=PALE)
        a.poly([(x + 2, 150), (x + 24, 152), (x + 50, 92), (x + 40, 88)], fill=PALE)
    a.rect(50, 230, 550, 233, fill=BLACK)
    a.rect(50, 238, 550, 239, fill=BLACK)
    a.rect(50, 400, 550, 401, fill=BLACK)
    a.rect(50, 406, 550, 409, fill=BLACK)
    a.save("author")


def best_day(scale):
    a = Art(scale)
    a.pattern((0, 0, W, H), "dots", spacing=11, size=1.5)
    a.rect(0, 28, 480, 96, fill=WHITE)
    a.pattern((170, 150, 470, 600), "hatch", spacing=5, size=1.6)
    a.rect(145, 125, 445, 575, fill=WHITE, outline=BLACK, width=4)
    a.rect(145, 125, 445, 215, fill=BLACK)
    for x in (190, 240, 350, 400):
        a.circle(x, 125, 9, fill=WHITE, outline=BLACK, width=3)
    a.rect(70, 650, 530, 740, fill=WHITE, outline=BLACK, width=2)
    a.save("best_day")


def session(scale):
    a = Art(scale)
    cx, cy = 300, 390
    random.seed(7)
    angle = 0.0
    while angle < 360:
        step = random.uniform(1.0, 3.2)
        r0 = random.uniform(215, 280)
        p1 = (cx + r0 * math.cos(math.radians(angle)), cy + r0 * math.sin(math.radians(angle)) * 1.15)
        p2 = (cx + 900 * math.cos(math.radians(angle - step / 2)), cy + 900 * math.sin(math.radians(angle - step / 2)))
        p3 = (cx + 900 * math.cos(math.radians(angle + step / 2)), cy + 900 * math.sin(math.radians(angle + step / 2)))
        a.poly([p1, p2, p3], fill=BLACK)
        angle += step + random.uniform(1.6, 5.0)
    burst = []
    for i in range(32):
        t = math.radians(i * 360 / 32)
        r = 225 if i % 2 else 192
        burst.append((cx + r * math.cos(t), cy + r * math.sin(t) * 0.92))
    a.poly(burst, fill=WHITE, outline=BLACK, width=4)
    a.save("session")


def hours(scale):
    a = Art(scale, BLACK)
    random.seed(9)
    for _ in range(46):
        a.circle(random.uniform(10, 590), random.uniform(60, 770), random.choice((1, 1, 1.4, 2)), fill=WHITE)
    a.circle(490, 130, 44, fill=WHITE)
    a.circle(470, 118, 42, fill=BLACK)
    a.circle(300, 465, 247, fill=BLACK)
    a.save("hours")


def speed(scale):
    a = Art(scale)
    cx, cy, r = 300, 480, 240
    a.d.arc(a.s(cx - r, cy - r, cx + r, cy + r), 180, 360, fill=BLACK, width=8 * a.k)

    def ring(d):
        d.pieslice(a.s(cx - r + 6, cy - r + 6, cx + r - 6, cy + r - 6), 180, 360, fill=255)
        d.pieslice(a.s(cx - r + 44, cy - r + 44, cx + r - 44, cy + r - 44), 180, 360, fill=0)
    a.pattern((cx - r, cy - r, cx + r, cy), "hatch", spacing=6, size=1.3, mask=ring)
    for value in range(0, 101, 10):
        t = math.radians(180 + value * 1.8)
        length = 26 if value % 50 == 0 else 15
        a.line([(cx + (r - 44) * math.cos(t), cy + (r - 44) * math.sin(t)), (cx + (r - 44 - length) * math.cos(t), cy + (r - 44 - length) * math.sin(t))], width=3)
    a.save("speed")


def summary(scale):
    a = Art(scale)
    a.pattern((0, 0, W, H), "dots", spacing=11, size=1.5)
    x0, y0, x1, y1 = 50, 70, 550, 640
    a.pattern((x0 + 10, y0 + 10, x1 + 10, y1 + 10), "hatch", spacing=4, size=1.8)
    a.rect(x0, y0, x1, y1, fill=WHITE, outline=BLACK, width=4)
    a.circle(300, y0 + 26, 11, fill=WHITE, outline=BLACK, width=3)
    a.rect(x0 + 18, y0 + 90, x1 - 18, y0 + 93, fill=BLACK)
    a.circle(160, 590, 42, fill=WHITE, outline=BLACK, width=3)
    a.circle(160, 590, 35, outline=BLACK, width=1.4)
    a.save("summary")


def tarot_frame(a, x0=110, y0=90, x1=490, y1=585):
    a.rect(x0, y0, x1, y1, fill=WHITE, outline=BLACK, width=5)
    a.rect(x0 + 11, y0 + 11, x1 - 11, y1 - 11, outline=BLACK, width=1.6)
    a.rect(x0 + 18, y0 + 18, x1 - 18, y1 - 92, fill=BLACK)


def stars(a, seed, count=46):
    random.seed(seed)
    for _ in range(count):
        a.circle(random.uniform(134, 466), random.uniform(114, 485), random.choice((1, 1.3, 2)), fill=WHITE)


def moon_disc(a, r=128, cy=275):
    a.circle(300, cy, r, fill=WHITE)
    a.pattern((300 - r, cy - r, 300 + r, cy + r), "dots", spacing=6, size=1.3, mask=lambda d: d.ellipse(a.s(300 - r, cy - r, 300 + r, cy + r), fill=255))


def night_owl(a):
    stars(a, 21)
    moon_disc(a)
    cx, cy, s = 300, 305, 0.92
    a.poly([(cx - 90 * s, cy + 120 * s), (cx - 96 * s, cy - 55 * s), (cx - 66 * s, cy - 118 * s), (cx - 34 * s, cy - 92 * s), (cx + 34 * s, cy - 92 * s), (cx + 66 * s, cy - 118 * s), (cx + 96 * s, cy - 55 * s), (cx + 90 * s, cy + 120 * s)], fill=WHITE, outline=BLACK, width=4)
    a.pattern((cx - 60 * s, cy + 2 * s, cx + 60 * s, cy + 118 * s), "hatch", spacing=6, size=1.5, mask=lambda d: d.ellipse(a.s(cx - 60 * s, cy + 2 * s, cx + 60 * s, cy + 150 * s), fill=255))
    for side in (-1, 1):
        ex = cx + side * 42 * s
        a.circle(ex, cy - 44 * s, 38 * s, fill=WHITE, outline=BLACK, width=4)
        a.circle(ex, cy - 44 * s, 24 * s, fill=BLACK)
        a.circle(ex + 6 * s, cy - 52 * s, 7 * s, fill=WHITE)
    a.poly([(cx - 12 * s, cy - 18 * s), (cx + 12 * s, cy - 18 * s), (cx, cy + 10 * s)], fill=BLACK)
    a.rect(cx - 138 * s, cy + 118 * s, cx + 138 * s, cy + 128 * s, fill=WHITE)
    for x in (-34, 0, 34):
        a.line([(cx + x * s, cy + 104 * s), (cx + x * s, cy + 118 * s)], width=4)


def early_bird(a):
    # The bird stays entirely inside the white sun, so black never touches the black sky.
    cx, cy = 300, 400
    for i in range(30, 151, 15):
        t = math.radians(180 + i)
        a.line([(cx + 166 * math.cos(t), cy + 166 * math.sin(t)), (cx + 192 * math.cos(t), cy + 192 * math.sin(t))], fill=WHITE, width=4)
    a.circle(cx, cy, 155, fill=WHITE)
    a.rect(128, cy, 472, 493, fill=BLACK)
    a.rect(128, cy, 472, cy + 6, fill=WHITE)
    a.pattern((128, cy + 16, 472, 493), "dots", ink=WHITE, spacing=9, size=1.6)
    bx, by = 292, 335
    a.line([(bx - 8, by + 30), (bx - 8, cy)], width=5)
    a.line([(bx + 14, by + 30), (bx + 14, cy)], width=5)
    a.circle(bx, by, 44, fill=BLACK)
    a.circle(bx + 40, by - 34, 24, fill=BLACK)
    a.poly([(bx + 58, by - 42), (bx + 88, by - 34), (bx + 58, by - 24)], fill=BLACK)
    a.circle(bx + 46, by - 40, 5, fill=WHITE)
    a.poly([(bx - 34, by - 14), (bx - 84, by - 26), (bx - 40, by + 22)], fill=BLACK)
    a.poly([(bx - 20, by - 8), (bx + 18, by - 2), (bx - 6, by + 22)], fill=WHITE)


def steady(a):
    # A metronome. Its arm and weight stay inside the white body, away from the black sky.
    stars(a, 22, 22)
    a.poly([(226, 462), (374, 462), (336, 150), (264, 150)], fill=WHITE)
    a.rect(212, 458, 388, 480, fill=WHITE)
    a.pattern((240, 340, 360, 450), "hatch", spacing=6, size=1.5, mask=lambda d: d.polygon(a.s(248, 448, 352, 448, 339, 345, 261, 345), fill=255))
    a.line([(300, 415), (276, 186)], fill=BLACK, width=7)
    a.rect(270, 240, 300, 264, fill=BLACK)
    a.circle(300, 415, 13, fill=BLACK)
    a.circle(300, 138, 12, fill=WHITE)


def marathoner(a):
    a.circle(390, 180, 36, fill=WHITE)
    a.poly([(285, 300), (315, 300), (470, 485), (130, 485)], fill=WHITE)
    a.line([(300, 320), (300, 345)], width=4)
    a.line([(300, 375), (300, 410)], width=5)
    a.line([(300, 440), (300, 480)], width=7)
    a.line([(134, 300), (466, 300)], fill=WHITE, width=3)
    a.line([(300, 300), (300, 170)], fill=WHITE, width=5)
    a.rect(300, 170, 380, 222, fill=WHITE)
    for row in range(2):
        for col in range(4):
            if (row + col) % 2 == 0:
                a.rect(300 + col * 20, 170 + row * 26, 320 + col * 20, 196 + row * 26, fill=BLACK)


def heart(a, cx, cy, s, fill):
    # The classic parametric heart: one smooth curve, with no joints between shapes.
    points = []
    for step in range(360):
        t = math.radians(step)
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append((cx + x * 5.2 * s, cy - y * 5.2 * s))
    a.poly(points, fill=fill)


def loyal(a):
    stars(a, 24, 26)
    heart(a, 300, 215, 1.0, WHITE)
    a.poly([(150, 330), (300, 372), (450, 330), (450, 450), (300, 490), (150, 450)], fill=WHITE, outline=WHITE, width=2)
    a.line([(300, 372), (300, 490)], width=4)
    for i in range(4):
        y = 360 + i * 22
        a.line([(172, y), (276, y + 26)], width=2)
        a.line([(428, y), (324, y + 26)], width=2)


def weekender(a):
    a.circle(390, 190, 54, fill=WHITE)
    for i in range(0, 360, 30):
        t = math.radians(i)
        a.line([(390 + 66 * math.cos(t), 190 + 66 * math.sin(t)), (390 + 86 * math.cos(t), 190 + 86 * math.sin(t))], fill=WHITE, width=4)
    a.poly([(164, 268), (244, 268), (244, 352), (430, 352), (430, 432), (164, 432)], fill=WHITE)
    a.pattern((178, 282, 232, 392), "hatch", spacing=6, size=1.5)
    a.pattern((256, 366, 418, 396), "hatch", spacing=6, size=1.5)
    for x in (178, 402):
        a.rect(x, 432, x + 14, 472, fill=WHITE)


def explorer(a):
    stars(a, 25, 30)
    cx, cy = 300, 300
    a.circle(cx, cy, 138, fill=WHITE)
    a.circle(cx, cy, 124, outline=BLACK, width=3)
    for i in range(0, 360, 30):
        t = math.radians(i)
        a.line([(cx + 108 * math.cos(t), cy + 108 * math.sin(t)), (cx + 122 * math.cos(t), cy + 122 * math.sin(t))], width=3)
    a.poly([(cx + 70, cy - 70), (cx + 12, cy + 12), (cx - 12, cy - 12)], fill=BLACK)
    a.poly([(cx - 70, cy + 70), (cx + 12, cy + 12), (cx - 12, cy - 12)], fill=WHITE, outline=BLACK, width=3)
    a.circle(cx, cy, 8, fill=WHITE, outline=BLACK, width=3)


def curious(a):
    stars(a, 26, 32)
    a.line([(370, 370), (452, 462)], fill=WHITE, width=24)
    a.circle(280, 270, 118, fill=WHITE)
    a.circle(280, 270, 90, fill=BLACK)
    a.pattern((190, 180, 370, 360), "dots", ink=WHITE, spacing=7, size=1.6, mask=lambda d: d.ellipse(a.s(204, 194, 356, 346), fill=255))
    a.d.arc(a.s(226, 216, 334, 324), 190, 270, fill=WHITE, width=6 * a.k)


PROFILES = {
    "night_owl": night_owl, "early_bird": early_bird, "steady": steady, "marathoner": marathoner,
    "loyal": loyal, "weekender": weekender, "explorer": explorer, "curious": curious,
}


def main():
    for scale in (1, 2):
        for draw in (cover, time_art, pages, author, best_day, session, hours, speed, summary):
            draw(scale)
        for name, draw in PROFILES.items():
            a = Art(scale)
            tarot_frame(a)
            draw(a)
            a.save("profile_" + name)
    print("Card art generated")


if __name__ == "__main__":
    main()
