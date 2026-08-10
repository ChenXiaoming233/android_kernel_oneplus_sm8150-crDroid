# OnePlus 7 Pro (guacamole) Droidspaces 内核适配技术说明

本文记录 `droidspaces/crdroid-10.11-guacamole` 分支为 OnePlus 7 Pro
(`guacamole`) 的 crDroid 10.11 / Android 14 所做的 Droidspaces 内核适配。
它既是构建与刷写的维护文档，也明确每一项结论的证据等级，避免把
“配置存在”“CI 编译成功”和“真机可用”混为一谈。

## 1. 结论与范围

| 项目 | 状态 | 证据或边界 |
| --- | --- | --- |
| 基线识别 | 已确认 | 上游 `14.0` 的 `a9f392aca6a4453660bc80682f4b68a8cf4712d5` 与设备原始内核版本后缀一致。 |
| 非 GKI 必要能力 | 已修改并由 CI 脚本审计 | `lineage_sm8150_defconfig` 和 `scripts/verify-droidspaces-config.sh`。 |
| cgroup 前缀兼容 | 已修改 | `kernel/cgroup/cgroup.c` 的兼容链接。 |
| AK3 构建、签名模块打包 | 已实现 | `.github/workflows/build-droidspaces-ak3.yml` 与 `.github/ak3/anykernel.sh`。 |
| 内核和基础 Droidspaces 运行 | 已真机验证 | 已刷入 `61a12d4d9554` 构建；系统开机、Droidspaces 自检、Wi-Fi 和 NAT 容器网络均通过。 |
| UFW / Fail2ban 所需 netfilter 扩展 | 已提交，未以该提交完成真机验证 | `412cae350847` 晚于当前设备所运行的 `61a12d4d9554`。 |
| Ubuntu 24 容器 | 已运行验证 | `Container-Home` 的 systemd、NAT、DNS、外网连通性和 SSH 已验证。 |

本文不改变 ROM 的 userspace、Droidspaces APK 或容器 rootfs，也不承诺让
Linux 4.14 获得新 GKI 内核的全部能力。适配目标是提供 Droidspaces
Non-GKI 路径所需的内核接口，并将内核镜像与其可加载模块作为同一个可回滚
交付物。

本文中的状态含义如下：**已修改**表示代码已进入该分支；**CI 验证**表示
工作流已能把该分支的输入编译并完成脚本门槛；**真机验证**表示该具体提交已
刷入本设备并完成对应运行时测试。后一层不能由前两层推导出来。

## 2. 版本、设备与分支

| 属性 | 值 |
| --- | --- |
| 设备 | OnePlus 7 Pro (`guacamole` / `OnePlus7Pro`) |
| ROM 基线 | crDroid 10.11，Android 14 |
| 上游仓库/分支 | `crdroidandroid/android_kernel_oneplus_sm8150:14.0` |
| 上游基线提交 | `a9f392aca6a4453660bc80682f4b68a8cf4712d5` |
| 内核家族 | Qualcomm SM8150，Linux 4.14，Non-GKI |
| 设备 defconfig | `arch/arm64/configs/lineage_sm8150_defconfig` |
| 适配分支 | `droidspaces/crdroid-10.11-guacamole` |
| 本文对应的分支 HEAD | `412cae3508478c249dba1b6ac11fd836c941ea38` |
| 已刷入并开机的提交 | `61a12d4d9554` |
| 已见真机内核版本 | `4.14.355-perf-g61a12d4d9554` |

不要使用同设备的 LineageOS 压缩源码或其他 SM8150 内核替代上述基线。即使
版本号相近，boot 镜像布局、设备树、模块 ABI、厂商配置和编译器组合也可能
不同。

### 2.1 适配过程与提交边界

| 提交 | 工作内容 | 影响范围 |
| --- | --- | --- |
| `554d05865592` | 加入 Non-GKI 必要配置、cgroup 兼容补丁、配置验证脚本、AK3 工作流和初始文档。 | 运行时能力与 CI 交付链。 |
| `40df5c19bc20` | 明确 LLVM 工具变量，使用固定的 crDroid Clang。 | 编译可复现性。 |
| `c87f9c465419` | 清理 Oplus Kconfig 重复声明。 | Kconfig 解析稳定性。 |
| `282fe36a7ae3` | 打包并验证匹配的签名模块。 | Wi-Fi 等可加载硬件模块。 |
| `d70a92f7ca88`、`61a12d4d9554` | 增强 Magisk ramdisk 预检日志并修正绝对路径。 | AK3 刷写前诊断和保护。 |
| `412cae350847` | 加入 UFW/Fail2ban 所需 netfilter 与 ipset 能力。 | 容器防火墙功能。 |

