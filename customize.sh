#!/system/bin/sh
ui_print "*****************************************"
ui_print " QIMU · Boot Animation Manager"
ui_print "*****************************************"
ui_print "- Animation library: /data/adb/bootanims"
ui_print "- Active theme path: /data/system/theme/boots/bootanimation.zip"
ui_print "*****************************************"

MODDIR="${MODPATH:-${0%/*}}"
LIB=/data/adb/bootanims
STATE="$MODDIR/var/state"

mkdir -p "$MODDIR/var/logs" "$STATE" "$LIB" 2>/dev/null
chmod 0755 "$MODDIR"/*.sh "$MODDIR/bin/ctl.sh" 2>/dev/null
chmod 0644 "$MODDIR/module.prop" "$MODDIR/webroot/index.html" "$MODDIR/webroot/i18n.js" 2>/dev/null

# ---- Seed built-in animations (skip existing to preserve user files) ----
seeded=0; kept_n=0; kept_names=""
for f in "$MODDIR"/animations/*.zip; do
  [ -f "$f" ] || continue
  n=$(basename "$f")
  if [ ! -f "$LIB/$n" ]; then
    cp -f "$f" "$LIB/$n" 2>/dev/null && chmod 0644 "$LIB/$n" 2>/dev/null && seeded=$((seeded + 1))
  else
    kept_n=$((kept_n + 1))
    [ "$kept_n" -le 3 ] && kept_names="$kept_names $n"
  fi
done
[ "$seeded" -gt 0 ] && ui_print "- Seeded built-in animations: $seeded item(s)"
if [ "$kept_n" -gt 0 ]; then
  [ "$kept_n" -gt 3 ] && kept_names="$kept_names and others ($kept_n total)"
  ui_print "- Existing animation kept: $kept_names"
fi

count=$(ls "$LIB"/*.zip 2>/dev/null | wc -l | tr -d ' ')
ui_print "- Animation library total: $count animation(s)"

# ---- Preserve settings across upgrades ----
OLD_STATE="/data/adb/modules/custom_bootanimation/var/state"
if [ ! -s "$STATE/selected.txt" ] && [ -s "$OLD_STATE/selected.txt" ]; then
  cp -f "$OLD_STATE/selected.txt" "$STATE/selected.txt" 2>/dev/null
  [ -s "$OLD_STATE/order.txt" ] && cp -f "$OLD_STATE/order.txt" "$STATE/order.txt" 2>/dev/null
  [ -s "$OLD_STATE/manual.txt" ] && cp -f "$OLD_STATE/manual.txt" "$STATE/manual.txt" 2>/dev/null
  ui_print "- Preserved previous selection: $(cat "$STATE/selected.txt" 2>/dev/null)"
fi

# ---- Initial install: set a default active animation ----
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
    ui_print "- Default animation: $default_anim"
  fi
fi

# ---- Install guard scripts to restore stock animation if module is disabled ----
if [ -x "$MODDIR/bin/ctl.sh" ]; then
  "$MODDIR/bin/ctl.sh" guard >/dev/null 2>&1
fi
guard_n=0
for d in /data/adb/post-fs-data.d /data/adb/service.d; do
  [ -f "$d/qimu-guard.sh" ] && guard_n=$((guard_n + 1))
done
[ "$guard_n" -gt 0 ] && ui_print "- Guard scripts installed (restores stock boot animation if disabled)"

ui_print "- Installation completed successfully"
ui_print "- Reboot device, then open module Action/WebUI to configure"
