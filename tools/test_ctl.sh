#!/system/bin/sh
# 启幕 ctl.sh 回归测试（沙箱）
#
#   PC（Git bash / Linux）:  sh tools/test_ctl.sh
#   Android:                 adb push tools/test_ctl.sh /data/local/tmp/
#                             adb shell su -c 'sh /data/local/tmp/test_ctl.sh'
#
# 全套用例都在沙箱里跑，不碰真实动画库和主题路径：
#   QIMU_LIB_DIR / QIMU_STATE_DIR / QIMU_LOG_DIR / QIMU_THEME_DIR / QIMU_GUARD_DIRS /
#   QIMU_LS_ROOTS 指到 $BASE 下，QIMU_NO_PROP=1 不写系统属性，QIMU_SCREEN 伪造屏幕尺寸。
# 测试包是内嵌的 base64（设备上没有 zip 命令，必须预先生成好再解码）。
# 退出码：0 = 全过；1 = 有用例失败（失败摘要打在最后）。

CR=$(printf '\r')
TAB=$(printf '\t')
NL='
'

# ---------- 沙箱目录 ----------
if [ -n "$QIMU_TEST_BASE" ]; then
  BASE=$QIMU_TEST_BASE
elif [ -d /data/adb ]; then
  BASE=/data/local/tmp/qtest
else
  BASE=${TMPDIR:-/tmp}/qtest
fi
SCREEN="1440 3200"                      # 伪装成 K60 Pro 的物理分辨率
FIX="$BASE/fix"
LIB="$BASE/lib"
STATE="$BASE/state"
THEME_DIR="$BASE/theme"
THEME="$THEME_DIR/bootanimation.zip"
GUARD_A="$BASE/pfd"
GUARD_B="$BASE/sd"
BROWSE="$BASE/browse"
PV="$BASE/preview"                      # 预览抽帧目录（不写进模块 webroot）

HERE=$(cd "$(dirname "$0")" && pwd -P)
CTL="$HERE/../bin/ctl.sh"
[ -f "$CTL" ] || { echo "找不到 $CTL"; exit 1; }

# 每次调用都把沙箱环境带上；ctl.sh 的目录变量全部支持环境变量覆盖
c() {
  QIMU_LIB_DIR="$LIB" \
  QIMU_STATE_DIR="$STATE" \
  QIMU_LOG_DIR="$BASE/logs" \
  QIMU_THEME_DIR="$THEME_DIR" \
  QIMU_GUARD_DIRS="$GUARD_A $GUARD_B" \
  QIMU_LS_ROOTS="$BROWSE /data/local/tmp" \
  QIMU_PREVIEW_DIR="$PV" \
  QIMU_NO_PROP=1 \
  QIMU_SCREEN="$SCREEN" \
  sh "$CTL" "$@"
}

# 预览抽帧上限要单独压的时候用（上限是环境变量，普通 c 固定用 24）
cpv() {
  QIMU_LIB_DIR="$LIB" \
  QIMU_STATE_DIR="$STATE" \
  QIMU_LOG_DIR="$BASE/logs" \
  QIMU_THEME_DIR="$THEME_DIR" \
  QIMU_GUARD_DIRS="$GUARD_A $GUARD_B" \
  QIMU_LS_ROOTS="$BROWSE /data/local/tmp" \
  QIMU_PREVIEW_DIR="$PV" \
  QIMU_PREVIEW_MAX="$1" \
  QIMU_NO_PROP=1 \
  QIMU_SCREEN="$SCREEN" \
  sh "$CTL" preview "$2"
}

# ---------- 断言 ----------
PASS=0; FAIL=0; FAILED=""
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED="$FAILED$NL  - $1"; printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$(cut_head "$2")"; }
cut_head() { printf '%s' "$1" | head -c 400 | tr '\n' '|'; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "输出里没有「$3」：<$2>" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "输出里不该出现「$3」：<$2>" ;; *) ok "$1" ;; esac; }
eq()    { [ "$2" = "$3" ] && ok "$1" || bad "$1" "期望[$3] 实际[$2]" ; }
ne()    { [ "$2" != "$3" ] && ok "$1" || bad "$1" "值和期望相同：[$2]" ; }
is_file(){ [ -f "$2" ] && ok "$1" || bad "$1" "文件不存在：$2" ; }
no_file(){ [ ! -e "$2" ] && ok "$1" || bad "$1" "文件还在：$2" ; }
sec()   { printf '\n== %s\n' "$*"; }

blen() { printf '%s' "$1" | wc -c | tr -d ' '; }
# 合法 UTF-8 检查：走位检查（续字节 0x80-0xBF 的个数必须和首字节声明的一致）
is_utf8() {
  printf '%s' "$1" | od -An -tu1 -v | awk '
    { for (i = 1; i <= NF; i++) { b = $i
        if (need > 0) { if (b < 128 || b > 191) bad = 1; need-- }
        else if (b < 128) { }
        else if (b >= 194 && b <= 223) need = 1
        else if (b >= 224 && b <= 239) need = 2
        else if (b >= 240 && b <= 244) need = 3
        else bad = 1 } }
    END { exit ((bad || need > 0) ? 1 : 0) }'
}
mt() { stat -c %i "$1" 2>/dev/null || stat -f %i "$1" 2>/dev/null; }   # inode：判断有没有重拷

