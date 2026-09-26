#!/system/bin/sh
# 开机动画管理器 - 控制脚本
# 用法: ctl.sh {list|status|info|select N|fit N|desc N|setres N W H|swap N|rename N 名字|import PATH|delete N|scan|ls DIR|reset|order NAME...|audio N|audioout N|guard|unguard|deploy}
#
# 几处踩过坑的地方，改的时候注意：
#   - 动画库列表每次运行只枚举一次，order.txt 一次读进来用纯 shell 比较，
#     别对每个文件 fork 一次 grep
#   - 校验压缩方式用「读 zip 本地文件头的压缩方法字节 + grep 方法名兜底」，
#     不要解析 unzip -v 的列：不同机型 unzip 实现不一样（Info-ZIP / toybox）
#   - 别用 ${var%%|*} 这种带 | 的参数展开，Android 的 mksh 会把模式里的 | 当“或”运算符
#   - 部署带 stamp，开机时 stamp 和大小都对得上就直接跳过，不再每次算 md5

MODDIR=${0%/*}
MODDIR=${MODDIR%/bin}
LIB_DIR="/data/adb/bootanims"
STATE_DIR="$MODDIR/var/state"
LOG_DIR="$MODDIR/var/logs"
SELECTED_FILE="$STATE_DIR/selected.txt"
THEME_DIR="/data/system/theme/boots"
THEME_FILE="$THEME_DIR/bootanimation.zip"
STAMP_FILE="$STATE_DIR/deployed.stamp"
SCAN_DIRS="/sdcard/Download /storage/emulated/0/Download /sdcard/CustomBoot /sdcard /data/local/tmp"
NO_ANIM_NAME="不播放动画"
ORDER_FILE="$STATE_DIR/order.txt"
# 手动分辨率名单：在界面/命令里 setres、swap 设过的动画记在这里，
# 部署/导入时的自动适配跳过它们（否则一部署就被「适配到屏幕」覆盖回去，手动调的等于白调）
MANUAL_FILE="$STATE_DIR/manual.txt"
# 包内音频：导入时包里带的音频（有的包会夹 boot.ogg/mp3）自动解到这里，按动画名分目录。
# bootanimation 本身不播声音，解出来是给用户留档/取用的（删动画时一起删）
AUDIO_DIR="$LIB_DIR/audio"
AUDIO_EXTS="mp3 ogg oga wav m4a aac flac opus"

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

# 取不带 .zip 的动画名
name_of() { n=${1##*/}; printf '%s\n' "${n%.zip}"; }
file_size() {
  fs_s=$(wc -c <"$1" 2>/dev/null) || { echo ""; return 0; }
  set -- $fs_s                                   # 按空白拆分，替代 tr -d ' '
  echo "${1:-}"
}

# 清理会被列表格式/模式匹配弄坏的名字（仅导入时调用）
sanitize_name() {
  printf '%s' "$1" | tr -d '\t\r\n' | sed 's/[*?[\]|\\]/_/g' | cut -c1-60
}

