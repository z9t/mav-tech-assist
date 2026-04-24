# Self-Hosted Install

This guide is for a clean install that does not depend on `z9t.me`.

## What you need

- one Windows machine for the USB bundle and launcher scripts
- one hostname for the hosted browser portal, such as `showtime.example.com`
- optional Linux VPS if you want real `iperf3` throughput testing
- HTTPS for the public site if operators will use the hosted portal directly

## Recommended model

Use the toolkit in the same three-mode pattern as the MAV deployment:

1. hosted site for the normal online path
2. USB offline portal as the fallback
3. local Windows dashboard helper for tasks that cannot run in the browser

## 1. Clone the repo

```bash
git clone https://github.com/z9t/mav-tech-assist.git
cd mav-tech-assist
```

## 2. Choose your network-test hostname

Pick the hostname that the Windows network test should call.

Example:

- hosted site: `showtime.example.com`
- `iperf3` host: `showtime.example.com`

If you prefer, the static site and the `iperf3` endpoint can be different hosts.

## 3. Update network config

Edit `config/network-servers.json` and replace the default `showtime.mav.z9t.me` values with your own hostname and ports.

At minimum review:

- `iperf3.servers[].host`
- `diagnostics.host`
- `diagnostics.iperfPort`
- `diagnostics.httpsPort`

## 4. Build the USB bundle

On Windows:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-UsbBundle.ps1
```

Expected result:

- `MAV-Tech-Assist-USB.zip` is created in the project root

## 5. Deploy the hosted files

The hosted site expects this layout:

- site root: copies of `web\*.html`
- site root: `MAV-Tech-Assist-USB.zip`
- `docs/`: the browser-friendly handbook pages from `docs\*.html` plus `docs\handbook.css`

Example copy list:

- `web/index.html`
- `web/desktop-generator.html`
- `web/test-pattern-generator.html`
- `web/event-timer.html`
- `web/led-wall-test-generator.html`
- `web/network-helper.html`
- `docs/daily-use.html`
- `docs/troubleshooting.html`
- `docs/deployment-and-qa.html`
- `docs/handbook.css`
- `MAV-Tech-Assist-USB.zip`

## 6. Example Caddy setup

```caddy
showtime.example.com {
    root * /srv/mav-tech-assist
    file_server
}
```

Example filesystem layout:

- `/srv/mav-tech-assist/index.html`
- `/srv/mav-tech-assist/desktop-generator.html`
- `/srv/mav-tech-assist/test-pattern-generator.html`
- `/srv/mav-tech-assist/event-timer.html`
- `/srv/mav-tech-assist/led-wall-test-generator.html`
- `/srv/mav-tech-assist/network-helper.html`
- `/srv/mav-tech-assist/MAV-Tech-Assist-USB.zip`
- `/srv/mav-tech-assist/docs/daily-use.html`
- `/srv/mav-tech-assist/docs/troubleshooting.html`
- `/srv/mav-tech-assist/docs/deployment-and-qa.html`
- `/srv/mav-tech-assist/docs/handbook.css`

## 7. Optional `iperf3` server setup

On Ubuntu or Debian:

```bash
sudo apt update
sudo apt install -y iperf3
sudo tee /etc/systemd/system/iperf3.service >/dev/null <<'EOF'
[Unit]
Description=iperf3 server
After=network.target

[Service]
ExecStart=/usr/bin/iperf3 -s
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now iperf3
sudo ufw allow 5201/tcp
```

## 8. Validate the install

On Windows:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Toolkit.ps1 -StartDashboard -CheckBundle
```

Then manually confirm:

1. the hosted portal opens
2. the USB zip downloads
3. the offline portal opens from disk
4. the local dashboard starts from `launchers\0-Dashboard.cmd`
5. `Invoke-NetworkDiagnostics.ps1` can resolve and reach your chosen host

## Important limits

- hosted and offline browser pages cannot run Windows cleanup tasks directly
- Windows script buttons only work through the local helper dashboard
- the local network helper is monitoring-oriented, not full device control
