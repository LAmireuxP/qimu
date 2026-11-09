#!/system/bin/sh
# 开机动画管理器 - 控制脚本
# 用法: ctl.sh {list|status|info|select N|fit N|desc N|setres N W H|swap N|rename N 名字|import PATH|export N 路径|delete N|ls DIR|reset|order NAME...|guard|unguard|deploy|check|sync|gc}
#
# 几处踩过坑的地方，改的时候注意：
#   - 动画库列表每次运行只枚举一次，order.txt 一次读进来用纯 shell 比较，
#     别对每个文件 fork 一次 grep
#   - 校验压缩方式用「读 zip 本地文件头的压缩方法字节 + grep 方法名兜底」，
#     不要解析 unzip -v 的列：不同机型 unzip 实现不一样（Info-ZIP / toybox）
#   - 别用 ${var%%|*} 这种带 | 的参数展开，Android 的 mksh 会把模式里的 | 当“或”运算符
#   - 部署带 stamp，开机时 stamp 和大小都对得上就直接跳过，不再每次算 md5
#   - 改 desc.txt 只能等长原地覆盖：设备上没有任何能重建 zip 的工具（没有 zip 命令），
#     长度不够就返回「写不进去」，别想着把后面的数据整体挪一段——那会把中央目录里的
#     所有本地头偏移全部写错，bootanimation 直接打不开包

# MODDIR 从 $0 反推。别假设 $0 一定带 /bin/ 前缀：直接在模块目录里跑 `sh bin/ctl.sh`
# 时 $0 是相对路径，老的 ``${MODDIR%/bin}`` 会得到空串，state/log 全写到 /var 下去。
case "$0" in
  */*) MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd -P) ;;
  *)   MODDIR=$(pwd -P 2>/dev/null) ;;
esac
[ -n "$MODDIR" ] || MODDIR=/data/adb/modules/custom_bootanimation
MODDIR=${MODDIR%/bin}
# 目录可用环境变量覆盖：tools/test_ctl.sh 靠它在 /data/local/tmp 下跑全套用例，默认值不变
LIB_DIR=${QIMU_LIB_DIR:-/data/adb/bootanims}
STATE_DIR=${QIMU_STATE_DIR:-$MODDIR/var/state}
LOG_DIR=${QIMU_LOG_DIR:-$MODDIR/var/logs}
SELECTED_FILE="$STATE_DIR/selected.txt"
THEME_DIR=${QIMU_THEME_DIR:-/data/system/theme/boots}
# 「选择文件」能翻的目录白名单；tools/test_ctl.sh 用 QIMU_LS_ROOTS 指到沙箱
LS_ROOTS=${QIMU_LS_ROOTS:-"/sdcard /storage /mnt/media_rw /data/local/tmp"}
THEME_FILE="$THEME_DIR/bootanimation.zip"
STAMP_FILE="$STATE_DIR/deployed.stamp"
SCREEN_CACHE_FILE="$STATE_DIR/screen.txt"
# desc 信息缓存（每行「名字/宽/高/帧率/大小」），让 cmd_list 免掉「每行 fork 一次 unzip」。
# 新鲜度：名字集合变了（改名/删除/导入）由 cmd_list 的内容比对自动收敛；
# 唯独 desc_replace 是等长改写、文件大小不变，只能靠它自己主动删缓存。
DESC_CACHE="$STATE_DIR/desc.cache"
NO_ANIM_NAME="不播放动画"
ORDER_FILE="$STATE_DIR/order.txt"
# 手动分辨率名单：在界面/命令里 setres、swap 设过的动画记在这里，
# 部署/导入时的自动适配跳过它们（否则一部署就被「适配到屏幕」覆盖回去，手动调的等于白调）
MANUAL_FILE="$STATE_DIR/manual.txt"

# fit_zip 算好后把「目标宽 高」放这里，供 cmd_fit 汇报用
FIT_TW=""; FIT_TH=""
# desc_replace 改写成功就置 1，部署据此判断「desc 变过了，必须重拷生效文件」
FIT_WROTE=""

mkdir -p "$LIB_DIR" "$STATE_DIR" "$LOG_DIR" 2>/dev/null

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_DIR/ctl.log" 2>/dev/null; }

# ---------- 工具（参数展开，不派生子进程） ----------
# 设备上 fork+exec 很贵（一次 5-15ms），info/部署这类每次操作要跑几十条命令的路径
# 能用参数展开解决的都不开子进程；只有 unzip/wm/grep/dd 这种必须调外部命令的才 fork
CR=$(printf '\r'); TAB=$(printf '\t')
# 换行符用源码里的字面量（省一次 fork）——后面纯 shell 拆行/查表都拿它当分隔符
NL='
'

# 去掉行尾空格。desc.txt 的原地改写只能等长覆盖，新串比旧串短时用空格补齐，
# 所以重新读出来的首行可能带一串尾随空格（例：「1440 3200 30      」）。
# 比较「已经是不是目标值」必须先 trim，否则每次部署都以为还要改一遍，
# 白白清掉 stamp、把几十兆的主题文件重拷一次。
trim_tail() { tt="$1"; while [ "${tt% }" != "$tt" ]; do tt=${tt% }; done; printf '%s' "$tt"; }

# 取不带 .zip 的动画名
name_of() { n=${1##*/}; printf '%s\n' "${n%.zip}"; }
file_size() {
  fs_s=$(wc -c <"$1" 2>/dev/null) || { echo ""; return 0; }
  set -- $fs_s                                   # 按空白拆分，替代 tr -d ' '
  echo "${1:-}"
}

# 数一个包的帧数：输入是 `unzip -l` 的整段输出，结果放 FRAMES（不 fork、不 echo）。
# 判据只看条目名最后一列有没有「目录/xxx.(png|jpg|jpeg|webp)」——unzip -l 的列宽因实现而异，
# 只有「最后一列是路径」这一点各家一致（Info-ZIP 和 toybox 都是）。
count_frames() {
  cf_n=0; cf_rest="$1$NL"
  while [ -n "$cf_rest" ]; do
    cf_l=${cf_rest%%"$NL"*}; [ "$cf_l" = "$cf_rest" ] && cf_rest="" || cf_rest=${cf_rest#"$cf_l"$NL}
    case "${cf_l##* }" in
      */*.png|*/*.PNG|*/*.jpg|*/*.JPG|*/*.jpeg|*/*.JPEG|*/*.webp|*/*.WEBP) cf_n=$((cf_n + 1)) ;;
    esac
  done
  FRAMES=$cf_n
}

# 清理会被列表/模式匹配弄坏的名字（导入、改名时调用）
# 注意：字符类 [*?[\]|\\] 在标准 sed 下会被解析成「多字符序列」而完全匹配不上（实测是哑弹，
#      一个字符都不替换）。所以这里逐个字符替换。另外 / 不能被保留——它会让名字越出动画库
#      目录（rename 传 ../x 就会写到 /data/adb/bootanims 外），一并换成 _
sanitize_name() {
  sn=$(printf '%s' "$1" | tr -d '\t\r\n' \
    | sed 's/\*/_/g; s/?/_/g; s/\[/_/g; s/\]/_/g; s/|/_/g; s/\\/_/g; s|/|_|g')
  utf8_clip "$sn" 180
}

# 按 UTF-8 字符边界截断到最多 $2 字节。
# 为什么要专门写这个：toybox 的 cut -c 实际按字节切（-c 和 -b 一个实现），一个汉字 3 字节，
# 切在第 60 字节就会得到半个汉字——文件名变成非法 UTF-8，列表经 WebView 显示再回传时
# 对不上原名，之后改名/删除/应用全部失败，而且用户看不出原因。
# 判据：切点后一个字节如果是续字节（0x80-0xBF），说明正好把一个字符劈开了，往回退一个字节。
utf8_clip() {
  uc_s="$1"; uc_max="$2"
  uc_n=$(printf '%s' "$uc_s" | wc -c) || uc_n=0
  set -- $uc_n; uc_n=${1:-0}
  [ "$uc_n" -gt "$uc_max" ] || { printf '%s' "$uc_s"; return 0; }
  uc_len=$uc_max
  while [ "$uc_len" -gt 0 ]; do
    uc_b=$(printf '%s' "$uc_s" | dd bs=1 skip="$uc_len" count=1 2>/dev/null | od -An -tu1)
    set -- $uc_b
    uc_b=${1:-256}
    if [ "$uc_b" -ge 128 ] && [ "$uc_b" -lt 192 ]; then uc_len=$((uc_len - 1)); else break; fi
  done
  printf '%s' "$uc_s" | cut -b1-"$uc_len"
}