适配顺序刻意先解决“可编译、可打包、内核和模块不分离”，再增加可选的防火墙
能力。这样当后续刷写或容器网络异常时，能够按提交范围收敛问题，而不会把
工具链、模块、cgroup 和防火墙变化混在一次回归中。

## 3. Droidspaces 对内核的依赖原理

Droidspaces 在 Android 已取得 root 的前提下创建 Linux 容器。容器并不拥有
独立内核，所有进程、网络命名空间和 cgroup 都由 Android 宿主内核提供。
因此能否启动并不取决于 Ubuntu rootfs 本身，而取决于以下链路是否完整：

```text
Android boot image
  -> Linux 4.14 内核及 DTB
    -> namespaces / cgroups / seccomp / VFS
      -> OverlayFS + tmpfs + devtmpfs
        -> veth + bridge + netfilter/NAT
          -> Droidspaces daemon
            -> systemd 容器与 Docker 等容器内服务
```

关键约束如下：

- **必须以内建方式提供基础能力。** Droidspaces 创建容器和 NAT 网络的早期
  阶段不能依赖一个尚未可用的外置模块；验证脚本要求关键符号最终为 `=y`。
- **cgroup 是接口兼容问题，不只是打开 Kconfig。** Android 4.14 的 cgroup
  实现与容器运行时期望的文件命名方式存在差异，错误会发生在容器恢复或
  systemd 初始化阶段。
- **NAT 是内核与 userspace 的共同结果。** `veth`、bridge、conntrack、
  iptables/NAT 和路由策略都必须存在；容器配置中的静态地址还必须由
  Droidspaces 的 DHCP/NAT 逻辑正确下发。
- **内核镜像和模块必须同批次。** 模块的 `vermagic`、签名公钥和内核 ABI
  相关。只更新 `Image-dtb` 而沿用旧 Wi-Fi 模块，可能导致 Wi-Fi 不可用或
  模块被内核拒绝加载。

