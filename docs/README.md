# MAV Tech Assist

This folder is a starter toolkit for Windows laptops that rotate between hires.

It is designed around a USB workflow:

- double-click a launcher
- let the script do one focused job
- check the JSON report in `reports\`

There are also bundled launchers:

- `launchers\0-Dashboard.cmd`
- `launchers\0-Offline-Browser-Portal.cmd`
- `launchers\0-After-Hire-Pack.cmd`
- `launchers\0-Before-Hire-Pack.cmd`
- `launchers\5-LED-Wall-Test-Generator.cmd`
- `launchers\6-Local-Network-Helper.cmd`
- `launchers\7-Desktop-Generator.cmd`
- `launchers\8-Test-Pattern-Generator.cmd`
- `launchers\9-Event-Timer.cmd`

Related planning doc:

- `docs\DAILY_USE_GUIDE.md`
- `docs\TROUBLESHOOTING_GUIDE.md`
- `docs\DEPLOYMENT_AND_QA_GUIDE.md`
- `docs\SELF_HOSTED_INSTALL.md`
- `docs\MAV_Z9T_INSTALL_AND_USAGE.md`
- `docs\MOBILE_AND_BROWSER_TEST_PLAN.md`
- `docs\SITE_DEPLOYMENT_MODEL.md`
- `docs\LOCAL_NETWORK_HELPER.md`

## Dashboard

Launcher: `launchers\0-Dashboard.cmd`

This serves the same `web\index.html` browser site locally, then enables buttons, progress bars, green ticks, red stops, follow-up help for Windows script tasks, and the helper-backed local network page.

How it works:

- the browser does not run scripts directly
- PowerShell starts a local-only helper server on `127.0.0.1`
- the helper serves the same `web\` static site used by the hosted and offline versions
- the dashboard buttons call that local helper
- the helper runs the scripts with the current Windows user's permissions
- detailed logs are written to `reports\dashboard-runs\...`
- each dashboard launch uses a one-time local token so other web pages cannot trigger runs by guessing the port
- the same helper token also gates the local network helper API endpoints

Permission notes:

- no admin rights should be needed just to open the dashboard
- scripts that touch user files, browser profiles, Desktop, Downloads, and reports run as the signed-in user
- if you later add admin-level actions, such as uninstalling software or changing machine-wide settings, launch the dashboard as administrator
- the dashboard binds to `127.0.0.1`, not the LAN, so other devices should not be able to trigger it

## Local Network Helper

Launcher: `launchers\6-Local-Network-Helper.cmd`

What it does:

- opens the local helper page directly in the browser
- asks for show name, subnet, and watch-list devices
- can run a dry-run or real local Windows setup for network discovery, OpenSSH Server, and file-sharing prerequisites
- scans the subnet for likely devices such as PTZ cameras, projectors, sound desks, and other managed endpoints
- keeps a live red/green table showing whether watched devices are up or down

What it does not do:

- log into or reconfigure third-party devices on the LAN
- publish a chosen SMB share automatically
- take control of devices beyond reachability and lightweight fingerprinting

## Offline Browser Portal

Launcher: `launchers\0-Offline-Browser-Portal.cmd`

This opens `web\index.html` directly from the USB stick. It is the no-internet fallback version of the same browser site.

What it can do:

- explain which tests are browser-only, launcher-only, or online/server-backed
- auto-detect phone/tablet/desktop and move unsuitable tests into a greyed-out area
- open local browser tools such as the desktop generator, test pattern generator, event timer, and LED wall generator
- link to local docs and the launchers folder
- point users to `showtime.mav.z9t.me` when internet is available
- offer a hosted USB bundle download when opened from the live site

What it cannot do by itself:

- run PowerShell scripts directly from the browser
- inspect installed programs
- clean browser profiles
- run full Windows network diagnostics

For those, use `launchers\0-Dashboard.cmd` or the individual `.cmd` files.

## Included scripts

### 1. Declientify

Launcher: `launchers\1-Declientify.cmd`

What it does:

- checks Microsoft 365 status before cleanup
- closes major browsers
- moves browser profile stores out of the live path so Google and other web sessions are effectively logged out
- re-checks Microsoft 365 status afterwards

Why it is conservative:

- it does not try to wipe Office activation
- it does not hard-delete browser data by default
- archived browser stores are placed in `C:\Users\Public\Documents\MAV\ArchivedProfiles\...`

## 2. Network Test

Launcher: `launchers\2-Network-Test.cmd`

What it does:

- finds active physical Wi-Fi and Ethernet adapters
- pings each adapter's default gateway from its own source IP
- runs concurrent throughput tests
- compares Wi-Fi and Ethernet if both return usable results
- saves a JSON report with issues and raw summary values

Preferred tooling:

- bundled `tools\iperf3.exe` plus local servers in `config\network-servers.json`
- fallback: `speedtest.exe` or a Speedtest CLI already on `PATH`

Recommended setup for Melbourne:

- `config\network-servers.json` is currently set to `showtime.mav.z9t.me`
- keep the bundled `tools\iperf3.exe`, `cygcrypto-3.dll`, `cygwin1.dll`, and `cygz.dll` together
- run `iperf3` server-side on `showtime.mav.z9t.me` with TCP port `5201` open if you want true throughput tests
- HTTPS on `showtime.mav.z9t.me` is treated as optional in diagnostics; `iperf3` on TCP `5201` is the important throughput requirement
- if you prefer Ookla, add server IDs to `ookla.serverIds` or leave the array empty and let it choose automatically

Why `showtime.mav.z9t.me`:

- keeps network-test traffic separate from the client-assistance app on `mav.z9t.me`
- makes logs, firewall rules, DNS, and future routing easier to understand
- avoids accidentally coupling laptop testing to the client-assistance app hostname

## 3. Pre-Hire Prep

Launcher: `launchers\3-Pre-Hire-Prep.cmd`

What it does:

- scans Desktop and Downloads for large files
- moves loose Desktop and Downloads items into `C:\Users\<user>\Old\<timestamp>\...`
- checks disk free space against thresholds in `config\prep-settings.json`
- checks Microsoft 365 status
- downloads the live MAV logo from `mav.com.au`
- creates a black wallpaper with the logo centered and sets it as the desktop wallpaper

## 4. Baseline Audit

Launcher: `launchers\4-Baseline-Audit.cmd`

What it does:

- reads installed desktop apps from the Windows uninstall registry keys
- compares them against `config\baseline-programs.json`
- reports missing required software
- reports unexpected installed programs that are outside your defined baseline

## Browser Display Tools

Launchers:

- `launchers\7-Desktop-Generator.cmd`
- `launchers\8-Test-Pattern-Generator.cmd`
- `launchers\9-Event-Timer.cmd`
- `launchers\5-LED-Wall-Test-Generator.cmd`

What they do:

- `Desktop Generator`: creates a clean branded source-identification screen with client name, device/location label, MAV logo, optional client logo, and common output presets
- `Test Pattern Generator`: creates general display patterns such as grid/crosshair, safe margins, colour bars, greyscale, focus, and overscan checks
- `Event Timer`: creates a fullscreen countdown-to-time, countdown-duration, or count-up display with overtime support, MAV logo toggle, and optional client logo upload
- `LED Wall Test Generator`: creates a numbered panel map driven by panel count, panel pixel size, and panel physical size, then calculates the total wall resolution and dimensions

## USB Bundle Builder

Script: `scripts\Build-UsbBundle.ps1`

What it does:

- creates `MAV-Tech-Assist-USB.zip` at the project root
- bundles `launchers\`, `scripts\`, `config\`, `docs\`, `tools\`, and `web\`
- skips nesting an old bundle zip inside the new bundle

## Smoke Check

Script: `scripts\Test-Toolkit.ps1`

Recommended release check:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Toolkit.ps1 -StartDashboard -CheckBundle -CheckHostedSite
```