# 设置系统属性。post-fs-data 阶段（本模块 post-fs-data.sh 会走 deploy）用 setprop 会与 init
# 互等死锁——KernelSU / Magisk 官方文档都明令「post-fs-data 用 setprop 会死锁，请改用
# resetprop -n」。所以优先 resetprop -n（直写属性区、不经 init）；老环境没有 resetprop 才退回 setprop。
nb_setprop() {
  if [ "$QIMU_NO_PROP" = "1" ]; then log "setprop(skip) $1=$2"; return 0; fi
  if command -v resetprop >/dev/null 2>&1; then
    resetprop -n "$1" "$2" 2>/dev/null && return 0
  fi
  setprop "$1" "$2" 2>/dev/null
  return 0
}

# ---------- 校验 ----------
# 注意：不要用 ${var%%|*} / ${var#*|} 这类带 | 的参数展开 ——
# Android 的 mksh 会把模式里的 | 当作"或"运算符，得到与 bash 不同的结果。
VALID_MSG=""
validate_zip() {
  vf="$1"; VALID_MSG=""
  [ -s "$vf" ] || { VALID_MSG="文件不存在或为空"; return 1; }
  # 一次 dd+od 读前 4 字节：PK\x03\x04 本地文件头魔数
  v_hdr=$(dd if="$vf" bs=1 count=4 2>/dev/null | od -An -tx1 2>/dev/null)
  set -- $v_hdr
  [ "$1" = "50" ] && [ "$2" = "4b" ] && [ "$3" = "03" ] && [ "$4" = "04" ] \
    || { VALID_MSG="不是有效的 zip 文件"; return 1; }

  # 根目录要有 desc.txt，且它自己必须是 STORED。用本地文件头定位（desc_data），
  # 不再用 `unzip -l | grep desc.txt`——那样 part0/desc.txt 也算数，而且有多个 desc.txt
  # 时根本不知道拿到的是哪个。顺带拿到数据区偏移，BOM 检查省一次 unzip。
  v_region=$(desc_data "$vf") || { VALID_MSG="zip 根目录缺少 desc.txt"; return 1; }
  set -- $v_region; v_off=$1; v_len=$2
  [ "$v_len" -gt 0 ] || { VALID_MSG="desc.txt 是空的"; return 1; }

  # desc_data 找的是「本地文件头 + 名字 desc.txt」，而嵌套包（模块壳里的
  # bootanimation.zip）内部同样有这个头——只按头判断会把内层 desc.txt 当成外层的。
  # 所以再用条目表确认根目录真的有 desc.txt；没有 unzip 时退回只信 desc_data。
  if command -v unzip >/dev/null 2>&1; then
    v_root=$(zip_root_entry "$vf" desc.txt)
    [ -n "$v_root" ] || { VALID_MSG="zip 根目录缺少 desc.txt"; return 1; }
  fi

  # desc.txt 带 UTF-8 BOM（Windows 记事本常见）会让 bootanimation 解析首行失败 → 黑屏。
  # BOM 在等长覆盖下去不掉（去掉 3 字节就得重建 zip），只能在这里明确拒绝
  v_bom=$(dd if="$vf" bs=1 skip="$v_off" count=3 2>/dev/null | od -An -tx1 2>/dev/null)
  set -- $v_bom
  [ "$1" = "ef" ] && [ "$2" = "bb" ] && [ "$3" = "bf" ] \
    && { VALID_MSG="desc.txt 带 UTF-8 BOM，会导致开机黑屏——请用无 BOM 的 UTF-8 重新保存"; return 1; }

  command -v unzip >/dev/null 2>&1 || return 0

  # 首行必须解析得出宽高。desc 格式不对的包以前能导进来，刷进去就是黑屏，
  # 用户在导入这一步就该看到原因，而不是重启后对着一块黑屏猜
  v_line=$(desc_line "$vf")
  parse_desc_line "$v_line" \
    || { VALID_MSG="desc.txt 首行不是「宽 高 帧率」格式"; return 1; }

  # 一帧都没有的包（只有 desc.txt）必然黑屏，导入阶段就拦掉
  v_list=$(unzip -l "$vf" 2>/dev/null)
  count_frames "$v_list"; v_frames=$FRAMES
  [ "$v_frames" -gt 0 ] || { VALID_MSG="包里没有帧图片（只有 desc.txt，开机会黑屏）"; return 1; }

  # 段落校验：desc 里每个 p/c 段引用的目录必须真实存在、且至少有一帧。
  # 以前只数「整包有没有图片」——desc 写 `p 1 0 part1` 而帧在 part0 里，校验照样过，
  # 刷进去就是一段黑屏。这是从网上下载的包里最常见的坏法之一，导入阶段就该拦住。
  v_desc=$(unzip -p "$vf" desc.txt 2>/dev/null)
  v_badpart=""; v_seen_first=0
  while IFS= read -r v_dl || [ -n "$v_dl" ]; do
    v_dl=${v_dl%"$CR"}
    [ "$v_seen_first" = "1" ] || { v_seen_first=1; continue; }   # 首行是宽高，不是段落
    set -- $v_dl
    case "${1:-}" in
      p|c|P|C)
        v_dir=""
        case "$#" in
          4) v_dir=$4 ;;                 # p 1 0 part0
          3) v_dir=$3 ;;                 # 少数包省掉 pause 字段
        esac
        [ -n "$v_dir" ] || continue
        v_dir=${v_dir%/}
        v_hit=0
        v_rest2="$v_list$NL"
        while [ -n "$v_rest2" ]; do
          v_l2=${v_rest2%%"$NL"*}; [ "$v_l2" = "$v_rest2" ] && v_rest2="" || v_rest2=${v_rest2#"$v_l2"$NL}
          case "${v_l2##* }" in
            "$v_dir"/*.png|"$v_dir"/*.PNG|"$v_dir"/*.jpg|"$v_dir"/*.JPG|\
            "$v_dir"/*.jpeg|"$v_dir"/*.JPEG|"$v_dir"/*.webp|"$v_dir"/*.WEBP) v_hit=1; break ;;
          esac
        done
        [ "$v_hit" = "1" ] || v_badpart="$v_badpart $v_dir"
        ;;
    esac
  done <<DESC_IN
$v_desc
DESC_IN
  [ -z "$v_badpart" ] || { VALID_MSG="desc 里的段落目录不存在或没有帧：$v_badpart（开机会黑屏）"; return 1; }

  # 兜底全量检查：若该 unzip 的 -v 会打印方法名，出现压缩方法名即拒绝（覆盖混合压缩包）
  if unzip -v "$vf" 2>/dev/null | grep -qE 'Defl|DefN|BZip2|LZMA|Zstd'; then
    VALID_MSG="动画必须是 ZIP_STORED 无压缩格式"
    return 1
  fi
  return 0
}

# ---------- desc.txt 首行改写 ----------
# 归一化与分辨率适配都落在 desc.txt 的第一个有效行上，而且都只能「等长原地覆盖」——
# 设备上没有能重建 zip 的工具（toybox/busybox 都没有 zip 子命令），新内容不能比原行长。
# 副作用：CRC 与实际内容对不上，但 bootanim 读 STORED 条目是直接 memcpy、不校验 CRC，
# 照常播放（真机验证过）。原地改过要清掉 stamp，否则大小没变、部署会以为「已是最新」。
# 定位 desc.txt 的数据区，输出「偏移 长度」，失败返回 1。
# 为什么不直接 grep 整个包找那行文字：帧是 PNG/JPG，像素数据里完全可能碰巧出现同样的
# 字节串，先匹配到就写进图片里，包直接坏掉（CRC 也对不上）。这里只认「PK\x03\x04 +
# 压缩方法 0 + 名字恰好是 desc.txt」的本地文件头，之后的读写都限定在它自己的数据区。
desc_data() {
  dd_f="$1"
  dd_hits=$(grep -abo 'desc\.txt' "$dd_f" 2>/dev/null)
  [ -n "$dd_hits" ] || return 1
  dd_rest="$dd_hits$NL"
  while [ -n "$dd_rest" ]; do
    dd_l=${dd_rest%%"$NL"*}; [ "$dd_l" = "$dd_rest" ] && dd_rest="" || dd_rest=${dd_rest#"$dd_l"$NL}
    dd_pos=${dd_l%%:*}
    dd_base=$((dd_pos - 30))
    [ "$dd_base" -ge 0 ] || continue
    dd_sig=$(dd if="$dd_f" bs=1 skip="$dd_base" count=4 2>/dev/null | od -An -tx1)
    set -- $dd_sig
    [ "$1" = "50" ] && [ "$2" = "4b" ] && [ "$3" = "03" ] && [ "$4" = "04" ] || continue
    # 本地文件头 8..31 共 24 字节：8-9 压缩方法、18-21 压缩后长度、26-27 名字长度、
    # 28-29 扩展区长度，全部小端。
    # 拆字段必须用 awk：POSIX sh 的 $19 会被读成「$1 跟字面量 9」（>9 的位置参数要写 ${19}），
    # 拼出来的 "09" 进 $(( )) 还会被 bash/dash 当八进制 → 整个偏移算错（真机 mksh 同样会错）。
    dd_m=$(dd if="$dd_f" bs=1 skip=$((dd_base + 8)) count=24 2>/dev/null \
      | od -An -tu1 -v \
      | awk '{ for (i = 1; i <= NF; i++) b[n++] = $i }
             END { if (n < 24) exit 1
                   printf "%d %d %d %d\n", b[0] + b[1] * 256, b[18] + b[19] * 256,
                          b[20] + b[21] * 256, b[10] + b[11] * 256 + b[12] * 65536 + b[13] * 16777216 }')
    [ -n "$dd_m" ] || continue
    set -- $dd_m; dd_meth=$1; dd_nl=$2; dd_el=$3; dd_len=$4
    [ "$dd_meth" = "0" ] || continue                    # desc.txt 自己必须是 STORED
    dd_name=$(dd if="$dd_f" bs=1 skip="$dd_pos" count=8 2>/dev/null)
    [ "$dd_name" = "desc.txt" ] || continue
    [ "$dd_len" -gt 0 ] || continue
    printf '%s %s\n' $((dd_base + 30 + dd_nl + dd_el)) "$dd_len"
    return 0
  done
  return 1
}

# desc.txt 的第一个有效行（跳过空行和 # 注释）。只 fork 一次 unzip，行筛选用纯 shell：
# 返回的行保持原样（仅去 \r），因为 desc_replace 要拿它在 zip 里做逐字节定位
desc_line() {
  unzip -p "$1" desc.txt 2>/dev/null | while :; do
    l=""
    IFS= read -r l || [ -n "$l" ] || break      # 最后一行没有换行符也不能丢
    dl_t=${l%"$CR"}
    dl_c=$dl_t
    while :; do                                 # 判断用的副本去行首空白；返回的行不动
      case "$dl_c" in
        ' '*) dl_c=${dl_c#' '} ;;
        "$TAB"*) dl_c=${dl_c#"$TAB"} ;;
        *) break ;;
      esac
    done
    case "$dl_c" in ''|'#'*) continue ;; esac
    printf '%s\n' "$dl_t"
    break
  done
}

# 解析 desc 首行，兼容两种写法：
#   标准：  宽 高 帧率
#   小米：  g 宽 高 偏移x 偏移y 帧率
# 成功设 D_W / D_H / D_FPS（帧率缺省按 30），g 写法另设 D_G=1；解析不了 return 1
parse_desc_line() {
  D_W=""; D_H=""; D_FPS=""; D_G=""
  set -- $1
  case "$1" in
    g) D_G=1; D_W=$2; D_H=$3; D_FPS=$6 ;;
    *) D_W=$1; D_H=$2; D_FPS=$3 ;;
  esac
  case "$D_W" in ''|*[!0-9]*) return 1 ;; esac
  case "$D_H" in ''|*[!0-9]*) return 1 ;; esac
  case "$D_FPS" in ''|*[!0-9]*) D_FPS=30 ;; esac
  return 0
}

# 把 desc.txt 里的 old 这一行原地换成 new。返回 0=已改 1=出错 2=new 更长、改不了
desc_replace() {
  dr_f="$1"; dr_old="$2"; dr_new="$3"
  # 值已经就是目标值（旧串只是被上一次等长改写补了尾随空格）→ 不写、不动 stamp
  [ "$(trim_tail "$dr_old")" = "$dr_new" ] && return 0
  dr_pad=$(( ${#dr_old} - ${#dr_new} ))
  [ "$dr_pad" -ge 0 ] || return 2
  dr_repl=$(printf "%s%*s" "$dr_new" "$dr_pad" "")
  dr_region=$(desc_data "$dr_f") || return 1
  set -- $dr_region; dr_off=$1; dr_len=$2
  # 只在 desc 数据区里找这一行；grep 输出相对偏移，加回数据区起点才是文件内绝对偏移
  dr_hit=$(dd if="$dr_f" bs=1 skip="$dr_off" count="$dr_len" 2>/dev/null \
    | grep -aboF -e "$dr_old" 2>/dev/null | head -1)
  [ -n "$dr_hit" ] || return 1
  dr_at=$(( dr_off + ${dr_hit%%:*} ))
  if printf '%s' "$dr_repl" | dd of="$dr_f" bs=1 seek="$dr_at" conv=notrunc 2>/dev/null; then
    FIT_WROTE=1                                  # 标记 desc 被改写过，部署据此决定必须重拷
    rm -f "$STAMP_FILE" "$DESC_CACHE" 2>/dev/null  # desc 等长改写大小不变，缓存只能这样失效
    return 0
  fi
  return 1
}

# ---------- 手动分辨率名单 ----------
# setres/swap 设过的动画记在 manual.txt，部署/导入的自动适配跳过它们——
# 不然给正在使用的动画手动设的分辨率一部署就被「适配到屏幕」覆盖回去。
# 点「自适应屏幕」（cmd_fit）会把名字移出名单，恢复自动适配。
manual_has() {
  [ -s "$MANUAL_FILE" ] || return 1
  mn_has=0
  while IFS= read -r mn_l || [ -n "$mn_l" ]; do
    [ "${mn_l%"$CR"}" = "$1" ] && { mn_has=1; break; }
  done <"$MANUAL_FILE"
  [ "$mn_has" -eq 1 ]
}
manual_add() {
  manual_has "$1" && return 0
  printf '%s\n' "$1" >>"$MANUAL_FILE" 2>/dev/null
  log "manual res: $1"
}
manual_del() {
  [ -f "$MANUAL_FILE" ] || return 0
  mn_tmp="$STATE_DIR/.manual.$$.tmp"
  : >"$mn_tmp" 2>/dev/null || return 0
  while IFS= read -r mn_l || [ -n "$mn_l" ]; do
    mn_l=${mn_l%"$CR"}
    [ -n "$mn_l" ] || continue
    [ "$mn_l" = "$1" ] && continue
    printf '%s\n' "$mn_l" >>"$mn_tmp"
  done <"$MANUAL_FILE"
  mv -f "$mn_tmp" "$MANUAL_FILE" 2>/dev/null || rm -f "$mn_tmp"
}

# 在 order.txt 里把 $1 换成 $2；$2 传空就是删掉这条（改名/删除后清理）。
# 不清理也不会出错（entry_paths 会跳过不存在的文件），但 order.txt 会越攒越长，
# 删掉再导入同名动画时还会被塞回旧位置，用户看着像「排序自己乱了」。
order_map() {
  [ -s "$ORDER_FILE" ] || return 0
  om_tmp="$STATE_DIR/.order.$$.tmp"
  : >"$om_tmp" 2>/dev/null || return 0
  while IFS= read -r om_l || [ -n "$om_l" ]; do
    om_l=${om_l%"$CR"}
    [ -n "$om_l" ] || continue
    if [ "$om_l" = "$1" ]; then
      [ -n "$2" ] && printf '%s\n' "$2" >>"$om_tmp"
    else
      printf '%s\n' "$om_l" >>"$om_tmp"
    fi
  done <"$ORDER_FILE"
  mv -f "$om_tmp" "$ORDER_FILE" 2>/dev/null || rm -f "$om_tmp"
  return 0
}

# 本机屏幕物理分辨率（输出「宽 高」；读不到就输出空）。只 fork 一次 wm，行解析用纯 shell。
# 读到就写进 screen.txt 缓存：post-fs-data 阶段 window 服务还没起来，wm 一定失败，这时
# 退回上次的值——否则升级后第一次开机没法适配分辨率，动画带着黑边播一整个开机过程。
# 默认先看缓存、缓存有就不调 wm：app_process 启动一次要几百毫秒，开机关键路径上不值得花。
# 需要确认真实值的地方（service.sh 的 sync、界面操作）把 SCREEN_FRESH 置 1。
SCREEN_MEM=""; SCREEN_TRIED=""; SCREEN_FRESH=""
screen_wh() {
  if [ -n "$SCREEN_TRIED" ]; then
    [ -n "$SCREEN_MEM" ] && printf '%s\n' "$SCREEN_MEM"
    return 0
  fi
  SCREEN_TRIED=1
  if [ -n "$QIMU_SCREEN" ]; then                          # 测试钩子：不依赖 wm
    SCREEN_MEM="$QIMU_SCREEN"; printf '%s\n' "$SCREEN_MEM"; return 0
  fi
  # 缓存
  scr_cached=""
  if [ -s "$SCREEN_CACHE_FILE" ]; then
    sc_l=""; IFS= read -r sc_l <"$SCREEN_CACHE_FILE" 2>/dev/null
    sc_l=${sc_l%"$CR"}
    set -- $sc_l
    case "${1:-}" in ''|*[!0-9]*) ;; *) case "${2:-}" in ''|*[!0-9]*) ;; *) scr_cached="$1 $2" ;; esac ;; esac
  fi
  if [ -z "$scr_cached" ] || [ "$SCREEN_FRESH" = "1" ]; then
    scr_raw=$(wm size 2>/dev/null) || scr_raw=""
    scr_line=""
    if [ -n "$scr_raw" ]; then
      while IFS= read -r scr_l || [ -n "$scr_l" ]; do   # 取 Physical size 行（Override 行不要）
        scr_l=${scr_l%"$CR"}
        case "$scr_l" in
          *Physical*size*) scr_line=$scr_l; break ;;
        esac
      done <<SCR_IN
$scr_raw
SCR_IN
    fi
    if [ -n "$scr_line" ]; then
      scr_line=${scr_line#*:}                    # 去掉 "Physical size" 前缀
      while :; do
        case "$scr_line" in ' '*) scr_line=${scr_line#' '} ;; *) break ;; esac
      done
      scr_w=${scr_line%x*}; scr_h=${scr_line#*x}
      case "$scr_w" in ''|*[!0-9]*) scr_w="" ;; esac
      case "$scr_h" in ''|*[!0-9]*) scr_h="" ;; esac
      if [ -n "$scr_w" ] && [ -n "$scr_h" ]; then
        SCREEN_MEM="$scr_w $scr_h"
        printf '%s\n' "$SCREEN_MEM" >"$SCREEN_CACHE_FILE" 2>/dev/null
        printf '%s\n' "$SCREEN_MEM"
        return 0
      fi
    fi
  fi
  SCREEN_MEM="$scr_cached"
  [ -n "$SCREEN_MEM" ] && printf '%s\n' "$SCREEN_MEM"
  return 0
}

# 小米系动画的 desc.txt 首行常写成 `g 宽 高 偏移x 偏移y 帧率`，AOSP 的 bootanimation
# 不认这行，会直接放弃解析 → 开机黑屏。改成标准的 `宽 高 帧率`。
normalize_zip() {
  nz="$1"; [ -f "$nz" ] || return 1
  line=$(desc_line "$nz"); [ -n "$line" ] || return 1
  parse_desc_line "$line" || return 1
  [ -n "$D_G" ] || return 0                       # 不是 g 写法，多半已经是标准写法
  new="$D_W $D_H $D_FPS"
  desc_replace "$nz" "$line" "$new" || return 1
  log "normalized desc.txt: $line -> $new ($nz)"
  return 0
}

# 适配本机分辨率：desc 首行声明的宽高就是 bootanimation 实际渲染的尺寸——比屏幕小 →
# 四周黑边，比屏幕大 → 被裁掉一圈。改成屏幕物理分辨率（帧率保留）就能满屏。
#
# 关键：保留源动画的方向。wm size 在某些机型/ROM 上会按当前旋转或「长边优先」返回，
# 屏幕读到的宽高方向未必和物理竖屏一致。若源动画是竖屏(sw<sh)而屏幕读到横屏(cw>ch)，
# 直接写 cw×ch 就会把竖屏动画塞进横屏尺寸 → 出现「长宽互换」。所以方向相反时先把
# 屏幕宽高对调再写，保证写进去的方向和源动画一致。
fit_zip() {
  fz="$1"; [ -f "$fz" ] || return 1
  if manual_has "$(name_of "$fz")"; then return 0; fi   # 手动设定过的，自动适配不碰
  line=$(desc_line "$fz"); [ -n "$line" ] || return 1
  parse_desc_line "$line" || return 1              # g 写法这里也能解析，写入时顺带归一化
  wh=$(screen_wh)
  if [ -z "$wh" ]; then
    # 读不到屏幕就没法适配；但 g 写法必须归一化掉，否则开机会黑屏
    normalize_zip "$fz" >/dev/null 2>&1
    return 1
  fi
  cw=${wh%% *}; ch=${wh##* }
  # 方向相反 → 对调屏幕宽高，避免长宽互换
  if [ "$D_W" -lt "$D_H" ] && [ "$cw" -gt "$ch" ]; then
    tw=$ch; th=$cw
  elif [ "$D_W" -gt "$D_H" ] && [ "$cw" -lt "$ch" ]; then
    tw=$ch; th=$cw
  else
    tw=$cw; th=$ch
  fi
  FIT_TW=$tw; FIT_TH=$th
  new="$tw $th $D_FPS"
  [ "$new" = "$(trim_tail "$line")" ] && return 0  # 已经是本机分辨率（含带尾随空格的旧行）
  desc_replace "$fz" "$line" "$new" || return 1
  log "fitted desc: $line -> $new ($fz)"
  return 0
}

# ---------- 动画库列表（每次运行只枚举一次） ----------
ENTRIES_INIT=""
ENTRIES=""
load_entries() {
  [ -n "$ENTRIES_INIT" ] && return 0
  ENTRIES_INIT=1
  ENTRIES=$(ls -1 "$LIB_DIR"/*.zip 2>/dev/null | sort)
}

# 按「order.txt 里登记的先后 + 其余按名称」输出全部动画路径。
# 注意：本机 printf 不是内建（走 /system/bin/printf，一次 ~7ms），所以这里拼好整块再一次吐出，
# 不要每行 printf 一次。行遍历也改成纯 shell，省掉 printf|while 那个管道子 shell。
entry_paths() {
  load_entries
  seen="|"; ep_out=""
  if [ -s "$ORDER_FILE" ]; then
    # 一次读入 order.txt：纯 shell 建集合，不 fork grep
    while IFS= read -r n || [ -n "$n" ]; do
      [ -n "$n" ] || continue
      seen="$seen$n|"
      [ -f "$LIB_DIR/$n.zip" ] && ep_out="$ep_out$LIB_DIR/$n.zip$NL"
    done <"$ORDER_FILE"
  fi
  ep_rest="$ENTRIES"
  while [ -n "$ep_rest" ]; do
    p=${ep_rest%%"$NL"*}; [ "$p" = "$ep_rest" ] && ep_rest="" || ep_rest=${ep_rest#"$p"$NL}
    [ -n "$p" ] || continue
    n=${p##*/}; n=${n%.zip}
    case "$seen" in *"|$n|"*) continue ;; esac
    ep_out="$ep_out$p$NL"
  done
  printf '%s' "$ep_out"
}

