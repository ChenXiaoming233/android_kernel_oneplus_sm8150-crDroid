# Droidspaces support for OnePlus 7 Pro

This tree carries the kernel-side configuration required to evaluate
Droidspaces on the OnePlus 7 Pro (`guacamole`) running crDroid 10.11 /
Android 14.

## Baseline

- Upstream branch: `crdroidandroid/android_kernel_oneplus_sm8150:14.0`
- Upstream commit: `a9f392aca6a4453660bc80682f4b68a8cf4712d5`
- Kernel family: Linux 4.14, non-GKI
- Device defconfig: `arch/arm64/configs/lineage_sm8150_defconfig`

## Adaptation

The device defconfig enables the IPC, namespace, cgroup, seccomp, devtmpfs,
OverlayFS, veth/bridge and netfilter features required by the current
[Droidspaces non-GKI guide](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/zh-CN/Kernel-Configuration.md#non-gki).

The cgroup v2 file-prefix compatibility change is adapted from Droidspaces'
[`02.fix_restore cgroup file prefix handling .patch`](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/resources/kernel-patches/non-GKI/02.fix_restore%20cgroup%20file%20prefix%20handling%20.patch).

The duplicate `OPLUS_SHORT_C_BATT_CHECK`, `OPLUS_SHORT_IC_CHECK` and
`OPLUS_SHORT_HW_CHECK` declarations are removed from the nested Oplus Kconfig.
Their original `tristate` definitions in `drivers/power/Kconfig` remain the
authoritative definitions, avoiding type-redefinition warnings without
changing the resolved device configuration.

The companion `xt_qtaguid` patch is intentionally not applied because this
kernel baseline does not contain `net/netfilter/xt_qtaguid.c`. Reintroducing
that removed implementation solely to apply the patch would be incorrect.

The guide contains names that are unavailable in this Linux 4.14 tree:

- `CONFIG_NF_CONNTRACK_NETLINK` is provided as `CONFIG_NF_CT_NETLINK`.
- `CONFIG_NETFILTER_XT_TARGET_MASQUERADE` is provided by the IPv4-specific
  `CONFIG_IP_NF_TARGET_MASQUERADE` path.
- `CONFIG_FW_LOADER_COMPRESS` is not defined.
- `CONFIG_ANDROID_PARANOID_NETWORK` is not defined.

## Configuration verification

Generate and normalize the resolved configuration outside the source tree:

```sh
make O="$PWD/.out/droidspaces" ARCH=arm64 lineage_sm8150_defconfig
make O="$PWD/.out/droidspaces" ARCH=arm64 olddefconfig
```

The resolved `.config` must be audited rather than assuming every defconfig
line survives Kconfig dependency resolution. This adaptation has passed that
static configuration audit. The CI build repeats the audit with
`scripts/verify-droidspaces-config.sh` before compiling the kernel.

## GitHub Actions build and AnyKernel3 packaging

The `.github/workflows/build-droidspaces-ak3.yml` workflow builds this branch
on an Ubuntu runner. It runs when the
`droidspaces/crdroid-10.11-guacamole` branch is pushed and also exposes a
manual trigger once GitHub can resolve the workflow from the default branch.
It does not build from a second recipe repository and it does not publish a
GitHub Release.

The build inputs that are external to this repository are pinned:

- crDroid's Android 14 `clang-r487747c` mirror at commit
  `19f5a09ce1b016b21a6ead1ed5d84c816586ebb6`;
- the OnePlus 7 family AnyKernel3 template at commit
  `9b319a806d36be2ea2eca8bad85bff0e03ce784f`.

The workflow performs these gates in order:

1. generate `lineage_sm8150_defconfig` and normalize it with `olddefconfig`;
2. require the resolved namespaces, cgroups, seccomp, OverlayFS, bridge/veth
   and netfilter options to be built in;
3. compile `Image-dtb` and the configured kernel modules;
4. install and sign the four loadable modules with the same generated key
   embedded in that kernel, verify their `vermagic`, and rename `wlan.ko` to
   the device-facing `qca_cld3_wlan.ko`;
5. replace the upstream AnyKernel3 device script with the repository-owned
   `.github/ak3/anykernel.sh` restricted to `guacamole` / `OnePlus7Pro`;
6. package `Image-dtb` plus the matching modules under
   `modules/vendor/lib/modules`, leaving the existing DTBO partition
   unchanged;
7. upload the AK3 ZIP, raw `Image-dtb`, resolved `.config`, module manifest,
   build logs, provenance and SHA-256 checksums as workflow artifacts.

The AK3 package requires an existing Magisk installation and a Magisk-patched
active boot image. Installation aborts before repacking or flashing when either
condition is missing. AnyKernel3 installs the matching modules through its
systemless `ak3-helper` Magisk module, so the kernel and modules from one
workflow run must be installed and rolled back as a single unit. Restoring an
older boot image also requires removing or disabling `ak3-helper`. The
preflight checks prevent AnyKernel3's known "skip modules but flash the
kernel" path; they do not make writes to the boot partition and `/data`
strictly transactional, so a known-good boot image and recovery path remain
mandatory.

When the ramdisk check fails, the installer log records the `magiskboot cpio
test` exit code plus the presence of Magisk and legacy-root markers. This is a
diagnostic-only report; it does not relax the Magisk requirement or proceed to
write the boot partition.

Every candidate must complete the workflow successfully before its packaging
can be treated as build-validated. A device flash and `droidspaces check`
runtime validation are separate gates. Back up the current boot image and
retain a known-good recovery path before flashing the AK3 package.
