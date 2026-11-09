#!/system/bin/sh
# late_start 兜底：主题引擎若在启动过程中清空了动画文件，这里补写一次。
# 用 sync 不用 deploy：sync 会强制重读一次真实屏幕分辨率（此时 window 服务已起来），
# 把结果缓存进 state/screen.txt，下次开机早期 post-fs-data 阶段适配用得上；顺带清残留。
MODDIR=${0%/*}
mkdir -p "$MODDIR/var/logs" 2>/dev/null
exec >>"$MODDIR/var/logs/service.log" 2>&1
sleep 20
echo "[$(date '+%Y-%m-%d %H:%M:%S')] service check"
if [ ! -f /data/system/theme/boots/bootanimation.zip ]; then
  echo "theme file missing, re-sync"
else
  echo "theme file present, refresh screen cache"
fi
# 都在的时候也跑：补一次真实屏幕尺寸缓存 + 清中断的转换残留
"$MODDIR/bin/ctl.sh" sync