entry_count() {
  load_entries
  [ -n "$ENTRIES" ] || { echo 0; return 0; }
  ec_n=0
  while IFS= read -r ec_l; do ec_n=$((ec_n + 1)); done <<EC_IN
$ENTRIES
EC_IN
  echo "$ec_n"
}

entry_at() {
  want="$1"
  i=0
  entry_paths | while IFS= read -r p; do
    i=$((i + 1))
    if [ "$i" = "$want" ]; then printf '%s\n' "$p"; break; fi
  done
}

active_name() {
  [ -s "$SELECTED_FILE" ] || return 0
  an_l=""
  IFS= read -r an_l <"$SELECTED_FILE" 2>/dev/null  # 纯 shell 读首行，不开 cat/tr
  printf '%s' "${an_l%"$CR"}"
}
active_path() {
  an=$(active_name)
  [ -n "$an" ] && [ -f "$LIB_DIR/$an.zip" ] && echo "$LIB_DIR/$an.zip"
}

# ---------- 守卫脚本（关键：让「关闭模块」也能恢复出厂动画） ----------
# 模块被关闭(disable)时，模块自己的任何脚本都不会运行，所以「清理主题路径」这件事
# 必须交给一个位于模块之外、始终会运行的脚本。/data/adb/post-fs-data.d 正合适：
# 它在 post-fs-data 阶段执行（早于 SurfaceFlinger/bootanim），且不受模块启用状态影响。
GUARD_NAME="qimu-guard.sh"
# 测试时可替换成沙箱目录（tools/test_ctl.sh 会带 QIMU_GUARD_DIRS），默认路径不变
GUARD_DIRS=${QIMU_GUARD_DIRS:-"/data/adb/post-fs-data.d /data/adb/service.d"}

