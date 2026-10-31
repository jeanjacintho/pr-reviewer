xml_value() {
    printf '%s' "$1" | perl -pe 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g; s/"/&quot;/g; s/\x27/&apos;/g'
}

# Prints a launchd job. $3 is the schedule or keep-alive part, $4 extra environment, $5 the log name.
launch_plist() {
    local label="$1" arguments="$2" schedule="$3" environment="$4" root_xml path_xml
    root_xml="$(xml_value "$ROOT")"
    path_xml="$(xml_value "$PATH")"
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$arguments</array>
$schedule
<key>RunAtLoad</key><true/>
<key>EnvironmentVariables</key><dict><key>PR_REVIEWER_ROOT</key><string>$root_xml</string><key>PATH</key><string>$path_xml</string>$environment</dict>
<key>StandardOutPath</key><string>$root_xml/state/$5</string>
<key>StandardErrorPath</key><string>$root_xml/state/$5</string>
</dict></plist>
PLIST
}

write_launch_plist() {
    launch_plist com.jeanjacintho.pr-reviewer "<string>/bin/bash</string><string>$(xml_value "$SOURCE_ROOT/poll.sh")</string>" '<key>StartInterval</key><integer>120</integer>' '' launchd.log
}

write_dashboard_plist() {
    local environment=''
    if [ -n "${DASHBOARD_PORT:-}" ]; then environment="<key>DASHBOARD_PORT</key><string>$(xml_value "$DASHBOARD_PORT")</string>"; fi
    launch_plist com.jeanjacintho.pr-reviewer-dashboard "<string>$(xml_value "$NODE_BIN")</string><string>$(xml_value "$SOURCE_ROOT/dashboard/server.js")</string>" '<key>KeepAlive</key><true/>' "$environment" dashboard.log
}

# Reads a plist on stdin, saves it as $1's job file and (re)loads the job.
register_service() {
    local plist="$LAUNCH_AGENTS_DIR/$1.plist"
    cat > "$plist"
    launchctl bootout "gui/$UID/$1" 2>/dev/null || printf 'Launchd bootout failed; continuing installation.\n'
    launchctl bootstrap "gui/$UID" "$plist"
}

install_dashboard() {
    NODE_BIN="$(command -v node || true)"
    if [ -z "$NODE_BIN" ]; then
        printf 'Node not found; the dashboard was not installed.\n'
        return 0
    fi
    write_dashboard_plist | register_service com.jeanjacintho.pr-reviewer-dashboard
    printf 'Dashboard: http://127.0.0.1:%s\n' "${DASHBOARD_PORT:-4777}"
}

install_repos_file() {
    local legacy="$1"
    [ ! -f "$ROOT/repos.json" ] || return 0
    if [ "$legacy" = yes ]; then
        local next="$ROOT/repos.json.next"
        migrate_legacy_config "$ROOT/config.sh" > "$next" || { rm -f "$next"; return 1; }
        mv "$next" "$ROOT/repos.json"
        printf 'Migrated repositories and trusted users from config.sh to repos.json.\n'
    else
        cp "$SOURCE_ROOT/repos.example.json" "$ROOT/repos.json"
    fi
}

valid_port() {
    case "$1" in *[!0-9]* | ??????*) return 1 ;; esac
    [ "$((10#$1))" -ge 1 ] && [ "$((10#$1))" -le 65535 ]
}

install_main() {
    local dependency
    if [ -n "${DASHBOARD_PORT:-}" ] && ! valid_port "$DASHBOARD_PORT"; then
        printf 'DASHBOARD_PORT must be a number from 1 to 65535.\n' >&2
        return 1
    fi
    for dependency in gh jq git codex perl launchctl; do
        command -v "$dependency" >/dev/null || { printf 'Missing dependency: %s\n' "$dependency" >&2; return 1; }
    done
    gh auth status
    codex --version
    jq --version
    mkdir -p "$STATE_DIR" "$WORK_DIR" "$LAUNCH_AGENTS_DIR"
    local legacy=no
    if [ -f "$ROOT/config.sh" ]; then legacy=yes; else cp "$SOURCE_ROOT/config.example.sh" "$ROOT/config.sh"; fi
    install_repos_file "$legacy"
    if [ ! -f "$STATE_DIR/started-at" ]; then date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE_DIR/started-at"; fi
    write_launch_plist | register_service com.jeanjacintho.pr-reviewer
    install_dashboard
    printf 'Installed. Configure repositories, trusted users and models in %s/repos.json.\n' "$ROOT"
}
