#!/usr/bin/env python3
"""生成内置的演示开机动画（默认写到 animations/演示动画.zip）——本模块自有素材，无第三方版权。

画面：深色底 + 一圈旋转的加载环（配色取自模块界面），24 帧一循环、首尾无缝衔接。

几个为了让包尽量小而做的取舍：
- 帧只做 720×1600。bootanimation 播放时会按 desc 声明的尺寸缩放帧，模块刷入/导入时也会把
  desc 首行改成设备分辨率，所以帧不需要按屏幕尺寸存——这正是原内置动画占 13MB 的原因。
- desc 声明的尺寸写成 1080×2400（而不是帧的真实尺寸）：模块的 fit 是「等长原地改写」，
  声明 4 位数宽高（各行 12 字符）才能被改写成 1080×2400 / 1440×3120 这些常见分辨率；
  声明成 720×1600（11 字符）会写不下、在 1080p 机器上点「自适应屏幕」会报错。
- 画完 4 倍超采样再缩小（PIL 画圆不抗锯齿），最后量化成 16 色调色板——同样观感下体积约为
  全彩 RGB PNG 的 1/2.6。

用法: python tools/make_demo.py [输出zip] [帧宽x帧高]
依赖: pip install pillow
"""
import io, os, sys, zipfile
from PIL import Image, ImageDraw

W, H = 720, 1600               # 帧的真实尺寸
DECL_W, DECL_H = 1080, 2400    # desc 里声明的渲染尺寸（见上面说明）
FPS = N = 24                   # 24 帧 / 24fps = 1 秒一循环
SS = 4                         # 超采样倍数
PAL = 16                       # 调色板色数
BG, TRACK, ACC = (13, 15, 20), (30, 36, 48), (79, 140, 255)
SWEEP = 100                    # 弧长（度）

if len(sys.argv) > 2:
    W, H = (int(x) for x in sys.argv[2].lower().split("x", 1))


def frame(i):
    im = Image.new("RGB", (W * SS, H * SS), BG)
    d = ImageDraw.Draw(im)
    cx, cy = W * SS // 2, H * SS // 2
    r = int(W * SS * 0.17)
    lw = max(2, int(W * SS * 0.013))
    box = [cx - r, cy - r, cx + r, cy + r]
    d.ellipse(box, outline=TRACK, width=lw)                # 底环
    a0 = -90 + 360.0 * i / N                               # 起始角绕满一圈 → 循环无缝
    d.arc(box, a0, a0 + SWEEP, fill=ACC, width=lw)         # 旋转弧
    return im.resize((W, H), Image.LANCZOS).convert("P", palette=Image.ADAPTIVE, colors=PAL)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "animations", "演示动画.zip")
    prev = None
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:   # bootanimation 硬性要求不压缩
        z.writestr(zipfile.ZipInfo("desc.txt"), f"{DECL_W} {DECL_H} {FPS}\np 0 0 part0\n".encode())
        for i in range(N):
            im = frame(i)
            b = io.BytesIO()
            im.save(b, "PNG", optimize=True)
            z.writestr(zipfile.ZipInfo(f"part0/{i:05d}.png"), b.getvalue())
            prev = im
    tot = os.path.getsize(out)
    print(f"帧 {W}×{H} × {N} @ {FPS}fps，desc 声明 {DECL_W}×{DECL_H}，调色板 {PAL} 色")
    print(f"写出 {out}: {tot:,} bytes")


if __name__ == "__main__":
    main()