# ---------- 校验 ----------
# 注意：不要用 ${var%%|*} / ${var#*|} 这类带 | 的参数展开 ——
# Android 的 mksh 会把模式里的 | 当作"或"运算符，得到与 bash 不同的结果。
VALID_MSG=""
validate_zip() {
  vf="$1"; VALID_MSG=""
  [ -s "$vf" ] || { VALID_MSG="文件不存在或为空"; return 1; }
  # 一次 dd+od 读本地文件头前 10 字节：偏移 0-1 是 PK 魔数（80 75），
  # 偏移 8-9 是压缩方法（0 0 = STORED）。比原先两次 dd 少 2 次 fork
  v_hdr=$(dd if="$vf" bs=1 count=10 2>/dev/null | od -An -tu1 2>/dev/null)
  set -- $v_hdr
  [ "$1" = "80" ] && [ "$2" = "75" ] || { VALID_MSG="不是有效的 zip 文件"; return 1; }
  # 注意 ${10} 要带花括号：$10 会被当成 ${1}0（mksh/bash 都这样）
  [ "$9" = "0" ] && [ "${10}" = "0" ] || { VALID_MSG="动画必须是 ZIP_STORED 无压缩格式"; return 1; }
  command -v unzip >/dev/null 2>&1 || return 0

  # 根目录必须有 desc.txt（用 -l 列表 + grep，不依赖任何列格式）
  unzip -l "$vf" 2>/dev/null | grep -q 'desc\.txt' || { VALID_MSG="zip 根目录缺少 desc.txt"; return 1; }

  # desc.txt 带 UTF-8 BOM（Windows 记事本常见）会让 bootanimation 解析首行失败 → 黑屏。
  # BOM 在等长覆盖下去不掉（去掉 3 字节就得重建 zip），只能在这里明确拒绝
  v_bom=$(unzip -p "$vf" desc.txt 2>/dev/null | dd bs=1 count=3 2>/dev/null | od -An -tx1 2>/dev/null)
  set -- $v_bom
  [ "$1" = "ef" ] && [ "$2" = "bb" ] && [ "$3" = "bf" ] \
    && { VALID_MSG="desc.txt 带 UTF-8 BOM，会导致开机黑屏——请用无 BOM 的 UTF-8 重新保存"; return 1; }

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
  dr_pad=$(( ${#dr_old} - ${#dr_new} ))
  [ "$dr_pad" -ge 0 ] || return 2
  dr_repl=$(printf "%s%*s" "$dr_new" "$dr_pad" "")
  dr_g=$(grep -abo "$dr_old" "$dr_f" 2>/dev/null) || return 1
  dr_off=${dr_g%%:*}                             # 多处匹配时取第一处；desc 行里不会有冒号
  [ -n "$dr_off" ] || return 1
  if printf '%s' "$dr_repl" | dd of="$dr_f" bs=1 seek="$dr_off" conv=notrunc 2>/dev/null; then
    FIT_WROTE=1                                  # 标记 desc 被改写过，部署据此决定必须重拷
    rm -f "$STAMP_FILE" 2>/dev/null
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

# ---------- 包内音频 ----------
# 有的动画包会夹带音频（boot.ogg / sound/*.mp3 之类）。bootanimation 不播声音，
# 但音频值得留档：导入时自动解到 audio/<动画名>/，界面可查看、可导出到下载目录。
# 注意： toybox unzip 的「无匹配」也 rc=0 且会建空目录，所以以解出文件数为准，0 就把目录删掉。
has_audio() {
  set -- "$AUDIO_DIR/$1"/*
  [ -e "$1" ]                                    # 顶层条目即可（嵌套目录也算有）
}
audio_extract() {                                # $1=zip 路径 $2=动画名 → 输出提取到的文件数
  ad="$AUDIO_DIR/$2"
  rm -rf "$ad" 2>/dev/null
  mkdir -p "$ad" 2>/dev/null || { echo 0; return; }
  # 门禁：先按扩展名在 -l 全文里找（名字列格式各家 unzip 不同，但音频扩展名总在行尾，
  # 按行尾匹配可靠）。没有就直接返回，省掉大包的全量解压
  au_pat='[.](mp3|ogg|oga|wav|m4a|aac|flac|opus)[[:space:]]*$'
  unzip -l "$1" 2>/dev/null | grep -iqE "$au_pat" || { rm -rf "$ad" 2>/dev/null; echo 0; return; }
  # 有音频 → 全量解到临时目录再按文件名挑（各家 unzip 的通配语义不一致，按名字最稳）
  au_tmp="$LIB_DIR/.audio.$$.tmp"
  rm -rf "$au_tmp" 2>/dev/null
  mkdir -p "$au_tmp" 2>/dev/null || { rm -rf "$ad" 2>/dev/null; echo 0; return; }
  unzip -o "$1" -d "$au_tmp" >/dev/null 2>&1
  find "$au_tmp" -type f \( -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.oga' \
    -o -iname '*.wav' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.flac' \
    -o -iname '*.opus' \) > "$au_tmp/.list" 2>/dev/null
  while IFS= read -r au_f; do
    [ -n "$au_f" ] || continue
    au_rel=${au_f#"$au_tmp"/}
    au_sub=${au_rel%/*}
    [ "$au_sub" = "$au_rel" ] || mkdir -p "$ad/$au_sub" 2>/dev/null
    mv -f "$au_f" "$ad/$au_rel" 2>/dev/null
  done < "$au_tmp/.list"
  rm -rf "$au_tmp" 2>/dev/null
  au_n=$(find "$ad" -type f 2>/dev/null | grep -c .)
  [ "$au_n" -gt 0 ] || rm -rf "$ad" 2>/dev/null
  echo "$au_n"
}
audio_ensure() {                                 # $1=zip 路径 $2=动画名：目录没有就补提取（兼容旧导入的包）
  has_audio "$2" && return 0
  audio_extract "$1" "$2" >/dev/null
}

# 本机屏幕物理分辨率（输出「宽 高」；读不到就输出空）。只 fork 一次 wm，行解析用纯 shell
screen_wh() {
  scr_raw=$(wm size 2>/dev/null) || return 0
  scr_line=""
  while IFS= read -r scr_l; do                   # 取 Physical size 行（Override 行不要）
    case "$scr_l" in
      *Physical*size*) scr_line=$scr_l; break ;;
    esac
  done <<SCR_IN
$scr_raw
SCR_IN
  [ -n "$scr_line" ] || return 0
  scr_line=${scr_line%"$CR"}
  scr_line=${scr_line#*:}                        # 去掉 "Physical size" 前缀
  while :; do
    case "$scr_line" in ' '*) scr_line=${scr_line#' '} ;; *) break ;; esac
  done
  set -- ${scr_line%x*} ${scr_line#*x}
  echo "$1 $2"
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
  [ "$new" = "$line" ] && return 0                 # 已经是本机分辨率
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

# 按「order.txt 里登记的先后 + 其余按名称」输出全部动画路径
entry_paths() {
  load_entries
  seen="|"
  if [ -s "$ORDER_FILE" ]; then
    # 一次读入 order.txt：纯 shell 建集合，不 fork grep
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      seen="$seen$n|"
      [ -f "$LIB_DIR/$n.zip" ] && printf '%s\n' "$LIB_DIR/$n.zip"
    done <"$ORDER_FILE"
  fi
  [ -n "$ENTRIES" ] || return 0
  printf '%s\n' "$ENTRIES" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=${p##*/}; n=${n%.zip}
    case "$seen" in *"|$n|"*) continue ;; esac
    printf '%s\n' "$p"
  done
}

entry_count() {
  load_entries
  [ -n "$ENTRIES" ] || { echo 0; return 0; }
  printf '%s\n' "$ENTRIES" | grep -c . 2>/dev/null || echo 0
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

# 列表里每行显示的「宽×高 · 帧率fps」（读不出就空）。复用 desc_line+parse，每行只 fork 一次 unzip
desc_info() {
  di_line=$(desc_line "$1")
  [ -n "$di_line" ] || return 0
  parse_desc_line "$di_line" || return 0
  printf '%s\n' "$D_W×$D_H · ${D_FPS}fps"
}

# ---------- 守卫脚本（关键：让「关闭模块」也能恢复出厂动画） ----------
# 模块被关闭(disable)时，模块自己的任何脚本都不会运行，所以「清理主题路径」这件事
# 必须交给一个位于模块之外、始终会运行的脚本。/data/adb/post-fs-data.d 正合适：
# 它在 post-fs-data 阶段执行（早于 SurfaceFlinger/bootanim），且不受模块启用状态影响。
GUARD_NAME="qimu-guard.sh"
GUARD_DIRS="/data/adb/post-fs-data.d /data/adb/service.d"

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
setprop debug.sf.nobootanimation 0 2>/dev/null
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
deploy_active() {
  ap=$(active_path)
  if [ -z "$ap" ]; then log "deploy skipped: no active animation"; return 1; fi
  an=$(active_name)
  new_size=$(file_size "$ap")
  stamp_val="$an:$new_size"

  # 「不播放动画」：设 debug.sf.nobootanimation=1，让 SurfaceFlinger 不启动 bootanim 进程
  if [ "$an" = "$NO_ANIM_NAME" ]; then
    setprop debug.sf.nobootanimation 1 2>/dev/null
    log "debug.sf.nobootanimation=1 (不播放动画)"
  else
    setprop debug.sf.nobootanimation 0 2>/dev/null
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
  stamp_val="$an:$new_size"

  if [ ! -d "$THEME_DIR" ]; then
    mkdir -p "$THEME_DIR" 2>/dev/null || { log "theme dir create failed"; return 1; }
  fi
  chown system_theme:system_theme "$THEME_DIR" 2>/dev/null
  chmod 0775 "$THEME_DIR" 2>/dev/null
  chcon u:object_r:theme_data_file:s0 "$THEME_DIR" 2>/dev/null

  # desc 没被这次部署改写（FIT_WROTE 空）且大小一致 → 主题里那份多半就是当前的，
  # md5 确认后跳过；desc 改写过就无论如何重拷，保证手动设的分辨率真落到生效文件上
  if [ -z "$FIT_WROTE" ] && [ -f "$THEME_FILE" ] && [ "$(file_size "$THEME_FILE")" = "$new_size" ]; then
    if command -v md5sum >/dev/null 2>&1; then
      if [ "$(md5sum "$THEME_FILE" 2>/dev/null | awk '{print $1}')" = "$(md5sum "$ap" 2>/dev/null | awk '{print $1}')" ]; then
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
  chown system_theme:system_theme "$tmp" 2>/dev/null
  chmod 0644 "$tmp" 2>/dev/null
  chcon u:object_r:theme_data_file:s0 "$tmp" 2>/dev/null
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
cmd_list() {
  i=0
  an=$(active_name)
  entry_paths | while IFS= read -r p; do
    i=$((i + 1))
    n=${p##*/}; n=${n%.zip}
    act=no
    [ "$n" = "$an" ] && act=yes
    info=$(desc_info "$p")
    has_audio "$n" && info="$info ♪"              # 包里有音频留档就标一笔
    printf '%s\t%s\t%s\t%s\t%s\n' "$i" "$n" "$(file_size "$p")" "$act" "$info"
  done
}

cmd_status() {
  an=$(active_name)
  echo "active=${an:-无}"
  # 界面要显示「文件位置」：当前动画在库里的源文件 + 刷入的主题路径 + 本机屏幕分辨率
  echo "active_path=$(active_path)"
  echo "theme_path=$THEME_FILE"
  echo "library=$LIB_DIR"
  wh=$(screen_wh)
  if [ -n "$wh" ]; then echo "screen=${wh%% *}x${wh##* }"; else echo "screen=未知"; fi
  echo "count=$(entry_count)"
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
  idx="$1"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 编号无效"; return 1;; esac
  p=$(entry_at "$idx")
  if [ -z "$p" ] || [ ! -f "$p" ]; then echo "ERROR 找不到该动画"; return 1; fi
  validate_zip "$p" || { echo "ERROR $VALID_MSG"; return 1; }
  n=$(name_of "$p")
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
  idx="$1"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 用法: fit N"; return 1;; esac
  p=$(entry_at "$idx")
  [ -n "$p" ] && [ -f "$p" ] || { echo "ERROR 找不到该动画"; return 1; }
  wh=$(screen_wh)
  [ -n "$wh" ] || { echo "ERROR 读不到本机分辨率"; return 1; }
  n=$(name_of "$p")
  manual_del "$n"                                # 显式自适应 = 恢复自动，移出手动名单
  if fit_zip "$p"; then
    finish_desc_change fitted "$n" "${FIT_TW}x${FIT_TH}"   # 方向感知后实际写入的宽高
  else
    echo "ERROR 适配失败：新分辨率串比原来的长，或 desc 不是标准格式"
    return 1
  fi
}

# 只读：打印某动画当前的 desc 分辨率，给界面里「分辨率」面板用，不写文件
cmd_desc() {
  idx="$1"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 用法: desc N"; return 1;; esac
  p=$(entry_at "$idx")
  [ -n "$p" ] && [ -f "$p" ] || { echo "ERROR 找不到该动画"; return 1; }
  line=$(desc_line "$p")
  [ -n "$line" ] || { echo "ERROR 读不到 desc.txt"; return 1; }
  parse_desc_line "$line" || { echo "ERROR desc 不是标准格式"; return 1; }
  echo "desc_w=$D_W"
  echo "desc_h=$D_H"
  echo "desc_fps=$D_FPS"
  if manual_has "$(name_of "$p")"; then echo "mode=manual"; else echo "mode=auto"; fi
  wh=$(screen_wh)
  if [ -n "$wh" ]; then echo "screen=${wh%% *}x${wh##* }"; else echo "screen=未知"; fi
  echo "desc_line=$line"
  return 0
}

# 手动设置某动画的 desc 分辨率（帧率保留）。设备上不能重建 zip，新串不能比原行长。
# 直接解析原始行（g 写法也行），写入标准格式时顺带归一化，不用先单独 normalize
cmd_setres() {
  idx="$1"; w="$2"; h="$3"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 用法: setres N 宽 高"; return 1;; esac
  case "$w" in ''|*[!0-9]*) echo "ERROR 宽必须是数字"; return 1;; esac
  case "$h" in ''|*[!0-9]*) echo "ERROR 高必须是数字"; return 1;; esac
  # 手动设定的值会进 manual.txt、部署时不再自动修正——坏值会跨重启存活，入口必须把严
  [ "${#w}" -le 5 ] && [ "${#h}" -le 5 ] || { echo "ERROR 宽高位数太长"; return 1; }
  [ "$w" -ge 100 ] && [ "$w" -le 16384 ] && [ "$h" -ge 100 ] && [ "$h" -le 16384 ] \
    || { echo "ERROR 宽高超出合理范围（100-16384）"; return 1; }
  p=$(entry_at "$idx")
  [ -n "$p" ] && [ -f "$p" ] || { echo "ERROR 找不到该动画"; return 1; }
  line=$(desc_line "$p")
  [ -n "$line" ] || { echo "ERROR 读不到 desc.txt"; return 1; }
  parse_desc_line "$line" || { echo "ERROR desc 不是标准格式"; return 1; }
  n=$(name_of "$p")
  new="$w $h $D_FPS"
  desc_replace "$p" "$line" "$new"; rc=$?
  case "$rc" in
    0) ;;
    2) echo "ERROR 新分辨率串比原来的长，写不进去（设备上不能重建 zip）"; return 1;;
    *) echo "ERROR 写入 desc 失败"; return 1;;
  esac
  log "setres: $line -> $new ($p)"
  manual_add "$n"                                # 手动设定过，自动适配不再碰它
  finish_desc_change setres "$n" "${w}x${h}"
}

