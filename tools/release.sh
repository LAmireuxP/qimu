#!/usr/bin/env bash
# 打包某版本 Release zip。用法: release.sh <commit> <version>
# 在对应 commit 的代码树上打包，文件强制 LF、脚本 0755、module.prop/webroot 0644，
# 外层用 ZIP_DEFLATED（只是分发用，不影响模块内动画的 STORED 要求）。
# 生成的 zip 放回仓库的 release/ 目录（不进 git 跟踪）。
set -e
commit="$1"; ver="$2"
[ -n "$commit" ] && [ -n "$ver" ] || { echo "用法: $0 <commit> <version>"; exit 1; }
repo="$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git archive "$commit" | tar -x -C "$work"
cd "$work"
python3 - "$ver" <<'PYEOF'
import zipfile, os, glob, sys
ver = sys.argv[1]
files = ['module.prop','post-fs-data.sh','service.sh','uninstall.sh','customize.sh','bin/ctl.sh','webroot/index.html']
files += sorted(glob.glob('animations/*.zip'))
TEXT = ('.sh','.prop','.html','.md','.txt')
os.makedirs('release', exist_ok=True)
path = f'release/qimu-{ver}.zip'
with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if not os.path.isfile(f): continue
        data = open(f,'rb').read()
        if f.endswith(TEXT): data = data.replace(b'\r\n',b'\n')
        zi = zipfile.ZipInfo(f)
        zi.external_attr = (0o755 if f.endswith('.sh') else 0o644) << 16
        z.writestr(zi, data, compress_type=zipfile.ZIP_DEFLATED)
    z.writestr('var/logs/.keep','')
    z.writestr('var/state/.keep','')
print(path, os.path.getsize(path))
PYEOF
# 复制回仓库的 release 目录
mkdir -p "$repo/release"
cp -f "release/qimu-${ver}.zip" "$repo/release/qimu-${ver}.zip"
echo "$repo/release/qimu-${ver}.zip"
