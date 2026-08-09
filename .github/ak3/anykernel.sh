# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
# begin properties
properties() { '
kernel.string=Droidspaces kernel for crDroid 10.11 (OnePlus 7 Pro)
do.devicecheck=1
do.modules=0
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
ui_print " ";

## AnyKernel install
dump_boot;
write_boot;
## end install