# 查看/导出包内音频。audio N：列出某动画的音频留档（旧导入的包现场补提取）；
# audioout N：把音频拷到 /sdcard/Download/qimu-audio/<动画名>/ 给用户取用
cmd_audio() {
  idx="$1"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 用法: audio N"; return 1;; esac
  p=$(entry_at "$idx")
  [ -n "$p" ] && [ -f "$p" ] || { echo "ERROR 找不到该动画"; return 1; }
  n=$(name_of "$p")
  audio_ensure "$p" "$n"                         # 老导入的包音频还在 zip 里，现场补提取
  ad="$AUDIO_DIR/$n"
  au_n=0
  if has_audio "$n"; then
    au_n=$(find "$ad" -type f 2>/dev/null | grep -c .)
  fi
  echo "audio_n=$au_n"
  if [ "$au_n" -gt 0 ]; then
    find "$ad" -type f 2>/dev/null | while IFS= read -r f; do
      echo "FILE=${f#"$ad"/}"
    done
  fi
  return 0
}

cmd_audioout() {
  idx="$1"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 用法: audioout N"; return 1;; esac
  p=$(entry_at "$idx")
  [ -n "$p" ] && [ -f "$p" ] || { echo "ERROR 找不到该动画"; return 1; }
  n=$(name_of "$p")
  audio_ensure "$p" "$n"
  has_audio "$n" || { echo "ERROR 这个动画包里没有音频"; return 1; }
  ad="$AUDIO_DIR/$n"
  dst="/sdcard/Download/qimu-audio/$n"
  rm -rf "$dst" 2>/dev/null
  mkdir -p "$dst" 2>/dev/null || { echo "ERROR 建不了下载目录"; return 1; }
  cp -rf "$ad"/. "$dst"/ 2>/dev/null || { echo "ERROR 拷贝失败"; return 1; }
  find "$dst" -type f 2>/dev/null -exec chmod 0644 {} \;
  au_n=$(find "$dst" -type f 2>/dev/null | grep -c .)
  log "audio out: $n -> $dst ($au_n)"
  echo "OK audioout=$n to=$dst n=$au_n"
  return 0
}

