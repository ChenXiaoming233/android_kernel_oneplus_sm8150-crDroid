# macOS 大小写不敏感文件系统维护说明

## 适用范围

本说明面向在 macOS 上维护本仓库的开发者。它不影响 GitHub Actions 或 Linux
构建环境；后者使用大小写敏感文件系统，可以正常处理本内核树。

## 问题根因

Linux 内核树包含名称仅大小写不同、但语义和内容不同的合法文件。例如：

```text
include/uapi/linux/netfilter/xt_DSCP.h
include/uapi/linux/netfilter/xt_dscp.h
net/netfilter/xt_DSCP.c
net/netfilter/xt_dscp.c
```

其中大写名称与小写名称分别对应不同的 netfilter target 或 match 实现，不能
合并、改名或删除任一版本。

macOS 默认 APFS 通常大小写不敏感，无法在同一目录中表示这类路径。Git checkout、
分支切换或 GUI 客户端可能因此产生 `*-1` 副本、显示伪修改，或将其中一个文件的
内容覆盖到另一个同名路径上。

## 推荐工作方式

1. 对内核源码、defconfig、Kconfig 或 netfilter 文件的实际编辑，使用 Linux
   环境，或使用大小写敏感的 APFS volume/disk image。
2. 在默认 macOS 文件系统上，将本仓库用于阅读文档、查看历史和触发 CI；不要把
   该工作树视为可可靠本地编译的源码副本。
3. 始终由 GitHub Actions 生成可刷写 AK3 artifact。CI runner 使用 Linux，因而
   不受此限制。

## 已存在 checkout 的处理

出现 `*-1` 文件或仅大小写不同路径的伪修改时，不要提交、删除或重命名这些内核
文件。先保存需要保留的真实改动，再在大小写敏感环境恢复工作树。

本机可以将无法同时落盘的一组路径标记为 Git `skip-worktree`，以保持 `git status`
干净。这只是本地 index 状态：不会写入提交、不会传递给其他 clone，也不代表两个
文件已被正确保存在 macOS 工作树中。执行重新 clone、清除 index、`git reset` 或
切换到需要这些文件的分支后，仍可能需要重新应用该本地处理。

如需长期维护，请迁移到大小写敏感文件系统；不要试图通过修改仓库路径来适配
macOS。这样会破坏 Linux 内核上游路径和构建规则。

## 相关文档

- [Droidspaces 适配、构建、刷写与回滚说明](droidspaces-guacamole.md)
