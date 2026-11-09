#!/usr/bin/env python3
"""打模块包：把仓库内容 + META-INF 打成可以直接在 KernelSU / Magisk 里刷的 zip。
用法: python tools/pack.py [--out release]
产物: release/qimu-<version>-<versionCode>.zip
"""
import argparse, os, pathlib, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# 模块里要带的东西。tools/ 是电脑端的辅助脚本，不进包；README 也不进。
PAYLOAD = ["module.prop", "customize.sh", "post-fs-data.sh", "service.sh", "uninstall.sh",
           "LICENSE", "bin", "webroot", "animations"]
EXEC = {"customize.sh", "post-fs-data.sh", "service.sh", "uninstall.sh", "bin/ctl.sh",
        "META-INF/com/google/android/update-binary"}

# Magisk 官方模板的安装器：KernelSU / SukiSU / APatch 也都认这套
UPDATE_BINARY = """#!/sbin/sh
umask 022
OUTFD=$2
ZIPFILE=$3
mount /data 2>/dev/null
[ -f /data/adb/magisk/util_functions.sh ] && . /data/adb/magisk/util_functions.sh
install_module
exit 0
"""
UPDATER_SCRIPT = "#MAGISK\n"


def read_prop(p):
    props = {}
    for line in (ROOT / p).read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    return props


def collect():
    items = []
    for name in PAYLOAD:
        p = ROOT / name
        if not p.exists():
            sys.exit(f"缺文件：{p}")
        if p.is_dir():
            for f in sorted(p.rglob("*")):
                if f.is_file():
                    items.append((f.relative_to(ROOT).as_posix(), f))
        else:
            items.append((name, p))
    return items


def main():
    ap = argparse.ArgumentParser(description="启幕模块打包")
    ap.add_argument("--out", default="release", help="输出目录，缺省 release/")
    args = ap.parse_args()

    props = read_prop("module.prop")
    ver, code = props.get("version", "0.0.0"), props.get("versionCode", "0")
    outdir = ROOT / args.out
    outdir.mkdir(parents=True, exist_ok=True)
    dst = outdir / f"qimu-{ver}-{code}.zip"

    items = collect()
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, path in items:
            zi = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            # 嵌套的动画包/图片已经是压缩过的，再 deflate 只是白花时间
            zi.compress_type = zipfile.ZIP_STORED if path.suffix.lower() in (".zip", ".png", ".jpg", ".webp") else zipfile.ZIP_DEFLATED
            zi.external_attr = (0o755 if name in EXEC else 0o644) << 16
            z.writestr(zi, path.read_bytes(), compress_type=zi.compress_type)
        for name, data in (("META-INF/com/google/android/update-binary", UPDATE_BINARY),
                           ("META-INF/com/google/android/updater-script", UPDATER_SCRIPT)):
            zi = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            zi.external_attr = (0o755 if name in EXEC else 0o644) << 16
            z.writestr(zi, data, compress_type=zipfile.ZIP_DEFLATED)

    print(f"完成: {dst}  {dst.stat().st_size} bytes, {len(items) + 2} 个条目")
    print(f"版本: {ver} ({code})")


if __name__ == "__main__":
    main()
