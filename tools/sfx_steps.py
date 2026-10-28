"""발자국 소리 → 한 걸음씩 자르기 (캐릭터 걷기·뛰기 애니메이션에서 발이 땅에 닿는 프레임마다 한 조각씩 재생).

사용:
  python3 tools/sfx_steps.py <캐릭터 id> <walk|run> <발자국.mp3>
  → assets/characters/<캐릭터>/sfx/<동작>_01.ogg, _02.ogg … (걸음마다 한 조각, 돌아가며 재생)
     원본은 assets/source/sfx/<캐릭터>_<동작>.mp3 로 보관
  python3 tools/sfx_steps.py --common dead <소리.mp3>   공용 소리 → assets/sfx/dead.ogg (원본 보관 같음)

걸음 찾기: 소리 크기(RMS)가 최대의 25% 를 넘는 순간 = 발 닿음, 걸음 사이 최소 0.18초.
조각 = 발 닿기 20ms 전 ~ 다음 걸음 20ms 전 (마지막은 소리가 잦아들 때까지), 끝 30ms 페이드.
다른 걸음보다 4dB 넘게 작거나 큰 조각은 중간값 크기로 맞춤.
"""
import os
import shutil
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "2", "-ar", str(SR), "-f", "s16le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.int16).reshape(-1, 2).astype(np.float32) / 32768.0


def encode(samples, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=pcm, check=True)


def onsets(a, rel=0.25, gap=0.18):
    """발 닿는 순간들 (초)"""
    mono = a.mean(1)
    w = int(SR * 0.01)
    env = np.sqrt(np.convolve(mono * mono, np.ones(w) / w, "same"))
    th = env.max() * rel
    out = []
    i = 0
    n = len(env)
    while i < n:
        if env[i] > th:
            # 이 걸음의 시작 = 문턱을 넘기 직전 조용한 곳 (최대의 5% 아래로 거슬러 올라감, 최대 60ms)
            j = i
            while j > 0 and i - j < SR * 0.06 and env[j] > env.max() * 0.05:
                j -= 1
            out.append(j / SR)
            i += int(SR * gap)
            while i < n and env[i] > th * 0.6:   # 같은 걸음의 울림은 건너뜀
                i += 1
        else:
            i += 1
    return out, env


def slice_steps(a, ts, env):
    pre = int(SR * 0.02)
    fade = int(SR * 0.03)
    quiet = env.max() * 10 ** (-40 / 20)
    pieces = []
    for k, t in enumerate(ts):
        s = max(0, int(t * SR) - pre)
        if k + 1 < len(ts):
            e = int(ts[k + 1] * SR) - pre
        else:
            loud = np.nonzero(env[s:] > quiet)[0]
            e = s + (int(loud[-1]) + fade if len(loud) else len(env) - s)
        p = a[s:min(e, len(a))].copy()
        f = min(fade, len(p))
        p[-f:] *= np.linspace(1, 0, f)[:, None]
        pieces.append(p)
    return pieces


def level_outliers(pieces, tol_db=4.0):
    """다른 걸음보다 tol_db 넘게 작거나 큰 조각(녹음 처음의 작은 걸음 등)은 중간값 크기로 — 돌아가며 재생할 때 튀지 않게"""
    peaks = [float(np.abs(p).max()) + 1e-9 for p in pieces]
    med = float(np.median(peaks))
    out = []
    for p, pk in zip(pieces, peaks):
        diff = 20 * np.log10(pk / med)
        out.append(p * (med / pk) if abs(diff) > tol_db else p)
        if abs(diff) > tol_db:
            print("  조각 크기 맞춤: %+.1f dB → 0" % diff)
    return out


def main():
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "--common":
        name, src = args[1], args[2]
        os.makedirs(os.path.join(ROOT, "assets", "source", "sfx"), exist_ok=True)
        shutil.copy(src, os.path.join(ROOT, "assets", "source", "sfx", name + ".mp3"))
        encode(decode(src), os.path.join(ROOT, "assets", "sfx", name + ".ogg"))
        print("공용", name, "→ assets/sfx/%s.ogg" % name)
        return
    if len(args) != 3:
        print(__doc__)
        sys.exit(1)
    cid, anim, src = args
    a = decode(src)
    ts, env = onsets(a)
    if not ts:
        sys.exit("걸음을 못 찾았습니다")
    out_dir = os.path.join(ROOT, "assets", "characters", cid, "sfx")
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.startswith(anim + "_") and (f.endswith(".ogg") or f.endswith(".ogg.import")):
            os.remove(os.path.join(out_dir, f))
    pieces = level_outliers(slice_steps(a, ts, env))
    for k, p in enumerate(pieces):
        encode(p, os.path.join(out_dir, "%s_%02d.ogg" % (anim, k + 1)))
    os.makedirs(os.path.join(ROOT, "assets", "source", "sfx"), exist_ok=True)
    shutil.copy(src, os.path.join(ROOT, "assets", "source", "sfx", "%s_%s.mp3" % (cid, anim)))
    gaps = np.diff(ts)
    print(cid, anim, "걸음 %d개" % len(ts), "시각", [round(t, 2) for t in ts],
          "간격 %.2f초" % (float(np.median(gaps)) if len(gaps) else 0), "조각 길이", [round(len(p) / SR, 2) for p in pieces])


if __name__ == "__main__":
    main()
