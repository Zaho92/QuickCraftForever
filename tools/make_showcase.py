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


def panel(x, y, images, title, text):
    draw.text((x, y), title, font=font(26, True), fill=GOLD)
    draw.text((x, y + 36), text, font=font(19), fill=DIM)
    cy = y + 76
    for im in images:
        draw.rectangle((x - 4, cy - 4, x + im.width + 3, cy + im.height + 3), fill=PANEL, outline=(70, 52, 30))
        canvas.paste(im, (x, cy))
        cy += im.height + 22


panel(60, 200, [shot("2.png", 1.2)], "Hover, click, crafted",
      "Favourites fan out. Click = craft one, number = craft all.")
panel(626, 200, [shot("3.png", 0.92)], "Pick your favourites", "A star behind every recipe.")
panel(972, 200, [shot("4.png", 0.78), shot("6.png", 1.3)], "Make it yours",
      "Vertical or horizontal, two looks, sizes, fonts, bars.")

out = os.path.join(repo, "assets", "showcase.png")
canvas.save(out)
os.makedirs(os.path.join(repo, "assets", "screenshots"), exist_ok=True)
for name, label in (("2.png", "fan-out"), ("3.png", "favourites"), ("4.png", "options"),
                    ("5.png", "bar-vertical"), ("6.png", "bar-horizontal")):
    im = Image.open(os.path.join(shots, name)).convert("RGB")
    im.resize((im.width * 2, im.height * 2), Image.LANCZOS).save(
        os.path.join(repo, "assets", "screenshots", label + ".png"))
print(out)
