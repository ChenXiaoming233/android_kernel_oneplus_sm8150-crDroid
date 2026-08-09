# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
# begin properties
properties() { '
kernel.string=Droidspaces kernel for crDroid 10.11 (OnePlus 7 Pro)
do.devicecheck=1
do.modules=1
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=guacamole
device.name2=OnePlus7Pro
supported.versions=14
supported.patchlevels=
'; } # end properties

# OnePlus 7 Pro uses an A/B boot partition. AnyKernel3 resolves the active
# slot before unpacking and repacking the existing boot image.
block=/dev/block/by-name/boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

## AnyKernel methods (DO NOT CHANGE)
. tools/ak3-core.sh;

ui_print " ";
ui_print "Droidspaces kernel for OnePlus 7 Pro (guacamole)";
ui_print "Target ROM: crDroid 10.11 / Android 14";
ui_print "Installs matching signed modules through Magisk ak3-helper";
ui_print " ";

## AnyKernel install
[ -d /data/adb/magisk ] || abort "Magisk is required for matching modules. Aborting...";

for module in msm-geni-ir.ko gspca_main.ko qca_cld3_wlan.ko lcd.ko; do
  [ -f "$home/modules/vendor/lib/modules/$module" ] || \
    abort "Missing matching kernel module: $module. Aborting...";
done;

dump_boot;

ui_print "Checking active boot ramdisk for Magisk...";
tools/magiskboot cpio "$split_img/ramdisk.cpio" test;
magisk_status=$?;
ui_print "Magisk ramdisk test exit code: $magisk_status";

for marker in .backup/.magisk init.magisk.rc overlay/init.magisk.rc; do
  tools/magiskboot cpio "$split_img/ramdisk.cpio" "exists $marker" >/dev/null 2>&1;
  marker_status=$?;
  if [ "$marker_status" -eq 0 ]; then
    ui_print "Magisk marker present: $marker";
  else
    ui_print "Magisk marker absent: $marker (exit $marker_status)";
  fi;
done;

for legacy in sbin/launch_daemonsu.sh sbin/su init.xposed.rc boot/sbin/launch_daemonsu.sh; do
  tools/magiskboot cpio "$split_img/ramdisk.cpio" "exists $legacy" >/dev/null 2>&1;
  legacy_status=$?;
  if [ "$legacy_status" -eq 0 ]; then
    ui_print "Legacy root marker present: $legacy";
  else
    ui_print "Legacy root marker absent: $legacy (exit $legacy_status)";
  fi;
done;

[ $((magisk_status & 3)) -eq 1 ] || \
  abort "The active boot image is not Magisk patched. Aborting...";

write_boot;
[ -f "$home/magisk_patched" ] || \
  abort "Failed to preserve the Magisk-patched boot image. Aborting...";
## end install
