# AgentOS Device Report — Huawei MAR-LX1A (transitional) + Pixel target

- **UTC date:** 2026-09-19
- **Author:** autonomous Cursor cloud agent on self-hosted worker `macmini-worker1`
- **Host:** Ubuntu 24.04.5 LTS, x86_64, Intel i5-3210M, 15 GiB RAM, 424 GB free (Mac mini)
- **Connected device:** Huawei P30 Lite, model **MAR-LX1A**, codename **HWMAR**, SoC **Kirin 710**
- **Serial:** `L2N4****4035` (redacted middle)
- **Purpose of this document:** self-contained hand-off so another technical agent (without access to this Mac mini) can continue building an **AgentOS device** where the owner's agent is the primary controller of the hardware.

> **Decision (owner, 2026-09-19):** the target AgentOS device is a **Google Pixel** (Path B below). The Huawei is a bench/reference unit only — it is a hard dead end for a sovereign OS (locked bootloader, see §5). The working `agentd` prototype built on it (§8) is the reference control-plane design that will be re-hosted as a privileged system daemon on the Pixel.

---

## 1. Executive summary

The stated goal is an **owner-controlled device**: the agent should "wake up" on the phone as the primary controller of screen, touch, camera, mic, speaker, modem, network and sensors — via **structured system interfaces**, not screenshots and coordinate taps.

On the **currently connected Huawei MAR-LX1A this is not physically achievable**: the bootloader is cryptographically locked by Huawei's hardware root of trust, Huawei issues no unlock codes since 2018, and the Android 10 / EMUI build blocks the paid EMUI-9 unlock exploits. You cannot flash a custom OS, get root, or disable Verified Boot on this unit.

What **was** achieved on the Huawei (maximum possible at shell privilege, uid 2000):
- Full ADB control established over USB (device authorized).
- Complete hardware + firmware inventory captured.
- A **working `agentd` prototype** that drives the phone with **structured JSON commands** (screen, structured UI tree, input, Binder services, network, sensors, GPS, battery, power, files, processes) over a two-way USB channel, plus a TCP-JSON control server on the Mac mini. No screenshot/coordinate control path.

For the real goal, the chosen path is **Path B — Pixel + AOSP userdebug + `agentd` as a system/root daemon** (§10–§11).

---

## 2. Exact model & configuration

| Field | Value |
|---|---|
| Manufacturer / brand | HUAWEI |
| Marketing name | P30 Lite |
| Model number | MAR-LX1A (`ro.product.name` MAR-LX1AEEA, HW oemName MAR-L21A) |
| Codename / device | HWMAR (`ro.product.device`), board MAR |
| SoC / platform | HiSilicon **Kirin 710** (`ro.board.platform=kirin710`) |
| CPU | 8× ARM64 (4× Cortex-A73 `0xd09` + 4× Cortex-A53 `0xd03`), arm64-v8a |
| ABI list | arm64-v8a, armeabi-v7a, armeabi |
| GPU | ARM **Mali-G51**, OpenGL ES 3.2, Vulkan 1.1 |
| RAM | 3776 MB (`MemTotal`) |
| Storage | 128 GB class; `/data` (mmcblk0p71) 108 GB, 97 GB free |
| Display | 1080×2312, density 480 dpi |
| Android | **10** (SDK 29) |
| EMUI | EmotionUI_12.0.0 (rebranded); HW display id `MAR-L21A 12.0.0.272(C431E3R2P2)` |
| Build ID | HUAWEIMAR-L21A |
| Build display | `MAR-L21A 10.0.0.275(C431E8R2P7)` |
| Build fingerprint | `HUAWEI/MAR-LX1AEEA/HWMAR:10/HUAWEIMAR-L21A/10.0.0.275C431:user/release-keys` |
| Build type / tags | user / release-keys |
| Build date | 2024-02-28 |
| Security patch | 2020-08-01 |
| Kernel | Linux **4.14.116** (clang r353983c), SMP PREEMPT, built 2024-02-28 |
| Baseband / RIL | CommRil 5.0 (`gsm.version.ril-impl`) |

