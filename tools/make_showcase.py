"""Builds assets/showcase.png (title image for the project pages) from the logo and the screenshots."""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
shots = sys.argv[1]
W, H = 1600, 960
BG, PANEL, GOLD, TEXT, DIM = (17, 14, 11), (28, 23, 18), (227, 171, 92), (236, 228, 214), (160, 148, 130)


def font(size, bold=False):
    try:
        return ImageFont.truetype("segoeuib.ttf" if bold else "segoeui.ttf", size)
    except OSError:
        return ImageFont.load_default()


def shot(name, scale):
    im = Image.open(os.path.join(shots, name)).convert("RGB")
    return im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)


canvas = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(canvas)

logo = Image.open(os.path.join(repo, "assets", "logo.png")).convert("RGBA").resize((120, 120), Image.LANCZOS)
canvas.paste(logo, (60, 34), logo)
draw.text((204, 36), "QuickCraft Forever", font=font(58, True), fill=GOLD)
draw.text((206, 112), "Your professions on one bar. Favourite recipes one hover and one click away.",
          font=font(26), fill=TEXT)
draw.line((60, 176, W - 60, 176), fill=(70, 52, 30), width=2)


def panel(x, y, rows, title, text):
    """rows: list of rows, each a list of (image, label) placed side by side."""
    draw.text((x, y), title, font=font(26, True), fill=GOLD)
    draw.text((x, y + 36), text, font=font(19), fill=DIM)
    cy = y + 76
    for row in rows:
        cx = x
        for im, label in row:
            top = cy
            if label:
                draw.text((cx, cy), label, font=font(17, True), fill=TEXT)
                top = cy + 30
            draw.rectangle((cx - 4, top - 4, cx + im.width + 3, top + im.height + 3), fill=PANEL, outline=(70, 52, 30))
            canvas.paste(im, (cx, top))
            cx += im.width + 34
        cy += max(im.height for im, _ in row) + (30 if row[0][1] else 0) + 22


panel(60, 200, [[(shot("2.png", 1.2), "WoW: Forever look"), (shot("5.png", 1.2), "EllesmereUI look")]],
      "Hover, click, crafted", "Favourites fan out. Click = craft one, number = craft all.")
panel(770, 200, [[(shot("3.png", 0.88), "")]], "Pick your favourites", "A star behind every recipe.")
panel(1090, 200, [[(shot("4.png", 0.62), "")], [(shot("6.png", 1.25), "")]], "Make it yours",
      "Vertical or horizontal, two looks, sizes, fonts.")

out = os.path.join(repo, "assets", "showcase.png")
canvas.save(out)
os.makedirs(os.path.join(repo, "assets", "screenshots"), exist_ok=True)
for name, label in (("2.png", "fan-out"), ("3.png", "favourites"), ("4.png", "options"),
                    ("5.png", "bar-vertical"), ("6.png", "bar-horizontal")):
    im = Image.open(os.path.join(shots, name)).convert("RGB")
    im.resize((im.width * 2, im.height * 2), Image.LANCZOS).save(
        os.path.join(repo, "assets", "screenshots", label + ".png"))
print(out)
