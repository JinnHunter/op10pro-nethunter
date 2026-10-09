#!/bin/bash
# =============================================================================
# WildKernels feature patches for the OnePlus 10 Pro (android12-5.10) tree:
#   BBRv3, NTSync, Droidspaces kABI guards, IPv6-NAT fix, Ptrace leak fix,
#   Unicode bypass fix
# Source: https://github.com/WildKernels/kernel_patches (pinned commit)
# Called from .github/workflows/build.yml with $KDIR + $GITHUB_WORKSPACE set.
# =============================================================================
set -eo pipefail
: "${KDIR:?KDIR not set}"
: "${GITHUB_WORKSPACE:?}"

KP_REF="${KP_REF:-41ae18b35d20e0c6ac04116785a4a1089528ae94}"
KP="$GITHUB_WORKSPACE/wild_patches"

rm -rf "$KP"
for i in 1 2 3; do
  git clone -q https://github.com/WildKernels/kernel_patches.git "$KP" && break
  echo "clone failed, retry $i"; rm -rf "$KP"; sleep 10
done
git -C "$KP" checkout -q "$KP_REF"

cd "$KDIR"
apply() {
  local p="$1"
  if [ ! -e "$p" ]; then
    echo "::warning::patch missing in kernel_patches repo: $(basename "$p")"
    return 0
  fi
  if git apply --check "$p" 2>/dev/null; then
    git apply "$p"
    echo "APPLIED: $(basename "$p")"
  else
    echo "::error::patch does NOT apply cleanly: $(basename "$p")"
    return 1
  fi
}

# --- root-hiding hardening (kernels < 5.16) ---------------------------------
apply "$KP/gki_ptrace.patch"

# --- unicode bypass fix (experimental; name may vary) -----------------------
shopt -s nullglob
for p in "$KP"/common/*nicode*.patch "$KP"/common/*unicode*.patch; do
  apply "$p" || true
done
shopt -u nullglob

# --- BBRv3 (android12-5.10 backport) ----------------------------------------
apply "$KP/common/bbrv3/0001-net-tcp-backport-BBRv3-to-android12-5.10.patch"
apply "$KP/common/bbrv3/sysctl_add_proc_dou8vec_minmax.patch"
apply "$KP/common/bbrv3/sysctl_fix_data-races_in_proc_dou8vec_minmax.patch"

# --- NTSync (wine/winlator sync primitives) ---------------------------------
apply "$KP/common/ntsync/ntsync_base.patch"
# OOS15 userspace = A14+ SELinux policy variant
apply "$KP/common/ntsync/ntsync_compat_android12-5.10_A14.patch"

# --- Droidspaces kABI guards (keep stock vendor modules loading!) -----------
apply "$KP/common/droidspaces/fix_sysvipc_kabi_1_2_3.patch"
apply "$KP/common/droidspaces/fix_sysvipc_kabi_3_4_5.patch"
apply "$KP/common/droidspaces/fix_sysvipc_kabi_6_7_8.patch"
apply "$KP/common/droidspaces/fix_abi_padding_for_posix_mqueue.patch"
apply "$KP/common/droidspaces/0001-Guard-USER_NS-for-non-root-users.patch"
# oplus BSP ghost-task fix (OnePlus trees)
apply "$KP/common/droidspaces/0001-Return-ghost-task-if-task-is-null-and-is-requested-b.patch"

# --- IPv6 NAT: fake "no internet" Android error fix --------------------------
apply "$KP/common/IPv6_NAT_FIX.patch"

echo "Wild patches done."