idx_of() {                              # 按名字查列表编号（编号会随排序变，测试里一律现查）
  c list | while IFS=$TAB read -r io_i io_n io_rest; do
    if [ "$io_n" = "$1" ]; then printf '%s' "$io_i"; break; fi
  done
}
desc_line_of() { c desc "$1" | sed -n 's/^desc_line=//p'; }
desc_trim_of() { desc_line_of "$1" | sed 's/ *$//'; }   # 等长改写会补尾随空格
unz() { unzip -p "$1" "$2" 2>/dev/null; }
md5_of() { md5sum | awk '{print $1}'; }

# ---------- 内嵌测试包 ----------
TRAP_FRAME_MD5=7f06ce0edb8bf791cae7487731838335
FIX_good='UEsDBBQAAAAAAAAAIVBHeSSCGQAAABkAAAAIAAAAZGVzYy50eHQxMDgwIDI0MDAgMzAKcCAxIDAgcGFydDAKUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDEucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAyLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMy5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsBAhQAFAAAAAAAAAAhUEd5JIIZAAAAGQAAAAgAAAAAAAAAAAAAAIABAAAAAGRlc2MudHh0UEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABPwAAAHBhcnQwLzAwMDAxLnBuZ1BLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAa8AAABwYXJ0MC8wMDAwMi5wbmdQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAEfAQAAcGFydDAvMDAwMDMucG5nUEsFBgAAAAAEAAQA7QAAAI8BAAAAAA=='
FIX_small='UEsDBBQAAAAAAAAAIVDXqLKCGAAAABgAAAAIAAAAZGVzYy50eHQ3MjAgMTYwMCAzMApwIDEgMCBwYXJ0MApQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMS5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDIucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAzLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwECFAAUAAAAAAAAACFQ16iyghgAAAAYAAAACAAAAAAAAAAAAAAAgAEAAAAAZGVzYy50eHRQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAE+AAAAcGFydDAvMDAwMDEucG5nUEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABrgAAAHBhcnQwLzAwMDAyLnBuZ1BLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAR4BAABwYXJ0MC8wMDAwMy5wbmdQSwUGAAAAAAQABADtAAAAjgEAAAAA'
FIX_gstyle='UEsDBBQAAAAAAAAAIVAr4CtaHwAAAB8AAAAIAAAAZGVzYy50eHRnIDEwODAgMjQwMCAwIDAgMzAKcCAxIDAgcGFydDAKUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDEucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAyLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMy5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsBAhQAFAAAAAAAAAAhUCvgK1ofAAAAHwAAAAgAAAAAAAAAAAAAAIABAAAAAGRlc2MudHh0UEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABRQAAAHBhcnQwLzAwMDAxLnBuZ1BLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAbUAAABwYXJ0MC8wMDAwMi5wbmdQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAElAQAAcGFydDAvMDAwMDMucG5nUEsFBgAAAAAEAAQA7QAAAJUBAAAAAA=='
FIX_module='UEsDBBQAAAAAAAAAIVD8RMrgRQAAAEUAAAALAAAAbW9kdWxlLnByb3BpZD10ZXN0YW5pbQpuYW1lPVRlc3QKdmVyc2lvbj0xCnZlcnNpb25Db2RlPTEKYXV0aG9yPXgKZGVzY3JpcHRpb249eApQSwMEFAAAAAAAAAAhUKauW5iSAgAAkgIAAB4AAABzeXN0ZW0vbWVkaWEvYm9vdGFuaW1hdGlvbi56aXBQSwMEFAAAAAAAAAAhUEd5JIIZAAAAGQAAAAgAAABkZXNjLnR4dDEwODAgMjQwMCAzMApwIDEgMCBwYXJ0MApQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMS5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDIucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAzLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwECFAAUAAAAAAAAACFQR3kkghkAAAAZAAAACAAAAAAAAAAAAAAAgAEAAAAAZGVzYy50eHRQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAE/AAAAcGFydDAvMDAwMDEucG5nUEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABrwAAAHBhcnQwLzAwMDAyLnBuZ1BLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAR8BAABwYXJ0MC8wMDAwMy5wbmdQSwUGAAAAAAQABADtAAAAjwEAAAAAUEsBAhQAFAAAAAAAAAAhUPxEyuBFAAAARQAAAAsAAAAAAAAAAAAAAIABAAAAAG1vZHVsZS5wcm9wUEsBAhQAFAAAAAAAAAAhUKauW5iSAgAAkgIAAB4AAAAAAAAAAAAAAIABbgAAAHN5c3RlbS9tZWRpYS9ib290YW5pbWF0aW9uLnppcFBLBQYAAAAAAgACAIUAAAA8AwAAAAA='
FIX_deflate='UEsDBBQAAAAAAAAAIVBHeSSCGQAAABkAAAAIAAAAZGVzYy50eHQxMDgwIDI0MDAgMzAKcCAxIDAgcGFydDAKUEsDBBQAAAAIAAAAIVB7kHQsOwAAAEMAAAAPAAAAcGFydDAvMDAwMDEucG5n6wzwc+flkuJiYGDg9fRwCQLSjCDMwQYk5UWPdIIlXBxDKuYkJzAwMAFlHynuMQaKMni6+rmsc0poAgBQSwECFAAUAAAAAAAAACFQR3kkghkAAAAZAAAACAAAAAAAAAAAAAAAgAEAAAAAZGVzYy50eHRQSwECFAAUAAAACAAAACFQe5B0LDsAAABDAAAADwAAAAAAAAAAAAAAgAE/AAAAcGFydDAvMDAwMDEucG5nUEsFBgAAAAACAAIAcwAAAKcAAAAAAA=='
FIX_descdeflated='UEsDBBQAAAAIAAAAIVBHeSSCGwAAABkAAAAIAAAAZGVzYy50eHQzNLAwUDAyMTBQMDbgKlAwVDBQKEgsKjHgAgBQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMS5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsBAhQAFAAAAAgAAAAhUEd5JIIbAAAAGQAAAAgAAAAAAAAAAAAAAIABAAAAAGRlc2MudHh0UEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABQQAAAHBhcnQwLzAwMDAxLnBuZ1BLBQYAAAAAAgACAHMAAACxAAAAAAA='
FIX_baddesc='UEsDBBQAAAAAAAAAIVDF9oExGAAAABgAAAAIAAAAZGVzYy50eHRoZWxsbyB3b3JsZApwIDEgMCBwYXJ0MApQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMS5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDIucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAzLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwECFAAUAAAAAAAAACFQxfaBMRgAAAAYAAAACAAAAAAAAAAAAAAAgAEAAAAAZGVzYy50eHRQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAE+AAAAcGFydDAvMDAwMDEucG5nUEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABrgAAAHBhcnQwLzAwMDAyLnBuZ1BLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAR4BAABwYXJ0MC8wMDAwMy5wbmdQSwUGAAAAAAQABADtAAAAjgEAAAAA'
FIX_noframes='UEsDBBQAAAAAAAAAIVBHeSSCGQAAABkAAAAIAAAAZGVzYy50eHQxMDgwIDI0MDAgMzAKcCAxIDAgcGFydDAKUEsBAhQAFAAAAAAAAAAhUEd5JIIZAAAAGQAAAAgAAAAAAAAAAAAAAIABAAAAAGRlc2MudHh0UEsFBgAAAAABAAEANgAAAD8AAAAAAA=='
FIX_bom='UEsDBBQAAAAAAAAAIVBzUhaUHAAAABwAAAAIAAAAZGVzYy50eHTvu78xMDgwIDI0MDAgMzAKcCAxIDAgcGFydDAKUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDEucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAyLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMy5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsBAhQAFAAAAAAAAAAhUHNSFpQcAAAAHAAAAAgAAAAAAAAAAAAAAIABAAAAAGRlc2MudHh0UEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABQgAAAHBhcnQwLzAwMDAxLnBuZ1BLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAbIAAABwYXJ0MC8wMDAwMi5wbmdQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAEiAQAAcGFydDAvMDAwMDMucG5nUEsFBgAAAAAEAAQA7QAAAJIBAAAAAA=='
FIX_part0desc='UEsDBBQAAAAAAAAAIVBHeSSCGQAAABkAAAAOAAAAcGFydDAvZGVzYy50eHQxMDgwIDI0MDAgMzAKcCAxIDAgcGFydDAKUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDEucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAyLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMy5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsBAhQAFAAAAAAAAAAhUEd5JIIZAAAAGQAAAA4AAAAAAAAAAAAAAIABAAAAAHBhcnQwL2Rlc2MudHh0UEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABRQAAAHBhcnQwLzAwMDAxLnBuZ1BLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAbUAAABwYXJ0MC8wMDAwMi5wbmdQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAElAQAAcGFydDAvMDAwMDMucG5nUEsFBgAAAAAEAAQA8wAAAJUBAAAAAA=='
FIX_trap='UEsDBBQAAAAAAAAAIVA66qjyUAAAAFAAAAAPAAAAcGFydDAvMDAwMDEucG5nMTA4MCAyNDAwIDMwColQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwMEFAAAAAAAAAAhUEd5JIIZAAAAGQAAAAgAAABkZXNjLnR4dDEwODAgMjQwMCAzMApwIDEgMCBwYXJ0MApQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMi5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsBAhQAFAAAAAAAAAAhUDrqqPJQAAAAUAAAAA8AAAAAAAAAAAAAAIABAAAAAHBhcnQwLzAwMDAxLnBuZ1BLAQIUABQAAAAAAAAAIVBHeSSCGQAAABkAAAAIAAAAAAAAAAAAAACAAX0AAABkZXNjLnR4dFBLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAbwAAABwYXJ0MC8wMDAwMi5wbmdQSwUGAAAAAAMAAwCwAAAALAEAAAAA'
FIX_moduleroot='UEsDBBQAAAAAALOLaV38RMrgRQAAAEUAAAALAAAAbW9kdWxlLnByb3BpZD10ZXN0YW5pbQpuYW1lPVRlc3QKdmVyc2lvbj0xCnZlcnNpb25Db2RlPTEKYXV0aG9yPXgKZGVzY3JpcHRpb249eApQSwMEFAAAAAAAs4tpXaauW5iSAgAAkgIAABEAAABib290YW5pbWF0aW9uLnppcFBLAwQUAAAAAAAAACFQR3kkghkAAAAZAAAACAAAAGRlc2MudHh0MTA4MCAyNDAwIDMwCnAgMSAwIHBhcnQwClBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAxLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MC8wMDAwMi5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDMucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAQIUABQAAAAAAAAAIVBHeSSCGQAAABkAAAAIAAAAAAAAAAAAAACAAQAAAABkZXNjLnR4dFBLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAT8AAABwYXJ0MC8wMDAwMS5wbmdQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAGvAAAAcGFydDAvMDAwMDIucG5nUEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABHwEAAHBhcnQwLzAwMDAzLnBuZ1BLBQYAAAAABAAEAO0AAACPAQAAAABQSwECFAAUAAAAAACzi2ld/ETK4EUAAABFAAAACwAAAAAAAAAAAAAAgAEAAAAAbW9kdWxlLnByb3BQSwECFAAUAAAAAACzi2ldpq5bmJICAACSAgAAEQAAAAAAAAAAAAAAgAFuAAAAYm9vdGFuaW1hdGlvbi56aXBQSwUGAAAAAAIAAgB4AAAALwMAAAAA'
FIX_badpart='UEsDBBQAAAAAAAAAIVAGSD+bGQAAABkAAAAIAAAAZGVzYy50eHQxMDgwIDI0MDAgMzAKcCAxIDAgcGFydDEKUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDEucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAyLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwECFAAUAAAAAAAAACFQBkg/mxkAAAAZAAAACAAAAAAAAAAAAAAAgAEAAAAAZGVzYy50eHRQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAE/AAAAcGFydDAvMDAwMDEucG5nUEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABrwAAAHBhcnQwLzAwMDAyLnBuZ1BLBQYAAAAAAwADALAAAAAfAQAAAAA='
FIX_multi='UEsDBBQAAAAAAAAAIVD44R8eJQAAACUAAAAIAAAAZGVzYy50eHQxMDgwIDI0MDAgMzAKcCAxIDAgcGFydDAKYyAyIDEgcGFydDEKUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDAucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAHBhcnQwLzAwMDAxLnBuZ4lQTkcNChoKAAAADUlIRFIAAAABAAAAAQgGAAAAHxXEiQAAAA1JREFUeJxjYAAAAgABAOIhvDMAAAAASUVORK5CYIJQSwMEFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAABwYXJ0MS8wMDAwMC5wbmeJUE5HDQoaCgAAAA1JSERSAAAAAQAAAAEIBgAAAB8VxIkAAAANSURBVHicY2AAAAIAAQDiIbwzAAAAAElFTkSuQmCCUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDEvMDAwMDEucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAQIUABQAAAAAAAAAIVD44R8eJQAAACUAAAAIAAAAAAAAAAAAAACAAQAAAABkZXNjLnR4dFBLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAUsAAABwYXJ0MC8wMDAwMC5wbmdQSwECFAAUAAAAAAAAACFQe5B0LEMAAABDAAAADwAAAAAAAAAAAAAAgAG7AAAAcGFydDAvMDAwMDEucG5nUEsBAhQAFAAAAAAAAAAhUHuQdCxDAAAAQwAAAA8AAAAAAAAAAAAAAIABKwEAAHBhcnQxLzAwMDAwLnBuZ1BLAQIUABQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAAAAAAAAAAACAAZsBAABwYXJ0MS8wMDAwMS5wbmdQSwUGAAAAAAUABQAqAQAACwIAAAAA'
TRUNC_B64='UEsDBBQAAAAAAAAAIVBHeSSCGQAAABkAAAAIAAAAZGVzYy50eHQxMDgwIDI0MDAgMzAKcCAxIDAgcGFydDAKUEsDBBQAAAAAAAAAIVB7kHQsQwAAAEMAAAAPAAAAcGFydDAvMDAwMDEucG5niVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgAAACAAEA4iG8MwAAAABJRU5ErkJgglBLAwQU'

