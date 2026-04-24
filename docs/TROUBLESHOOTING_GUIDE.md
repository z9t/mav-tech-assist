# Troubleshooting Guide

This guide is for operators who need a fast decision path.

## Hosted site will not open

Try this:

1. Open `https://showtime.mav.z9t.me` again
2. If it still fails, switch to `launchers\0-Offline-Browser-Portal.cmd`
3. If the USB copy works, the issue is probably internet or hosting, not the browser tools themselves

Escalate when:

- the hosted site is down for more than a few minutes
- the USB copy also fails to open

## Browser page opens but buttons do nothing

Check:

- whether you are on the hosted site, USB offline site, or local helper site
- whether the tool is meant to be browser-only or Windows-only

Remember:

- browser pages can open generators, timers, and display tools directly
- Windows script actions only work through `launchers\0-Dashboard.cmd`

If a Windows button is greyed out or missing:

1. open `launchers\0-Dashboard.cmd`
2. wait for the local page to load
3. try the task again from that dashboard

## Download USB zip is missing or fails

Check:

- that you are on the hosted site, not the USB copy
- that the file name shown is `MAV-Tech-Assist-USB.zip`

If download fails:

1. refresh the page once
2. try the direct file link again
3. if it still fails, use the current USB copy you already have and escalate for a hosted update

## Event timer shows the wrong old show name

This usually means the browser kept the last saved timer values.

Fix:

1. open `Event timer`
2. click `Clear saved settings`
3. enter the current show details again

## Timer is red immediately

This is usually not a bug.

Check:

- whether the timer is in countdown mode and the target time is already passed
- whether the duration is only a few seconds or minutes
- whether the red state is expected because you are already in overtime

Fix:

1. click `Reset`
2. set the correct target time or duration
3. click `Start` again

## Dashboard opens but scripts fail

Do this:

1. read the fail or warning text in the dashboard
2. open the matching JSON report in `reports\`
3. check whether the problem is a missing tool, low disk space, missing permissions, or network reachability

Common reasons:

- the bundled `iperf3.exe` or its companion DLLs are missing from `tools\`
- the hosted test server cannot be reached
- the laptop needs admin rights for a setup change
- disk space is too low for cleanup or archiving

## Network helper shows strange device names

This is expected sometimes.

The helper fingerprints devices by best-effort clues only. Trust the up/down state more than the guessed device type.

What to do:

1. use discovery to find likely devices
2. rename important watch-list entries manually if needed
3. rely on the IP and status more than the guessed category

## When to stop and escalate

Stop and escalate when:

- the same tool fails twice in a row
- the hosted site and USB copy both fail
- a Windows setup step asks for admin rights and you do not expect it
- a script says a required executable is missing
- a script says the bundled `iperf3` files are incomplete
- a report shows unexpected app drift, repeated low disk warnings, or unresolved network reachability issues
