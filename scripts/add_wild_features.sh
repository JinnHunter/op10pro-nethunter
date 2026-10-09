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

# Apply chain: strict git apply -> ignore-whitespace -> patch -p1 -> patch fuzz3
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
  if git apply --check --ignore-whitespace "$p" 2>/dev/null; then
    git apply --ignore-whitespace "$p" && { echo "APPLIED (iws): $b"; return 0; }
  fi
  if patch -p1 --dry-run -f -s <"$p" >/dev/null 2>&1; then
    patch -p1 -f -s <"$p" && { echo "APPLIED (patch): $b"; return 0; }
  fi
  if patch -p1 --dry-run -f -s --fuzz=3 --ignore-whitespace <"$p" >/dev/null 2>&1; then
    patch -p1 -f -s --fuzz=3 --ignore-whitespace <"$p" && { echo "APPLIED (fuzz3): $b"; return 0; }
  fi
  echo "::error::patch does NOT apply cleanly: $b"
  return 1
}

# optional = skip with warning if it can't apply (device-tree dependent patches)
apply_opt() {
  apply "$1" || echo "::warning::SKIPPED (not applicable on this tree): $(basename "$1")"
}

# dry-run version of the same 4-method chain
can_apply() {
  local p="$1"
  git apply --check "$p" 2>/dev/null && return 0
  git apply --check --ignore-whitespace "$p" 2>/dev/null && return 0
  patch -p1 --dry-run -f -s <"$p" >/dev/null 2>&1 && return 0
  patch -p1 --dry-run -f -s --fuzz=3 --ignore-whitespace <"$p" >/dev/null 2>&1 && return 0
  return 1
}

# --- root-hiding hardening (kernels < 5.16) ---------------------------------
apply "$KP/gki_ptrace.patch"

# --- BBRv3 (android12-5.10 backport) ----------------------------------------
apply "$KP/common/bbrv3/0001-net-tcp-backport-BBRv3-to-android12-5.10.patch"
# OnePlus stock tree ALREADY ships proc_dou8vec_minmax (kernel/sysctl.c:1078 +
# sysctl.h decl). Applying sysctl_add there = redefinition compile error.
if grep -q "^int proc_dou8vec_minmax" kernel/sysctl.c; then
  echo "proc_dou8vec_minmax already in stock tree: sysctl_add skipped"
  apply_opt "$KP/common/bbrv3/sysctl_fix_data-races_in_proc_dou8vec_minmax.patch"
else
  apply "$KP/common/bbrv3/sysctl_add_proc_dou8vec_minmax.patch"
  apply "$KP/common/bbrv3/sysctl_fix_data-races_in_proc_dou8vec_minmax.patch"
fi

# --- NTSync (wine/winlator sync primitives) ---------------------------------
apply "$KP/common/ntsync/ntsync_base.patch"
# OOS15 userspace = A14+ SELinux policy variant
apply "$KP/common/ntsync/ntsync_compat_android12-5.10_A14.patch"

# --- Droidspaces kABI guards: ALL-OR-NOTHING (3 parts of ONE change!) --------
# Aadha lagana = ipc/ compile error. Teeno dry-check karo, phir sab lagao.
S1="$KP/common/droidspaces/fix_sysvipc_kabi_1_2_3.patch"
S2="$KP/common/droidspaces/fix_sysvipc_kabi_3_4_5.patch"
S3="$KP/common/droidspaces/fix_sysvipc_kabi_6_7_8.patch"
if can_apply "$S1" && can_apply "$S2" && can_apply "$S3"; then
  apply "$S1" && apply "$S2" && apply "$S3"
  echo "sysvipc kABI guards: all 3 applied"
else
  echo "::warning::sysvipc kABI guards SKIPPED (all-or-nothing; stock SYSVIPC=y on this device, safe)"
fi
apply "$KP/common/droidspaces/fix_abi_padding_for_posix_mqueue.patch"
apply "$KP/common/droidspaces/0001-Guard-USER_NS-for-non-root-users.patch"
# oplus BSP ghost-task fix (OnePlus trees)
apply "$KP/common/droidspaces/0001-Return-ghost-task-if-task-is-null-and-is-requested-b.patch"

# --- IPv6 NAT: fake "no internet" Android error fix --------------------------
apply "$KP/common/IPv6_NAT_FIX.patch"

echo "Wild patches done."
