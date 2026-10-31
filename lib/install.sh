xml_value() {
    printf '%s' "$1" | perl -pe 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g; s/"/&quot;/g; s/\x27/&apos;/g'
}

write_launch_plist() {
    local root_xml path_xml script_xml
    script_xml="$(xml_value "$SOURCE_ROOT/poll.sh")"
    root_xml="$(xml_value "$ROOT")"
    path_xml="$(xml_value "$PATH")"
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.jeanjacintho.pr-reviewer</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$script_xml</string></array>
<key>StartInterval</key><integer>120</integer>
<key>RunAtLoad</key><true/>
<key>EnvironmentVariables</key><dict><key>PR_REVIEWER_ROOT</key><string>$root_xml</string><key>PATH</key><string>$path_xml</string></dict>
<key>StandardOutPath</key><string>$root_xml/state/launchd.log</string>
<key>StandardErrorPath</key><string>$root_xml/state/launchd.log</string>
</dict></plist>
PLIST
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

install_main() {
    local dependency
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
    local plist="$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer.plist"
    write_launch_plist > "$plist"
    launchctl bootout "gui/$UID/com.jeanjacintho.pr-reviewer" 2>/dev/null || printf 'Launchd bootout failed; continuing installation.\n'
    launchctl bootstrap "gui/$UID" "$plist"
    printf 'Installed. Configure repositories, trusted users and models in %s/repos.json.\n' "$ROOT"
}
