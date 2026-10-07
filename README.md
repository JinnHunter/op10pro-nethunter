# NetHunter kernel for OnePlus 10 Pro (NE2211) - OxygenOS 15

Builds on GitHub Actions. Output:

| File | What it is |
|---|---|
| `NetHunter-OP10Pro-OOS15-<ver>-AK3.zip` | AnyKernel3 zip - replaces only the kernel `Image` in your `boot` partition |
| `NetHunter-OP10Pro-OOS15-<ver>-modules.zip` | External USB Wi-Fi / Bluetooth driver modules + a loader script |
| `...-config.txt`, `build.log` | The final `.config` and the full compile log |

## How this build works (and why earlier attempts probably failed)

* The 10 Pro (SM8450 "waipio") runs a **GKI 5.10.226** kernel (`android12-5.10`) + vendor modules.
  We rebuild the GKI `Image` only; touch, camera, modem, internal Wi-Fi etc. stay the **stock vendor modules** from your firmware.
  Therefore: **your firmware must match the source** (`NE2211_15.0.0.1302`). Check with `adb shell uname -r` -> must start with `5.10.226-android12-9`.
* **Source layout is the #1 failure.** OnePlus' `android_kernel_common_oneplus_sm8450` has symlinks into the *other* repo
  (`drivers/soc/oplus/storage -> ../../../../../vendor/oplus/kernel/storage`). If you only clone `common`, `make gki_defconfig` dies with
  `drivers/soc/Kconfig: 'drivers/soc/oplus/storage/Kconfig' not found`. The workflow clones
  `android_kernel_modules_and_devicetree_oneplus_sm8450` as the root and puts `common` in `kernel_platform/common`
  (this is what OnePlus' `kernel_manifest/oneplus_10_pro_v.xml` does).
* **Toolchain:** OnePlus' own Clang `r416183b`, fetched from the exact CodeLinaro commit in OnePlus' manifest. A random system/Ubuntu Clang gives
  `CFI`/`LTO`/`SCS` errors. Runner is `ubuntu-22.04` (24.04 breaks old 5.10 host tools).
* **ABI rules:** we only *add drivers*. `CFI_CLANG`, `SHADOW_CALL_STACK`, `MODVERSIONS` stay as stock. Turning those off (a common "fix" for
  build errors) makes every vendor `.ko` fail to load -> bootloop. LTO is switched FULL->THIN only because FULL needs more RAM than a runner has;
  that does not change the ABI.
* Mac80211 / cfg80211 are **modules** on this phone; external-adapter drivers are built as modules against them (`modules.zip`).

## Use it

1. Create a **public** GitHub repo (private runners have 2 cores / 7 GB RAM and OOM during thin-LTO link) and upload everything in this folder
   (keep the `.github/workflows/build.yml` path).
2. **Actions -> Build NetHunter kernel... -> Run workflow.** First build is ~60-90 min, later ones are faster (ccache).
3. If it fails, open the red step: the *"Show the real error"* step prints the first real errors. Send me that text.
4. Download the artifact zips.

## Flash (read first)

* Unlocked bootloader required. **Back up your boot first:** with Kernel Flasher (fatalcoder524) -> "Backup boot", and keep a copy of the stock `boot.img` from your OxygenOS
  firmware on your PC as well.
* Flash `*-AK3.zip` with **Kernel Flasher** (or a recovery that supports AK3). The ramdisk is not touched.
* **Root is now KernelSU-Next (built into this kernel), not Magisk.** Flash the AK3 zip onto a **stock** (un-patched) boot, install the
  **KernelSU-Next manager APK** and it works with no boot patching. If your current boot is Magisk-patched, restore the stock `boot.img`
  first (Magisk and KSU together fight each other). Nothing is rooted for apps until the manager grants it.
* Built with `enable_ksu=false` you get the plain NetHunter kernel back (then use Magisk as before).
* Recovery from a bad flash: boot to fastboot and `fastboot flash boot boot_stock.img` (or `fastboot flash boot_a/boot_b`).

## KernelSU-Next + SUSFS + Baseband-guard (what was added and how it is pinned)

| Part | Version (pinned in workflow inputs / `scripts/add_ksu_susfs_bbg.sh`) | Notes |
|---|---|---|
| KernelSU-Next | commit `234f6e04` = version **33239** (Aug 2026) | built in (`CONFIG_KSU=y`), manual SUSFS hooks, no kprobes hook mode |
| SUSFS | `ee7dc7a` = **v2.2.0** (`gki-android12-5.10`) | kernel half only. Hiding rules need the SUSFS userspace module (e.g. `susfs4ksu-module`) |
| Wild fix patches | `WildKernels/kernel_patches` `41ae18b` | glue that makes SUSFS v2.2.0 apply on that KSUN commit |
| Baseband-guard | `a54e0dc`, in the LSM list | blocks writes to modem/EFS/etc. `BBG_BLOCK_BOOT`/`RECOVERY` are **off** so you can still flash kernels |
| Vendor-module blocklist | `block_oplus_modules` (on) | Oplus `oplus_security_guard`-family `.ko`s are refused at boot; edit `block_module_list` or untick it |

**Do not "update to latest":** KSUN `dev` (Oct 2026) and SUSFS v2.3.0 no longer match the fix patches, and `susfs_ref`/`ksun_ref` must be moved together.
The *Add KernelSU-Next...* step fails with a clear message (`unexpected reject in ...`) if a combination doesn't match.
These pins were dry-run applied (zero failed hunks) on the OnePlus 5.10.226 tree and the resulting Kconfig resolves, but the compile itself
can only be verified by your Actions run.

NetHunter notes with KSU: the NetHunter app / Kali chroot work with any root, but modules written only for Magisk (firmware pack, etc.) may need a
KernelSU-compatible zip or manual copy of the firmware into `/vendor/firmware`.

## Wi-Fi (external adapter) and USB features

1. Unzip `*-modules.zip` to `/data/local/tmp/nh-modules` (`adb push`), then:
   `su -c "sh /data/local/tmp/nh-modules/load-nethunter-modules.sh"`
2. Adapter firmware (needed by e.g. AR9271 `htc_9271.fw`, RT2870, MT7601U...): install the NetHunter app's firmware module (KSU module manager) / a
   "Nethunter wireless firmware" zip so the files appear in `/vendor/firmware` or `/system/etc/firmware`.
3. Plug adapter (OTG), then in the Kali chroot / root shell:
   ```
   ip link set wlan1 down; iw dev wlan1 set type monitor; ip link set wlan1 up
   iw dev wlan1 set channel 6; aireplay-ng -9 wlan1     # injection test
   ```
4. HID keyboard/mouse (BadUSB), RNDIS, mass-storage and USB serial adapters (CH341/CP210x/FTDI/PL2303) are built into the kernel.

**Honest limits**
* **Internal Wi-Fi (Qualcomm qcacld `wlan.ko`) is a vendor module** - this build doesn't change it. Monitor mode there is not guaranteed and
  **injection on the internal chip does not work** on any Qualcomm phone; use an external adapter.
* Popular out-of-tree adapters (RTL8812AU/8814AU/8821AU "aircrack-ng" drivers) are not in this first build. In-tree: AR9271/AR9170, RTL8187,
  RTL8188/8192CU/8723AU, RT2800USB (RT3070/5370/5572), MT7601U, MT76x0U/x2U, ZD1211. Ask me to add 8812AU as a next step.
* Not enabled on purpose (changes structs the stock modules depend on): extra netfilter/conntrack options, SDR (optional input exists), PREEMPT, etc.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `drivers/soc/oplus/storage/Kconfig not found` | You built `common` alone -> use this workflow's layout |
| `clang: error: ... unknown argument / unsupported option` | System clang used. Must be OnePlus `clang-r416183b` first in `PATH` |
| `make: *** No rule to make target 'nethunter_defconfig'` | Fragment not appended / wrong branch |
| Build killed, "Terminated" / `ld.lld: error: ... out of memory` | Private repo / low RAM. Make repo public |
| Boots to bootloader / bootloop after flashing | Firmware != source (check `uname -r`), or you changed ABI options. Flash stock boot, tell me your build number |
| Wi-Fi/touch dead after flash | Same: stock vendor modules rejected (`dmesg \| grep -i "disagrees about version"`) |
| `insmod: Unknown symbol __ieee80211_create_tpt_led_trigger` | Stock mac80211 still loaded - script unloads it; run it again |
| `unexpected reject in <file> and no fix_<file>.patch` (KSU step) | KSUN/SUSFS refs were changed separately. Restore the pinned defaults |
| `50_add_susfs_... does not apply` | `kernel_ref` is a different OnePlus release than NE2211_15.0.0.1302 |
| Manager says "kernel not supported / needs update" | Use a KernelSU-Next manager release close to version 33239 (Aug 2026) |
| `Config not applied` warnings in the workflow | A symbol lacks a dependency - paste the warning |