install_guard() {
  [ -d "$MODDIR" ] || return 0
  for d in $GUARD_DIRS; do
    [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || continue
    g="$d/$GUARD_NAME"
    cat >"$g" <<'GUARD_EOF'
#!/system/bin/sh
# 启幕 QiMu 守卫脚本 —— 由「开机动画管理器」模块安装，请勿手动修改
# 作用：模块被关闭(disable)或移除时，清掉主题路径里的开机动画，
#       让开机动画回到出厂（否则那个文件留在 /data 下会一直生效）。
MOD=/data/adb/modules/custom_bootanimation
THEME=/data/system/theme/boots/bootanimation.zip
# 模块启用中 → 交给模块自己管理，本脚本不动任何东西
if [ -d "$MOD" ] && [ ! -e "$MOD/disable" ] && [ ! -e "$MOD/remove" ]; then
  exit 0
fi
[ -e "$THEME" ] && rm -f "$THEME" 2>/dev/null
# 本脚本跑在 post-fs-data 阶段，setprop 会与 init 互等死锁（官方文档明令）→ 优先 resetprop -n
if command -v resetprop >/dev/null 2>&1; then
  resetprop -n debug.sf.nobootanimation 0 2>/dev/null
else
  setprop debug.sf.nobootanimation 0 2>/dev/null
fi
exit 0
GUARD_EOF
    chmod 0755 "$g" 2>/dev/null
    log "guard installed: $g"
  done
  return 0
}

remove_guard() {
  for d in $GUARD_DIRS; do
    rm -f "$d/$GUARD_NAME" 2>/dev/null
  done
}

# ---------- 部署到主题路径 ----------
# 主题路径上文件的属主/权限/SELinux 标签（best-effort，失败不拦）
theme_own() { chown system_theme:system_theme "$1" 2>/dev/null; chmod "$2" "$1" 2>/dev/null; chcon u:object_r:theme_data_file:s0 "$1" 2>/dev/null; }

deploy_active() {
  ap=$(active_path)
  if [ -z "$ap" ]; then
    an=$(active_name)
    if [ -n "$an" ]; then
      # 选择记录还在、库里的包却没了（被文件管理器删掉/存储清理）：主题路径上那份是旧的，
      # 留着会一直播一个已经不存在的动画，还让「当前动画」显示成正常状态 → 清掉回出厂
      log "deploy: active '$an' missing from library, clearing theme file"
      if [ -e "$THEME_FILE" ] || [ -L "$THEME_FILE" ]; then rm -f "$THEME_FILE" 2>/dev/null; fi
      rm -f "$STAMP_FILE" 2>/dev/null
    fi
    log "deploy skipped: no active animation"
    return 1
  fi
  an=$(active_name)
  new_size=$(file_size "$ap")
  # 屏幕尺寸进 stamp：早期阶段算不出屏幕时这一项是空的，service.sh 起来后 sync 一次
  # 会发现对不上 → 补做适配；下次开机缓存已就绪，post-fs-data 也能直接算出同样的值，
  # 不会每次开机都重拷一遍 50MB 的动画
  swh=$(screen_wh)
  stamp_val="$an:$new_size:$swh"

  # 「不播放动画」：设 debug.sf.nobootanimation=1，让 SurfaceFlinger 不启动 bootanim 进程
  if [ "$an" = "$NO_ANIM_NAME" ]; then
    nb_setprop debug.sf.nobootanimation 1
    log "debug.sf.nobootanimation=1 (不播放动画)"
  else
    nb_setprop debug.sf.nobootanimation 0
  fi

  # 守卫脚本随部署一并确保存在（模块被关闭后由它负责清理）
  install_guard

  # 快路径：主题文件在、大小一致、stamp 一致 → 就是本模块上次写的那份，直接跳过。
  # fit 也不用跑：fit/setres/swap 改过 desc 都会清掉 stamp，stamp 还在就说明 desc 没动过。
  # （旧顺序每次开机都先白跑一遍 fit 的 unzip+wm——post-fs-data 阶段 wm 根本连不上）
  if [ -f "$THEME_FILE" ] && [ "$(file_size "$THEME_FILE")" = "$new_size" ]; then
    if [ "$(cat "$STAMP_FILE" 2>/dev/null)" = "$stamp_val" ]; then
      log "theme already current (stamp)"
      return 0
    fi
  fi

  # 慢路径：先归一化 g 写法 + 适配本机分辨率（等长原地覆盖，大小不变；改过会清 stamp）
  fit_zip "$ap" >/dev/null 2>&1
  new_size=$(file_size "$ap")
  stamp_val="$an:$new_size:$swh"

  [ -d "$THEME_DIR" ] || mkdir -p "$THEME_DIR" 2>/dev/null || { log "theme dir create failed"; return 1; }
  theme_own "$THEME_DIR" 0775

  # desc 没被这次部署改写（FIT_WROTE 空）且大小一致 → 主题里那份多半就是当前的，
  # md5 确认后跳过；desc 改写过就无论如何重拷，保证手动设的分辨率真落到生效文件上
  if [ -z "$FIT_WROTE" ] && [ -f "$THEME_FILE" ] && [ "$(file_size "$THEME_FILE")" = "$new_size" ]; then
    if command -v md5sum >/dev/null 2>&1; then
      set -- $(md5sum "$THEME_FILE" 2>/dev/null); m1=$1
      set -- $(md5sum "$ap" 2>/dev/null); m2=$1
      if [ "$m1" = "$m2" ] && [ -n "$m1" ]; then
        printf '%s\n' "$stamp_val" >"$STAMP_FILE" 2>/dev/null
        log "theme already current (md5)"
        return 0
      fi
    else
      printf '%s\n' "$stamp_val" >"$STAMP_FILE" 2>/dev/null
      log "theme already current (size only)"
      return 0
    fi
  fi

  # 注意：主题路径上可能残留旧版做的符号链接 → 先删掉，避免 cp 写到链接目标上
  [ -L "$THEME_FILE" ] && rm -f "$THEME_FILE" 2>/dev/null

  tmp="$THEME_FILE.tmp.$$"
  rm -f "$tmp" 2>/dev/null
  cp -f "$ap" "$tmp" 2>/dev/null || { log "theme copy failed"; rm -f "$tmp"; return 1; }
  theme_own "$tmp" 0644
  if mv -f "$tmp" "$THEME_FILE" 2>/dev/null; then
    printf '%s\n' "$stamp_val" >"$STAMP_FILE" 2>/dev/null
    log "theme deployed: $an ($new_size bytes)"
    return 0
  fi
  log "theme deploy failed"
  rm -f "$tmp" 2>/dev/null
  return 1
}

# ---------- 命令 ----------
# 编号校验（$2 = 编号非法时要显示的提示）
need_idx() { case "$1" in ''|*[!0-9]*) echo "ERROR $2"; return 1 ;; esac; return 0; }
# 取第 N 个动画的路径到 EP
take_entry() { EP=$(entry_at "$1"); [ -n "$EP" ] && [ -f "$EP" ] || { echo "ERROR 找不到该动画"; return 1; }; }
# 读 desc 首行到 D_LINE，解析出 D_W/D_H/D_FPS
read_desc() { D_LINE=$(desc_line "$1"); [ -n "$D_LINE" ] || { echo "ERROR 读不到 desc.txt"; return 1; }; parse_desc_line "$D_LINE" || { echo "ERROR desc 不是标准格式"; return 1; }; }
# 原地改写 desc 首行（$4 = 「新串更长」时的提示语）
write_desc() {
  desc_replace "$1" "$2" "$3"; rc=$?
  case "$rc" in
    0) return 0 ;;
    2) echo "ERROR $4"; return 1 ;;
    *) echo "ERROR 写入 desc 失败"; return 1 ;;
  esac
}
# 「宽x高」，读不到屏幕就是「未知」
screen_size() { wh=$(screen_wh); if [ -n "$wh" ]; then echo "${wh%% *}x${wh##* }"; else echo "未知"; fi; }