write_fixtures() {
  mkdir -p "$FIX" || { echo "无法创建 $FIX"; exit 1; }
  dec() { printf '%s' "$1" | base64 -d >"$FIX/$2" 2>/dev/null; }
  dec "$FIX_good" good.zip
  dec "$FIX_small" small.zip
  dec "$FIX_gstyle" gstyle.zip
  dec "$FIX_module" module.zip
  dec "$FIX_moduleroot" moduleroot.zip
  dec "$FIX_deflate" deflate.zip
  dec "$FIX_descdeflated" descdeflated.zip
  dec "$FIX_baddesc" baddesc.zip
  dec "$FIX_noframes" noframes.zip
  dec "$FIX_bom" bom.zip
  dec "$FIX_part0desc" part0desc.zip
  dec "$FIX_trap" trap.zip
  dec "$FIX_badpart" badpart.zip
  dec "$FIX_multi" multi.zip
  dec "$TRUNC_B64" trunc.zip
  : >"$FIX/empty.zip"
}

# ---------- 开始 ----------
printf '启幕 ctl.sh 测试\n  脚本: %s\n  沙箱: %s\n  屏幕: %s\n' "$CTL" "$BASE" "$SCREEN"
rm -rf "$BASE"
mkdir -p "$LIB" "$STATE" "$BASE/logs" "$THEME_DIR" "$GUARD_A" "$GUARD_B" "$BROWSE/sub" "$FIX"
write_fixtures

