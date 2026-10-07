#!/bin/bash
# Adds KernelSU-Next + SUSFS + Baseband-guard (+ optional vendor-module blocklist)
# to the OnePlus 10 Pro (sm8450, android12-5.10) GKI source tree.
#
# Ported from WildKernels/OnePlus_KernelSU_SUSFS (their OP10pro config) and pinned to a
# combination that was dry-run tested against NE2211_15.0.0.1302 (5.10.226):
#   KernelSU-Next 234f6e04 (= version 33239)  +  SUSFS 2.2.0 (ee7dc7a)  +  Wild fix patches 41ae18b
# Bumping any ONE of the three usually needs the matching fix patches -> keep them in sync.
#
# env in : KDIR (kernel_platform/common), WORK (scratch dir), OUT_FRAGMENT (file to append defconfig lines to)
#          ENABLE_KSU ENABLE_BBG BLOCK_MODULES (true/false), BLOCK_MODULE_LIST (comma list)
#          KSUN_REF SUSFS_REF BBG_REF PATCHES_REF
set -euo pipefail

: "${KDIR:?KDIR not set}" "${WORK:?WORK not set}" "${OUT_FRAGMENT:?OUT_FRAGMENT not set}"
ENABLE_KSU="${ENABLE_KSU:-true}"
ENABLE_BBG="${ENABLE_BBG:-true}"
BLOCK_MODULES="${BLOCK_MODULES:-true}"
BLOCK_MODULE_LIST="${BLOCK_MODULE_LIST:-oplus_security_guard,oplus_secure_harden,oplus_security_keventupload,oplus_secure_guard_new,oplus_secure_guard}"
KSUN_REF="${KSUN_REF:-234f6e040fcbca18b16d2398e1aa225712ec99ad}"
SUSFS_REF="${SUSFS_REF:-ee7dc7a}"
BBG_REF="${BBG_REF:-a54e0dc6cf0aff4dd87fec49644a02d2eb612905}"
PATCHES_REF="${PATCHES_REF:-41ae18b35d20e0c6ac04116785a4a1089528ae94}"
SUSFS_BRANCH="gki-android12-5.10"

KP="$(dirname "$KDIR")"                       # .../kernel_platform
mkdir -p "$WORK"; : >> "$OUT_FRAGMENT"
die() { echo "::error title=KSU/SUSFS/BBG step::$*"; exit 1; }

fetch_ref() {   # fetch_ref <url> <dir> <ref>   (works for branches, tags and full/short SHAs)
  local url="$1" dir="$2" ref="$3"
  for i in 1 2 3; do
    rm -rf "$dir"; git clone -q "$url" "$dir" && git -C "$dir" checkout -q "$ref" && return 0
    echo "retry $i for $url"; sleep 8
  done
  die "could not clone/checkout $url @ $ref"
}

