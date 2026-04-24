# Mobile and Browser Test Plan

## Recommendation

Use three test modes:

- Windows full tests: keep using the USB launcher plus local PowerShell dashboard.
- iOS and Android quick tests: use a hosted mobile web app/PWA at `showtime.mav.z9t.me`.
- Offline/no-internet fallback: open `web\index.html` from the USB as a browser menu and local test page launcher.
- Native companion app: only add this later if browser-only tests are not enough.

This keeps the common workflow painless. Staff open the dashboard on Windows from the USB, or scan a QR code on a phone. The web app auto-detects iOS, Android, Windows, or desktop browser and only shows tests that can actually run on that device.

The split is user-agent based at the browser-site level: mobile/tablet tests are shown first on mobile user agents, and laptop/desktop tests are shown first on laptop/desktop user agents. Tests for the other class are moved into a greyed-out area.

## Browser Sandbox Escape

Browsers intentionally cannot run arbitrary scripts, inspect installed software, enumerate local files, or open raw network sockets. The least painful escape hatches are:

- Best for Windows: local helper launched from USB. This is the current `0-Dashboard.cmd` approach. The browser UI talks to `127.0.0.1`; PowerShell does the real work.
- Best polished PC app later: Tauri or Electron wrapper. This gives one app icon, bundled scripts, a browser-like UI, and easier status streaming, but it adds build/signing/update work.
- Possible but clunky: custom URL protocol such as `mavtoolkit://run/network`. It still needs a local install or registry setup and is awkward for live progress.
- Avoid unless necessary: browser extension plus native messaging. It is browser-specific and adds more support burden than the USB helper.
- Do not use: ActiveX, Java applets, old IE-only tricks, or disabling browser security.

Security rules for the local helper:

- bind only to `127.0.0.1`
- require a per-launch token
- expose only named task IDs from `dashboard-tasks.json`
- never accept arbitrary shell commands from the page
- write logs to `reports\dashboard-runs\...`
- run non-admin by default; only launch as admin when a task truly needs admin rights
- optionally auto-exit after 10-20 minutes idle

## Mobile Auto-Detection

The mobile web app can detect platform and capabilities:

- use `navigator.userAgentData` where available
- fall back to `navigator.userAgent`
- detect microphone support with `navigator.mediaDevices.getUserMedia`
- detect audio output support with `AudioContext`
- detect camera support with `getUserMedia`
- detect PWA/install mode with `matchMedia('(display-mode: standalone)')`
- show iOS-safe, Android-safe, and desktop-only tests separately

Mobile browser limits to expect:

- iOS and Android browsers cannot run PowerShell, batch files, or local scripts.
- Mobile browsers cannot reliably run raw TCP/UDP port scans.
- Mobile browsers cannot query the configured DNS server directly.
- iOS Safari does not expose detailed Wi-Fi metadata such as SSID/BSSID.
- Browser upload/download tests can be very useful, but they test HTTPS/WebRTC paths rather than every app-specific media path.

## Phone Tests

### Wi-Fi Speed and Streaming Readiness

Web-only version:

- download test from `https://showtime.mav.z9t.me/speed/download`
- upload test to `https://showtime.mav.z9t.me/speed/upload`
- latency/jitter estimate using repeated small HTTPS requests
- WebRTC test to a TURN/STUN endpoint to check real-time media viability
- optional HLS/DASH sample stream playback from `showtime.mav.z9t.me`

Better native-app version:

- raw TCP and UDP tests
- iperf-style throughput
- more accurate jitter and packet loss
- Wi-Fi SSID/BSSID/channel where OS permissions allow

### Zoom and Teams Contactability

Web-only version:

- HTTPS fetch checks to known public endpoints
- WebRTC connectivity check for UDP/TCP relay behavior
- DNS/timing checks for key hostnames
- show "likely OK" rather than pretending to prove the native app will connect

Relevant current guidance:

- Zoom documents web/client access over TCP 80/443, UDP 443, and meetings/webinars on TCP 443/8801/8802 plus UDP 3478/3479/8801-8810.
- Microsoft documents Teams media optimization on UDP 3478-3481 and Teams service access on TCP 80/443 plus UDP 443 for listed Microsoft 365 endpoints.

Sources:

- Zoom firewall/proxy settings: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060548
- Microsoft Teams network preparation: https://learn.microsoft.com/en-ca/MicrosoftTeams/prepare-network
- Microsoft 365 URLs and IP ranges: https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges

### DNS Health

Web-only version:

