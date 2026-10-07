### AnyKernel3 Ramdisk Mod Script - OnePlus 10 Pro (NE2211) NetHunter kernel
## osm0sis @ xda-developers

properties() { '
kernel.string=OnePlus 10 Pro NetHunter kernel (OxygenOS 15, 5.10 GKI)
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

# boot partition, A/B device, keep the existing ramdisk (Magisk etc.) untouched
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# only replace the kernel, do not modify the ramdisk
split_boot;
flash_boot;
