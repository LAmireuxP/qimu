#!/system/bin/sh
# late_start 兜底：主题引擎若在启动过程中清空了动画文件，这里补写一次
MODDIR=${0%/*}
mkdir -p "$MODDIR/var/logs" 2>/dev/null
exec >>"$MODDIR/var/logs/service.log" 2>&1
sleep 20
echo "[$(date '+%Y-%m-%d %H:%M:%S')] service check"
if [ ! -f /data/system/theme/boots/bootanimation.zip ]; then
  echo "theme file missing, re-deploy"
  "$MODDIR/bin/ctl.sh" deploy
else
  echo "theme file present, nothing to do"
fi