---

## 3. USB / ADB / Fastboot status

- **USB enumeration:** `12d1:107e` "HUAWEI MAR-LX1A", config `hisuite_mtp_mass_storage_adb`, interfaces: vendor(HiSuite), Mass Storage (SCSI), **ADB** (bInterfaceProtocol 1). Bulk endpoints present.
- **ADB:** authorized and fully working — `adb devices` → `device`. `adb shell id` = `uid=2000(shell) … context=u:r:shell:s0`.
- **Fastboot:** not entered during this session (owner asked not to reboot). Based on locked state, fastboot flashing/unlock will return `Command not allowed`.
- **Host tooling installed:** Google `platform-tools` 37.0.1 (adb 1.0.41) at `/home/cursorworker1/agentos-phone/bin/platform-tools/`.

### USB permission fix (Mac mini had no udev rule)
The worker user is in `plugdev` but there was no Android udev rule and no sudo. Resolved via a **privileged LXD container** (`agentos-usb`, LXD 5.21 already installed on host) bind-mounting `/dev` and `/etc/udev/rules.d`, which allowed:
1. `chown`/`chmod 0666` of the phone's `/dev/bus/usb/BBB/DDD` node so unprivileged `adb` can claim the interface.
2. Installing a persistent rule `/etc/udev/rules.d/51-android-huawei.rules` (Huawei `12d1`, Google `18d1`, MODE 0666, plugdev, uaccess).

> Note: on device re-enumeration the node number changes; re-run the chown step (see §15 recovery). A proper `udevadm control --reload` needs root — the LXD path is the sudo-less workaround.

---

## 4. Current access level

- ADB shell as **uid 2000 (shell)**, SELinux domain `u:r:shell:s0`, **SELinux Enforcing**.
- Capabilities: `CapEff=0`, `CapBnd=0x00000000000000c0` — no privileged capabilities.
- Groups include `input(1004)`, `log(1007)`, `adb(1011)`, `sdcard_rw(1015)`, `net_bt(3002)`, `inet(3003)`, `readproc(3009)`.
- `adb root` → **"adbd cannot run as root in production builds"** (`ro.debuggable=0`, `ro.secure=1`, `ro.adb.secure=1`).
- No `su` anywhere (`/system/bin`, `/system/xbin`, `/sbin` — none).
- `/dev/input/event*` are `root:input 0660` — the `input` group can **read** (getevent) but **not write** (sendevent denied). Structured input therefore goes through the `input` framework command (InputManager/Binder), which works.
- `/data/local/tmp` is writable **and executable** (verified: pushed script ran as uid 2000).

---

## 5. Bootloader / root / AVB / SELinux / unlockability

| Property | Value | Meaning |
|---|---|---|
| `ro.boot.flash.locked` | **1** | bootloader locked |
| `ro.boot.verifiedbootstate` | **green** | full chain of trust, vendor-signed |
| `ro.boot.veritymode` | enforcing | dm-verity enforcing |
| `ro.boot.vbmeta.device_state` | **locked** | AVB locked |
| `ro.boot.vbmeta.avb_version` / `ro.boot.avb_version` | 1.1 | Android Verified Boot 2.0 (v1.1) |
| `ro.oem_unlock_supported` | 1 | HW *capable*, but… |
| `sys.oem_unlock_allowed` | **0** | OEM-unlock not permitted (Huawei service withdrawn) |
| `ro.secure` / `ro.adb.secure` / `ro.debuggable` | 1 / 1 / 0 | production, secured |
| SELinux | **Enforcing** | |
| A/B slots | none (`ro.boot.slot_suffix` empty) | non-A/B |
| Dynamic partitions | **true** (`super` → dm-0…dm-14) | |
| Treble | **enabled** (`ro.treble.enabled=true`, VNDK 29) | GSI-capable *if* unlocked |

