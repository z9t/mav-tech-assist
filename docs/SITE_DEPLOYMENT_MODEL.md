# Site Deployment Model

Goal: the toolkit should feel like the same browser app everywhere.

## Modes

- Hosted mode: open `https://showtime.mav.z9t.me`.
- USB offline mode: open `web\index.html` from the USB stick.
- USB helper mode: run `launchers\0-Dashboard.cmd`, which serves the same `web\index.html` locally and enables Windows script buttons.

## Folder Roles

- `web\`: static browser site. This should be deployable to `showtime.mav.z9t.me` as-is.
- `web\index.html`: main menu and user-agent-based routing for mobile/tablet versus laptop/desktop tests.
- `web\desktop-generator.html`: branded source-identification screen for normal laptop/display outputs.
- `web\test-pattern-generator.html`: general display test-pattern page for non-LED outputs.
- `web\event-timer.html`: hosted and offline event timer page for countdowns and count-up displays.
- `web\led-wall-test-generator.html`: local and hosted LED wall test page.
- `MAV-Tech-Assist-USB.zip`: downloadable hosted bundle for building or refreshing a USB stick.
- `scripts\`: local Windows PowerShell scripts that cannot run inside a normal browser sandbox.
- `launchers\`: Windows `.cmd` entry points for USB use.
- `config\`: JSON task, network, baseline, and prep settings.
- `tools\`: bundled helper executables for throughput testing plus any optional extras such as `speedtest.exe`.

## User-Agent Split

The browser site should sort tests by detected user agent:

- Mobile/tablet tests: phone Wi-Fi checks, audio tests, microphone tests, quick display/test-pattern checks, and hosted network checks.
- Laptop/desktop tests: browser display tools plus Windows cleanup, Microsoft 365, baseline, and deeper network checks.

Tests for the other device class should move into a greyed-out "Not for this device" area.

## Browser Sandbox Rule

Browser-safe tests must run directly in hosted and offline modes. These include display patterns, LED wall grids, logo uploads, audio generation, microphone-based approximate tests, and server-backed speed checks.

Windows-only tests must not pretend to run from the browser alone. They should be enabled only when the USB helper is present. The helper exposes named task IDs only; it does not accept arbitrary shell commands.

## Recommended Flow

1. Try hosted site first: `https://showtime.mav.z9t.me`.
2. If there is no internet, open `web\index.html` from the USB.
3. If laptop Windows scripts are needed, run `launchers\0-Dashboard.cmd`.
4. If only a local browser display tool is needed, open the relevant local HTML page directly.