# 交换某动画 desc 的宽高（一键修正长宽互换）。宽高位数相同，串长不变，必能写入。
cmd_rename() {
  idx="$1"; newn="$2"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 用法: rename N 新名字"; return 1;; esac
  [ -n "$newn" ] || { echo "ERROR 名字不能为空"; return 1; }
  p=$(entry_at "$idx")
  [ -n "$p" ] && [ -f "$p" ] || { echo "ERROR 找不到该动画"; return 1; }
  oldn=$(name_of "$p")
  newn=$(sanitize_name "$newn")
  [ -n "$newn" ] || { echo "ERROR 名字无效"; return 1; }
  [ "$newn" = "$oldn" ] && { echo "OK renamed=$newn"; return 0; }
  target="$LIB_DIR/$newn.zip"
  [ -e "$target" ] && { echo "ERROR 已有同名动画"; return 1; }
  was_active=no
  [ "$oldn" = "$(active_name)" ] && was_active=yes
  mv -f "$p" "$target" 2>/dev/null || { echo "ERROR 改名失败"; return 1; }
  chmod 0644 "$target" 2>/dev/null
  # 音频留档、手动分辨率名单跟着改名
  [ -d "$AUDIO_DIR/$oldn" ] && mv -f "$AUDIO_DIR/$oldn" "$AUDIO_DIR/$newn" 2>/dev/null
  if manual_has "$oldn"; then manual_del "$oldn"; manual_add "$newn"; fi
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
  idx="$1"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 用法: swap N"; return 1;; esac
  p=$(entry_at "$idx")
  [ -n "$p" ] && [ -f "$p" ] || { echo "ERROR 找不到该动画"; return 1; }
  line=$(desc_line "$p")
  [ -n "$line" ] || { echo "ERROR 读不到 desc.txt"; return 1; }
  parse_desc_line "$line" || { echo "ERROR desc 不是标准格式"; return 1; }
  n=$(name_of "$p")
  new="$D_H $D_W $D_FPS"                           # 宽高对调
  desc_replace "$p" "$line" "$new"; rc=$?
  case "$rc" in
    0) ;;
    2) echo "ERROR 交换后串更长，写不进去"; return 1;;
    *) echo "ERROR 写入 desc 失败"; return 1;;
  esac
  log "swap: $line -> $new ($p)"
  manual_add "$n"
  finish_desc_change swap "$n" "${D_H}x${D_W}"
}

