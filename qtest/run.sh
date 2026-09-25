source "$(dirname "$0")/lib.sh"
pass=0; fail=0
ck() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok  %s\n' "$1";
  else fail=$((fail+1)); printf 'FAIL  %s | 期望[%s] 实际[%s]\n' "$1" "$2" "$3"; fi; }
Q="$PWD/qtest/dep2"; rm -rf "$Q"; mkdir -p "$Q"
LIB_DIR="$PWD/qtest/lib"; STAMP_FILE="$Q/stamp"; SELECTED_FILE="$Q/sel"
LOG_DIR="$Q/logs"; MANUAL_FILE="$Q/manual"; AUDIO_DIR="$Q/audio"
mkdir -p "$LOG_DIR" "$LIB_DIR" "$AUDIO_DIR"

# 每次运行都重建干净的库（幂等）
rm -f "$LIB_DIR"/*.zip; rm -rf "$AUDIO_DIR"
cp "$PWD/audio_test.zip" "$LIB_DIR/audio_test.zip"
python3 - "$LIB_DIR" <<'PY'
import zipfile, struct, zlib, sys
def png(w=108,h=240):
    def ch(t,d):
        c=t+d; return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
    ihdr=struct.pack('>IIBBBBB',w,h,8,2,0,0,0)
    raw=b''.join(b'\x00'+b'\x00\x00\x00'*w for _ in range(h))
    return b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',ihdr)+ch(b'IDAT',zlib.compress(raw,1))+ch(b'IEND',b'')
with zipfile.ZipFile(sys.argv[1]+'/plain.zip','w',zipfile.ZIP_STORED) as z:
    zi=zipfile.ZipInfo('desc.txt'); z.writestr(zi,b'1080 2400 30\np 1 0 part0\n')
    zi=zipfile.ZipInfo('part0/000.png'); z.writestr(zi,png())
PY

idx_of() { # idx_of 动画名 → 在 cmd_list 里的编号
  cmd_list | while IFS= read -r l; do
    case "$l" in *"$1"*) printf '%s\n' "${l%%$'\t'*}"; break ;; esac
  done | head -1
}

echo "== audio_extract =="
n=$(audio_extract "$LIB_DIR/audio_test.zip" audio_test)
ck "带音频包提取2个" "2" "$n"
ck "boot.ogg 落位" "yes" "$([ -f "$AUDIO_DIR/audio_test/boot.ogg" ] && echo yes)"
ck "嵌套 sound/poweron.mp3 落位" "yes" "$([ -f "$AUDIO_DIR/audio_test/sound/poweron.mp3" ] && echo yes)"
n=$(audio_extract "$LIB_DIR/plain.zip" plain)
ck "无音频包提取0" "0" "$n"
ck "空目录清掉" "no" "$([ -d "$AUDIO_DIR/plain" ] && echo yes || echo no)"
has_audio audio_test; ck "has_audio 真" "0" "$?"
has_audio plain;      ck "has_audio 假" "1" "$?"

echo "== cmd_audio（含老包补提取）=="
rm -rf "$AUDIO_DIR/audio_test"
out=$(cmd_audio "$(idx_of audio_test)")
ck "补提取 audio_n=2" "2" "$(echo "$out" | sed -n 's/^audio_n=//p')"
ck "FILE 列 boot.ogg" "yes" "$(echo "$out" | grep -q 'FILE=boot.ogg' && echo yes)"
ck "FILE 列嵌套 mp3" "yes" "$(echo "$out" | grep -q 'FILE=sound/poweron.mp3' && echo yes)"
out=$(cmd_audio "$(idx_of plain)")
ck "无音频 audio_n=0" "0" "$(echo "$out" | sed -n 's/^audio_n=//p')"

echo "== cmd_list ♪ =="
out=$(cmd_list)
ck "带音频行有♪" "yes" "$(echo "$out" | grep "audio_test" | grep -q '♪' && echo yes)"
ck "无音频行无♪" "yes" "$(echo "$out" | grep "plain" | grep -qv '♪' && echo yes)"

echo "== cmd_audioout（PC 上验证不了 /sdcard，跳过，真机测）=="
echo "== import OK 行 =="
rm -f "$LIB_DIR/audio_test.zip" "$LIB_DIR/audio_test-2.zip"
rm -rf "$AUDIO_DIR/audio_test" "$AUDIO_DIR/audio_test-2"
out=$(cmd_import "$LIB_DIR/audio_test.zip" 2>/dev/null)
[ -f "$LIB_DIR/audio_test.zip" ] || cp "$PWD/audio_test.zip" "$LIB_DIR/audio_test.zip"
out=$(cmd_import "$PWD/audio_test.zip")
ck "同名导入落 -2" "yes" "$([ -f "$LIB_DIR/audio_test-2.zip" ] && echo yes)"
ck "-2 包音频也收" "2" "$(audio_extract "$LIB_DIR/audio_test-2.zip" audio_test-2 2>/dev/null)"
rm -f "$LIB_DIR/audio_test.zip" "$LIB_DIR/audio_test-2.zip"
rm -rf "$AUDIO_DIR/audio_test" "$AUDIO_DIR/audio_test-2"
cp "$PWD/audio_test.zip" "$LIB_DIR/audio_test.zip"
out=$(cmd_import "$PWD/audio_test.zip")   # lib 里已有 → 落 -2
# 重新只留一份干净库再测标准导入
rm -f "$LIB_DIR"/*.zip; rm -rf "$AUDIO_DIR"
cp "$PWD/audio_test.zip" "$LIB_DIR/audio_test.zip"
rm -f "$LIB_DIR/audio_test.zip"
out=$(cmd_import "$PWD/audio_test.zip")
ck "OK 行含 audio=2" "yes" "$(echo "$out" | grep -q 'OK stored=audio_test.zip audio=2' && echo yes)"
ck "导入后音频在" "yes" "$([ -f "$AUDIO_DIR/audio_test/boot.ogg" ] && echo yes)"

echo "== cmd_delete 联动 =="
i=$(idx_of audio_test)
out=$(cmd_delete "$i")
ck "音频目录联动删" "no" "$([ -d "$AUDIO_DIR/audio_test" ] && echo yes || echo no)"
ck "zip 联动删" "no" "$([ -f "$LIB_DIR/audio_test.zip" ] && echo yes || echo no)"

echo; echo "通过 $pass / $((pass+fail))"
[ "$fail" -eq 0 ] && echo "ALL PASS" || exit 1