- time cache-busted HTTPS requests to several hostnames
- compare first-hit and repeat-hit timings
- check whether expected hostnames resolve indirectly by successfully connecting
- report "DNS or connection path is slow" rather than claiming exact DNS server latency

Native-app version:

- direct DNS queries to chosen resolvers
- DNS-over-HTTPS and normal DNS comparison
- resolver IP, timeout, NXDOMAIN, and captive portal checks

### White Noise Generator

Web-only version:

- generate pink noise, white noise, brown noise, and sine tones in Web Audio
- calibrated-ish volume warning and mute safety
- one-tap 30-second playback for room masking tests
- optional left/right channel checks

This is a good browser test. It does not need native access.

### Standing Wave Finder

Web-only version:

- ask for microphone permission
- run a slow sine sweep, for example 40 Hz to 300 Hz for room modes and 300 Hz to 8 kHz for harsh reflections
- read microphone level with `AnalyserNode`
- plot detected peaks by frequency
- export rough EQ suggestions such as "cut 125 Hz by 3 dB, Q 4"

Limitations:

- phone microphones, AGC, echo cancellation, and speaker response make this approximate
- the app should tell the user it finds room/device resonances, not lab-grade acoustic measurements
- headphones/Bluetooth should be avoided during this test

Best workflow:

- use phone speaker for a quick check
- for better results, let the user connect the phone to the room PA or play the sweep from the actual presentation laptop while the phone listens

### Test Pattern Generator

Web-only version:

- full-screen display pattern with MAV logo
- client name field
- optional client logo upload
- device/location label, such as `Main PPT laptop 1`, `Presenter Notes`, or `Sponsor Loop Laptop`
- selectable resolution labels, such as 1920x1080, 3840x2160, ultrawide, custom
- patterns: grid, safe margins, color bars, grayscale ramp, focus/sharpness, overscan border, text legibility, countdown clock

This is an excellent browser test. It works on phones, tablets, and laptops, and it helps confirm the correct source is routed to the correct display.

Implementation note:

- logo upload can stay local in the browser using `URL.createObjectURL`
- no client logo needs to be sent to the server unless the user chooses to save a report
- use the Fullscreen API where supported, with a manual fallback for iOS

### LED Wall Config Test Generator

Web-only version:

- inherits the test pattern generator fields for client name, device/location label, output resolution, MAV branding, fullscreen mode, and optional client logo upload
- adds panel pixel width and height fields, for example 192x108, 256x128, 384x216, or custom cabinet/receiving-card sizes
- maps the output canvas into a numbered coloured grid where each tile represents one LED panel or logical processor panel
- shows panel number, row/column, panel pixel size, and top-left pixel coordinate
- supports different numbering orders such as left-to-right rows, top-to-bottom columns, and snake rows
- highlights partial edge panels when the output resolution is not an exact multiple of the panel pixel size
- helps troubleshoot swapped panels, wrong processor mapping, scaling errors, missing tiles, and "which source is feeding which wall" confusion

USB implementation:

- standalone file: `web\led-wall-test-generator.html`
- launcher: `launchers\5-LED-Wall-Test-Generator.cmd`

Future hosted/PWA version:

- add as `/display/led-wall`
- optionally save presets per venue, wall size, processor, or recurring event
- optionally export a PNG test image at the exact output resolution
- optionally add QR/report capture so techs can document the wall config used on site

## Suggested PWA Pages

- `/` device detection and test menu
- `/network` Wi-Fi, internet, speed, streaming, Zoom/Teams checks
- `/audio/noise` white/pink/brown noise generator
- `/audio/standing-waves` sweep, microphone graph, and EQ suggestions
- `/display/pattern` branded test pattern generator
- `/display/led-wall` numbered LED wall panel map and config checker
- `/report` summary with pass/warn/fail and QR/share/export

## Server Endpoints Needed

On `showtime.mav.z9t.me`, add:

- `GET /healthz`
- `GET /speed/download?size=25mb`
- `POST /speed/upload`
- `GET /stream/test.m3u8`
- WebSocket echo endpoint for latency checks
- optional TURN/STUN endpoint for WebRTC testing
- optional `iperf3` service on TCP `5201` for PC/native throughput tests

## Build Order

1. Keep the USB dashboard for Windows full tests.
2. Add a QR code/button in the Windows dashboard: "Open phone tests".
3. Keep `web\index.html` as the offline mirror/menu for no-internet venues.
4. Build the hosted PWA with Network, White Noise, Test Pattern, and LED Wall first.
5. Add Standing Wave Finder after the audio UI is stable.
6. Only build native iOS/Android helpers if the browser version cannot answer a real operational question.