sec "0 测试包自身可用"
has "good.zip 能列目录" "$(unzip -l "$FIX/good.zip" 2>&1)" "desc.txt"
eq  "屏幕钩子生效" "$(c status | sed -n 's/^screen=//p')" "1440x3200"

sec "1 空库状态"
o=$(c status)
has "count=0" "$o" "count=0"
has "theme_ok=no" "$o" "theme_ok=no"
has "noanim=no" "$o" "noanim=no"
has "active=无" "$o" "active=无"
eq  "空库 list 无输出" "$(c list)" ""
has "info 带 ##LIST" "$(c info)" "##LIST"
has "空库 select 报错" "$(c select 1)" "ERROR 找不到该动画"
o=$(c 2>&1); rc=$?
eq  "无参数退出码 64" "$rc" "64"
has "无参数打用法" "$o" "用法:"

sec "2 导入与校验"
o=$(c import "$FIX/good.zip")
has "裸包导入成功" "$o" "OK stored=good.zip"
is_file "库文件已落盘" "$LIB/good.zip"
eq  "导入时自动适配到屏幕" "$(desc_line_of "$(idx_of good)")" "1440 3200 30"

o=$(c import "$FIX/small.zip")
has "720x1600 也能导入" "$o" "OK stored=small.zip"
eq  "适配串放不下时 desc 不动" "$(desc_line_of "$(idx_of small)")" "720 1600 30"

