# Xiaomi Book 12.4 安装 Debian 13（arm64）

本文针对 Qualcomm SC8180X 平台的 **Xiaomi Book 12.4**。它不是文章示例中的 Qualcomm Primus，不能直接使用 `sc8180x-primus.dtb`。

设备树来自开源社区仓库 [CerteKim/linux-a51](https://github.com/CerteKim/linux-a51) 的 `xiaomi-book12-touch-audio` 分支，文件为 [`sc8180x-xiaomi-book-12.4.dts`](https://github.com/CerteKim/linux-a51/blob/xiaomi-book12-touch-audio/arch/arm64/boot/dts/qcom/sc8180x-xiaomi-book-12.4.dts)（分支提交示例：[`ddbac09241dc`](https://github.com/CerteKim/linux-a51/commit/ddbac09241dc0e35350bcdc7513bbe7b98e16ec8)）。安装流程参考[高通 Primus 安装 Debian 13 分享](https://driver1998.github.io/posts/qualcomm-primus-debian-13/)，但设备树和启动参数已按 Xiaomi Book 12.4 调整。

## 已制作的安装 U 盘

已将下列定制镜像写入 `/dev/sdb`（USB 型号 `wen yuan`，序列号 `2802111003517606976`）。U 盘原有数据已被覆盖：

* 镜像：`/data/mibook/img/debian-13.6.0-arm64-xiaomi-book-12.4.iso`
* 基础镜像：`debian-13.6.0-arm64-DVD-1.iso`（Debian 13.6 arm64）
* ISO 根目录：`/sc8180x-xiaomi-book-12.4.dtb`
* 定制镜像 SHA-256：`3e7e78eefb009f18b0595e4621edd614730aa8d5e5f37fbe28137942e5dd3c54`
* DTB SHA-256：`1769eb0486ccf97f6eb05969af27fd45db74c62d6275c6882bf192fc53a3f420`
* 已按镜像字节逐字节回读校验（3,989,438,464 字节）。

若需在另一台 Linux 主机重做 U 盘，先确认设备名，再执行（`/dev/sdX` **必须是 U 盘，不能是系统盘**）：

```sh
lsblk -o NAME,PATH,SIZE,MODEL,TRAN,RM,MOUNTPOINTS
sudo umount /dev/sdX?* 2>/dev/null || true
sudo dd if=/data/mibook/img/debian-13.6.0-arm64-xiaomi-book-12.4.iso \
        of=/dev/sdX bs=4M status=progress conv=fsync
sudo sync
```

## 安装前准备

1. 备份 Windows 和 EFI 分区中的重要数据，并在 Windows 磁盘管理中为 Debian 预留空间。
2. 准备 USB 有线网卡（安装阶段不要依赖内置 Wi-Fi）以及 USB 键盘。安装程序使用 arm64 网络/安装源时需要可用网络。
3. Xiaomi Book 12.4 通常同时显示 UFS、NVMe 和若干固件分区。分区时选择“手动”，**不要删除、格式化或移动任何看起来像 Qualcomm/固件的分区，也不要使用自动分区**。可将根文件系统放在 NVMe；EFI/`/boot` 应放在 UEFI 能启动的存储上，并保留现有 Windows EFI 分区。

## 启动安装程序

1. 关机，插入上述 U 盘和有线网卡。开机时按住“音量+”再按电源键进入 BDS 菜单，选择 U 盘的 `EFI/BOOT/BOOTAA64.EFI`。
2. 进入 GRUB 后按 **c**，执行：

   ```text
   devicetree /sc8180x-xiaomi-book-12.4.dtb
   ```

   按 Esc 返回菜单。
3. 选中 **Install** 或 **Graphical install**，不要回车，按 **e** 编辑启动项。找到以 `linux` 开头的一行，删除 `quiet`，在行尾加入：

   ```text
   pd_ignore_unused clk_ignore_unused efi=novamap acpi=off modprobe.blacklist=msm,dispcc_sm8250 nomodeset
   ```

   `acpi=off` 很重要：Xiaomi Book 固件同时提供 ACPI，Debian 安装器内核可能错误地按 ACPI 枚举 GENI I²C，触发 `i2c_qcom_geni` 空指针并导致 HID 键盘/触摸设备不出现。该参数让内核使用 U 盘中的 Xiaomi 设备树。`nomodeset` 和 GPU 黑名单用于安装阶段避免因固件尚未安装而黑屏。按 **Ctrl-X** 启动安装。
4. 安装器中的分区步骤选择手动分区。EFI 分区使用 FAT32、挂载到 `/boot/efi`，不要格式化已有 Windows EFI 分区；根分区、交换分区按自己的磁盘容量规划。

## 第一次启动和设备树

安装完成后，固件可能没有保存 Debian EFI 启动项。若菜单中没有 Debian：进入 BDS 的 EFI Shell，手动执行：

```text
fs0:
\EFI\debian\grubaa64.efi
```

进入 GRUB 后按 c 加载设备树。若设备树复制到了 ESP：

```text
devicetree /sc8180x-xiaomi-book-12.4.dtb
```

也可以从 U 盘临时加载（设备号用 `devicetree (hd` 后按 Tab 探测）：

```text
devicetree (hdX,gpt1)/sc8180x-xiaomi-book-12.4.dtb
```

进入系统后，将同一个 DTB 复制到 ESP 根目录，并在 `/boot/efi/EFI/debian/grub.cfg` 最前面加入：

```text
devicetree /sc8180x-xiaomi-book-12.4.dtb
```

这样 GRUB 每次都会自动加载正确的 Xiaomi 设备树。内核更新后，应从对应内核目录复制新的 `sc8180x-xiaomi-book-12.4.dtb` 到 ESP。

## 内核、GPU、Wi-Fi/蓝牙

Debian 安装器的通用 arm64 内核不一定包含 Xiaomi Book 12.4 的最新支持。建议安装完成后使用上述社区仓库的内核分支构建/安装内核，并保留 DTB。下面的命令必须在**内核源码树的顶层目录**执行，用于编译设备树，并不是已安装系统必须执行的复制命令：

```sh
make ARCH=arm64 defconfig
make ARCH=arm64 qcom/sc8180x-xiaomi-book-12.4.dtb
```

编译结果位于 `arch/arm64/boot/dts/qcom/sc8180x-xiaomi-book-12.4.dtb`。如果只需要让 GRUB 启动已安装的 Debian，直接使用前面复制到 `/boot/efi/` 的 DTB 即可，不需要再次运行 `make`；只有在更换/更新内核源码后，才需要重新编译并将新 DTB 复制到 ESP。

在确认 SSH 或串口可用后再启用 GPU：

1. 从 Windows 驱动包取得 `qcdxkmsuc8180.mbn`，放入设备专用目录
   `/lib/firmware/qcom/XIAOMI/BOOK124/`（部署包中的同名路径）。
2. 启用 `trixie-backports`，安装 `firmware-qcom-soc`，然后执行 `sudo update-initramfs -u`。
3. 重启测试；确认画面正常后，从 GRUB 和 `/etc/default/grub` 删除 `modprobe.blacklist=msm,dispcc_sm8250 nomodeset`，并执行 `sudo update-grub`。

Wi-Fi/蓝牙还需要 `qcadsp8180.mbn`、`qcmpss8180.mbn`、改为小写文件名的 `wlanmdsp.mbn`，以及：

```sh
sudo apt install qrtr-tools
sudo apt -t trixie-backports install firmware-atheros
sudo update-initramfs -u
```

`tqftpserv` 和 `rmtfs` 不要与本项目的内核内置 RMTFS/TQFTP 服务同时启用，详见下文。
文章记录了该平台可能出现的随机 Wi-Fi MAC 和蓝牙 MAC 问题；如遇到这种情况，再按文章中的 udev 规则和 `hci-btaddress@.service` 固定地址。音频、虚拟化和视频输出仍可能受当前主线支持状态限制。

### 已验证的 6.18 内核与 GPU

本机实际运行过的内核为 `6.18.2-gf9df074a5a4b-dirty`。GPU 固件安装后，`dmesg`
能够看到 A680 GMU/SQE 固件加载成功，Mesa 渲染器显示为 `FD680`，且
`Accelerated: yes`。升级内核时应同时保留匹配的 Xiaomi DTB；DTB 是设备树，不是
内核模块，不需要复制到 `/lib/linux-image-<版本>/qcom/`。推荐把它放在 EFI 系统分区，
例如 `/boot/efi/sc8180x-xiaomi-book-12.4.dtb`，并由 GRUB 的 `devicetree` 命令加载。
发行版 `firmware-qcom-soc` 提供的 `a680_gmu.bin`/`a680_sqe.fw` 位于
`/lib/firmware/qcom/`；设备专用的 `qcdxkmsuc8180.mbn` 则放在下方所述的
`qcom/XIAOMI/BOOK124/` 目录。

快速验证：

```sh
uname -r
dmesg | grep -Ei 'a680|qcom.*firmware|remoteproc' | tail -50
glxinfo -B 2>/dev/null | grep -E 'OpenGL renderer|Accelerated'
```

如果 `glxinfo` 不存在，先安装 `mesa-utils`。看到 `llvmpipe` 或
`Accelerated: no` 时，检查 A680 固件、initramfs，以及 GRUB 中是否仍残留
`nomodeset` 或 GPU 黑名单参数。

### 屏幕方向（GRUB、TTY、登录界面和 KDE）

该机面板物理安装方向与默认 DRM 方向相差 90°，正确的横向布局是对 `DSI-1` 顺时针
旋转 90°（X11 中对应 `xrandr --output DSI-1 --rotate right`）。当前配置分层处理：

* SDDM：`/etc/sddm.conf.d/10-xiaomi-book-orientation.conf` 调用
  `/usr/local/bin/xiaomi-book-display-rotate`，登录界面启动时自动旋转；
* KDE/X11：`/etc/xdg/autostart/xiaomi-book-display-rotate.desktop` 在用户会话启动时
  应用同一设置；
* TTY：内核启用 `CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y`，GRUB（包括自定义
  `06_xiaomi-book-rmtfs` 菜单项）加入 `fbcon=rotate:1`。`rotate:1` 表示顺时针 90°。

验证命令：

```sh
cat /proc/cmdline                         # 应包含 fbcon=rotate:1
cat /sys/class/graphics/fbcon/rotate      # 切换到活动 TTY 后通常为 1；图形会话下可能仍为 0
DISPLAY=:0 xrandr --query                 # DSI-1 应显示 2560x1600 ... right
```

GRUB 的 `gfxterm` 本身没有通用的旋转选项，因此启动菜单仍可能以固件原生方向显示；
进入内核后 TTY、SDDM 和 KDE 会切换为横向。若使用 KDE Wayland，需在 Plasma 的显示
设置中把 `DSI-1` 旋转为 90°（X11 的 `xrandr` 只作用于 X11 会话）。

### NetworkManager 与固定 MAC（KDE 推荐）

KDE 的网络小程序原生使用 NetworkManager。不要让 NetworkManager、独立的
`wpa_supplicant@wlan0` 和 `dhcpcd-wlan0` 同时管理同一接口，否则会出现抢占、掉线和
MAC 被改回硬件地址。通过 Wi-Fi SSH 切换管理器时连接会短暂中断，建议预留有线或串口
作为恢复通道。

首次配置（将 `<密码>` 替换为实际密码，不要把密码提交到仓库）：

```sh
sudo nmcli connection add type wifi ifname wlan0 con-name SunnyMoom ssid SunnyMoom \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk '<密码>' ipv4.method auto \
  connection.autoconnect yes
sudo nmcli connection modify SunnyMoom \
  802-11-wireless.cloned-mac-address 02:11:22:33:44:55 \
  802-11-wireless.mac-address-randomization never
sudo systemctl disable --now wpa_supplicant@wlan0.service
sudo systemctl disable --now dhcpcd-wlan0.service
sudo nmcli connection up SunnyMoom
```

验证：

```sh
nmcli device status
nmcli -f GENERAL.STATE,GENERAL.CONNECTION,GENERAL.HWADDR device show wlan0
ip link show wlan0                         # 应显示 02:11:22:33:44:55
ip -4 addr show wlan0                      # 应取得 DHCP 地址
```

固定 MAC 只保证二层地址，不等于固定 IP。设备重启后 DHCP 地址仍可能变化；需要在
路由器中为 `02:11:22:33:44:55` 建立 DHCP 地址保留（例如保留原来的
`192.168.50.198`），然后同步更新端口转发。NetworkManager 连接文件位于
`/etc/NetworkManager/system-connections/`，权限应为 `600`，其中包含 Wi-Fi 密钥，
不要上传或纳入版本控制。

### 触摸屏

触摸屏在 Windows DSDT 中称为 `I2C2`，但其 MMIO 地址 `0x00884000` 对应 Linux
设备树的 `&i2c1`（QUP0 SE1）。旧配置把 HID 节点放在禁用的 `&i2c2`，因此系统只有
USB 触摸板而没有内置触摸屏。社区 `xiaomi-book12-touch-clean` 分支的修复已移植到
本设备树：启用 `&i2c1`、挂载 `hid-over-i2c` 地址 `0x4f`，并使用 GPIO122 中断。

编译并更新 DTB 后重启，以下设备应出现在 `/proc/bus/input/devices`：

```text
hid-over-i2c 4858:121A Touchscreen
hid-over-i2c 4858:121A Stylus
```

如果触摸屏不出现，确认 GRUB 实际加载的是更新后的 DTB（本机有两个启动项，需同时
更新 `/boot/efi/sc8180x-xiaomi-book-12.4.dtb` 和
`/boot/sc8180x-xiaomi-book-12.4-rmtfs.dtb`），并检查：

```sh
find /sys/firmware/devicetree/base -name 'touchscreen@4f'
dmesg | grep -Ei 'i2c_hid|geni_i2c|touchscreen'
```

### 蓝牙

WCN3998 蓝牙固件 `qca/crbtfw21.tlv` 与 `qca/crnv21.bin` 已能正常下载，控制器会以
HCI UART 方式出现。该机需要先通过 BlueZ 管理接口写入公共地址，再执行上电；否则
`hciconfig hci0 up` 会返回 `Operation not supported`，`bluetoothctl` 也会显示没有
默认控制器。

本机采用地址 `39:90:21:64:07:00`，并安装了：

* `/etc/udev/rules.d/99-xiaomi-book-bluetooth.rules`：HCI 设备加入时触发服务；
* `/etc/systemd/system/hci-btaddress@.service`：等待固件初始化后运行
  `btmgmt public-addr` 和 `btmgmt power on`。

验证蓝牙：

```sh
systemctl status bluetooth hci-btaddress@hci0.service
btmgmt info
bluetoothctl list
hciconfig -a                         # 应为 UP RUNNING，HCI 5.0
```

`btmgmt info` 应列出 `hci0`，并显示 `powered ... br/edr le`。如果服务只显示
`Invalid Index`，通常是它执行得太早；确认服务仍为模板服务并由 udev 触发，等待下一次
启动即可。不要使用随机蓝牙地址，否则已配对设备会失效。

### RMTFS/TQFTP 服务的经验

SC8180X 的 MPSS/RMTFS 支持由定制内核提供时，不要启用用户态 `tqftpserv.service` 或
`rmtfs.service`。它们会寻找不存在的 `modemst1/modemst2` 分区，导致报错甚至触发
MPSS 崩溃循环。若已安装，可停止并禁用：

```sh
sudo systemctl disable --now tqftpserv.service rmtfs.service
```

## 维护清单

* 内核更新：重新编译匹配的 `arch/arm64/boot/dts/qcom/sc8180x-xiaomi-book-12.4.dtb`，复制到 ESP，并确认 GRUB 仍加载它。
* 固件更新：按部署包规定的 `/lib/firmware` 子目录安装 GPU、ADSP/MPSS、WLAN DSP、蓝牙和 ath10k 校准文件，运行 `update-initramfs -u` 后重启验证。
* 网络变更：只使用 NetworkManager；固定 MAC 后在路由器同步设置 DHCP 保留和端口转发。
* 触摸/蓝牙：保持最新 DTB；确认 `Touchscreen`、`Stylus` 输入设备和 `hci0` 控制器均已出现。
* 故障记录：保存 `uname -r`、`dmesg` 中 remoteproc/GPU/WCN 错误、`nmcli device status` 和 `ip addr`。

## 变更记录

* **2026-08-31**：完成 A680 GPU 固件验证（`FD680`、硬件加速开启）；将 Wi-Fi 规划为
  NetworkManager 单一管理，连接名 `SunnyMoom`，关闭随机 MAC 并固定为
  `02:11:22:33:44:55`；停用会与内核 RMTFS/TQFTP 冲突的用户态服务。
* **2026-08-31**：移植社区触摸屏 I²C 映射修复，验证内置触摸屏和 Stylus 输入设备出现；
  增加 udev/systemd 蓝牙地址初始化并验证 `hci0` 自动上电。
* **2026-08-31**：为面板方向增加 SDDM/KDE X11 旋转脚本；启用内核 framebuffer 控制台
  旋转支持，并在所有 GRUB 启动项加入 `fbcon=rotate:1`。
* **2026-08-31**：启用 SC8180X PMIC PON 电源键（`pmc8180_pwrkey`），使实体电源键
  注册为 `KEY_POWER` 并具备挂起唤醒资格；此前该节点在基线设备树中被禁用。
* **2026-08-31**：清理未生效的 systemd 背光睡眠钩子；Wayland KDE 的亮度由 KWin/PowerDevil
  管理，修正 `kwinoutputconfig.json` 中将软件亮度锁定为 `0.005` 的旧配置，并允许 SDR
  软件亮度控制。重新登录 KDE 后亮度滑块才会加载该设置。
* **2026-08-31**：修正 SDDM Xorg 登录界面的触控坐标，新增
  `40-xiaomi-touchscreen.conf`，将触控矩阵与 `xrandr --rotate right` 同步；该配置不影响
  KDE Wayland 会话。

## 故障安全

* 安装器黑屏：确认 DTB 文件名是 `sc8180x-xiaomi-book-12.4.dtb`，并检查启动行仍包含 `acpi=off`、`nomodeset`、`modprobe.blacklist=msm,dispcc_sm8250`。
* 内置键盘无响应：先接入 USB 键盘，在 GRUB 启动编辑中加入 `acpi=off`。若加入后键盘恢复，说明原先是 ACPI 枚举 GENI I²C 时的内核崩溃；若仍无响应，请保留 USB 键盘完成安装，后续需要带有 Xiaomi/GENI ACPI 修复的内核。
* 找不到内置磁盘：先不要修改分区；确认使用的是正确的 UFS/NVMe 设备，并从有线网卡继续安装。
* 进入 Qualcomm Crashdump Mode：长按电源重启；稳定系统前不要尝试虚拟化（Primus/SC8180X 平台的 `slbounce` 可能触发固件崩溃）。
* 睡眠无法唤醒：当前平台仅暴露 `s2idle`，且旧 DTB 未启用 PMIC 电源键。已在新 DTB
  中启用 `pmc8180_pwrkey`；更新 ESP 中 DTB 后再验证。若仍无法恢复，先在
  `/etc/systemd/logind.conf.d/` 将电源键/合盖动作设为 `lock`，避免再次进入不可恢复的睡眠，
  不要在无本地恢复手段时直接写入 `/sys/power/state`。
