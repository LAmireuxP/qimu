#!/system/bin/sh
# 开机动画管理器 - 控制脚本
# 用法: ctl.sh {list|status|info|select N|import PATH|delete N|scan|reset|order NAME...|guard|unguard|deploy}
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

mkdir -p "$LIB_DIR" "$STATE_DIR" "$LOG_DIR" 2>/dev/null

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_DIR/ctl.log" 2>/dev/null; }

# ---------- 工具（参数展开，不派生子进程） ----------
# 取不带 .zip 的动画名
name_of() { n=${1##*/}; printf '%s\n' "${n%.zip}"; }
file_size() { wc -c <"$1" 2>/dev/null | tr -d ' '; }

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
  [ "$(dd if="$vf" bs=2 count=1 2>/dev/null)" = "PK" ] || { VALID_MSG="不是有效的 zip 文件"; return 1; }
  command -v unzip >/dev/null 2>&1 || return 0

  # 1) 根目录必须有 desc.txt（用 -l 列表 + grep，不依赖任何列格式）
  unzip -l "$vf" 2>/dev/null | grep -q 'desc\.txt' || { VALID_MSG="zip 根目录缺少 desc.txt"; return 1; }

  # 2) 压缩方式：直接读第一个本地文件头的「压缩方法」字段（偏移 8-9，小端；0=STORED）
  #    与 unzip 实现无关，也比解析 unzip -v 的列更可靠
  m=$(dd if="$vf" bs=1 skip=8 count=2 2>/dev/null | od -An -tu1 2>/dev/null | tr -s ' ')
  case "$m" in
    " 0 0") ;;
    *) VALID_MSG="动画必须是 ZIP_STORED 无压缩格式"; return 1 ;;
  esac

  # 3) 兜底全量检查：若该 unzip 的 -v 会打印方法名，出现压缩方法名即拒绝（覆盖混合压缩包）
  if unzip -v "$vf" 2>/dev/null | grep -qE 'Defl|DefN|BZip2|LZMA|Zstd'; then
    VALID_MSG="动画必须是 ZIP_STORED 无压缩格式"
    return 1
  fi
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

active_name() { [ -s "$SELECTED_FILE" ] && cat "$SELECTED_FILE" 2>/dev/null | tr -d '\r\n'; }
active_path() {
  an=$(active_name)
  [ -n "$an" ] && [ -f "$LIB_DIR/$an.zip" ] && echo "$LIB_DIR/$an.zip"
}

desc_info() {
  unzip -p "$1" desc.txt 2>/dev/null | tr -d '\r' | awk '/^[0-9]+[ \t]+[0-9]+/ {print $1"×"$2" · "$3"fps"; exit}'
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

  if [ ! -d "$THEME_DIR" ]; then
    mkdir -p "$THEME_DIR" 2>/dev/null || { log "theme dir create failed"; return 1; }
  fi
  chown system_theme:system_theme "$THEME_DIR" 2>/dev/null
  chmod 0775 "$THEME_DIR" 2>/dev/null
  chcon u:object_r:theme_data_file:s0 "$THEME_DIR" 2>/dev/null

  if [ -f "$THEME_FILE" ] && [ "$(file_size "$THEME_FILE")" = "$new_size" ]; then
    # 大小一致才有必要细究；stamp 一致说明就是本模块上次写的那一份 → 直接跳过
    if [ "$(cat "$STAMP_FILE" 2>/dev/null)" = "$stamp_val" ]; then
      log "theme already current (stamp)"
      return 0
    fi
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
    printf '%s\t%s\t%s\t%s\t%s\n' "$i" "$n" "$(file_size "$p")" "$act" "$(desc_info "$p")"
  done
}

cmd_status() {
  an=$(active_name)
  echo "active=${an:-无}"
  echo "count=$(entry_count)"
  echo "library=$LIB_DIR"
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

cmd_import() {
  src="$1"
  [ -n "$src" ] || { echo "ERROR 未指定文件"; return 1; }
  [ -f "$src" ] || { echo "ERROR 找不到文件: $src"; return 1; }
  validate_zip "$src" || { echo "ERROR $VALID_MSG"; return 1; }
  base=$(sanitize_name "$(name_of "$src")")
  [ -n "$base" ] || base="imported"
  target="$LIB_DIR/$base.zip"
  n=2
  while [ -e "$target" ]; do target="$LIB_DIR/$base-$n.zip"; n=$((n + 1)); done
  tmp="$LIB_DIR/.import.$$.tmp"
  if cp -f "$src" "$tmp" 2>/dev/null && mv -f "$tmp" "$target" 2>/dev/null; then
    chmod 0644 "$target" 2>/dev/null
    log "imported: $target"
    echo "OK stored=${target##*/}"
  else
    rm -f "$tmp" 2>/dev/null
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
  import) cmd_import "$2" ;;
  delete) cmd_delete "$2" ;;
  scan) cmd_scan ;;
  reset) cmd_reset ;;
  order) shift; cmd_order "$@" ;;
  guard) install_guard && echo "OK guard installed" ;;
  unguard) remove_guard && echo "OK guard removed" ;;
  deploy) deploy_active && echo "OK deployed" ;;
  *) echo "用法: $0 {list|status|info|select N|import PATH|delete N|scan|reset|order NAME...|guard|unguard|deploy}"; exit 64 ;;
esac