o=$(c import "$FIX/gstyle.zip")
has "g 写法包导入成功" "$o" "OK stored=gstyle.zip"
eq  "g 写法归一化 + 适配" "$(desc_trim_of "$(idx_of gstyle)")" "1440 3200 30"

o=$(c import "$FIX/module.zip")
has "模块壳包解出内层" "$o" "OK stored=module.zip"
eq  "内层 desc 也已适配" "$(desc_line_of "$(idx_of module)")" "1440 3200 30"

o=$(c import "$FIX/moduleroot.zip")
has "内层包在根目录的模块壳也能导入" "$o" "OK stored=moduleroot.zip"
eq  "根目录内层 desc 也已适配" "$(desc_line_of "$(idx_of moduleroot)")" "1440 3200 30"

has "带压缩的帧被拒" "$(c import "$FIX/deflate.zip")" "必须是 ZIP_STORED"
has "desc.txt 被压缩也被拒" "$(c import "$FIX/descdeflated.zip")" "zip 根目录缺少 desc.txt"
has "首行不是宽高帧率被拒" "$(c import "$FIX/baddesc.zip")" "首行不是「宽 高 帧率」格式"
has "只有 desc 没有帧被拒" "$(c import "$FIX/noframes.zip")" "包里没有帧图片"
has "BOM 被拒" "$(c import "$FIX/bom.zip")" "BOM"
has "空文件被拒" "$(c import "$FIX/empty.zip")" "文件不存在或为空"
has "part0/desc.txt 不算根目录" "$(c import "$FIX/part0desc.zip")" "根目录缺少 desc.txt"
has "desc 段落目录不存在被拒" "$(c import "$FIX/badpart.zip")" "段落目录不存在或没有帧"
has "截断包被拒" "$(c import "$FIX/trunc.zip")" "ERROR "
has "不存在的文件报错" "$(c import "$FIX/nope.zip")" "ERROR 找不到文件"
has "未指定文件报错" "$(c import)" "ERROR 未指定文件"

o=$(c import "$FIX/trap.zip")
has "陷阱包导入成功" "$o" "OK stored=trap.zip"
eq  "desc 已被适配" "$(desc_line_of "$(idx_of trap)")" "1440 3200 30"
eq  "帧里的同名字节没被改写" "$(unz "$LIB/trap.zip" part0/00001.png | md5_of)" "$TRAP_FRAME_MD5"

