### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
## begin properties
properties() { '
kernel.string=ShockWave Kernel
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=selene
supported.versions=
supported.patchlevels=
'; }
## end properties

### AnyKernel install
## begin attributes
attributes() {
set_perm_recursive 0 0 755 644 "$ramdisk"/*
set_perm_recursive 0 0 750 750 "$ramdisk"/init* "$ramdisk"/sbin
}
## end attributes

## boot shell variables
BLOCK=auto
IS_SLOT_DEVICE=auto
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

## import functions/variables and setup patching
. tools/ak3-core.sh && attributes

## boot install
dump_boot
write_boot
