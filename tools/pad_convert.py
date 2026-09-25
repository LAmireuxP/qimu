#!/usr/bin/env python3
"""把任意 AOSP 格式 bootanimation.zip 转为指定尺寸的无压缩版本：
- 帧按 cover 方式缩放（取较大的缩放比）居中裁切到目标尺寸——满屏无黑边、
  每颗像素都用上（原生分辨率），LANCZOS 高质量重采样 + PNG 无损保存
- desc.txt 首行改为「目标宽 目标高 <fps>」，保留原有段落定义
- 全部条目 ZIP_STORED（bootanimation 二进制硬性要求）
用法: python pad_convert.py <src.zip> <dst.zip> [name] [WxH]
  WxH 缺省 1440x3120（K60 Pro）；给别的机器用传各自屏幕尺寸，如 1080x2400
"""
import sys, os, io, zipfile
from PIL import Image

W, H = 1440, 3120
if len(sys.argv) > 4:
    W, H = (int(x) for x in sys.argv[4].lower().split('x', 1))


def parse_desc(raw):
    lines = [l.strip() for l in raw.replace('\r', '').split('\n')]
    lines = [l for l in lines if l]
    first = lines[0].split() if lines else []
    fps = first[2] if len(first) >= 3 else '30'
    parts = [l for l in lines[1:] if l and l[0] in ('p', 'c')]
    return fps, parts


def pad_frame(data, target_w=W, canvas=(W, H)):
    """cover 缩放 + 居中裁切到 canvas：满屏无黑边，像素最大化"""
    im = Image.open(io.BytesIO(data)).convert('RGB')
    cw, ch = canvas
    scale = max(cw / im.width, ch / im.height)
    nw, nh = max(cw, round(im.width * scale)), max(ch, round(im.height * scale))
    if (nw, nh) != (im.width, im.height):
        im = im.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - cw) // 2, (nh - ch) // 2
    return im.crop((left, top, left + cw, top + ch))


def encode_png(im):
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def convert(src, dst, name=''):
    with zipfile.ZipFile(src) as zin:
        desc = zin.read('desc.txt').decode('utf-8', 'ignore')
        fps, parts = parse_desc(desc)
        names = [n for n in zin.namelist() if n.strip()]
        frames = [n for n in names if n.lower().endswith(('.png', '.jpg', '.jpeg'))]
        dirs = [n for n in names if n.endswith('/')]
        with zipfile.ZipFile(dst, 'w', zipfile.ZIP_STORED) as zout:
            newdesc = '\n'.join([f'{W} {H} {fps}'] + parts) + '\n'
            zi = zipfile.ZipInfo('desc.txt'); zi.compress_type = zipfile.ZIP_STORED
            zout.writestr(zi, newdesc.encode())
            for d in dirs:
                zi = zipfile.ZipInfo(d); zi.compress_type = zipfile.ZIP_STORED
                zout.writestr(zi, b'')
            for n in frames:
                zi = zipfile.ZipInfo(n); zi.compress_type = zipfile.ZIP_STORED
                zout.writestr(zi, encode_png(pad_frame(zin.read(n))))
    print(f'{name or src}: {len(frames)} frames -> {os.path.getsize(dst)} bytes; desc={newdesc.strip()[:50]!r}')


if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else '')