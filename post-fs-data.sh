#!/system/bin/sh
# post-fs-data 阶段部署开机动画（早于 SurfaceFlinger/bootanim，此阶段生效最可靠）
MODDIR=${0%/*}
mkdir -p "$MODDIR/var/logs" 2>/dev/null
exec >>"$MODDIR/var/logs/post-fs-data.log" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data start"
"$MODDIR/bin/ctl.sh" deploy
echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data done"