cmd_import() {
  src="$1"
  [ -n "$src" ] || { echo "ERROR 未指定文件"; return 1; }
  [ -f "$src" ] || { echo "ERROR 找不到文件: $src"; return 1; }

  # 用原始文件名命名库里的动画（解包后 src 可能变成临时文件，名字得先记下来）
  base=$(sanitize_name "$(name_of "$src")")
  [ -n "$base" ] || base="imported"

  # 「模块壳」包：根目录没有 desc.txt，但内含 bootanimation.zip 条目
  #   （KSU/Magisk 模块式的开机动画包就是这种结构，动画被裹在一层模块里）
  #   解出内层 bootanimation.zip 再走正常校验/入库流程
  inner_tmp=""
  if ! unzip -l "$src" 2>/dev/null | grep -q 'desc\.txt'; then
    inner_tmp="$LIB_DIR/.unwrap.$$.tmp"
    if unzip -p "$src" bootanimation.zip > "$inner_tmp" 2>/dev/null && [ -s "$inner_tmp" ]; then
      [ "$(dd if="$inner_tmp" bs=2 count=1 2>/dev/null)" = "PK" ] && { log "unwrap module wrapper: $1 -> bootanimation.zip"; src="$inner_tmp"; } || { rm -f "$inner_tmp"; inner_tmp=""; }
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
    # 包里夹带的音频也一起收进来（bootanimation 不播声音，解出来是给用户留档/取用）
    sn=${target##*/}; sn=${sn%.zip}
    au_n=$(audio_extract "$target" "$sn")
    rm -f "$inner_tmp" 2>/dev/null             # 解包临时文件用完即删
    log "imported: $target (audio=$au_n)"
    if [ "$au_n" -gt 0 ]; then
      echo "OK stored=${target##*/} audio=$au_n"
    else
      echo "OK stored=${target##*/}"
    fi
  else
    rm -f "$tmp" 2>/dev/null
    rm -f "$inner_tmp" 2>/dev/null
    echo "ERROR 复制文件失败"
    return 1
  fi
}

cmd_delete() {
  idx="$1"
  case "$idx" in ''|*[!0-9]*) echo "ERROR 编号无效"; return 1;; esac
  p=$(entry_at "$idx")
  if [ -z "$p" ] || [ ! -f "$p" ]; then echo "ERROR 找不到该动画"; return 1; fi
  n=$(name_of "$p")
  if [ "$n" = "$(active_name)" ]; then
    echo "ERROR 该动画正在使用中，请先切换到其他动画"
    return 1
  fi
  rm -f "$p" 2>/dev/null || { echo "ERROR 删除失败"; return 1; }
  manual_del "$n"                                # 名单里残留的手动标记一并清掉
  rm -rf "$AUDIO_DIR/$n" 2>/dev/null             # 包内音频留档一起删
  log "deleted: $p"
  echo "OK deleted=$n"
}

