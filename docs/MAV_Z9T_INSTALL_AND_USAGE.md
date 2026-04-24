# MAV.Z9T.ME Install And Usage

This guide documents the current MAV-hosted deployment.

## Current live endpoints

- hosted portal: `https://showtime.mav.z9t.me`
- guest-assistance app: `https://mav.z9t.me`
- throughput test endpoint: `showtime.mav.z9t.me:5201`

Keep `showtime.mav.z9t.me` separate from `mav.z9t.me` so the toolkit does not conflict with the guest-assistance app.

## Current server model

- static toolkit files are served from `/srv/showtime`
- browser handbook pages are served from `/srv/showtime/docs`
- `iperf3` runs on the VPS and listens on TCP `5201`
- Caddy handles HTTPS for `showtime.mav.z9t.me`

## Updating the hosted copy

1. update the local project files
2. rebuild the USB bundle
3. run the smoke check
4. copy the hosted files to the VPS
5. verify the public URLs

## Files to copy to `/srv/showtime`

Copy these files into the site root:

- `web/index.html`
- `web/desktop-generator.html`
- `web/test-pattern-generator.html`
- `web/event-timer.html`
- `web/led-wall-test-generator.html`
- `web/network-helper.html`
- `MAV-Tech-Assist-USB.zip`

Copy these files into `/srv/showtime/docs`:

- `docs/daily-use.html`
- `docs/troubleshooting.html`
- `docs/deployment-and-qa.html`
- `docs/handbook.css`

## Example deployment commands

From a local machine with SSH access, replace `showtime-vps` with your SSH alias or host:

```bash
SHOWTIME_TARGET="<ssh-user>@showtime-vps"
scp web/index.html "${SHOWTIME_TARGET}:/srv/showtime/"
scp web/desktop-generator.html "${SHOWTIME_TARGET}:/srv/showtime/"
scp web/test-pattern-generator.html "${SHOWTIME_TARGET}:/srv/showtime/"
scp web/event-timer.html "${SHOWTIME_TARGET}:/srv/showtime/"
scp web/led-wall-test-generator.html "${SHOWTIME_TARGET}:/srv/showtime/"
scp web/network-helper.html "${SHOWTIME_TARGET}:/srv/showtime/"
scp MAV-Tech-Assist-USB.zip "${SHOWTIME_TARGET}:/srv/showtime/"
scp docs/daily-use.html docs/troubleshooting.html docs/deployment-and-qa.html docs/handbook.css "${SHOWTIME_TARGET}:/srv/showtime/docs/"
```

## Example Caddy intent

The `showtime` site should point to the static toolkit root, not the guest-assistance backend.

Conceptually it should behave like:

```caddy
showtime.mav.z9t.me {
    root * /srv/showtime
    file_server
}
```

If `showtime.mav.z9t.me` ever starts showing the guest-assistance app again, the Caddy site target is the first place to check.

## Operator usage

Use the hosted portal when:

- internet is available
- you only need browser-safe tools
- you want the easiest path for phones and tablets

Use the USB fallback when:

- internet is missing or unstable
- you need the same browser tools from disk
- you want a backup copy on-site

Use the dashboard helper when:

- you need Windows cleanup tasks
- you need baseline audit or declientify
- you need local-helper-backed network or monitoring features

## MAV-specific checks after an update

1. open `https://showtime.mav.z9t.me`
2. confirm the heading says `MAV Tech Assist`
3. confirm the home page shows `Run Online (here)`
4. confirm the USB download works
5. confirm `/docs/daily-use.html` and `/docs/troubleshooting.html` load
6. confirm `showtime.mav.z9t.me:5201` is reachable for the Windows network diagnostics

## Related docs

- `docs/DEPLOYMENT_AND_QA_GUIDE.md`
- `docs/DAILY_USE_GUIDE.md`
- `docs/TROUBLESHOOTING_GUIDE.md`