# 列表：每行 fork 一次 unzip + 一次 wc 的话，12 个动画要 400ms（fork 一次 5~10ms，与包大小无关）。
# 所以这里 —— 大小用一次 wc -c 全取（1 次 fork 顶 N 次）、「宽×高·帧率」查 desc.cache、
# 行遍历与查表全用纯 shell（不 fork）。缓存全命中时整条 list 只剩枚举 + 一次 wc 的开销。
cmd_list() {
  # 所有包的大小 → 查表串（每段「换行 名字<TAB>大小」，前置换行方便整段定位）
  list_sz=""; ls_rest=$(wc -c "$LIB_DIR"/*.zip 2>/dev/null)
  while [ -n "$ls_rest" ]; do
    ls_l=${ls_rest%%"$NL"*}; [ "$ls_l" = "$ls_rest" ] && ls_rest="" || ls_rest=${ls_rest#"$ls_l"$NL}
    ls_l=${ls_l#"${ls_l%%[! ]*}"}                 # wc 多文件时数字右对齐，先去掉前导空格
    case "$ls_l" in *" total") continue ;; esac   # 多文件时它还会多打一行汇总
    ls_n=${ls_l#* }; ls_n=${ls_n##*/}
    list_sz="$list_sz$NL${ls_n%.zip}$TAB${ls_l%% *}"
  done
  # desc 缓存（纯 shell 读入，不用 cat）
  list_c=""; [ -s "$DESC_CACHE" ] && while IFS= read -r ls_c || [ -n "$ls_c" ]; do
    list_c="$list_c$ls_c$NL"
  done <"$DESC_CACHE"

  an=$(active_name); list_new=""; list_out=""; i=0; rest=$(entry_paths)
  while [ -n "$rest" ]; do
    p=${rest%%"$NL"*}; [ "$p" = "$rest" ] && rest="" || rest=${rest#"$p"$NL}
    i=$((i + 1))
    n=${p##*/}; n=${n%.zip}
    sz=""
    case "$list_sz" in *"$NL$n$TAB"*) sz=${list_sz#*"$NL$n$TAB"}; sz=${sz%%"$NL"*} ;; esac
    w=""; h=""; f=""
    case "$NL$list_c" in
      *"$NL$n$TAB"*)
        cr=${list_c#*"$NL$n$TAB"}; cr=${cr%%"$NL"*}
        w=${cr%%"$TAB"*}; cr=${cr#*"$TAB"}
        h=${cr%%"$TAB"*}; cr=${cr#*"$TAB"}
        f=${cr%%"$TAB"*}; cr=${cr#*"$TAB"}
        [ "$cr" = "$sz" ] || { w=""; h=""; f=""; }   # 大小对不上 = 包被换过，缓存作废
        ;;
    esac
    if [ -z "$w" ]; then                             # 只有首次/包变更才走这里（会 fork 一次 unzip）
      di=$(desc_line "$p")
      [ -n "$di" ] && parse_desc_line "$di" && { w=$D_W; h=$D_H; f=$D_FPS; }
    fi
    [ -n "$w" ] && list_new="$list_new$n$TAB$w$TAB$h$TAB$f$TAB$sz$NL"
    info=""; [ -n "$w" ] && info="$w×$h · ${f}fps"
    act=no; [ "$n" = "$an" ] && act=yes
    list_out="$list_out$i$TAB$n$TAB$sz$TAB$act$TAB$info$NL"
  done
  [ "$list_new" = "$list_c" ] || printf '%s' "$list_new" >"$DESC_CACHE" 2>/dev/null
  printf '%s' "$list_out"                            # 整块一次吐出（printf 很贵，别每行一次）
}

cmd_status() {
  an=$(active_name)
  echo "active=${an:-无}"
  # 「不播放动画」走的是 debug.sf.nobootanimation，不写主题路径；界面要能区分这个状态，
  # 不能只看 theme_ok 说「已写入，重启生效」
  if [ "$an" = "$NO_ANIM_NAME" ]; then echo "noanim=yes"; else echo "noanim=no"; fi
  # 界面要显示「文件位置」：当前动画在库里的源文件 + 刷入的主题路径 + 本机屏幕分辨率
  echo "active_path=$(active_path)"
  echo "theme_path=$THEME_FILE"
  echo "library=$LIB_DIR"
  echo "screen=$(screen_size)"
  echo "count=$(entry_count)"
  # 动画库总占用：一次 wc -c 全取（多文件时最后一行是 total 汇总），awk 只取最后一行的第一列。
  # 别对每个包 fork 一次 stat —— 12 个包就是 12 次 fork，界面每次刷新都要付这笔钱。
  echo "lib_size=$(wc -c "$LIB_DIR"/*.zip 2>/dev/null | awk 'END{print $1+0}')"
  if [ -f "$THEME_FILE" ]; then
    echo "theme_size=$(file_size "$THEME_FILE")"
    echo "theme_ok=yes"
  else
    echo "theme_size=0"
    echo "theme_ok=no"
  fi
  guard_count=0
  for gd in $GUARD_DIRS; do
    [ -f "$gd/$GUARD_NAME" ] && guard_count=$((guard_count + 1))
  done
  echo "guard_count=$guard_count"
}

# 界面用：一次调用同时拿到 status 与 list，省掉一次 exec 往返
cmd_info() {
  cmd_status
  printf '%s\n' "##LIST"
  cmd_list
}

cmd_select() {
  need_idx "$1" "编号无效" && take_entry "$1" || return 1
  validate_zip "$EP" || { echo "ERROR $VALID_MSG"; return 1; }
  n=$(name_of "$EP")
  printf '%s\n' "$n" >"$SELECTED_FILE" 2>/dev/null || { echo "ERROR 保存选择失败"; return 1; }
  if deploy_active; then
    echo "OK selected=$n"
  else
    echo "ERROR 动画已选择，但写入主题路径失败"
    return 1
  fi
}

# desc 改写成功后的统一收尾：动画正在使用就重新部署；输出统一的 OK 行
# （界面靠 OK 行里的 to=宽x高 直接更新面板，格式别乱动）
finish_desc_change() {   # $1=命令名(fitted/setres/swap) $2=动画名 $3=目标宽高(宽x高)
  if [ "$2" = "$(active_name)" ]; then
    if deploy_active >/dev/null 2>&1; then
      echo "OK $1=$2 to=$3 (redeployed)"
    else
      echo "OK $1=$2 to=$3 (但重新部署失败)"
    fi
  else
    echo "OK $1=$2 to=$3"
  fi
  return 0
}

# 手动把某个动画的 desc 适配到本机分辨率（部署时也会自动做，这里给排障/单独调用用）
cmd_fit() {
  need_idx "$1" "用法: fit N" && take_entry "$1" || return 1
  wh=$(screen_wh)
  [ -n "$wh" ] || { echo "ERROR 读不到本机分辨率"; return 1; }
  n=$(name_of "$EP")
  manual_del "$n"                                # 显式自适应 = 恢复自动，移出手动名单
  if fit_zip "$EP"; then
    finish_desc_change fitted "$n" "${FIT_TW}x${FIT_TH}"   # 方向感知后实际写入的宽高
  else
    echo "ERROR 适配失败：新分辨率串比原来的长，或 desc 不是标准格式"
    return 1
  fi
}

# 只读：打印某动画当前的 desc 分辨率，给界面里「分辨率」面板用，不写文件
cmd_desc() {
  need_idx "$1" "用法: desc N" && take_entry "$1" || return 1
  read_desc "$EP" || return 1
  echo "desc_w=$D_W"
  echo "desc_h=$D_H"
  echo "desc_fps=$D_FPS"
  if manual_has "$(name_of "$EP")"; then echo "mode=manual"; else echo "mode=auto"; fi
  echo "screen=$(screen_size)"
  # 帧数/时长：编辑面板里显示「这段动画播多久」。只有点开面板才算一次 unzip -l，
  # 不进列表路径（列表每刷新一次都算就是 N 次 fork）。
  count_frames "$(unzip -l "$EP" 2>/dev/null)"
  echo "frames=$FRAMES"
  case "$D_FPS" in
    ''|*[!0-9]*|0) ;;
    *) echo "dur=$(( (FRAMES * 10 + D_FPS / 2) / D_FPS / 10 )).$(( (FRAMES * 10 + D_FPS / 2) / D_FPS % 10 ))s" ;;
  esac
  echo "desc_line=$D_LINE"
  return 0
}

# 手动设置某动画的 desc 分辨率（帧率保留）。设备上不能重建 zip，新串不能比原行长。
# 直接解析原始行（g 写法也行），写入标准格式时顺带归一化，不用先单独 normalize
cmd_setres() {
  idx="$1"; w="$2"; h="$3"
  need_idx "$idx" "用法: setres N 宽 高" || return 1
  case "$w" in ''|*[!0-9]*) echo "ERROR 宽必须是数字"; return 1;; esac
  case "$h" in ''|*[!0-9]*) echo "ERROR 高必须是数字"; return 1;; esac
  # 手动设定的值会进 manual.txt、部署时不再自动修正——坏值会跨重启存活，入口必须把严
  [ "${#w}" -le 5 ] && [ "${#h}" -le 5 ] || { echo "ERROR 宽高位数太长"; return 1; }
  [ "$w" -ge 100 ] && [ "$w" -le 16384 ] && [ "$h" -ge 100 ] && [ "$h" -le 16384 ] \
    || { echo "ERROR 宽高超出合理范围（100-16384）"; return 1; }
  take_entry "$idx" || return 1
  read_desc "$EP" || return 1
  n=$(name_of "$EP")
  new="$w $h $D_FPS"
  write_desc "$EP" "$D_LINE" "$new" "新分辨率串比原来的长，写不进去（设备上不能重建 zip）" || return 1
  log "setres: $D_LINE -> $new ($EP)"
  manual_add "$n"                                # 手动设定过，自动适配不再碰它
  finish_desc_change setres "$n" "${w}x${h}"
}

# 改动画名：库文件、手动分辨率名单、生效记录一起联动改名
cmd_rename() {
  idx="$1"; newn="$2"
  need_idx "$idx" "用法: rename N 新名字" || return 1
  [ -n "$newn" ] || { echo "ERROR 名字不能为空"; return 1; }
  take_entry "$idx" || return 1
  oldn=$(name_of "$EP")
  newn=$(sanitize_name "$newn")
  [ -n "$newn" ] || { echo "ERROR 名字无效"; return 1; }
  case "$newn" in
    .*) echo "ERROR 名字不能以点开头（会变成隐藏文件，列表里看不到）"; return 1 ;;
  esac
  [ "$newn" = "$oldn" ] && { echo "OK renamed=$newn"; return 0; }
  target="$LIB_DIR/$newn.zip"
  [ -e "$target" ] && { echo "ERROR 已有同名动画"; return 1; }
  was_active=no
  [ "$oldn" = "$(active_name)" ] && was_active=yes
  mv -f "$EP" "$target" 2>/dev/null || { echo "ERROR 改名失败"; return 1; }
  chmod 0644 "$target" 2>/dev/null
  if manual_has "$oldn"; then manual_del "$oldn"; manual_add "$newn"; fi   # 手动名单跟着改名
  order_map "$oldn" "$newn"                      # 排序位置也跟着改名，别让用户重排
  # 生效中的动画改名 → 选择记录同步改，再重新部署（stamp 里记的名字也一并更新）
  if [ "$was_active" = "yes" ]; then
    printf '%s\n' "$newn" > "$SELECTED_FILE" 2>/dev/null
    deploy_active >/dev/null 2>&1
  fi
  log "renamed: $oldn -> $newn"
  echo "OK renamed=$newn"
  return 0
}

