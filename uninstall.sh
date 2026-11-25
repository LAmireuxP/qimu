#!/system/bin/sh
# Clean up on module uninstall:
#  1) Remove custom boot animation from theme path to revert to factory default
#  2) Remove guard scripts from post-fs-data.d and service.d
THEME_FILE="/data/system/theme/boots/bootanimation.zip"
rm -f "$THEME_FILE" 2>/dev/null
[ -L "$THEME_FILE" ] && rm -f "$THEME_FILE" 2>/dev/null
rm -f /data/adb/post-fs-data.d/qimu-guard.sh /data/adb/service.d/qimu-guard.sh 2>/dev/null
if command -v resetprop >/dev/null 2>&1; then
  resetprop -n debug.sf.nobootanimation 0 2>/dev/null
else
  setprop debug.sf.nobootanimation 0 2>/dev/null
fi
echo "QIMU: Cleaned up theme path animation and guard scripts. Restoring default boot animation after reboot."
