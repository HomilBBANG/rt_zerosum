#!/usr/bin/env python3
"""검정 배경 원화 → 투명 배경. 이미지 가장자리에서 '거의 순수 검정' 픽셀만 연결된 영역으로 채워 지운다
(캐릭터 안쪽의 검정 의상·부츠는 외곽선으로 막혀 있어 지워지지 않음). 경계는 밝기에 비례한 알파로 부드럽게.
사용: python3 tools/remove_black_bg.py 입력.png 출력.png [임곗값=10]"""
import sys
from collections import deque
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
th = int(sys.argv[3]) if len(sys.argv) > 3 else 10
im = np.array(Image.open(src).convert("RGB")).astype(np.int16)
h, w, _ = im.shape
mx = im.max(axis=2)
bg = np.zeros((h, w), bool)
q = deque()
for x in range(w):
    for y in (0, h - 1):
        if mx[y, x] <= th and not bg[y, x]:
            bg[y, x] = True; q.append((y, x))
for y in range(h):
    for x in (0, w - 1):
        if mx[y, x] <= th and not bg[y, x]:
            bg[y, x] = True; q.append((y, x))
while q:
    y, x = q.popleft()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and not bg[ny, nx] and mx[ny, nx] <= th:
            bg[ny, nx] = True; q.append((ny, nx))
alpha = np.where(bg, 0, 255).astype(np.uint8)
# 배경과 맞닿은 1px 테두리: 밝기에 비례한 반투명 (검정 배경에 섞인 안티앨리어싱 제거)
from PIL import ImageFilter
a_img = Image.fromarray(alpha)
edge = (np.array(a_img.filter(ImageFilter.MinFilter(3))) == 0) & (alpha == 255)
soft = np.clip(mx * 255 // max(th * 3, 1), 0, 255).astype(np.uint8)
alpha = np.where(edge, np.maximum(soft, 120), alpha)
out = np.dstack([im.astype(np.uint8), alpha])
Image.fromarray(out, "RGBA").save(dst)
print("bg px", int(bg.sum()), "of", h * w)