o=$(c import "$FIX/good.zip")
has "同名再导入自动加序号" "$o" "OK stored=good-2.zip"
o=$(c import "$FIX/good.zip" "自定义名")
has "第二参数指定动画名" "$o" "OK stored=自定义名.zip"
is_file "指定名文件已落盘" "$LIB/自定义名.zip"

sec "3 列表与状态"
o=$(c list)
has "列表含 good" "$o" "$TAB""good$TAB"
has "列表显示适配后的分辨率" "$o" "1440×3200 · 30fps"
has "列表显示 small 原分辨率" "$o" "720×1600 · 30fps"
eq  "列表编号从 1 开始" "$(printf '%s' "$o" | head -1 | cut -f1)" "1"
eq  "动画数量" "$(c status | sed -n 's/^count=//p')" "8"
has "desc 越界报错" "$(c desc 999)" "ERROR 找不到该动画"
has "desc 非数字报错" "$(c desc abc)" "ERROR"
o=$(c desc "$(idx_of good)")
has "desc 报 mode=auto" "$o" "mode=auto"
has "desc 报屏幕" "$o" "screen=1440x3200"
has "desc 报帧数" "$o" "frames=3"
has "desc 报时长" "$o" "dur=0.1s"

sec "4 应用与部署"
i=$(idx_of good)
o=$(c select "$i")
has "应用成功" "$o" "OK selected=good"
is_file "主题文件已写入" "$THEME"
eq  "主题文件大小与库一致" "$(wc -c <"$THEME" | tr -d ' ')" "$(wc -c <"$LIB/good.zip" | tr -d ' ')"
is_file "stamp 已落盘" "$STATE/deployed.stamp"
has "状态 theme_ok=yes" "$(c status)" "theme_ok=yes"
has "状态 noanim=no" "$(c status)" "noanim=no"
ino1=$(mt "$THEME")
c select "$i" >/dev/null
eq  "重复应用走快路径（不重拷）" "$(mt "$THEME")" "$ino1"

sec "5 分辨率"
o=$(c setres "$i" 1440 3000)
has "setres 成功" "$o" "OK setres=good to=1440x3000"
has "setres 后自动重新部署" "$o" "redeployed"
eq  "主题文件跟着更新" "$(unz "$THEME" desc.txt | sed -n 1p)" "1440 3000 30"
ne  "重新部署换了文件（不是旧副本）" "$(mt "$THEME")" "$ino1"
o=$(c desc "$i")
has "setres 记成手动" "$o" "mode=manual"
has "desc 改成 3000" "$o" "desc_h=3000"
has "setres 非法宽报错" "$(c setres "$i" 99 3000)" "超出合理范围"
has "setres 非数字报错" "$(c setres "$i" abc 3000)" "宽必须是数字"
has "setres 位数太长报错" "$(c setres "$i" 100000 3000)" "位数太长"
o=$(c fit "$i")
has "自适应恢复" "$o" "OK fitted=good to=1440x3200"
has "自适应后回到 auto" "$(c desc "$i")" "mode=auto"
o=$(c swap "$i")
has "交换宽高" "$o" "to=3200x1440"
eq  "交换后 desc 首行" "$(desc_line_of "$i")" "3200 1440 30"
has "换回来" "$(c swap "$i")" "to=1440x3200"
has "更长的串写不进去" "$(c setres "$i" 10000 10000)" "新分辨率串比原来的长"
has "720x1600 适配失败" "$(c fit "$(idx_of small)")" "ERROR 适配失败"
eq  "失败后 small 的 desc 没坏" "$(desc_line_of "$(idx_of small)")" "720 1600 30"

