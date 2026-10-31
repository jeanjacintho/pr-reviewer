#!/bin/bash
set -euo pipefail
LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
status=0
for label in com.jeanjacintho.pr-reviewer com.jeanjacintho.pr-reviewer-dashboard; do
    service="gui/$UID/$label"
    launchctl bootout "$service" 2>/dev/null || printf 'Launchd bootout failed; checking service status.\n' >&2
    rm -f "$LAUNCH_AGENTS_DIR/$label.plist"
    if launchctl print "$service" >/dev/null 2>&1; then
        printf 'Saved plist removed, but the service may still be running. Retry: launchctl bootout %s\n' "$service" >&2
        status=1
    fi
done
[ "$status" -eq 0 ] || exit 1
printf 'Uninstalled. Configuration, lessons, cached repositories and state were preserved.\n'
