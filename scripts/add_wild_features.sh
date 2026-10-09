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

# Apply chain: strict git apply -> 3-way merge -> patch -p1 with fuzz
apply() {
  local p="$1" b
  b=$(basename "$p")
  if [ ! -e "$p" ]; then
    echo "::warning::patch missing in kernel_patches repo: $b"
    return 0
  fi
  if git apply --check "$p" 2>/dev/null; then
    git apply "$p" && { echo "APPLIED: $b"; return 0; }
  fi
  if git apply --check -3 "$p" 2>/dev/null; then
    git apply -3 "$p" && { echo "APPLIED (3way): $b"; return 0; }
  fi
  if patch -p1 --dry-run -f -s <"$p" >/dev/null 2>&1; then
    patch -p1 -f -s <"$p" && { echo "APPLIED (fuzz): $b"; return 0; }
  fi
  echo "::error::patch does NOT apply cleanly: $b"
  return 1
}

# --- root-hiding hardening (kernels < 5.16) ---------------------------------
apply "$KP/gki_ptrace.patch"

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
