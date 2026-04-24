# Deployment And QA Guide

This is the release and handover checklist for MAV Tech Assist.

## What counts as a good release

A good release means:

- the hosted site opens
- the USB zip downloads
- the offline USB pages open
- the dashboard helper still starts
- the main browser tools load without console errors

## Release order

1. Update the local project files
2. Rebuild the USB zip
3. Run the smoke checks
4. Copy the updated `web\` files, `docs\` files, and USB zip to the hosted site
5. Re-check the live site in a browser

## Build the USB zip

Run:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-UsbBundle.ps1
```

Expected result:

- `MAV-Tech-Assist-USB.zip` is created at the project root

## Recommended smoke check

Run:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Toolkit.ps1 -StartDashboard -CheckBundle -CheckHostedSite
```

What this should prove:

- PowerShell files parse cleanly
- JSON config files are valid
- key static pages exist
- the dashboard helper starts and serves the expected pages
- the local helper APIs answer
- the USB zip exists and contains the required pages, launchers, scripts, docs, and config
- the hosted site answers on the key URLs

## Manual browser QA

Check these pages on the live site:

- `/`
- `/desktop-generator.html`
- `/test-pattern-generator.html`
- `/event-timer.html`
- `/led-wall-test-generator.html`
- `/network-helper.html`
- `/MAV-Tech-Assist-USB.zip`

What to look for:

- the home page heading says `MAV Tech Assist`
- hosted mode shows `Run Online (here)`
- the USB card still shows the zip download
- event timer starts and can be reset
- browser pages load without obvious layout breaks
- no console errors appear during page load

## Manual USB QA

From the USB copy:

1. open `launchers\0-Offline-Browser-Portal.cmd`
2. confirm the badge says `USB offline site`
3. open `Desktop generator`
4. open `Test pattern generator`
5. open `Event timer`
6. open `LED wall test`

Expected result:

- each page opens from the USB with no internet
- the USB card says `Or from USB (here)`
- `Clear saved settings` works in the event timer

## Deployment notes for the hosted copy

The hosted site currently serves static files from `/srv/showtime` on the VPS.

At minimum, update:

- `index.html`
- all required `web\*.html` pages
- the `docs\` files that the site links to
- `MAV-Tech-Assist-USB.zip`

## Known operational limits

- Windows-only tasks still need the local helper or direct launchers
- the local network helper uses best-effort device fingerprints
- throughput testing depends on the bundled `tools\iperf3.exe` files and a healthy remote server
- browser tools can verify a lot, but they do not replace Windows-side audits

## Handover note

If handing this off to a non-developer, hand over:

- the current USB stick or the current USB zip
- this deployment and QA guide
- the daily-use guide
- the troubleshooting guide
- the live hosted URL