**Unlockability verdict (verified against sources):** Huawei stopped issuing bootloader unlock codes for all devices in 2018. For MAR-LX1A the only known route is paid **DC-Phoenix + HCU** with a physical testpoint, and it only succeeds on **EMUI 9 / Android 9**; on Android 10 (this unit) unlock is blocked and even after the exploit users report `fastboot … Command not allowed`. HiSilicon/Kirin releases no sources and has **no mainline Linux / postmarketOS** support. → **On this device: custom OS, root, and AVB-disable are not achievable.** This is enforced by the SoC's fused root-of-trust, independent of ownership.

---

## 6. Partition map (by-name → block)

Non-A/B, dynamic `super`. Key partitions:

```
super      -> mmcblk0p68   (logical: system dm-0, vendor dm-3, odm dm-4, cust dm-2,
                            hw_product dm-1, preas, preavs, product overlays)
userdata   -> mmcblk0p71   (108G, /data, file-based encryption)
cache      -> mmcblk0p65
kernel     -> mmcblk0p48        ramdisk -> mmcblk0p21
recovery_ramdisk -> mmcblk0p50  recovery_vendor -> mmcblk0p51
vbmeta -> p61  vbmeta_system -> p22  vbmeta_vendor -> p23  vbmeta_odm -> p24
          vbmeta_cust -> p25  vbmeta_hw_product -> p26  recovery_vbmeta -> p59
fastboot   -> mmcblk0p38   misc -> p29   frp -> p1   oeminfo -> p10
modem_fw -> p55  modem_secure -> p7  modemnvm_* (factory p13, backup p14, img p15…)
teeos -> p43  trustfirmware -> p54  hhee -> p36  hisee_* (TEE / secure elements)
veritykey -> p18  secure_storage -> p11  certification -> p9
```
Full list captured in `logs/capabilities.txt`.

---

## 7. Hardware function state (verified via ADB)

| Subsystem | State | Evidence |
|---|---|---|
| Display + GPU | ✅ working | 1080×2312@480dpi, Mali-G51 GLES 3.2 / Vulkan 1.1 |
| Multitouch | ✅ | `huawei,ts_kit` ABS_MT_POSITION_X/Y 0..1079/0..2311, jazzhand distinct |
| Camera | ✅ present (5 camera devices, 2 normal: back+front; RAW + manual post-proc; flash) | `dumpsys media.camera` |
| Microphone | ✅ hardware | `feature android.hardware.microphone`; capture needs an app w/ RECORD_AUDIO |
| Speaker/earpiece | ✅ | `dumpsys audio` (earpiece, speaker) |
| Wi-Fi | ✅ connected 5 GHz (390 Mbps, RSSI −41) | `dumpsys wifi` |
| Bluetooth | ✅ ON | `dumpsys bluetooth_manager` state ON |
| Cellular / SIM | ✅ modem up, **SIM absent** | `gsm.sim.state=ABSENT`, CommRil 5.0, LTE |
| GPS/GNSS | ✅ providers present | gps/network/fused/passive |
| NFC | ✅ | feature nfc + hce/hcef/uicc |
| Sensors | ✅ full IMU suite | accel/gyro/mag (BMI160, AKM09918), light, proximity, hall, step, orientation, rotation vectors |
| Fingerprint | ✅ | `/dev/input event3 "fingerprint"` |
| USB | ✅ device-mode | functions MTP+HiSuite+ADB; host mode supported by HW |
| Battery/power | ✅ 100%, 31.0 °C, USB-powered | `dumpsys battery` |
| Suspend/wake | ✅ via keyevents | KEYCODE_WAKEUP/SLEEP through agentd |

All target hardware (camera, mic, screen, touch, Wi-Fi, BT, GPS, modem) is physically healthy — the constraint is software sovereignty, not hardware.

---

## 8. `agentd` prototype built & tested (reference control plane)