What it covers:

- PowerShell syntax checks
- JSON config checks
- local static page markers
- handover doc markers
- dashboard helper startup and local API checks
- USB bundle contents
- hosted site page and bundle checks

## Suggested extra scripts

These would be strong additions next:

- `9-Battery-Health.cmd`: battery report, cycle count, full-charge capacity vs design capacity
- `10-Peripheral-Check.cmd`: camera, mic, speakers, Bluetooth, USB ports, webcam privacy shutter notes
- `11-Windows-Update-Status.cmd`: pending reboot, paused updates, failed updates, driver update state
- `12-Quick-Handover-Report.cmd`: one-page summary of Microsoft 365 state, disk space, battery, network, and app drift
- `13-Profile-Scrub.cmd`: recent files, temp folders, Teams/Zoom caches, print queue, mapped drives, Wi-Fi profile cleanup
- `14-Hardware-Inventory.cmd`: serial, model, BIOS, RAM, SSD size, warranty tag, Windows build

## Assumptions

- target system is Windows with PowerShell 5.1 or later
- Microsoft 365 Apps are installed locally
- you want Microsoft 365 desktop activation preserved, even if browser web sessions are cleared
- the network test is best when you provide your own `iperf3` endpoints

## Notes

- `prep-settings.json` already points at the current MAV logo URL:
  `https://mav.com.au/wp-content/uploads/2022/09/logo-yw-1.png`
- Microsoft documents that `vnextdiag.ps1` is the supported way to inspect Microsoft 365 Apps activation on current versions of Microsoft 365 Apps:
  <https://learn.microsoft.com/en-us/microsoft-365-apps/licensing-activation/vnextdiag>
- Microsoft also documents the `LicensingNext` registry path and `%localappdata%\Microsoft\Office\Licenses` as signals for the newer activation method:
  <https://learn.microsoft.com/en-us/microsoft-365-apps/licensing-activation/vnextdiag>
