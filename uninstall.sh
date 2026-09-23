#!/system/bin/sh
# 卸载时清理：
#  1) 主题路径里由本模块写入的开机动画 → 让开机动画回到出厂
#  2) 守卫脚本（位于模块外的 post-fs-data.d / service.d）→ 避免残留
THEME_FILE="/data/system/theme/boots/bootanimation.zip"
rm -f "$THEME_FILE" 2>/dev/null
# 兼容旧版可能留下的符号链接
[ -L "$THEME_FILE" ] && rm -f "$THEME_FILE" 2>/dev/null
rm -f /data/adb/post-fs-data.d/qimu-guard.sh /data/adb/service.d/qimu-guard.sh 2>/dev/null
setprop debug.sf.nobootanimation 0 2>/dev/null
echo "启幕：已清理主题路径动画与守卫脚本，重启后恢复系统默认"