cmd_scan() {
  for d in $SCAN_DIRS; do
    [ -d "$d" ] || continue
    for f in "$d"/*.zip "$d"/*.ZIP; do
      [ -f "$f" ] || continue
      ok=no
      validate_zip "$f" >/dev/null 2>&1 && ok=yes
      printf '%s\t%s\t%s\n' "$f" "$(file_size "$f")" "$ok"
    done
  done
}

# 列目录，给界面里「选择文件」用（用户可以自己翻到动画放的位置）
# 用法: ctl.sh ls [目录]
# 输出: D<tab>名字<tab>路径         子目录
#       F<tab>文件名<tab>大小<tab>路径   zip
cmd_ls() {
  d="$1"
  [ -n "$d" ] || d="/sdcard"
  case "$d" in
    /sdcard|/sdcard/*|/storage|/storage/*|/mnt/media_rw|/mnt/media_rw/*|/data/local/tmp|/data/local/tmp/*) ;;
    *) echo "ERROR 这个路径不让浏览：$d"; return 1 ;;
  esac
  [ -d "$d" ] || { echo "ERROR 没有这个目录：$d"; return 1; }
  ls -1 "$d" 2>/dev/null | sort | while IFS= read -r x; do
    [ -n "$x" ] || continue
    case "$x" in .*) continue ;; esac
    p="$d/$x"
    if [ -d "$p" ]; then
      printf 'D\t%s\t%s\n' "$x" "$p"
    elif [ -f "$p" ]; then
      case "$x" in
        *.zip|*.ZIP) printf 'F\t%s\t%s\t%s\n' "$x" "$(file_size "$p")" "$p" ;;
        # 视频文件单列一类（V），给「视频转动画」用；选择文件列表里不显示导入按钮
        *.mp4|*.MP4|*.mov|*.MOV|*.mkv|*.MKV|*.webm|*.WEBM|*.m4v|*.M4V|*.3gp|*.3GP)
          printf 'V\t%s\t%s\t%s\n' "$x" "$(file_size "$p")" "$p" ;;
      esac
    fi
  done
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
  audio) cmd_audio "$2" ;;
  audioout) cmd_audioout "$2" ;;
  import) cmd_import "$2" ;;
  delete) cmd_delete "$2" ;;
  scan) cmd_scan ;;
  ls) cmd_ls "$2" ;;
  reset) cmd_reset ;;
  order) shift; cmd_order "$@" ;;
  guard) install_guard && echo "OK guard installed" ;;
  unguard) remove_guard && echo "OK guard removed" ;;
  deploy) deploy_active && echo "OK deployed" ;;
  *) echo "用法: $0 {list|status|info|select N|fit N|desc N|setres N W H|swap N|import PATH|delete N|scan|ls DIR|reset|order NAME...|guard|unguard|deploy}"; exit 64 ;;
esac