# 交换某动画 desc 的宽高（一键修正长宽互换）。宽高位数相同，串长不变，必能写入。
cmd_swap() {
  need_idx "$1" "用法: swap N" && take_entry "$1" || return 1
  read_desc "$EP" || return 1
  n=$(name_of "$EP")
  new="$D_H $D_W $D_FPS"                           # 宽高对调
  write_desc "$EP" "$D_LINE" "$new" "交换后串更长，写不进去" || return 1
  log "swap: $D_LINE -> $new ($EP)"
  manual_add "$n"
  finish_desc_change swap "$n" "${D_H}x${D_W}"
}

# 在 zip 里找「基名等于 $2」的条目，输出它在包里的完整路径。
# 不用 `unzip -Z1`：toybox 的 unzip 不一定带 -Z；-l 最后一行最后一列就是路径，够用。
zip_entry_named() {
  ze_list=$(unzip -l "$1" 2>/dev/null) || return 0
  ze_rest="$ze_list$NL"
  while [ -n "$ze_rest" ]; do
    ze_l=${ze_rest%%"$NL"*}; [ "$ze_l" = "$ze_rest" ] && ze_rest="" || ze_rest=${ze_rest#"$ze_l"$NL}
    ze_p=${ze_l##* }                             # 最后一列是路径
    [ "${ze_p##*/}" = "$2" ] && { printf '%s\n' "$ze_p"; return 0; }
  done
  return 0
}

# 同上，但只认根目录条目（不带 /）。desc.txt 必须落在根目录，part0/desc.txt 不算。
zip_root_entry() {
  zr_list=$(unzip -l "$1" 2>/dev/null) || return 0
  zr_rest="$zr_list$NL"
  while [ -n "$zr_rest" ]; do
    zr_l=${zr_rest%%"$NL"*}; [ "$zr_l" = "$zr_rest" ] && zr_rest="" || zr_rest=${zr_rest#"$zr_l"$NL}
    zr_p=${zr_l##* }
    case "$zr_p" in */*) continue ;; esac
    [ "$zr_p" = "$2" ] && { printf '%s\n' "$zr_p"; return 0; }
  done
  return 0
}

cmd_import() {
  src="$1"; want_name="$2"
  [ -n "$src" ] || { echo "ERROR 未指定文件"; return 1; }
  [ -f "$src" ] || { echo "ERROR 找不到文件: $src"; return 1; }

  # 用原始文件名命名库里的动画（解包后 src 可能变成临时文件，名字得先记下来）
  base=$(sanitize_name "${want_name:-$(name_of "$src")}")
  [ -n "$base" ] || base="imported"

  # 「模块壳」包：根目录没有 desc.txt，但内含 bootanimation.zip 条目
  #   （KSU/Magisk 模块式的开机动画包就是这种结构，动画被裹在一层模块里）
  #   解出内层 bootanimation.zip 再走正常校验/入库流程。
  #   判据用条目表（精确根目录名），不能用 `unzip -p ... desc.txt` 的退出码：
  #   toybox 的 unzip 找不到条目时照样返回 0，判定会整个失效（真机踩过）。
  inner_tmp=""
  if [ -z "$(zip_root_entry "$src" desc.txt)" ]; then
    inner_entry=$(zip_entry_named "$src" bootanimation.zip)
    inner_tmp="$LIB_DIR/.unwrap.$$.tmp"
    if [ -n "$inner_entry" ] && unzip -p "$src" "$inner_entry" >"$inner_tmp" 2>/dev/null && [ -s "$inner_tmp" ]; then
      log "unwrap: $inner_entry in $src"
      src="$inner_tmp"
    else
      rm -f "$inner_tmp" 2>/dev/null
      inner_tmp=""
    fi
  fi

  validate_zip "$src" || { echo "ERROR $VALID_MSG"; rm -f "$inner_tmp" 2>/dev/null; return 1; }
  target="$LIB_DIR/$base.zip"
  n=2
  while [ -e "$target" ]; do target="$LIB_DIR/$base-$n.zip"; n=$((n + 1)); done
  tmp="$LIB_DIR/.import.$$.tmp"
  if cp -f "$src" "$tmp" 2>/dev/null && mv -f "$tmp" "$target" 2>/dev/null; then
    chmod 0644 "$target" 2>/dev/null
    # 顺手改写 desc 首行（归一化 g 写法 + 适配本机分辨率）。改的是库里这份副本，
    # 这样列表里显示的分辨率就是实际会播的尺寸，跟部署时的结果一致。
    fit_zip "$target" >/dev/null 2>&1
    rm -f "$inner_tmp" 2>/dev/null             # 解包临时文件用完即删
    log "imported: $target"
    echo "OK stored=${target##*/}"
  else
    rm -f "$tmp" 2>/dev/null
    rm -f "$inner_tmp" 2>/dev/null
    echo "ERROR 复制文件失败"
    return 1
  fi
}

cmd_delete() {
  need_idx "$1" "编号无效" && take_entry "$1" || return 1
  n=$(name_of "$EP")
  if [ "$n" = "$(active_name)" ]; then
    echo "ERROR 该动画正在使用中，请先切换到其他动画"
    return 1
  fi
  rm -f "$EP" 2>/dev/null || { echo "ERROR 删除失败"; return 1; }
  manual_del "$n"                                # 名单里残留的手动标记一并清掉
  order_map "$n" ""                              # 排序表里的旧条目也一起清掉
  log "deleted: $EP"
  echo "OK deleted=$n"
}

# 列目录，给界面里「选择文件」用（用户可以自己翻到动画放的位置）
# 用法: ctl.sh ls [目录]
# 输出: D<tab>名字<tab>路径         子目录
#       F<tab>文件名<tab>大小<tab>路径   zip
cmd_ls() {
  d="$1"
  [ -n "$d" ] || d="/sdcard"
  while [ "${d%/}" != "$d" ]; do d=${d%/}; done     # 去掉末尾斜杠（/sdcard/ ≡ /sdcard）
  [ -n "$d" ] || d="/"
  # 白名单是按字面前缀比的，/data/local/tmp/../.. 这种也带前缀——必须先把穿越拦掉
  case "/$d/" in
    *"/../"*) echo "ERROR 路径里不能带 ..：$d"; return 1 ;;
  esac
  ls_ok=no
  for ls_r in $LS_ROOTS; do
    [ "$d" = "$ls_r" ] && { ls_ok=yes; break; }
    case "$d" in "$ls_r"/*) ls_ok=yes; break ;; esac
  done
  [ "$ls_ok" = "yes" ] || { echo "ERROR 这个路径不让浏览：$d"; return 1; }
  [ -d "$d" ] || { echo "ERROR 没有这个目录：$d"; return 1; }
  # 一次 ls 取全量（用变量，不接管道子 shell），目录排前、文件排后，
  # 最后整块 printf 一次——每行 fork 一次 printf 的话，50 个条目要 300ms+。
  # ls -p 给目录加尾斜杠：省掉「每个条目一次 test -d」的 fork（50 条就是 50 次）
  ls_all=$(ls -1p "$d" 2>/dev/null)
  ls_out=""
  ls_rest="$ls_all$NL"
  while [ -n "$ls_rest" ]; do
    ls_x=${ls_rest%%"$NL"*}; [ "$ls_x" = "$ls_rest" ] && ls_rest="" || ls_rest=${ls_rest#"$ls_x"$NL}
    [ -n "$ls_x" ] || continue
    case "$ls_x" in .*) continue ;; esac
    case "$ls_x" in
      */) ls_n=${ls_x%/}; ls_out="$ls_out"D"$TAB$ls_n$TAB$d/$ls_n$NL" ;;
    esac
  done
  ls_rest="$ls_all$NL"
  while [ -n "$ls_rest" ]; do
    ls_x=${ls_rest%%"$NL"*}; [ "$ls_x" = "$ls_rest" ] && ls_rest="" || ls_rest=${ls_rest#"$ls_x"$NL}
    [ -n "$ls_x" ] || continue
    case "$ls_x" in .*) continue ;; esac
    case "$ls_x" in */) continue ;; esac            # 目录已在上面的循环里输出过
    ls_p="$d/$ls_x"
    case "$ls_x" in
      *.zip|*.ZIP)
        ls_out="$ls_out""F$TAB$ls_x$TAB$(file_size "$ls_p")$TAB$ls_p$NL" ;;
      # 视频文件单列一类（V），给「视频转动画」用；选择文件列表里不显示导入按钮
      *.mp4|*.MP4|*.mov|*.MOV|*.mkv|*.MKV|*.webm|*.WEBM|*.m4v|*.M4V|*.3gp|*.3GP)
        ls_out="$ls_out""V$TAB$ls_x$TAB$(file_size "$ls_p")$TAB$ls_p$NL" ;;
    esac
  done
  printf '%s' "$ls_out"
}