sec "6 改名"
LONG=$(awk 'BEGIN { s = ""; for (i = 0; i < 70; i++) s = s "长"; print s }')
i=$(idx_of good)
o=$(c rename "$i" "$LONG")
has "改名成功" "$o" "OK renamed="
NEW=${o#*renamed=}
eq  "长名截到 180 字节" "$(blen "$NEW")" "180"
is_utf8 "$NEW" && ok "截断后仍是合法 UTF-8" || bad "截断后不是合法 UTF-8"
is_file "改名后的文件存在" "$LIB/$NEW.zip"
eq  "选择记录跟着改名" "$(cat "$STATE/selected.txt")" "$NEW"
has "列表里是新名字" "$(c list)" "$TAB""$NEW$TAB"
ne  "改名后主题仍是当前动画" "$(c status | sed -n 's/^theme_ok=//p')" "no"

i=$(idx_of "$NEW")
o=$(c rename "$i" 'a/b*c?d[e]f|g\h')
eq  "特殊字符被替换成下划线" "$o" "OK renamed=a_b_c_d_e_f_g_h"
no_file "没有在库外创建文件" "$BASE/lib/a"

i=$(idx_of a_b_c_d_e_f_g_h)
is_file "特殊字符改名后的文件存在" "$LIB/a_b_c_d_e_f_g_h.zip"
has "重名报错" "$(c rename "$i" trap)" "ERROR 已有同名动画"
has "点开头报错" "$(c rename "$i" .hidden)" "不能以点开头"
has "空名报错" "$(c rename "$i" '')" "ERROR 名字不能为空"
has "改名编号非法报错" "$(c rename 999 x)" "ERROR 找不到该动画"

sec "7 排序 / 删除 / 重置"
A=a_b_c_d_e_f_g_h
B=trap
c order "$A" "$B" >/dev/null
eq  "order 生效（第一条）" "$(c list | head -1 | cut -f2)" "$A"
eq  "order 生效（第二条）" "$(c list | sed -n 2p | cut -f2)" "$B"
i=$(idx_of "$A"); o=$(c rename "$i" "改过的名字")
has "改名成功" "$o" "OK renamed=改过的名字"
eq  "order.txt 跟着改名" "$(sed -n 1p "$STATE/order.txt")" "改过的名字"
has "order 忽略不存在的名字" "$(c order "$B" 不存在的包 改过的名字)" "OK order=updated"
eq  "order 只剩真实存在的" "$(wc -l <"$STATE/order.txt" | tr -d ' ')" "2"
has "删正在用的动画被拒" "$(c delete "$(idx_of 改过的名字)")" "正在使用中"
has "删非当前动画成功" "$(c delete "$(idx_of "$B")")" "OK deleted=trap"
no_file "文件已删除" "$LIB/trap.zip"
hasnt "order 里也清掉了" "$(cat "$STATE/order.txt")" "trap"
o=$(c reset)
has "重置为第一个" "$o" "OK selected="
is_file "重置后主题文件存在" "$THEME"

sec "8 守卫 / 清理 / 同步"
o=$(c guard)
has "装守卫" "$o" "OK guard installed"
is_file "post-fs-data.d 里的守卫" "$GUARD_A/qimu-guard.sh"
is_file "service.d 里的守卫" "$GUARD_B/qimu-guard.sh"
[ -x "$GUARD_A/qimu-guard.sh" ] && ok "守卫可执行" || bad "守卫没有执行位"
has "守卫用 resetprop -n" "$(cat "$GUARD_A/qimu-guard.sh")" "resetprop -n"
has "状态 guard_count=2" "$(c status)" "guard_count=2"
has "卸守卫" "$(c unguard)" "OK guard removed"
no_file "守卫已删除" "$GUARD_A/qimu-guard.sh"
has "状态 guard_count=0" "$(c status)" "guard_count=0"

: >"$LIB/.import.999.tmp"; touch -t 202001010000 "$LIB/.import.999.tmp"
: >"$LIB/.unwrap.999.tmp"
o=$(c gc)
has "gc 有输出" "$o" "OK gc="
no_file "6 小时前的残留被清" "$LIB/.import.999.tmp"
is_file "新残留保留" "$LIB/.unwrap.999.tmp"
rm -f "$LIB/.unwrap.999.tmp"

o=$(c sync)
has "sync 成功" "$o" "OK synced"
is_file "sync 后主题文件在" "$THEME"

cur=$(c status | sed -n 's/^active=//p')
rm -f "$LIB/$cur.zip"
o=$(c deploy); rc=$?
eq  "库文件失踪时 deploy 返回失败" "$rc" "1"
no_file "库文件失踪时清掉主题文件" "$THEME"
has "状态 theme_ok=no" "$(c status)" "theme_ok=no"
c reset >/dev/null
is_file "reset 后重新写入主题" "$THEME"

sec "9 目录浏览"
cp "$FIX/good.zip" "$BROWSE/动画.zip"
: >"$BROWSE/片子.mp4"
: >"$BROWSE/readme.txt"
o=$(c ls "$BROWSE")
has "列目录含子目录" "$o" "D$TAB""sub$TAB$BROWSE/sub"
has "列目录含 zip" "$o" "F$TAB""动画.zip"
has "列目录含视频" "$o" "V$TAB""片子.mp4"
hasnt "普通文件不列" "$o" "readme.txt"
eq  "目录排在文件前" "$(printf '%s' "$o" | head -1 | cut -f1)" "D"
has "末尾斜杠等价" "$(c ls "$BROWSE/")" "F$TAB""动画.zip"
has "非白名单路径被拒" "$(c ls /etc)" "ERROR 这个路径不让浏览"
has "路径穿越被拒" "$(c ls "$BROWSE/../../..")" "ERROR"
has "不存在的目录报错" "$(c ls "$BROWSE/nope")" "ERROR 没有这个目录"

sec "10 不播放动画"
cp "$FIX/good.zip" "$LIB/不播放动画.zip"
i=$(idx_of 不播放动画)
o=$(c select "$i")
has "选中不播放动画" "$o" "OK selected=不播放动画"
has "状态 noanim=yes" "$(c status)" "noanim=yes"
has "属性被置 1" "$(cat "$BASE/logs/ctl.log")" "nobootanimation=1"
o=$(c select "$(idx_of good-2)")
has "切回正常动画" "$o" "OK selected="
has "状态 noanim=no" "$(c status)" "noanim=no"

sec "11 体检 / 导出"
eq  "status 的 lib_size 等于实际总占用" \
    "$(c status | sed -n 's/^lib_size=//p')" \
    "$(wc -c "$LIB"/*.zip | awk 'END{print $1}')"

o=$(c check)
has "全库体检通过" "$o" "bad=0"
eq  "体检点数等于库内数量" \
    "$(printf '%s' "$o" | sed -n 's/^OK checked=\([0-9]*\) bad=.*/\1/p')" \
    "$(c status | sed -n 's/^count=//p')"

# 把库里的包改坏一个字节（干掉 PK 魔数），体检必须点名，而不是静默通过
cp "$FIX/good.zip" "$LIB/坏掉的.zip"
printf 'XX' | dd of="$LIB/坏掉的.zip" bs=1 count=2 conv=notrunc 2>/dev/null
o=$(c check)
has "坏包被点出来" "$o" "BAD$TAB""坏掉的"
has "体检统计坏包数" "$o" "bad=1"
has "体检同时报仍属正常" "$o" "checked="
rm -f "$LIB/坏掉的.zip"
has "清掉坏包后恢复" "$(c check)" "bad=0"

EXPORT="$BASE/export"
mkdir -p "$EXPORT"
i=$(idx_of small)
o=$(c export "$i" "$EXPORT")
has "导出到目录" "$o" "OK exported=$EXPORT/small.zip"
is_file "导出文件已落盘" "$EXPORT/small.zip"
eq  "导出大小与库里一致" \
    "$(wc -c <"$EXPORT/small.zip" | tr -d ' ')" \
    "$(wc -c <"$LIB/small.zip" | tr -d ' ')"
has "导出可指定完整文件名" "$(c export "$i" "$EXPORT/给别人的.zip")" "OK exported=$EXPORT/给别人的.zip"
is_file "自定名导出落盘" "$EXPORT/给别人的.zip"
has "导出到不存在目录报错" "$(c export "$i" "$BASE/nope/")" "ERROR 目录不存在"
has "导出编号非法报错" "$(c export 999 "$EXPORT")" "ERROR 找不到该动画"
has "导出未指定文件报错" "$(c export)" "ERROR 用法"

sec "17 预览抽帧"
i=$(idx_of small)
o=$(c preview "$i")
has "预览给出清单" "$o" "OK preview=small"
has "清单带分辨率" "$o" "w=720"
has "清单带帧率" "$o" "fps=30"
has "帧数没超上限时 stride=1" "$o" "stride=1"
eq  "三帧全抽出" "$(printf '%s' "$o" | sed -n 's/^frames=//p')" "3"
has "清单里有帧文件名" "$o" "img=f1.png"
has "清单里有段落" "$o" "seg=p,1,0,1,3"
is_file "抽出来的帧落盘" "$PV/f1.png"
eq  "抽帧目录里就是清单那些文件" "$(ls "$PV" | wc -l | tr -d ' ')" "3"
eq  "抽出来的帧和包里一致" \
    "$(md5sum <"$PV/f1.png" | awk '{print $1}')" \
    "$(unz "$LIB/small.zip" part0/00001.png | md5sum | awk '{print $1}')"

# 抽帧上限压到 1：普通包必须按 stride 跳帧，且上一轮的帧要被清掉（不能混进旧画面）
o=$(cpv 1 "$i")
has "抽帧上限生效" "$o" "stride=3"
has "上限 1 时只留一帧" "$o" "frames=1"
eq  "上一轮的帧已清掉" "$(ls "$PV" | wc -l | tr -d ' ')" "1"

# 两段动画：p 段 + c 段（带循环与停顿），段边界和帧号要能对上
c import "$FIX/multi.zip" >/dev/null
i=$(idx_of multi)
o=$(c preview "$i")
has "p 段进清单" "$o" "seg=p,1,0,1,2"
has "c 段带循环与停顿" "$o" "seg=c,2,1,3,2"
eq  "两段共四帧" "$(printf '%s' "$o" | sed -n 's/^frames=//p')" "4"

has "关面板清帧" "$(c previewclean)" "OK cleaned"
no_file "清完帧文件没了" "$PV/f1.png"

c preview "$i" >/dev/null
has "gc 回收预览目录" "$(c gc)" "OK gc="
no_file "gc 后抽帧目录没了" "$PV/f1.png"

has "预览编号非法报错" "$(c preview 999)" "ERROR 找不到该动画"
has "预览缺参数报用法" "$(c preview)" "ERROR 用法"
has "预览非数字报用法" "$(c preview abc)" "ERROR 用法"

cp "$FIX/noframes.zip" "$LIB/空帧.zip"
i=$(idx_of 空帧)
has "没有帧的包预览报错" "$(c preview "$i")" "ERROR 这个包没有可预览的帧"
rm -f "$LIB/空帧.zip"

sec "结果"
printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf '失败用例：%s\n' "$FAILED"
  printf '\n最近的日志（%s）：\n' "$BASE/logs/ctl.log"
  tail -n 20 "$BASE/logs/ctl.log" 2>/dev/null
  exit 1
fi
echo "全部通过"
