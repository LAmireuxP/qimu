# 启幕

HyperOS 的开机动画管理器，KernelSU / SukiSU / APatch / Magisk 都能用。中文界面，换动画、导入动画、删动画、把视频转成开机动画、调分辨率，或者干脆不显示动画。

HyperOS 找开机动画时先看 `/data/system/theme/boots/bootanimation.zip` 这一条，比 `/system/media`、`/product/media` 都靠前，所以这个模块直接往这条路径写，不用动系统分区。关掉模块或者卸载之后，下次开机会自动回到出厂的动画。

## 能干什么

- 换动画：界面里点「应用」，重启生效
- 导入自己的：zip 丢进「下载」目录点「扫描目录」，或者点「选择文件」自己翻到动画放的位置
- 调顺序：按住每行左边的 ⠿ 上下拖，或者用 ▲▼ 一格一格移，松手就存
- 不要动画：选「不播放动画」，开机黑屏直接进系统
- 视频转动画：手机里的视频（MP4/MOV/MKV/WEBM）直接转成开机动画并导入，全程手机本地完成，不用电脑
- 分辨率自动适配：刷入时自动改到你屏幕的尺寸，不会黑边也不会被裁掉；方向画反也能自动纠正，界面里还能手动调
- 界面跟随系统深浅色，也可以手动固定成浅色或深色

## 安装

管理器里刷 [Releases](https://github.com/LAmireuxP/qimu/releases) 里最新的 zip，重启，再打开模块的「设置」进界面。里面自带一个 LineageOS 的动画和「不播放动画」，装完就能用。升级直接刷新包，你之前选的动画和排序都会保留。

安装时会在 `/data/adb/post-fs-data.d/` 和 `/data/adb/service.d/` 各放一个 `qimu-guard.sh`。这两个目录在模块外面，作用只有一个：模块被关掉或删掉之后，把那条主题路径上的动画文件清掉，让开机动画回到出厂。卸载模块时脚本会一起删掉。

## 用法

1. 进界面，点某个动画的「应用」，重启
2. 加自己的动画：zip 得是 **ZIP_STORED 不压缩**、根目录有 `desc.txt`，放进「下载」目录后点「扫描目录」，或者点「选择文件」自己翻到它所在的位置导入。格式不对界面会告诉你原因
3. 想用视频当开机动画：点「视频转换」，选手机里的视频（下载/影片目录，或自己翻目录）一键转换导入，不用电脑
4. 正在用哪个动画，界面里有「使用中」标记

`tools/pad_convert.py` 可以把随便一个 AOSP 格式的动画转成能用的：帧按 cover 方式缩放裁切到目标分辨率（满屏无黑边、无损 PNG）、desc 首行改成目标分辨率、强制不压缩。用之前 `pip install pillow`，目标尺寸跟在名字后面传，如 `python tools/pad_convert.py 源.zip 目标.zip 名字 1080x2400`。

`tools/mp4_convert.py` 是视频转动画的电脑端版本，和模块里内置的「视频转换」效果一样，适合想批量转、或要精确控制帧率和分辨率的时候用：`pip install imageio-ffmpeg pillow` 之后 `python tools/mp4_convert.py 视频.mp4 动画包.zip`，视频里的音轨也会提取进包里。日常用模块界面里的「视频转换」就够了，这两个工具是备着批量处理和精细控制用的。

## 导入哪种包

网上下的「开机动画」常见两种，启幕都能吃：

**① 裸动画包** —— 就是 `bootanimation.zip` 本身，根目录直接是 `desc.txt` 加 `part0/` 这些帧目录。直接导入即可。

**② KSU/Magisk 模块包** —— 里面有 `module.prop`、`META-INF/com/google/android/update-binary`、`post-fs-data.sh`，动画被裹在里头一个 `bootanimation.zip` 里。导入时启幕会自动把内层 `bootanimation.zip` 解出来用，你不用自己拆；解出来的动画照样得过「不压缩 + 有 desc.txt」的校验，不过关会告诉你原因。

一眼区分：解压软件看一眼包里有什么——根目录直接看到 `desc.txt` + `part0` 就是 ①；看到 `module.prop` / `META-INF` 就是 ②。

> ② 这种模块包也可以直接丢进管理器里当独立模块刷，两种方式选一种就行。注意别两种都装：都装的话启幕的会生效，模块包自己的动画不会显示。

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

动画包的格式要求：根目录要有 `desc.txt`（第一行是「宽 高 帧率」），整个包不能压缩（ZIP_STORED）。用 Windows 记事本改过 `desc.txt` 的包可能带隐藏字符、刷进去会黑屏——导入时启幕会检查出来并告诉你原因。

有些小米系动画的 `desc.txt` 用的是小米自己的写法，标准播放器不认（直接黑屏）。启幕在导入和刷入时会自动转成标准写法，不用你管。

分辨率会自动适配：动画刷入时自动改成你屏幕的分辨率——比屏幕小会黑边、比屏幕大会被裁掉，适配后就满屏；方向也会自动识别，不会出现画面颠倒。在界面里手动调过分辨率（或点过「交换宽高」）的动画，之后刷入都按你手动设的来；想恢复自动适配，再点一次「自适应屏幕」就行。

界面「当前动画」那栏会显示这个动画的来源文件路径、刷入位置和你的屏幕分辨率，能看清「文件在哪、刷到哪」。

动画都放在 `/data/adb/bootanims/`，生效文件是 `/data/system/theme/boots/bootanimation.zip`。想用命令行操作的话，`bin/ctl.sh` 有这些子命令：`list / status / info / select / fit / desc / setres / swap / import / delete / scan / ls / reset / order / deploy`。

协议 MIT。仓库里没有商业 IP 的动画：内置的 LineageOS 那个是从 LineageOS 开源项目拿的，只当个默认例子，版权还是人家的；「不播放动画」是一帧纯黑。