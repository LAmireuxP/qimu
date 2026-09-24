# 启幕

HyperOS 的开机动画管理器，KernelSU / SukiSU / APatch / Magisk 都能用。中文界面，换动画、导入动画、删动画，或者干脆不显示动画。

HyperOS 找开机动画时先看 `/data/system/theme/boots/bootanimation.zip` 这一条，比 `/system/media`、`/product/media` 都靠前，所以这个模块直接往这条路径写，不用动系统分区。关掉模块或者卸载之后，下次开机会自动回到出厂的动画。

## 能干什么

- 换动画：界面里点「应用」，重启生效
- 导入自己的：zip 丢进「下载」目录点「扫描目录」，或者点「选择文件」自己翻到动画放的位置
- 调顺序：按住每行左边的 ⠿ 上下拖，或者用 ▲▼ 一格一格移，松手就存
- 不要动画：选「不播放动画」，开机黑屏直接进系统
- 界面跟随系统深浅色，也可以手动固定成浅色或深色

## 安装

管理器里刷 `release/qimu-1.0.1.zip`，重启，再打开模块的「设置」进界面。里面自带一个 LineageOS 的动画和「不播放动画」，装完就能用。

安装时会在 `/data/adb/post-fs-data.d/` 和 `/data/adb/service.d/` 各放一个 `qimu-guard.sh`。这两个目录在模块外面，作用只有一个：模块被关掉或删掉之后，把那条主题路径上的动画文件清掉，让开机动画回到出厂。卸载模块时脚本会一起删掉。

## 用法

1. 进界面，点某个动画的「应用」，重启
2. 加自己的动画：zip 得是 **ZIP_STORED 不压缩**、根目录有 `desc.txt`，放进「下载」目录后点「扫描目录」，或者点「选择文件」自己翻到它所在的位置导入。格式不对界面会告诉你原因
3. 动画都放在 `/data/adb/bootanims/`，当前选的是哪个记在 `var/state/selected.txt`

`tools/pad_convert.py` 可以把随便一个 AOSP 格式的动画转成能用的：按宽度缩放居中贴到黑底、desc 首行改成目标分辨率、强制不压缩。用之前 `pip install pillow`。

## 导入哪种包

网上下的「开机动画」常见两种，启幕都能吃：

**① 裸动画包** —— 就是 `bootanimation.zip` 本身，根目录直接是 `desc.txt` 加 `part0/` 这些帧目录。直接导入即可。

**② KSU/Magisk 模块包** —— 里面有 `module.prop`、`META-INF/com/google/android/update-binary`、`post-fs-data.sh`，动画被裹在里头一个 `bootanimation.zip` 里。导入时启幕会自动把内层 `bootanimation.zip` 解出来用，你不用自己拆；解出来的动画照样得过「不压缩 + 有 desc.txt」的校验，不过关会告诉你原因。

一眼区分：解压软件看一眼包里有什么——根目录直接看到 `desc.txt` + `part0` 就是 ①；看到 `module.prop` / `META-INF` 就是 ②。

> ② 这种模块包本身是设计成丢进 KernelSU/SukiSU/APatch/Magisk 管理器里「安装模块」刷的（靠开机时 bind-mount 到 `/system/media`）。你想让它当独立模块跑，就用管理器刷；想把它的动画纳入启幕统一管理，就直接导入，启幕只取内层动画。两种机制别同装：启幕走 `/data/system/theme/boots`（HyperOS 优先读这条），模块包走 `/system/media`（优先级更低），两个都装的话启幕的会赢，模块包的动画不会显示。

## 测过的机器

只有两台：

- Redmi K60 Pro（socrates，HyperOS 4.0 / Android 17 移植版，1440×3120，root 是 SukiSU）
- Redmi K30S 至尊纪念版（apollo，HyperOS 4.0 / Android 17，1080×2400，APatch，管理器 FolkPatch）

其他机器我没试过。装完重启看一眼开机动画有没有变就知道行不行，也可以跑一下看状态：

```
adb shell su -c "/data/adb/modules/custom_bootanimation/bin/ctl.sh status"
```

要是没反应，可能是你这台机器读开机动画的顺序不一样，不走主题路径。可以查一下：

```
adb shell su -c "strings /system/lib64/libbootanimation_preapex.so | grep theme/boots"
```

有输出就说明走这条路径，能生效；没输出就是不适用。

## 免责

就上面两台机器测过，别的都没测，情况可能不一样。刷这个有风险，自己判断要不要用；出了问题是自己的事（开不了机、动画不正常之类），我不担责任。刷之前先备份，确认自己有救砖的办法。

## 其他

动画格式是标准的 AOSP 那套：根目录一个 `desc.txt`，首行是「宽 高 帧率」，后面每行一个段落（`c` 或 `p` 开头），剩下的就是 part0、part1 这些目录里的帧图。整包必须不压缩，bootanimation 只认 STORED，压缩过的会被它直接拒掉。

动画格式不对的会被自动处理：小米系动画的 desc.txt 首行常写成 `g 宽 高 偏移x 偏移y 帧率`，AOSP 的 bootanimation 不认这行（会直接黑屏），本模块在导入和部署时会把它改成标准的 `宽 高 帧率`。

分辨率也会自动适配：desc 首行声明的「宽 高」就是 bootanimation 实际渲染的尺寸——比屏幕小就四周黑边，比屏幕大就被裁掉一圈。应用（部署）时本模块会把它改成屏幕的物理分辨率，让它满屏。改动同样是等长原地覆盖，所以只有新分辨率串不比原来的长时才改得动（低分辨率动画往高分屏改可能因串变长而改不了，这时保持原样）。也可以手动跑 `bin/ctl.sh fit N` 单独适配第 N 个动画。

选择记在 `var/state/selected.txt`，动画放 `/data/adb/bootanims/`，生效路径是 `/data/system/theme/boots/bootanimation.zip`（属主 system_theme，标签 theme_data_file）。开机时 `post-fs-data.sh` 负责写进去，`service.sh` 兜个底。命令行的话 `bin/ctl.sh` 有 `list / status / info / select / import / delete / scan / reset / order / deploy`。

协议 MIT。仓库里没有商业 IP 的动画：内置的 LineageOS 那个是从 LineageOS 开源项目拿的，只当个默认例子，版权还是人家的；「不播放动画」是一帧纯黑。