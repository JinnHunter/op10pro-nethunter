# From zero to a flashed NetHunter kernel (OnePlus 10 Pro, OxygenOS 15)

You will: (1) make a GitHub account, (2) put the project in a public repo, (3) press "Run workflow",
(4) download the result, (5) check your phone matches, (6) flash it, (7) test it.
Nothing is built on your PC. GitHub's servers do the compiling.

GitHub's buttons get renamed now and then. If a label differs slightly, look for the closest one.

---

## 0. Words you will see

| Word | Meaning |
|---|---|
| Repository ("repo") | A folder of files stored on GitHub |
| Actions | GitHub's free build servers |
| Workflow | The recipe file the servers follow (`.github/workflows/build.yml`) |
| Artifact | The files a build produces (your kernel zips) |
| AK3 zip | AnyKernel3 zip. A flashable file that swaps only the kernel in your `boot` partition |
| Slot A/B | The OnePlus 10 Pro has two copies of boot. You only touch the active one |

---

## 1. Make a GitHub account

1. Go to https://github.com/signup and register with your email.
2. Open the verification email and click the link. **Unverified accounts often can't run Actions.**
3. Optional: turn on 2-factor authentication (Settings -> Password and authentication).

## 2. Create the repository (it MUST be public)

1. Click the **+** at the top right -> **New repository**.
2. Name: `op10pro-nethunter` (any name works).
3. Visibility: **Public.**
   - Public repos get 4 CPU / 16 GB RAM build machines and free Actions time.
   - Private repos get 2 CPU / 7 GB RAM. The linking step runs out of memory and the build dies with "Terminated".
4. Leave "Add a README", ".gitignore" and "license" **unticked**. Click **Create repository**.

## 3. Get the project files onto GitHub

On your PC, download and unzip `nethunter-op10pro.zip` (it is in the workspace next to this guide).
You should see:

```
README.md   GUIDE.md   anykernel.sh   nethunter.fragment   nethunter.sdr.fragment
scripts/add_ksu_susfs_bbg.sh
.github/workflows/build.yml          <- hidden folder (starts with a dot)
```

### Option A: GitHub website only (easiest)

1. On your new empty repo page click **uploading an existing file** (or **Add file -> Upload files**).
2. Drag in these from the unzipped folder: `README.md`, `GUIDE.md`, `anykernel.sh`, `nethunter.fragment`,
   `nethunter.sdr.fragment` and the whole `scripts` folder.
   Commit them with the green **Commit changes** button.
3. Now add the workflow file by hand, because hidden folders are easy to lose when dragging:
   - **Add file -> Create new file**.
   - In the name box type exactly `.github/workflows/build.yml`. When you type each `/` GitHub makes a folder.
   - Open `build.yml` from the zip in Notepad/TextEdit, copy **everything**, and paste it into the big text box.
   - Click **Commit changes** (commit straight to `main`).
4. Check the repo page. You must see the folders `.github` and `scripts`, and the file path
   `.github/workflows/build.yml`. A typo in that path means the build never shows up.

### Option B: git on your PC (if you already use git)

```bash
cd nethunter-op10pro
git init -b main
git add -A            # -A includes the hidden .github folder
git commit -m "NetHunter kernel build"
git remote add origin https://github.com/<your-username>/op10pro-nethunter.git
git push -u origin main      # password = a Personal Access Token, not your login password
```

## 4. Turn on Actions and run the build

1. Open the **Actions** tab of your repo.
2. If you see "Workflows aren't being run on this repository", click the green
   **"I understand my workflows, go ahead and enable them"** button.
3. In the left list click **Build NetHunter kernel - OnePlus 10 Pro (NE2211) OxygenOS 15**.
4. Click **Run workflow** (grey button on the right). A small form appears:

| Field | What to do |
|---|---|
| `kernel_ref` | Leave the default (`oneplus/sm8450_v_15.0.0_oneplus_10_pro`) |
| `localversion` | Leave the default |
| `enable_ksu` | Leave ticked for KernelSU-Next + SUSFS. Untick for a plain NetHunter kernel (you then keep Magisk) |
| `enable_bbg` | Leave ticked (Baseband-guard) |
| `block_oplus_modules` / `block_module_list` | Leave the defaults |
| `ksun_ref` / `susfs_ref` | **Leave the defaults.** They are matched pins |
| `enable_sdr` | Leave unticked |
| `debug_single_thread` | Leave ticked. If the build fails you get a readable error |

5. Click the green **Run workflow**. Refresh after a few seconds. A yellow-dot run appears. Click it, then click the job
   named `build` to watch live logs.

**How long?** The first run takes roughly 60 to 120 minutes (the limit is 240). Later runs are faster because of the cache.
You can close the browser. It keeps running.

## 5. What a good and a bad run look like

Steps in order: install packages -> fetch source -> fetch Clang -> **Add KernelSU-Next + SUSFS + Baseband-guard**
-> configure -> verify config -> **Build** -> sanity check -> package -> upload.

- Green tick on every step = success.
- Red cross = click that step. Scroll to the first line containing `error`.
  The step **"Show the real error if the build failed"** prints the first errors for you.
