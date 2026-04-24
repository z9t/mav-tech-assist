# MAV Tech Assist

MAV Tech Assist is a hybrid hosted-and-USB toolkit for preparing, declientifying, testing, and presenting from hire laptops and show devices.

It is designed to feel like the same product in three modes:

- hosted site at `https://showtime.mav.z9t.me`
- offline browser portal from the USB stick
- local Windows helper dashboard for tasks that cannot run in a browser sandbox

## What it includes

- Windows cleanup tools for after-hire and before-hire workflows
- Microsoft 365-aware declientify and prep checks
- network diagnostics and throughput testing with bundled Windows `iperf3`
- browser display tools such as desktop generator, test pattern generator, LED wall map, and event timer
- local network helper for basic AV subnet discovery and up/down monitoring
- USB bundle builder and smoke-test script for repeatable releases

## Quick start

### Operators

1. Use the hosted site first: `https://showtime.mav.z9t.me`
2. If internet is unavailable, open `launchers\0-Offline-Browser-Portal.cmd`
3. If you need Windows-only actions, open `launchers\0-Dashboard.cmd`

### Maintainers

1. Build the USB bundle:

   ```powershell
   powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-UsbBundle.ps1
   ```

2. Run the smoke check:

   ```powershell
   powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Toolkit.ps1 -StartDashboard -CheckBundle -CheckHostedSite
   ```

3. Deploy the hosted files or refresh the USB stick.

## Runtime requirements

- Windows PowerShell 5.1 or later for the `.cmd` launchers and PowerShell scripts
- a modern browser for the hosted and offline HTML tools
- optional static hosting with HTTPS for online mode
- optional `iperf3` server on TCP `5201` for true throughput testing

`requirements.txt` is intentionally a no-op because the core toolkit does not require Python packages.

## Repository layout

- `launchers/`: Windows entry points for operators
- `scripts/`: PowerShell automation and helper server
- `config/`: baseline, prep, dashboard, and network settings
- `tools/`: bundled Windows helper executables for network testing
- `web/`: browser tools and hosted portal pages
- `docs/`: handover, deployment, troubleshooting, and install documentation

## Installation paths

- Independent deployment: see [docs/SELF_HOSTED_INSTALL.md](docs/SELF_HOSTED_INSTALL.md)
- Current `mav.z9t.me` deployment: see [docs/MAV_Z9T_INSTALL_AND_USAGE.md](docs/MAV_Z9T_INSTALL_AND_USAGE.md)
- Daily use: see [docs/DAILY_USE_GUIDE.md](docs/DAILY_USE_GUIDE.md)
- Troubleshooting: see [docs/TROUBLESHOOTING_GUIDE.md](docs/TROUBLESHOOTING_GUIDE.md)
- Deployment and QA: see [docs/DEPLOYMENT_AND_QA_GUIDE.md](docs/DEPLOYMENT_AND_QA_GUIDE.md)

## Notes

- The live hosted site is intentionally separate from the guest-assistance app on `mav.z9t.me`.
- Windows-only actions are only available through the local dashboard helper or direct launchers.
- The repo does not track generated JSON run reports or the generated USB zip; build them locally when needed.

## Public Repo Notes

- The public hostnames in this repo, such as `showtime.mav.z9t.me` and `mav.z9t.me`, are intentional deployment references.
- Do not commit passwords, SSH keys, operator-specific hosts, client data, or machine-local paths into this repository.
- Generated bundles, runtime reports, and local-only secret files are kept out of Git via `.gitignore`.