# ---------------------------------------------------------------------------
if [ "$ENABLE_KSU" = "true" ]; then
  echo "::group::KernelSU-Next + SUSFS"
  fetch_ref https://github.com/WildKernels/kernel_patches "$WORK/kernel_patches" "$PATCHES_REF"
  fetch_ref https://gitlab.com/simonpunk/susfs4ksu.git "$WORK/susfs4ksu" "$SUSFS_REF"
  # KSUN must stay a FULL git clone: its Kbuild derives KSU_VERSION from `git rev-list --count`
  fetch_ref https://github.com/KernelSU-Next/KernelSU-Next "$KP/KernelSU-Next" "$KSUN_REF"
  SUSFS="$WORK/susfs4ksu"; KSUN="$KP/KernelSU-Next"; PATCHES="$WORK/kernel_patches"

  SUSVER=$(grep '#define SUSFS_VERSION' "$SUSFS/kernel_patches/include/linux/susfs.h" | awk -F'"' '{print $2}')
  FIXDIR="$PATCHES/next/susfs_fix_patches/$SUSVER"
  echo "SUSFS $SUSVER, KSUN version $((30000 + $(git -C "$KSUN" rev-list --count HEAD)))"
  [ -d "$FIXDIR" ] || die "no Wild fix patches for SUSFS $SUSVER ($FIXDIR). Use a SUSFS_REF that reports v2.2.0"

  # --- what KernelSU-Next's setup.sh does: symlink + Makefile + Kconfig ---
  ln -sfn ../../KernelSU-Next/kernel "$KDIR/drivers/kernelsu"
  grep -q kernelsu "$KDIR/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KDIR/drivers/Makefile"
  if ! grep -q 'drivers/kernelsu/Kconfig' "$KDIR/drivers/Kconfig"; then
    last=$(grep -n '^endmenu' "$KDIR/drivers/Kconfig" | tail -1 | cut -d: -f1)
    sed -i "${last}i source \"drivers/kernelsu/Kconfig\"" "$KDIR/drivers/Kconfig"
  fi
  test -f "$KDIR/drivers/kernelsu/Kconfig" || die "drivers/kernelsu symlink is dangling"

  # --- SUSFS sources into the kernel ---
  cp "$SUSFS"/kernel_patches/fs/*            "$KDIR/fs/"
  cp "$SUSFS"/kernel_patches/include/linux/* "$KDIR/include/linux/"

  # --- SUSFS glue inside KernelSU-Next (rejects are expected, Wild ships a fix patch per reject) ---
  cd "$KSUN"
  patch -p1 --forward < "$SUSFS/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" || true
  for f in $(find ./kernel -maxdepth 2 -name '*.rej' -exec basename {} .rej \;); do
    echo "fixing reject: $f"
    [ -f "$FIXDIR/fix_$f.patch" ] || die "unexpected reject in $f and no fix_$f.patch -> KSUN/SUSFS/fix-patch versions don't match"
    patch -p1 --forward < "$FIXDIR/fix_$f.patch" || die "fix_$f.patch failed"
  done
  patch -p1 --forward < "$FIXDIR/overwrite_hook_mode.patch" || die "overwrite_hook_mode.patch failed"
  patch -p1 --forward < "$FIXDIR/ksu_toolkit.patch"         || die "ksu_toolkit.patch failed"
  find . \( -name '*.rej' -o -name '*.orig' \) -delete

  # --- SUSFS hooks into the kernel proper ---
  cd "$KDIR"
  patch -p1 --forward < "$SUSFS/kernel_patches/50_add_susfs_in_${SUSFS_BRANCH}.patch" \
    || die "50_add_susfs_in_${SUSFS_BRANCH}.patch does not apply to this kernel source"
  find . \( -name '*.rej' -o -name '*.orig' \) -not -path './out/*' -not -path './drivers/kernelsu/*' -delete 2>/dev/null || true

  cat >> "$OUT_FRAGMENT" <<'EOC'
# --- KernelSU-Next + SUSFS (v2.2.0: remaining SUSFS options default to y) ---
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOC
  echo "::endgroup::"
fi

# ---------------------------------------------------------------------------
if [ "$ENABLE_BBG" = "true" ]; then
  echo "::group::Baseband-guard"
  fetch_ref https://github.com/vc-teahouse/Baseband-guard "$KP/Baseband-guard" "$BBG_REF"
  ln -sfn ../../Baseband-guard "$KDIR/security/baseband-guard"
  grep -q 'baseband-guard/' "$KDIR/security/Makefile" || printf '\nobj-$(CONFIG_BBG) += baseband-guard/\n' >> "$KDIR/security/Makefile"
  if ! grep -q 'security/baseband-guard/Kconfig' "$KDIR/security/Kconfig"; then
    last=$(grep -n '^endmenu[[:space:]]*$' "$KDIR/security/Kconfig" | tail -1 | cut -d: -f1)
    sed -i "${last}i source \"security/baseband-guard/Kconfig\"" "$KDIR/security/Kconfig"
  fi
  # put baseband_guard into the default LSM list (GKI does not set CONFIG_LSM in defconfig)
  sed -i '/^config LSM$/,/^\thelp$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' "$KDIR/security/Kconfig"
  grep -q 'selinux,baseband_guard' "$KDIR/security/Kconfig" || die "could not add baseband_guard to the LSM list"
  test -f "$KDIR/security/baseband-guard/Kconfig" || die "baseband-guard symlink is dangling"
  cat >> "$OUT_FRAGMENT" <<'EOC'
# --- Baseband-guard (boot/recovery stay unprotected so you can still flash kernels from Android) ---
CONFIG_BBG=y
# CONFIG_BBG_BLOCK_BOOT is not set
# CONFIG_BBG_BLOCK_RECOVERY is not set
EOC
  echo "::endgroup::"
fi

# ---------------------------------------------------------------------------
if [ "$BLOCK_MODULES" = "true" ]; then
  echo "::group::Vendor module blocklist: $BLOCK_MODULE_LIST"
  [ -d "$WORK/kernel_patches" ] || fetch_ref https://github.com/WildKernels/kernel_patches "$WORK/kernel_patches" "$PATCHES_REF"
  cd "$KDIR"
  patch -p1 --forward < "$WORK/kernel_patches/common/vendor_modules/0001-Support-conditional-vendor-modules-blacklisting-5.15-and-below.patch" \
    || die "vendor module blocklist patch failed"
  printf 'CONFIG_DEBLOAT_VENDOR_MODULES="%s"\n' "$BLOCK_MODULE_LIST" >> "$OUT_FRAGMENT"
  echo "::endgroup::"
fi
echo "Generated fragment:"; cat "$OUT_FRAGMENT"
