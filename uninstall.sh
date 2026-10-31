#!/bin/bash
set -euo pipefail
LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
service="gui/$UID/com.jeanjacintho.pr-reviewer"
launchctl bootout "$service" 2>/dev/null || printf 'Launchd bootout failed; checking service status.\n' >&2
rm -f "$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer.plist"
if launchctl print "$service" >/dev/null 2>&1; then
    printf 'Saved plist removed, but the service may still be running. Retry: launchctl bootout %s\n' "$service" >&2
    exit 1
fi
printf 'Uninstalled. Configuration, lessons, cached repositories and state were preserved.\n'
