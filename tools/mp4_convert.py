#!/usr/bin/env python3
"""把 MP4（任意常见视频）转成可刷入的开机动画包：
- 按目标帧率抽帧，cover 缩放裁切到目标分辨率（满屏无黑边），PNG 无损（或 --jpg 高质量）
- desc.txt 首行「目标宽 目标高 帧率」，段落保留源段定义的思路但视频只有一段：
  默认时长 <8s 整段循环（p 0，播到系统起来为止），>=8s 播一遍（p 1）；--loop/--once 可强制
- 视频里的音轨提取成 sound/poweron.mp3 一并放进包里（bootanimation 不播声音，
  但启幕导入时会自动把音频解出来留档，需要时可导出取用）
- 全部条目 ZIP_STORED（bootanimation 硬性要求）
用法: python mp4_convert.py <in.mp4> <out.zip> [--wxh 1080x2400] [--fps 30] [--loop|--once] [--jpg]
依赖: pip install imageio-ffmpeg pillow （imageio-ffmpeg 自带静态 ffmpeg，不用手动装）
"""
import argparse, os, re, shutil, subprocess, sys, tempfile, zipfile
from PIL import Image


def find_ffmpeg():
    p = shutil.which("ffmpeg")
    if p:
        return p
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        sys.exit("缺 ffmpeg：pip install imageio-ffmpeg（或自己装 ffmpeg 并加入 PATH）")


def probe(ff, src):
    """ffmpeg -i 的 stderr 里抠出视频尺寸/帧率/时长/有无音轨"""
    r = subprocess.run([ff, "-hide_banner", "-i", src], capture_output=True, text=True, encoding="utf-8", errors="ignore")
    err = r.stderr
    vline = next((l for l in err.splitlines() if ": Video:" in l), "")
    mw = re.search(r"(\d{2,5})x(\d{2,5})", vline)
    if not mw:
        sys.exit(f"读不出视频信息（不是视频文件？）：\n{err[-500:]}")
    w, h = int(mw.group(1)), int(mw.group(2))
    mf = re.search(r"([\d.]+)\s*fps", vline)
    src_fps = float(mf.group(1)) if mf else 30.0
    md = re.search(r"Duration:\s*(\d+):(\d+):([\d.]+)", err)
    dur = (int(md.group(1)) * 3600 + int(md.group(2)) * 60 + float(md.group(3))) if md else 0.0
    has_audio = ": Audio:" in err
    return w, h, src_fps, dur, has_audio


def main():
    ap = argparse.ArgumentParser(description="MP4 → 开机动画包（ZIP_STORED）")
    ap.add_argument("src", help="输入视频（mp4/mkv/mov/webm…ffmpeg 认的都行）")
    ap.add_argument("dst", help="输出动画包 zip")
    ap.add_argument("--wxh", default="1080x2400", help="目标分辨率，缺省 1080x2400")
    ap.add_argument("--fps", type=float, default=30, help="目标帧率上限，缺省 30（再高解码容易掉帧）")
    ap.add_argument("--loop", action="store_true", help="整段循环（p 0，播到系统启动完成）")
    ap.add_argument("--once", action="store_true", help="只播一遍（p 1）")
    ap.add_argument("--jpg", action="store_true", help="帧存 JPG（体积小解码快；缺省 PNG 无损）")
    args = ap.parse_args()

    ff = find_ffmpeg()
    W, H = (int(x) for x in args.wxh.lower().split("x", 1))

    sw, sh, src_fps, dur, has_audio = probe(ff, args.src)
    fps = min(max(1.0, src_fps or 30.0), max(1.0, args.fps))
    fps_i = max(1, round(fps))
    n_frames = int(dur * fps) if dur else 0
    loop = True if args.loop else (False if args.once else (dur > 0 and dur < 8.0))

    print(f"源: {sw}x{sh} {src_fps:.2f}fps {dur:.1f}s 音轨={'有' if has_audio else '无'}")
    print(f"目标: {W}x{H} {fps_i}fps  帧数≈{n_frames}  {'循环' if loop else '播一遍'}")

    if n_frames > 900:
        print(f"⚠ 这段视频会生成约 {n_frames} 帧，包会很大、开机动画播完要 {dur:.0f}s。"
              f"建议先用剪辑软件截短，或加 --fps 降低帧率。仍继续执行。")

    tmp = tempfile.mkdtemp(prefix="mp4anim_")
    try:
        # 抽帧：fps 过滤器统一节奏 + cover 缩放裁切（lanczos 高质量），与 pad_convert 同一几何语义
        vf = f"fps={fps},scale={W}:{H}:force_original_aspect_ratio=increase:flags=lanczos,crop={W}:{H}"
        ext, enc = ("jpg", ["-q:v", "2"]) if args.jpg else ("png", [])
        cmd = [ff, "-hide_banner", "-loglevel", "error", "-i", args.src,
               "-vf", vf, *enc, os.path.join(tmp, f"%05d.{ext}")]
        subprocess.run(cmd, check=True)
        frames = sorted(f for f in os.listdir(tmp) if f.endswith("." + ext))
        if not frames:
            sys.exit("一帧都没抽出来，检查视频文件")

        # 音轨 → sound/poweron.mp3（bootanimation 不播，导入时启幕会自动解出来留档）
        audio_name = ""
        if has_audio:
            a = os.path.join(tmp, "poweron.mp3")
            r = subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-i", args.src,
                                "-vn", "-acodec", "libmp3lame", "-q:a", "2", a], capture_output=True)
            if r.returncode == 0 and os.path.getsize(a) > 0:
                audio_name = f"sound/{a and 'poweron.mp3'}"
                os.makedirs(os.path.join(tmp, "sound"), exist_ok=True)
                shutil.move(a, os.path.join(tmp, "sound", "poweron.mp3"))
            else:  # 个别精简 build 没 mp3 编码器就退 aac
                a = os.path.join(tmp, "poweron.m4a")
                r = subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-i", args.src,
                                    "-vn", "-acodec", "aac", "-b:a", "192k", a], capture_output=True)
                if r.returncode == 0 and os.path.getsize(a) > 0:
                    audio_name = "sound/poweron.m4a"
                    os.makedirs(os.path.join(tmp, "sound"), exist_ok=True)
                    shutil.move(a, os.path.join(tmp, "sound", "poweron.m4a"))

        with zipfile.ZipFile(args.dst, "w", zipfile.ZIP_STORED) as z:
            zi = zipfile.ZipInfo("desc.txt")
            z.writestr(zi, f"{W} {H} {fps_i}\np {0 if loop else 1} 0 part0\n".encode())
            for f in frames:
                zi = zipfile.ZipInfo(f"part0/{f}")
                with open(os.path.join(tmp, f), "rb") as fh:
                    z.writestr(zi, fh.read())
            if audio_name:
                zi = zipfile.ZipInfo(audio_name)
                with open(os.path.join(tmp, audio_name), "rb") as fh:
                    z.writestr(zi, fh.read())

        print(f"完成: {args.dst}  {os.path.getsize(args.dst)} bytes, {len(frames)} 帧, 音轨={'已收入包内' if audio_name else '无'}")
        if dur and dur > 8 and loop is False:
            print("提示：包是「播一遍」，播完若系统还没起来会黑屏到进桌面；想一直播到进系统加 --loop")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
