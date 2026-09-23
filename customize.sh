#!/system/bin/sh
ui_print "***************************"
ui_print " 启幕 · HyperOS 开机动画管理器"
ui_print "***************************"
ui_print "- 动画库：/data/adb/bootanims"
ui_print "- 生效路径：/data/system/theme/boots/bootanimation.zip"
ui_print "***************************"

MODDIR="${MODPATH:-${0%/*}}"
LIB=/data/adb/bootanims
STATE="$MODDIR/var/state"

mkdir -p "$MODDIR/var/logs" "$STATE" "$LIB" 2>/dev/null
chmod 0755 "$MODDIR"/*.sh "$MODDIR/bin/ctl.sh" 2>/dev/null
chmod 0644 "$MODDIR/module.prop" "$MODDIR/webroot/index.html" 2>/dev/null

# ---- 内置动画入库（已存在同名文件则跳过，保护用户自己的动画）----
seeded=0
for f in "$MODDIR"/animations/*.zip; do
  [ -f "$f" ] || continue
  n=$(basename "$f")
  if [ ! -f "$LIB/$n" ]; then
    cp -f "$f" "$LIB/$n" 2>/dev/null && chmod 0644 "$LIB/$n" 2>/dev/null && seeded=$((seeded + 1))
  fi
done
[ "$seeded" -gt 0 ] && ui_print "- 内置动画入库：$seeded 个"

count=$(ls "$LIB"/*.zip 2>/dev/null | wc -l | tr -d ' ')
ui_print "- 当前动画库共 $count 个动画"

# ---- 升级安装时沿用旧模块里的选择 ----
# 管理器更新模块会整个替换模块目录，var/state 里的选择也会一起没掉，
# 所以这里先把旧模块记的选择拷过来（旧目录在替换前仍然存在）。
OLD_STATE="/data/adb/modules/custom_bootanimation/var/state"
if [ ! -s "$STATE/selected.txt" ] && [ -s "$OLD_STATE/selected.txt" ]; then
  cp -f "$OLD_STATE/selected.txt" "$STATE/selected.txt" 2>/dev/null
  [ -s "$OLD_STATE/order.txt" ] && cp -f "$OLD_STATE/order.txt" "$STATE/order.txt" 2>/dev/null
  ui_print "- 已沿用上次的选择：$(cat "$STATE/selected.txt" 2>/dev/null)"
fi

# ---- 首次安装（没有选择记录）时给一个默认可用的动画 ----
if [ ! -s "$STATE/selected.txt" ]; then
  default_anim=""
  for f in "$MODDIR"/animations/*.zip; do
    [ -f "$f" ] || continue
    n=$(basename "$f"); n=${n%.zip}
    [ "$n" = "不播放动画" ] && continue
    [ -f "$LIB/$n.zip" ] && { default_anim="$n"; break; }
  done
  if [ -z "$default_anim" ] && [ -f "$LIB/不播放动画.zip" ]; then
    default_anim="不播放动画"
  fi
  if [ -n "$default_anim" ]; then
    printf '%s\n' "$default_anim" >"$STATE/selected.txt" 2>/dev/null
    ui_print "- 默认动画：$default_anim"
  fi
fi

# ---- 安装守卫脚本（模块被关闭时靠它把动画恢复出厂）----
if [ -x "$MODDIR/bin/ctl.sh" ]; then
  "$MODDIR/bin/ctl.sh" guard >/dev/null 2>&1
fi
guard_n=0
for d in /data/adb/post-fs-data.d /data/adb/service.d; do
  [ -f "$d/qimu-guard.sh" ] && guard_n=$((guard_n + 1))
done
[ "$guard_n" -gt 0 ] && ui_print "- 守卫脚本已装好（关掉模块后开机会回出厂动画）"

ui_print "- 装完重启，打开模块的「设置」就是界面"