cmd_reset() {
  first=$(entry_paths | head -1)
  if [ -z "$first" ]; then echo "ERROR 动画库为空"; return 1; fi
  n=$(name_of "$first")
  printf '%s\n' "$n" >"$SELECTED_FILE" 2>/dev/null
  if deploy_active; then echo "OK selected=$n"; else echo "ERROR 重置失败"; return 1; fi
}

cmd_order() {
  # 用法: ctl.sh order 名字1 名字2 ...  （按给定顺序重排动画库）
  if [ "$#" -eq 0 ]; then echo "ERROR 参数为空"; return 1; fi
  mkdir -p "$STATE_DIR" 2>/dev/null
  tmp="$STATE_DIR/.order.$$.tmp"
  : >"$tmp" 2>/dev/null || { echo "ERROR 无法写入排序"; return 1; }
  for n in "$@"; do
    [ -n "$n" ] || continue
    [ -f "$LIB_DIR/$n.zip" ] && printf '%s\n' "$n" >>"$tmp"
  done
  if mv -f "$tmp" "$ORDER_FILE" 2>/dev/null; then
    log "order updated: $(tr '\n' ' ' <"$ORDER_FILE" 2>/dev/null)"
    echo "OK order=updated"
  else
    rm -f "$tmp" 2>/dev/null
    echo "ERROR 保存排序失败"
    return 1
  fi
}

