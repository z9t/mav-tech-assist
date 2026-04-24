# Daily Use Guide

This guide is for day-to-day operators, not developers.

## Pick the right starting point

Use `Run Online` when:

- internet is working
- you only need browser-safe tools
- you want the simplest path on a phone, tablet, or laptop

Use `Or from USB` when:

- there is no internet
- you need the offline browser pages
- you want a backup copy of the toolkit on a stick

Use `launchers\0-Dashboard.cmd` when:

- you need Windows-only checks
- you want the declientify, cleanup, network, or baseline scripts
- you want progress bars and pass/fail feedback instead of raw PowerShell

## Normal daily flow

1. Try the hosted site first: `https://showtime.mav.z9t.me`
2. If internet is poor or missing, open `launchers\0-Offline-Browser-Portal.cmd`
3. If you need laptop cleanup or deeper Windows checks, open `launchers\0-Dashboard.cmd`
4. If you only need a browser display tool, open the specific generator directly from the portal or the matching launcher

## What each browser tool is for

`Desktop generator`

- shows a clean branded source-identification screen
- good for presenter notes, sponsor loop laptops, confidence screens, and comfort monitors

`Test pattern generator`

- good for general screen alignment, focus, overscan, safe margins, and colour checks

`Event timer`

- good for doors, session starts, rehearsals, cue points, and stage timing
- `Reset` stops the timer
- `Clear saved settings` removes the last show name, timer label, and other saved values from that browser

`LED wall test`

- good for wall mapping, checking panel order, confirming cabinet pixel size, and confirming total wall size

`Local network helper`

- good for scanning a local AV network and watching red/green device status
- use `Dry run first` before changing anything on the Windows laptop

## What success looks like

Hosted site:

- the page opens quickly
- the top badge says `Hosted site`
- browser tools open without blank pages or console errors

USB offline portal:

- the page opens even with no internet
- the top badge says `USB offline site`
- browser tools still open from the USB

Dashboard:

- the top badge says `USB helper connected` or the dashboard page opens on `127.0.0.1`
- buttons show progress and a final success or fail state
- reports are written into the toolkit `reports\` folder

## Before you hand a laptop over

1. Run the right browser tool or Windows script for the task
2. Check that the result actually looks correct on screen
3. If you used a Windows script, open the report if the dashboard shows a warning or fail
4. If something looks wrong, stop and use the troubleshooting guide instead of guessing

## If you are unsure

- do not keep clicking random tools
- use the smallest tool that answers the question
- if a page or script looks wrong, take a screenshot and note which launcher or page you used
- escalate if the same action fails twice
