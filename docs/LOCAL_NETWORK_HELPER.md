# Local Network Helper

This page is the browser front-end for quick event-LAN checks.

Open it from:

- `launchers\6-Local-Network-Helper.cmd`
- or `launchers\0-Dashboard.cmd`, then click `Local network helper`

## What it does

- asks for a show / room name, subnet, and monitor interval
- stores a watch list of important devices locally in the browser
- can run an optional dry-run or real setup pass on the current Windows laptop
- can scan the subnet for likely devices
- keeps a red/green status table running for the devices you care about

## What the laptop setup can do

The setup pass is local to the current Windows laptop only.

It can optionally:

- enable local OpenSSH Server
- enable network discovery firewall/service prerequisites
- enable Windows file-sharing prerequisites
- optionally move the active network profile toward `Private`

It does not:

- sign into other devices
- create credentials on cameras, projectors, or sound desks
- publish a specific SMB share for a chosen folder
- take remote control of third-party devices

## Discovery and monitor logic

The helper looks for:

- active local IPv4 adapters
- a requested CIDR range, or the first active adapter's suggested subnet if left blank
- quick ping responses
- a small set of common management/service ports

Current fingerprints are only best-effort, but they can help flag likely:

- PTZ cameras
- projectors / displays
- sound desks
- Windows PCs
- NAS / file boxes
- printers
- generic web-managed AV endpoints

## Permission notes

- opening the page does not require admin
- discovery and watch-table polling run as the signed-in Windows user
- setup steps that change firewall rules, services, network profile, or OpenSSH need admin rights
- `Dry run first` is enabled by default so you can see what would happen before changing Windows settings

## Good workflow

1. Open the helper from the USB dashboard.
2. Leave `Dry run first` enabled and test the laptop setup once.
3. Scan the subnet.
4. Add the discovered devices you actually care about into the watch list.
5. Start monitoring during setup, rehearsal, or pack-down.

## Future upgrades

Reasonable next steps later:

- better vendor fingerprints from MAC OUI lookups
- saved per-venue watch-list presets
- richer AV-specific port checks
- optional report export for show paperwork
