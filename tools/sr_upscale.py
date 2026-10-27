"""AI 시트 4배 확대 (Real-ESRGAN x4plus_anime_6B) — 작은 AI 시트를 키워도 흐려지지 않게.

AI 시트는 한 칸 키가 300px 정도라 게임 그림(키 760px)으로 키우면 흐릿함. 이 도구로 먼저 4배로 키운 시트를
char_sprites.py sheet 에 넣으면, sheet 가 기준 키에 맞춰 줄이므로 선이 또렷하게 남음.

준비 (한 번):
  pip install torch pillow numpy
  모델: https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth

사용:
  python3 tools/sr_upscale.py <시트.webp> <출력.png> --model RealESRGAN_x4plus_anime_6B.pth [--tile 256]
  → 출력 = 4배 크기 RGBA (색은 흰 바탕에 얹어 확대, 투명도는 따로 확대해 가장자리를 다시 또렷하게,
    발밑 반투명 바닥 그림자는 지움, 외곽선 밖 흰 테도 지움)
"""
import argparse

import numpy as np
from PIL import Image


def build(model_path):
    import torch
    from torch import nn
    import torch.nn.functional as F

    class RDB(nn.Module):
        def __init__(self, nf=64, gc=32):
            super().__init__()
            self.conv1 = nn.Conv2d(nf, gc, 3, 1, 1)
            self.conv2 = nn.Conv2d(nf + gc, gc, 3, 1, 1)
            self.conv3 = nn.Conv2d(nf + 2 * gc, gc, 3, 1, 1)
            self.conv4 = nn.Conv2d(nf + 3 * gc, gc, 3, 1, 1)
            self.conv5 = nn.Conv2d(nf + 4 * gc, nf, 3, 1, 1)
            self.lrelu = nn.LeakyReLU(0.2, True)

        def forward(self, x):
            x1 = self.lrelu(self.conv1(x))
            x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
            x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
            x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
            return self.conv5(torch.cat((x, x1, x2, x3, x4), 1)) * 0.2 + x

    class RRDB(nn.Module):
        def __init__(self, nf=64, gc=32):
            super().__init__()
            self.rdb1, self.rdb2, self.rdb3 = RDB(nf, gc), RDB(nf, gc), RDB(nf, gc)

        def forward(self, x):
            return self.rdb3(self.rdb2(self.rdb1(x))) * 0.2 + x

    class RRDBNet(nn.Module):
        def __init__(self, nb, nf=64, gc=32):
            super().__init__()
            self.conv_first = nn.Conv2d(3, nf, 3, 1, 1)
            self.body = nn.Sequential(*[RRDB(nf, gc) for _ in range(nb)])
            self.conv_body = nn.Conv2d(nf, nf, 3, 1, 1)
            self.conv_up1 = nn.Conv2d(nf, nf, 3, 1, 1)
            self.conv_up2 = nn.Conv2d(nf, nf, 3, 1, 1)
            self.conv_hr = nn.Conv2d(nf, nf, 3, 1, 1)
            self.conv_last = nn.Conv2d(nf, 3, 3, 1, 1)
            self.lrelu = nn.LeakyReLU(0.2, True)

        def forward(self, x):
            feat = self.conv_first(x)
            feat = feat + self.conv_body(self.body(feat))
            feat = self.lrelu(self.conv_up1(F.interpolate(feat, scale_factor=2, mode="nearest")))
            feat = self.lrelu(self.conv_up2(F.interpolate(feat, scale_factor=2, mode="nearest")))
            return self.conv_last(self.lrelu(self.conv_hr(feat)))

    sd = torch.load(model_path, map_location="cpu", weights_only=True)
    sd = sd.get("params_ema", sd.get("params", sd))
    nb = 1 + max(int(k.split(".")[1]) for k in sd if k.startswith("body."))
    net = RRDBNet(nb)
    net.load_state_dict(sd, strict=True)
    return net.eval()