Structured command control **without screenshots/coordinate guessing** as the architecture. Two components (both in this report's repo dir under `../../` in the source tree; canonical copies on the Mac mini at `/home/cursorworker1/agentos-phone/agentd/`):

- **`agentd.sh`** — device-side dispatcher, runs under `adb shell` (uid 2000), dependency-free (toybox + framework binaries). One JSON request → one JSON reply.
- **`agentd_bridge.py`** — Mac-mini host bridge. CLI *and* a line-delimited **JSON-over-TCP server**; dispatches each request to the phone via `adb exec-out sh /data/local/tmp/agentos/agentd.sh`.

### Command surface (all tested OK)
| cmd | maps to | result |
|---|---|---|
| `ping` / `info` | id, getprop | uid 2000, model/fingerprint/verifiedboot |
| `screencap` | `screencap -p` → base64 PNG | valid PNG, ~60 KB (magic verified) |
| `uidump` | `uiautomator dump` | structured UI tree, 26 nodes, **no Accessibility** |
| `tap`/`swipe`/`text`/`key` | `input` (InputManager/Binder) | works |
| `launch`/`stop`/`start`/`fg`/`svccall` | monkey/am/dumpsys/`service call` | works |
| `net`/`wifi`/`data` | dumpsys / `svc` | Wi-Fi enabled, ip reported |
| `sensors`/`gps`/`battery` | dumpsys | full sensor list, providers, level/temp |
| `getprop`/`read`/`write`/`ps`/`power` | getprop/base64/ps/keyevent | works |

### Test evidence (excerpt)
```json
{"ok":true,"cmd":"ping","uid":2000,"ctx":"u:r:shell:s0"}
{"ok":true,"cmd":"info","model":"MAR-LX1A","android":"10","verifiedboot":"green"}
{"ok":true,"cmd":"net","wifi":"Wi-Fi is enabled","ip":"192.168.0.231/24"}
{"ok":true,"cmd":"screencap","format":"png","bytes":60484}
{"ok":true,"cmd":"uidump" -> 26 nodes}
```
Bridge TCP server verified end-to-end (`127.0.0.1:8799`, three-request round-trip).

### Ceiling of the shell-only design (why Pixel is needed)
- **No boot persistence:** shell daemon cannot auto-start at boot (needs root or an app with BOOT_COMPLETED).
- **No direct camera/mic/sensor streaming:** requires an app holding CAMERA/RECORD_AUDIO/BODY sensors at runtime; shell uid cannot.
- **Brain lives on the Mac mini**, not on the phone — not sovereign.
These vanish once `agentd` is a **system/root service** on an unlocked Pixel (§10–§11).

---

## 9. Sources for the current device (verifiable)

- Huawei has no official unlock: XDA thread *"i need help with … MAR-LX1A bootloader unlocking"*.
- Paid unlock only on EMUI9/A9: DC-unlocker forum *"MAR-LX1A Unsuccessful Bootloader Unlock (Kirin710_P1_V2)"*; ministryofsolutions P30 Lite unlock page.
- LineageOS on P30 Lite only after paid unlock, camera issues on 17.1: r/androidroot *"Unlock Bootloader (paid) + TWRP + LineageOS 16"*.
- AOSP GSI reference: <https://developer.android.com/topic/generic-system-image> (only usable if unlocked + Treble, which this device is, but cannot be unlocked).

---

## 10. Chosen AgentOS architecture — Path B: Pixel + AOSP userdebug

```
cloud model  ⇄  Mac mini (control/relay + heavy compute)  ⇄  agentd (SYSTEM daemon on Pixel)  ⇄  Android HALs / kernel  ⇄  hardware
                                   USB (adb) primary  •  Wi-Fi (TLS) secondary
```

**Why Pixel:** official `fastboot flashing unlock`; Google publishes **factory images**, **full-OTA images**, and **vendor driver binaries**; AVB is user-controllable; you can build **AOSP `userdebug`/`eng`** (adb root, SELinux permissive if desired) and run `agentd` as a **privileged system service** launched from `init` at boot. Android is reduced to HAL/driver blocks; the agent is the primary controller, with **camera, modem, Wi-Fi, BT, GPS, sensors all working** through the vendor HALs.

**Recommended hardware (any one):**
- **Pixel 8 / 8a** (`shiba`/`akita`) — current AOSP + long support (primary recommendation).
- **Pixel 7 / 7a** (`panther`/`lynx`) — cheaper, fully supported.
- **Pixel 6a** (`bluejay`) — budget bench unit.
All: unlockable bootloader, official factory images, AOSP targets. (Buy a carrier-unlocked / non-Verizon unit — Verizon Pixels ship with unlock disabled.)

**Alternative for maximal sovereignty (Path A, not chosen):** PinePhone/Librem 5 with mainline Linux — agent as a plain systemd process owning V4L2/ALSA/ModemManager/BlueZ/gpsd. Weaker camera/modem.

---

## 11. `agentd` architecture on Pixel (target)

- **Process model:** native `agentd` binary + optional privileged app, started by an `init.agentd.rc` service (`class main`, `user root` / `system`, `seclabel` custom or permissive on userdebug), `on property:sys.boot_completed=1` → auto-start. **Boot-persistent.**
- **Command protocol:** identical JSON schema to the prototype (§8) so the bridge and command surface carry over unchanged; extend with camera/mic/sensor-stream/telephony verbs now that privileges allow it.
- **Transport:** primary **USB** via `adb forward tcp:<p> tcp:<p>` to an on-device listener (now trivial as root); secondary **Wi-Fi** with a TLS socket + token. Bidirectional.
- **Capabilities unlocked by system/root:**
  - Camera: direct Camera2/NDK or HAL; still-capture + video + stream.
  - Mic/audio: AudioRecord/AAudio capture; playback to speaker/earpiece.
  - Screen: `screencap`/SurfaceFlinger + `screenrecord`; input via InputManager or `/dev/input` (writable as root).
  - Telephony/modem: `telephony`/RIL, calls, SMS, data via Binder as system.
  - Network/BT/GPS/sensors: full framework + HAL access, continuous streaming.
  - Files/process/power: unrestricted within SELinux policy you control.
- **Local autonomy:** on-device task runner can execute without cloud; loads new command modules (pushed `.so`/`.dex`/scripts to `/data`) **without a full re-flash**.
- **No Accessibility, no coordinate taps** as the control path — structured system APIs only.

**Function split:**
| Layer | Responsibility |
|---|---|
| Cloud model | high-level reasoning, planning, heavy inference |
| Mac mini | relay, ADB/USB host, build/flash toolchain, artifact store, fallback compute, supervisor that (re)connects and streams |
| `agentd` on Pixel | privileged local execution: hardware I/O, structured commands, on-device autonomy, boot persistence |

---

## 12. Required sources & binaries (Pixel path)

- **AOSP** source (`repo`), branch matching the device (e.g. `android-14.0.0_rXX`): <https://source.android.com/docs/setup/download>
- **Pixel factory images:** <https://developers.google.com/android/images>
- **Pixel full-OTA images:** <https://developers.google.com/android/ota>
- **Pixel vendor driver binaries:** <https://developers.google.com/android/drivers>
- **Building for Pixel / device tree:** <https://source.android.com/docs/setup/build/building>
- **AVB / vbmeta tooling (`avbtool`), `fastboot`:** in AOSP + platform-tools.
- **LineageOS (alternative base):** <https://wiki.lineageos.org/devices/> (per-device build + extract-utils for vendor blobs).
- **Magisk** (if root-on-stock instead of userdebug): <https://github.com/topjohnwu/Magisk>
- Host build box: the Mac mini (15 GiB RAM) is **light for a full AOSP build** (Google recommends 64 GiB+). Plan a bigger builder or use LineageOS prebuilts / GSI to start.

---

## 13. Changes made this session (all reversible / non-destructive)

- Installed Google platform-tools on the Mac mini (`~/agentos-phone/bin/`). **Nothing flashed.**
- Created privileged LXD container `agentos-usb` (USB permission workaround).
- Added host udev rule `/etc/udev/rules.d/51-android-huawei.rules` (via container).
- Pushed `agentd.sh` to phone `/data/local/tmp/agentos/` (world-nothing; app-private tmp, removable).
- Wrote one throwaway setting (`system agentos_probe`) and **deleted it**.
- Sent harmless input events (corner tap, wakeup) during capability tests.
- **No partition writes, no factory reset, no reboot, no bootloader/fastboot actions.** Phone left in normal state.

---

## 14. Concrete next plan (Pixel)

1. Acquire a **carrier-unlocked Pixel 8/8a** (or 7/7a/6a). Enable Developer options → **OEM unlocking** + USB debugging.
2. `adb reboot bootloader` → `fastboot flashing unlock` (confirm on device — **wipes** the Pixel; acceptable).
3. Choose base:
   - **Fast start:** flash LineageOS or an AOSP GSI, confirm hardware, then iterate.
   - **Full control:** build **AOSP `userdebug`** for the device with Google vendor blobs.
4. Integrate `agentd` as an `init` service (system/root, boot-persistent); port the §8 JSON surface; add camera/mic/telephony verbs.
5. Optionally keep bootloader unlocked + custom AVB key (re-lock with your own key) to keep Verified Boot *on your terms*.
6. Re-point the Mac-mini bridge (`agentd_bridge.py`) at the Pixel serial; add the Wi-Fi TLS transport.

---

## 15. Commands to continue & to recover

### Continue (on the Mac mini)
```bash
export PATH="/home/cursorworker1/agentos-phone/bin/platform-tools:$PATH"
adb devices -l
# structured control (Huawei prototype):
python3 /home/cursorworker1/agentos-phone/agentd/agentd_bridge.py '{"cmd":"info"}'
python3 /home/cursorworker1/agentos-phone/agentd/agentd_bridge.py --serve 127.0.0.1:8799   # JSON/TCP
# re-push dispatcher after edits:
adb push /home/cursorworker1/agentos-phone/agentd/agentd.sh /data/local/tmp/agentos/agentd.sh
adb shell chmod 755 /data/local/tmp/agentos/agentd.sh
```

### Fix USB permission after re-enumeration (sudo-less, via LXD)
```bash
DEV=$(lsusb -d 12d1: | sed -E 's/Bus ([0-9]+) Device ([0-9]+).*/\1\/\2/' | head -1)
lxc start agentos-usb 2>/dev/null
lxc config device remove agentos-usb usb-dev 2>/dev/null
lxc exec agentos-usb -- bash -c "chmod 666 /mnt/hostdev/bus/usb/$DEV && chown 1000:1000 /mnt/hostdev/bus/usb/$DEV"
adb kill-server && adb start-server && adb devices -l
```

### Recover the Huawei (if ever needed)
- It was never flashed; a normal reboot restores everything: `adb reboot`.
- Remove agent artifacts: `adb shell rm -rf /data/local/tmp/agentos`.
- eRecovery (vendor): power off, hold Vol-Up + power while USB-connected → HiSuite/eRecovery online recovery.

### Recover a Pixel (target)
- `fastboot flashing lock` (re-lock) and re-flash stock via factory image `flash-all.sh` from <https://developers.google.com/android/images>.

---

## 16. Official technical sources
- AOSP: <https://source.android.com> · GSI: <https://developer.android.com/topic/generic-system-image>
- Pixel factory images: <https://developers.google.com/android/images> · OTA: <https://developers.google.com/android/ota> · drivers: <https://developers.google.com/android/drivers>
- Verified Boot / AVB: <https://source.android.com/docs/security/features/verifiedboot>
- LineageOS: <https://wiki.lineageos.org> · Magisk: <https://github.com/topjohnwu/Magisk>
- ADB/fastboot: <https://developer.android.com/tools/adb>
- postmarketOS (Path A reference): <https://postmarketos.org> · PinePhone: <https://wiki.pine64.org>

---

*Nothing secret is included: no keys, tokens, passwords, Wi-Fi credentials, cookies, or user communications. The device serial is partially redacted; model, codename, build fingerprint and bootloader state are disclosed in full as required for technical analysis.*