官方配置参考是 Droidspaces-OSS 的
[Non-GKI Kernel Configuration](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/zh-CN/Kernel-Configuration.md#non-gki)。
本分支没有机械复制文档符号，而是先将其映射到本树的 Linux 4.14 Kconfig。

## 4. 配置适配

### 4.1 必要能力与作用

以下能力由 `lineage_sm8150_defconfig` 打开，并由
[`scripts/verify-droidspaces-config.sh`](../scripts/verify-droidspaces-config.sh)
对 `olddefconfig` 后的实际 `.config` 强制检查。

| 类别 | 代表配置 | 作用 |
| --- | --- | --- |
| IPC 与命名空间 | `SYSVIPC`、`POSIX_MQUEUE`、`NAMESPACES`、`UTS_NS`、`IPC_NS`、`PID_NS`、`NET_NS` | 隔离容器的主机名、进程号、IPC 和网络栈。 |
| 资源控制 | `CGROUPS`、`CGROUP_DEVICE`、`CGROUP_PIDS`、`MEMCG`、`CGROUP_SCHED`、`FAIR_GROUP_SCHED`、`CGROUP_FREEZER`、`CGROUP_NET_PRIO` | 让 Droidspaces/systemd 能建立层级、限制进程/内存并冻结或恢复容器。 |
| 进程约束 | `SECCOMP`、`SECCOMP_FILTER` | 允许容器运行时和应用使用 syscall 过滤。 |
| 容器文件系统 | `DEVTMPFS`、`OVERLAY_FS`、`TMPFS`、`TMPFS_POSIX_ACL`、`TMPFS_XATTR` | 提供 `/dev`、可写层、临时文件系统及 ACL/xattr 语义。 |
| 虚拟网络 | `VETH`、`BRIDGE`、`BRIDGE_NETFILTER` | 连接容器 `eth0` 与宿主 NAT bridge，并让 bridge 流量经过防火墙路径。 |
| 基础 NAT | `NETFILTER`、`NF_CONNTRACK`、`NF_CT_NETLINK`、`NF_NAT`、`NF_NAT_IPV4`、`IP_NF_IPTABLES`、`IP_NF_NAT`、`IP_NF_TARGET_MASQUERADE`、`IP_NF_TARGET_REDIRECT` | 为 NAT 模式的连接跟踪、SNAT/MASQUERADE、端口重定向提供内核后端。 |
| 路由与常用匹配 | `IP_ADVANCED_ROUTER`、`IP_MULTIPLE_TABLES`、`XT_TARGET_TCPMSS`、`XT_MATCH_ADDRTYPE`、`XT_MATCH_CONNTRACK` 等 | 支撑策略路由、MSS 调整及 Docker/容器规则常用匹配。 |

验证脚本不检查 defconfig 文本是否恰好包含所有行。原因是部分配置由 Kconfig
依赖自动选择；真正有意义的是构建输出的 `.config` 是否解析成 `=y`。CI 的
顺序固定为：

```sh
make O="$OUT_DIR" CC="$CC" lineage_sm8150_defconfig
make O="$OUT_DIR" CC="$CC" olddefconfig
scripts/verify-droidspaces-config.sh "$OUT_DIR/.config"
```

这也避免了手写未知 Kconfig 符号后被静默忽略的错误。

### 4.2 Linux 4.14 符号映射与未应用项

| 文档中的概念/符号 | 本树实现 | 处理方式 |
| --- | --- | --- |
| `CONFIG_NF_CONNTRACK_NETLINK` | `CONFIG_NF_CT_NETLINK` | 使用本树实际存在的旧命名。 |
| `CONFIG_NETFILTER_XT_TARGET_MASQUERADE` | `CONFIG_IP_NF_TARGET_MASQUERADE` | Linux 4.14 的 IPv4 iptables 路径提供 MASQUERADE。 |
| `CONFIG_FW_LOADER_COMPRESS` | 不存在 | 不写入未知符号；本树使用 `FW_LOADER` 与 `FW_LOADER_USER_HELPER_FALLBACK`。 |
| `CONFIG_ANDROID_PARANOID_NETWORK` | 不存在 | 不伪造无定义配置。 |
| Droidspaces 的 `xt_qtaguid` 补丁 | `net/netfilter/xt_qtaguid.c` 不存在 | 不重新引入已移除实现；该补丁不适用于本基线。 |

### 4.3 cgroup 文件前缀兼容补丁

`kernel/cgroup/cgroup.c` 在 `cgroup_add_file()` 中增加了一段受限逻辑：当
cgroup root 带有 `CGRP_ROOT_NOPREFIX` 且文件并未声明 `CFTYPE_NO_PREFIX` 时，
额外建立一个 `subsystem.file` 形式的 kernfs 链接。

```c
if (cft->ss && (cgrp->root->flags & CGRP_ROOT_NOPREFIX) &&
    !(cft->flags & CFTYPE_NO_PREFIX)) {
        snprintf(name, CGROUP_FILE_NAME_MAX, "%s.%s",
                 cft->ss->name, cft->name);
        kernfs_create_link(cgrp->kn, name, kn);
}
```

该改动不替换原有 cgroup 文件，也不修改 cgroup 控制器的资源语义；它补充一个
名称兼容链接，使按带控制器前缀查找文件的 Droidspaces 恢复路径能够工作。它
来自 Droidspaces Non-GKI 资源补丁的同类修复，并针对本树的上下文重新适配。

### 4.4 Oplus Kconfig 清理

`drivers/power/oplus/Kconfig` 曾重复声明：

- `OPLUS_SHORT_C_BATT_CHECK`
- `OPLUS_SHORT_IC_CHECK`
- `OPLUS_SHORT_HW_CHECK`

这些符号在 `drivers/power/Kconfig` 已有权威 `tristate` 定义及依赖关系，嵌套
Oplus Kconfig 又以不同类型重复定义，会造成 type-redefinition 警告。适配中
删除了嵌套文件的重复声明，保留原有 `drivers/power/Kconfig` 定义与
`OPLUS_CHARGER` 菜单入口。这个清理只消除解析歧义，不主动改变已解析的设备
配置。

不要把 `arch/arm64/configs/vendor/oplus.config` 当作此设备 defconfig 的隐式
补丁。它是产品片段，可能改变 `HZ`、模块签名、调试选项及多项驱动配置；在
没有完整产品构建链和确认需求前，保持 `lineage_sm8150_defconfig` 为唯一 CI
输入更可控。

## 5. UFW 与 Fail2ban 的额外防火墙支持

提交 `412cae350847` 在基础 NAT 之上补充了容器中常见防火墙规则所需的功能：

- `NETFILTER_XT_MATCH_RECENT`：Fail2ban 常用的最近访问列表。
- `NETFILTER_XT_MATCH_HL`：TTL/hop-limit 匹配。
- `NETFILTER_NETLINK_LOG`、`NETFILTER_NETLINK_QUEUE`、`XT_TARGET_NFLOG`：
  NFLOG/NFQUEUE 事件通道。
- `IP_SET`、`IP_SET_HASH_IP`、`IP_SET_HASH_NET`、`NETFILTER_XT_SET`：UFW、
  Fail2ban 或自定义规则使用的 ipset 后端。
- `COMMENT`、`STATE`、`CONNTRACK`、`MULTIPORT`、`LIMIT`、`HASHLIMIT`、
  `OWNER`、`PKTTYPE`、`MARK` 和 `TARGET_MARK`：规则匹配与标记能力。

这些配置只提供内核后端，**不会**安装 UFW、Fail2ban 或替用户生成防火墙策略。
尤其是 NAT 容器中错误的 `FORWARD`/`INPUT` 规则可能切断容器自身网络。首次
启用时应在容器中先用 `iptables-save` 备份规则，并保留 ADB 作为带外恢复通道。

截至本文对应的设备验证，真机运行的是早于该提交的 `61a12d4d9554`。所以必须
重新刷入包含 `412cae350847` 的 AK3 包后，才能把 UFW/Fail2ban 标记为真机验证
通过；仅看 defconfig 或 CI 成功均不等于实际规则可用。

## 6. 编译、CI 与可复现性

### 6.1 为什么使用 GitHub Actions

本机不承担内核编译。工作流
[`build-droidspaces-ak3.yml`](../.github/workflows/build-droidspaces-ak3.yml) 在
Ubuntu 22.04 x86_64 runner 上构建，并固定外部输入：

| 输入 | 固定值 |
| --- | --- |
| Clang 仓库 | `crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r487747c` |
| Clang 提交 | `19f5a09ce1b016b21a6ead1ed5d84c816586ebb6` |
| AnyKernel3 仓库 | `classified/AnyKernel3` |
| AnyKernel3 提交 | `9b319a806d36be2ea2eca8bad85bff0e03ce784f` |
| 目标 | `ARCH=arm64`、`lineage_sm8150_defconfig`、`Image-dtb modules` |

选择固定的 crDroid 工具链是为贴近 ROM 内核的编译环境并避免缓存命中时编译器
漂移。这里没有把“切换到 Clang 19”作为必要条件；升级编译器会改变代码生成和
旧 Linux 4.14 的告警/兼容性面，必须作为独立变更重新完成启动与硬件验证。

工作流对配置、编译器提交、输出镜像、模块数目、模块 `vermagic`、签名者、
签名哈希和 ZIP 内容都设有失败门槛。成功构建时上传：

- AK3 ZIP 与原始 `Image-dtb`；
- 解析后的 `.config`；
- `build.log`、模块安装日志、ccache 统计；
- `kernel-release.txt`、模块清单、构建来源；
- `SHA256SUMS`。

工作流只接受 `workflow_dispatch` 手动触发；向任何分支 push commit 均不会启动
构建。GitHub 网页的 **Run workflow** 入口要求该 workflow 文件存在于仓库默认
分支。若默认分支没有该文件，应先将这份 workflow 同步到默认分支；仅推送到
适配分支不足以获得手动触发入口。

### 6.2 模块为何必须打包

此配置会生成四个可加载模块：

| 构建路径 | AK3 中的设备路径 |
| --- | --- |
| `drivers/media/rc/msm-geni-ir.ko` | `modules/vendor/lib/modules/msm-geni-ir.ko` |
| `drivers/media/usb/gspca/gspca_main.ko` | `modules/vendor/lib/modules/gspca_main.ko` |
| `drivers/staging/qcacld-3.0/wlan.ko` | `modules/vendor/lib/modules/qca_cld3_wlan.ko` |
| `drivers/video/backlight/lcd.ko` | `modules/vendor/lib/modules/lcd.ko` |

其中 WLAN 模块在包内重命名为设备侧所期望的 `qca_cld3_wlan.ko`。工作流使用
同一构建输出执行 `modules_install`，并验证：

1. 恰有四个目标模块；
2. 每个模块的 `vermagic` 版本前缀与 `kernelrelease` 相同；
3. 每个模块都有内核构建生成的签名，且 `sig_hashalgo=sha512`；
4. `modules.dep`、`modules.alias`、`modules.softdep` 与重命名后的文件一致；
5. ZIP 中不含签名私钥。

这解决了“内核已刷入但 Wi-Fi 模块仍来自旧内核”的高风险路径。它不能跨构建
复用模块，也不能将 AK3 中的模块替换为从其他内核包提取的版本。

## 7. AnyKernel3 与 Magisk 模块机制

### 7.1 为什么输出是 AK3 ZIP 而不是 `boot.img`

内核仓库能构建 `Image-dtb`，但不包含完整 Android 产品树的 `mkbootimg.py`、
AVB 参数、匹配的 ramdisk 和设备产品打包规则。因此不能把 `Image-dtb` 改名为
`boot.img` 后刷写。

AK3 的流程是在真机上：

```text
识别 A/B 当前 slot
  -> dump_boot 读取当前 boot image
    -> 替换内核 Image-dtb
      -> 保留现有 ramdisk/boot 布局并重打包
        -> write_boot 写回当前 slot
```

脚本设置 `is_slot_device=1`，并只针对 `guacamole` / `OnePlus7Pro` 与 Android 14
做设备检查。DTBO 不是该包的更新目标，保持原分区不变。

### 7.2 Magisk 前置检查和 `ak3-helper`

AK3 同时需要更新内核和 systemless 模块，因而 `.github/ak3/anykernel.sh` 执行
以下保护：

1. 检查 `/data/adb/magisk`；
2. 在写 boot 前确认四个配套模块都在 ZIP 中；
3. `dump_boot` 后用 `magiskboot cpio ... test` 检查活动 boot 的 ramdisk；
4. 记录 Magisk 与 legacy root 标记，便于排障；
5. 只在活动 boot 已被 Magisk patch 时继续；
6. 写入后确认 AK3 已保留 `magisk_patched`。

`do.modules=1` 和 `do.systemless=1` 使 AnyKernel3 通过名为 `ak3-helper` 的
Magisk 模块安装 `modules/vendor/lib/modules`。`ak3-helper` 不是预置在 ZIP 中
的 Magisk 本体；它依赖设备原本已有、且活动 boot 已 patch 的 Magisk 环境。

这意味着：

- AK3 不会向未 root 的设备植入 Magisk；
- AK3 通过重打包当前 boot 保留已有 Magisk，而不是用一个裸 boot 覆盖它；
- 内核和 `ak3-helper` 必须视为一个版本单元；
- 回刷旧 boot 时，也要移除或禁用对应的 `ak3-helper`，避免旧内核加载新模块。

检查失败时脚本会在写 boot 前中止，避免“跳过模块却刷入内核”。但 boot 分区
写入与 `/data` 中 Magisk 模块安装不是跨分区事务，故刷写前仍必须保存可工作的
boot 镜像，并保留 fastboot/recovery 恢复路径。

## 8. 真机验证记录

### 8.1 已完成的验证

已刷入的 `61a12d4d9554` 版本成功启动，设备报告：

```text
4.14.355-perf-g61a12d4d9554
```

以下现象已经在真机上观察到：

- Droidspaces 环境自检全部通过；
- Wi-Fi 正常工作，说明配套 WLAN 模块路径没有阻塞设备网络；
- NAT 模式容器获得预期的 `eth0` 地址并具备默认路由；
- 容器可以访问 NAT 网关、外网 IP 并完成 DNS 解析；
- Ubuntu 24 容器中 systemd 与 `systemd-networkd` 正常运行，失败单元为零；
- 容器内 SSH 监听正常，随后通过 Tailscale 验证了远程 SSH 路径。

这些结果证明基础容器、网络命名空间、NAT、配套模块和 Android 启动链在该提交上
共同工作；它们不是对 `412cae350847` 防火墙扩展的验证。

### 8.2 Ubuntu 版本经验

曾在较新的 Ubuntu rootfs 上遇到 PID 1 与 `/dev/console` 相关的启动阻塞风险。
这不能仅凭一次现象就归因为“Linux 4.14 绝对不支持 Ubuntu 26”，但说明较新的
systemd/userspace 会扩大旧内核接口兼容性风险。改用 Ubuntu 24.04 后，
`systemd 255` 和 NAT 容器工作正常。

实际部署建议优先采用已验证的 Ubuntu 24 rootfs；升级 rootfs 后，应重新验证
PID 1、journald、networkd、容器网络、Docker 和设备访问，而不是只检查容器
是否创建成功。

## 9. 验证与回归清单

### 构建前后

```sh
# 在 Linux x86_64 或 CI runner 中
make O="$OUT_DIR" CC="$CC" lineage_sm8150_defconfig
make O="$OUT_DIR" CC="$CC" olddefconfig
scripts/verify-droidspaces-config.sh "$OUT_DIR/.config"
make O="$OUT_DIR" CC="$CC" -j"$(nproc)" Image-dtb modules
```

下载 Actions artifact 后，至少核对：

```sh
sha256sum -c SHA256SUMS
unzip -Z1 Droidspaces-guacamole-crDroid-10.11-*.zip
```

检查 ZIP 同时包含 `Image-dtb`、`anykernel.sh`、四个 `.ko` 和三个模块元数据
文件。不要将 raw `Image-dtb` 直接当作刷写镜像。

### 刷写前

1. 确认机型为 `guacamole`，ROM 为预期 Android 14 基线。
2. 备份当前活动 slot 的 boot image，并确认可用的 fastboot/recovery 路径。
3. 确认 Magisk 已安装，当前活动 boot 已由 Magisk patch。
4. 将同一次 CI artifact 的 AK3 ZIP 与校验和一起保存。
5. 不要同时刷入来源不明的 DTBO、Wi-Fi 模块或 boot image。

### 启动后

```sh
uname -r
su -c /data/local/Droidspaces/bin/droidspaces check
su -c /data/local/Droidspaces/bin/droidspaces --name=Container-Home run /bin/sh -c \
  'systemctl is-system-running; ip -4 addr show dev eth0; ip route'
```

随后分别验证 Wi-Fi、移动网络、相机/音频等日常硬件、容器 DNS 与外网、Docker、
以及休眠/重启。若刷入包含 `412cae350847` 的版本，还应在容器内进行最小 UFW 或
Fail2ban 规则测试，并确认 NAT 未被 `FORWARD` 规则意外阻断。

## 10. 风险、回滚与后续维护

### 已知风险

- Linux 4.14 已较旧。新容器 userspace、较新的 systemd 和新防火墙工具可能要求
  本树没有的内核 API；编译成功不能覆盖这些运行时差异。
- Clang 升级、defconfig 改动、cgroup 补丁和模块签名策略都可能改变启动或硬件
  行为。一次只引入一类变量，便于回归定位。
- 模块 ABI 或签名不匹配时，最显著症状可能是 Wi-Fi 或其他模块化硬件不可用。
- UFW/Fail2ban 错误规则能让容器失联。始终保留 ADB 和宿主 shell 作为恢复路径。
- 任何 AK3 写入都有 boot 失败风险；前置检查降低风险但不能替代备份。

### 回滚原则

1. 无法启动或硬件异常时，在 fastboot/recovery 刷回已备份的原 boot image。
2. 同时删除或禁用与新内核对应的 `ak3-helper`，防止遗留模块在旧内核上加载。
3. 不要只回滚内核而保留新模块，也不要只替换模块而继续运行新内核。
4. 从 artifact 中保存的 `build-provenance.txt`、`module-manifest.txt`、
   `kernel-release.txt` 和日志追溯问题版本。

### 后续改动的最低门槛

每次修改内核配置、工具链、AK3 脚本、cgroup 或模块列表后，至少应完成：

1. CI 成功并保留 artifact；
2. 审核 resolved `.config` 与模块清单；
3. 在已备份 boot 的真机上刷写；
4. 验证启动、`/data/local/Droidspaces/bin/droidspaces check`、Wi-Fi、NAT、容器 systemd 和外网；
5. 若涉及防火墙，验证规则加载、Docker/bridge 转发和回滚路径。

只有在这五层均完成后，才应将某项改动标记为“可稳定日用”。
