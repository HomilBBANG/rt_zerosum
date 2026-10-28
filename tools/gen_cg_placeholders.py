"""[임시] 컷씬 CG·배경 자리표시 그림 생성 (assets/cg/*.png, 1280x720). 진짜 그림이 오면 같은 이름으로 덮어쓰거나 컷씬 에디터에서 바꾸면 됨.
   python3 tools/gen_cg_placeholders.py"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import random, math, os
W, H = 1280, 720
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "cg")
F = ImageFont.truetype(os.path.join(os.path.dirname(__file__), "..", "assets", "fonts", "Pretendard-Bold.ttf"), 20)


def grad(top, bot):
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)))
    return im.convert("RGBA")


def tag(im, text):   # 왼쪽 위 (컷씬 제목 아래) — 아래쪽은 대사 상자·안내 글
    ImageDraw.Draw(im).text((20, 42), text, font=F, fill=(230, 230, 240, 150))


def save(im, name):
    im.convert("RGB").save(os.path.join(OUT, name))


def opening():
    im = grad((40, 14, 40), (200, 70, 40))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W * 0.55, H * 0.45, W * 1.05, H * 1.1], fill=(255, 140, 60, 150))
    im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(80)))
    for layer, (col, base, hmax) in enumerate([((60, 22, 40), H * 0.62, 260), ((28, 10, 24), H * 0.72, 200), ((10, 4, 10), H * 0.82, 150)]):
        d = ImageDraw.Draw(im)
        x = -20
        while x < W:
            w = random.randint(40, 110)
            h = random.randint(60, int(hmax))
            d.rectangle([x, base - h, x + w, H], fill=col + (255,))
            if layer < 2:
                for wy in range(int(base - h + 12), int(base), 18):
                    for wx in range(x + 8, x + w - 8, 16):
                        if random.random() < 0.25:
                            d.rectangle([wx, wy, wx + 6, wy + 8], fill=(255, 190, 90, 200))
            x += w + random.randint(-10, 8)
    smoke = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s = ImageDraw.Draw(smoke)
    for _ in range(14):
        cx, cy, r = random.randint(500, 1200), random.randint(60, 380), random.randint(60, 160)
        s.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(30, 20, 30, 90))
    im = Image.alpha_composite(im, smoke.filter(ImageFilter.GaussianBlur(30)))
    tag(im, "[임시 CG] 오프닝 — 무너진 도시")
    save(im, "cg_opening.png")


def corridor():
    im = grad((14, 22, 30), (6, 10, 14))
    d = ImageDraw.Draw(im)
    for i in range(7):
        x = 90 + i * 180
        d.rectangle([x, 140, x + 120, 560], fill=(22, 34, 44, 255), outline=(40, 60, 72, 255), width=3)
    for y in (110, 600):
        d.rectangle([0, y, W, y + 14], fill=(34, 48, 58, 255))
    for i in range(6):
        x = 160 + i * 200
        lamp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(lamp).ellipse([x - 90, 40, x + 90, 260], fill=(120, 200, 220, 70))
        im = Image.alpha_composite(im, lamp.filter(ImageFilter.GaussianBlur(40)))
        ImageDraw.Draw(im).rectangle([x - 30, 100, x + 30, 110], fill=(190, 240, 255, 255))
    ImageDraw.Draw(im).polygon([(0, H), (W, H), (W, 620), (0, 620)], fill=(10, 14, 18, 255))
    tag(im, "[임시 배경] 기지 복도")
    save(im, "bg_base_corridor.png")


def rooftop():
    im = grad((6, 8, 24), (30, 40, 80))
    d = ImageDraw.Draw(im)
    for _ in range(260):
        x, y, r = random.randint(0, W), random.randint(0, 460), random.choice([1, 1, 1, 2])
        d.ellipse([x, y, x + r, y + r], fill=(230, 235, 255, random.randint(120, 255)))
    moon = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(moon).ellipse([940, 70, 1080, 210], fill=(250, 245, 220, 255))
    im = Image.alpha_composite(im, moon.filter(ImageFilter.GaussianBlur(2)))
    gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(gl).ellipse([880, 10, 1140, 270], fill=(220, 220, 180, 60))
    im = Image.alpha_composite(im, gl.filter(ImageFilter.GaussianBlur(40)))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 540, W, H], fill=(12, 14, 22, 255))
    for x in range(0, W, 60):
        d.rectangle([x, 500, x + 6, 540], fill=(20, 24, 34, 255))
    d.rectangle([0, 496, W, 504], fill=(24, 28, 40, 255))
    tag(im, "[임시 배경] 옥상의 밤")
    save(im, "bg_rooftop_night.png")


def hana_terra():
    im = grad((8, 24, 14), (2, 8, 4))
    gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(gl).ellipse([W / 2 - 380, H / 2 - 340, W / 2 + 380, H / 2 + 420], fill=(90, 230, 120, 140))
    im = Image.alpha_composite(im, gl.filter(ImageFilter.GaussianBlur(90)))
    ring = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    r = ImageDraw.Draw(ring)
    for rad, wd in ((300, 6), (330, 2), (250, 2)):
        r.ellipse([W / 2 - rad, H / 2 - rad + 30, W / 2 + rad, H / 2 + rad + 30], outline=(150, 255, 170, 200), width=wd)
    for k in range(12):
        a = k * math.pi / 6
        x, y = W / 2 + math.cos(a) * 315, H / 2 + 30 + math.sin(a) * 315
        r.ellipse([x - 8, y - 8, x + 8, y + 8], fill=(190, 255, 200, 230))
    im = Image.alpha_composite(im, ring.filter(ImageFilter.GaussianBlur(1)))
    hana = Image.open(os.path.join(os.path.dirname(__file__), "..", "assets", "characters", "hero2", "base.png")).convert("RGBA")
    s = 700 / hana.height
    hana = hana.resize((int(hana.width * s), 700), Image.LANCZOS)
    aura = Image.new("RGBA", hana.size, (140, 255, 160, 0))
    aura.putalpha(hana.getchannel("A").filter(ImageFilter.GaussianBlur(18)))
    x, y = (W - hana.width) // 2, H - 700 + 40
    im.alpha_composite(aura, (x, y))
    im.alpha_composite(aura, (x, y))
    tint = Image.new("RGBA", hana.size, (120, 255, 150, 60))
    tint.putalpha(hana.getchannel("A").point(lambda v: int(v * 0.25)))
    im.alpha_composite(hana, (x, y))
    im.alpha_composite(tint, (x, y))
    for _ in range(80):
        px, py, pr = random.randint(200, 1080), random.randint(80, 700), random.randint(2, 5)
        ImageDraw.Draw(im).ellipse([px, py, px + pr, py + pr], fill=(180, 255, 190, random.randint(80, 200)))
    tag(im, "[임시 CG] 하나 — 대지모 테라의 현신")
    save(im, "cg_hana_terra.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    random.seed(7)
    opening()
    corridor()
    rooftop()
    hana_terra()
    print("assets/cg 4장")