- Copy about 30 lines around the first error and send them to me. Do not send only "it failed".
- The "Add KernelSU-Next..." step is the most likely to fail on its first run. It prints a plain message such as
  `unexpected reject in ...`. Send that message to me as well.
- Orange "Config not applied" warnings are not failures. Mention them to me anyway.

## 6. Download your kernel

1. When the run finishes, click the run title (the page with the summary). Scroll to **Artifacts** at the bottom.
2. Click the artifact (named like `NetHunter-OP10Pro-OOS15-5.10.226-...`). You must be logged in. It downloads as a zip.
3. Unzip it once. Inside:
   - `...-AK3.zip` (**do not unzip this one**; it is what you flash)
   - `...-modules.zip` (external Wi-Fi / Bluetooth driver modules)
   - `...-config.txt` and `build.log` (only for debugging)

Artifacts are kept for 90 days.

---

## 7. Prepare the phone BEFORE flashing

Do all of this first. It is what saves you if something goes wrong.

1. **Bootloader must already be unlocked.** If it isn't, flashing is impossible. Unlocking wipes the phone.
2. **Firmware must match the source.** The build is based on OxygenOS 15 `NE2211_15.0.0.1302`.
   - Turn on Developer options -> USB debugging.
   - Install Android "platform-tools" on the PC (search "Android SDK Platform-Tools" at developer.android.com).
   - Run `adb shell uname -r`. It must start with `5.10.226-android12-9`.
   - If it doesn't match, **stop and tell me your build number** (Settings -> About -> Version). Flashing a kernel built for a different firmware breaks Wi-Fi and touch, or bootloops.
3. **Get the stock `boot.img` and keep it on your PC.** Two ways:
   - On the phone use the **Kernel Flasher** app (by fatalcoder524) -> *Backup boot*, then copy the file to the PC.
   - Or extract it from your firmware zip with a "payload dumper" tool.
4. If your boot is currently **Magisk-patched** and you built with KernelSU-Next, restore the stock boot first:
   `adb reboot bootloader`, then `fastboot flash boot boot_stock.img`, then `fastboot reboot`.
   Don't run Magisk and KernelSU together.
5. Install the **KernelSU-Next manager APK** from the KernelSU-Next GitHub releases page. Pick one close to version 33239
   (August 2026). Don't open it yet.

## 8. Flash

Easiest, with the phone booted:

1. Copy `...-AK3.zip` to the phone.
2. Open **Kernel Flasher**. Choose *Flash AK3 zip* and pick the file. (You can also use a custom recovery that supports AK3 zips.)
3. Wait for "Done", then reboot.

**If the phone does not boot** (stuck on logo, boot loop, or lands in fastboot):

```
adb reboot bootloader       # or hold Power + Volume Up/Down into fastboot
fastboot flash boot boot_stock.img
fastboot reboot
```

That returns you to the stock kernel. This is why step 7.3 matters.

## 9. Check it worked

```
adb shell uname -r          # should show 5.10.226-android12-9-nethunter...
```

Open the **KernelSU-Next manager**. It should say the kernel is working and show a version near 33239.
(If you built with `enable_ksu=false`, it won't be there. Use Magisk instead.)
Grant root to the **NetHunter app** and to your terminal app inside the manager.

## 10. Load the Wi-Fi / USB modules and test

1. Unzip `...-modules.zip` on the PC into a new folder called `nh-modules` (it contains `modules/` and `load-nethunter-modules.sh`).
   Push the folder to the phone: `adb push nh-modules /data/local/tmp/`
2. In a root shell on the phone (`adb shell` then `su`):
   `sh /data/local/tmp/nh-modules/load-nethunter-modules.sh`
3. Plug your USB Wi-Fi adapter through an OTG adapter. Then:
   ```
   ip link set wlan1 down
   iw dev wlan1 set type monitor
   ip link set wlan1 up
   aireplay-ng -9 wlan1       # injection test
   ```
4. Adapters need firmware files for some chips (AR9271, RT2870, MT7601U...). See README.md for where they go.
5. **Internal Wi-Fi injection won't work** on this phone (Qualcomm). That is normal. Use the external adapter.

The NetHunter app and Kali chroot are installed separately from the official NetHunter app/chroot. This kernel gives them the
features they need (HID, gadget, adapters).

## 11. Rebuilding later

Just go to **Actions -> Run workflow** again. You don't re-upload anything. If you change a file, edit it on GitHub
(click the file -> pencil icon -> Commit changes) and run again.

## Cheat sheet of common problems

| Problem | Fix |
|---|---|
| No "Run workflow" button | `build.yml` isn't at `.github/workflows/build.yml` on the `main` branch, or Actions isn't enabled |
| Build ends with "Terminated" or out of memory | Repo is private. Make it public |
| Red "Add KernelSU-Next..." step | Send me the error. Or re-run with `enable_ksu` unticked to get a plain NetHunter kernel |
| Phone bootloops | Fastboot-flash the stock boot (section 8) and send me `adb shell uname -r` and your build number |
| Wi-Fi or touch dead after flash | The firmware doesn't match the source. Restore stock boot |
| Manager app says "unsupported kernel" | Use a manager version close to 33239 |