def upscale_rgb(net, rgb, tile=256, pad=12):
    """rgb = HxWx3 float 0..1 → 4H x 4W x 3 (타일로 나눠 계산, 이음새 없게 겹쳐서)"""
    import torch
    H, W, _ = rgb.shape
    out = np.zeros((H * 4, W * 4, 3), np.float32)
    x = torch.from_numpy(rgb.transpose(2, 0, 1)[None].copy())
    with torch.inference_mode():
        for y0 in range(0, H, tile):
            for x0 in range(0, W, tile):
                y1, x1 = min(H, y0 + tile), min(W, x0 + tile)
                py0, px0, py1, px1 = max(0, y0 - pad), max(0, x0 - pad), min(H, y1 + pad), min(W, x1 + pad)
                o = net(x[:, :, py0:py1, px0:px1])[0].numpy().transpose(1, 2, 0)
                out[y0 * 4:y1 * 4, x0 * 4:x1 * 4] = o[(y0 - py0) * 4:(y1 - py0) * 4, (x0 - px0) * 4:(x1 - px0) * 4]
                print(f"  {y0}/{H} {x0}/{W}", end="\r", flush=True)
    print()
    return np.clip(out, 0, 1)


def remove_floor_shadow(im, min_px=12):
    """AI 시트 발밑 바닥 그림자(반투명 타원) 지우기 — 게임이 그림자를 따로 그림.
    반투명 픽셀 중 가장자리 안티에일리어싱(1~2px 띠)보다 두꺼운 덩어리 = 그림자"""
    from scipy import ndimage
    arr = np.array(im)
    al = arr[..., 3].astype(int)
    semi = (al > 3) & (al < 200)
    blob = ndimage.binary_opening(semi, iterations=1)
    lab, n = ndimage.label(blob)
    if n:
        sz = ndimage.sum(blob, lab, range(1, n + 1))
        shadow = np.isin(lab, [i + 1 for i in range(n) if sz[i] >= min_px])
        shadow = ndimage.binary_dilation(shadow, iterations=1) & semi
        arr[..., 3] = np.where(shadow, 0, arr[..., 3])
        print("바닥 그림자 지움:", int(shadow.sum()), "px")
    return Image.fromarray(arr)


def defringe(rgb, A, band=3, light=0.62):
    """검은 외곽선 바깥에 남은 밝은 테(흰 바탕 흔적) 지우기: 투명한 곳에서 시작해 흰·옅은 회색 픽셀만 따라
    band px 안까지 번지는 영역 = 테 → 투명. 외곽선(어두운 픽셀)을 넘지 않음."""
    from scipy import ndimage
    lum = rgb.mean(-1)
    outside = A < 0.5
    near = ndimage.binary_dilation(outside, iterations=band)
    sat = rgb.max(-1) - rgb.min(-1)
    cand = near & ~outside & (lum > light) & (sat < 0.12)   # 흰·옅은 회색만 (피부·옷 색은 안 건드림)
    seed = ndimage.binary_dilation(outside, iterations=1) & cand
    fringe = ndimage.binary_propagation(seed, mask=cand)
    A = A.copy()
    A[fringe] = 0
    return A


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--model", required=True)
    ap.add_argument("--tile", type=int, default=256)
    ap.add_argument("--threads", type=int, default=0)
    a = ap.parse_args()
    import torch
    if a.threads:
        torch.set_num_threads(a.threads)
    net = build(a.model)
    im = remove_floor_shadow(Image.open(a.src).convert("RGBA"))
    arr = np.array(im).astype(np.float32) / 255
    al = arr[..., 3:4]
    rgb = arr[..., :3] * al + (1 - al)   # 흰 바탕에 얹어 확대 (AI 시트는 흰 바탕에서 뽑은 것)
    big = upscale_rgb(net, rgb, a.tile)
    # 투명도: 부드럽게 4배 → 가장자리 대비를 올려 또렷하게 (반투명 테두리 1~2px 만 남김)
    A = np.array(im.split()[3].resize(big.shape[1::-1], Image.LANCZOS)).astype(np.float32) / 255
    A = np.clip((A - 0.5) * 2.2 + 0.5, 0, 1)
    rgb_out = (big - (1 - A[..., None])) / np.maximum(A[..., None], 1e-3)   # 흰 바탕 빼기 (가장자리 흰 테 방지)
    rgb_out = np.where(A[..., None] > 0.02, np.clip(rgb_out, 0, 1), big)
    A = defringe(rgb_out, A)
    out = np.concatenate([rgb_out, A[..., None]], -1)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA").save(a.dst)
    print(a.dst, Image.open(a.dst).size)


if __name__ == "__main__":
    main()