# 清理中断的导入/转换残留。只清 6 小时前的：视频写回期间是 4 个分片
# /data/local/tmp/<名>.zip.p0..p3，合并完才删，清早了会把正在跑的转换弄坏。
cmd_gc() {
  gc_n=0
  for gc_f in "$LIB_DIR"/.import.*.tmp "$LIB_DIR"/.unwrap.*.tmp \
              /data/local/tmp/.qimu-*.zip \
              /data/local/tmp/*.zip.p0 /data/local/tmp/*.zip.p1 /data/local/tmp/*.zip.p2 \
              /data/local/tmp/*.zip.p3 /data/local/tmp/*.zip.p4 /data/local/tmp/*.zip.p5; do
    [ -f "$gc_f" ] || continue
    [ -n "$(find "$gc_f" -mmin +360 2>/dev/null)" ] || continue
    rm -f "$gc_f" 2>/dev/null && gc_n=$((gc_n + 1))
  done
  log "gc: removed $gc_n temp file(s)"
  echo "OK gc=$gc_n"
}

# 全库体检：对库里每个包重跑一遍 validate_zip。导入时校验过，但包在库里可能被改坏
# （手动改 desc、同步软件写到一半、存储掉块），刷进去才发现就是重启黑屏。
# 正常条目不出声，坏条目一行一个 BAD<tab>名字<tab>原因，最后一律给 OK 行（界面按它结算）。
cmd_check() {
  ck_n=0; ck_bad=0; ck_out=""
  ck_rest=$(entry_paths)
  while [ -n "$ck_rest" ]; do
    ck_p=${ck_rest%%"$NL"*}; [ "$ck_p" = "$ck_rest" ] && ck_rest="" || ck_rest=${ck_rest#"$ck_p"$NL}
    ck_n=$((ck_n + 1))
    if validate_zip "$ck_p"; then
      :
    else
      ck_bad=$((ck_bad + 1))
      ck_out="$ck_out"BAD"$TAB$(name_of "$ck_p")$TAB$VALID_MSG$NL"
    fi
  done
  [ -z "$ck_out" ] || printf '%s' "$ck_out"
  echo "OK checked=$ck_n bad=$ck_bad"
  return 0
}

# 导出：把库里某个动画复制到能访问的目录（发给别人 / 备份 / 拷到别的机器）。
# 用法: export N [目标路径]
#   目标是个已存在的目录 → 存成 <动画名>.zip；否则当成完整文件路径（父目录不存在就建）。
#   不给目标 → 优先 /sdcard/Download。
cmd_export() {
  need_idx "$1" "用法: export N [目标路径]" && take_entry "$1" || return 1
  ex_n=$(name_of "$EP")
  ex_dst="$2"
  if [ -z "$ex_dst" ]; then
    if [ -d /sdcard/Download ]; then ex_dst=/sdcard/Download; else ex_dst=/sdcard; fi
  fi
  if [ -d "$ex_dst" ]; then
    ex_out="${ex_dst%/}/$ex_n.zip"
  else
    case "$ex_dst" in
      */) echo "ERROR 目录不存在：$ex_dst"; return 1 ;;
    esac
    ex_out="$ex_dst"
  fi
  [ "$ex_out" = "$EP" ] && { echo "ERROR 目标就是库里的文件本身"; return 1; }
  case "$ex_out" in
    */*) mkdir -p "${ex_out%/*}" 2>/dev/null ;;
  esac
  cp -f "$EP" "$ex_out" 2>/dev/null || { echo "ERROR 写入失败：$ex_out"; return 1; }
  chmod 0644 "$ex_out" 2>/dev/null
  log "export: $EP -> $ex_out"
  echo "OK exported=$ex_out"
  return 0
}

# 开机后（late_start）补一轮：主题引擎清掉的文件补写回来，并补做 post-fs-data 阶段
# 做不了的分辨率适配（那时 window 服务没起来）。SCREEN_FRESH=1 强制读一次真实屏幕，
# 顺便把结果写进 screen.txt，下次开机早期就能直接用。
cmd_sync() {
  SCREEN_FRESH=1
  if deploy_active; then
    cmd_gc >/dev/null 2>&1
    echo "OK synced"
    return 0
  fi
  echo "ERROR sync=deploy-failed"
  return 1
}

case "$1" in
  list) cmd_list ;;
  status) cmd_status ;;
  info) cmd_info ;;
  select) cmd_select "$2" ;;
  fit) cmd_fit "$2" ;;
  desc) cmd_desc "$2" ;;
  setres) cmd_setres "$2" "$3" "$4" ;;
  swap) cmd_swap "$2" ;;
  rename) cmd_rename "$2" "$3" ;;
  import) cmd_import "$2" "$3" ;;
  delete) cmd_delete "$2" ;;
  ls) cmd_ls "$2" ;;
  reset) cmd_reset ;;
  order) shift; cmd_order "$@" ;;
  guard) install_guard && echo "OK guard installed" ;;
  unguard) remove_guard && echo "OK guard removed" ;;
  deploy) deploy_active && echo "OK deployed" ;;
  check) cmd_check ;;
  export) cmd_export "$2" "$3" ;;
  sync) cmd_sync ;;
  gc) cmd_gc ;;
  *) echo "用法: $0 {list|status|info|select N|fit N|desc N|setres N W H|swap N|rename N 名字|import PATH [名字]|export N [路径]|delete N|ls DIR|reset|order NAME...|guard|unguard|deploy|check|sync|gc}"; exit 64 ;;
esac
