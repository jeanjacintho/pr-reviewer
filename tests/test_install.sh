install_setup() {
    INSTALL_SOURCE="$PR_REVIEWER_ROOT"
    export PR_REVIEWER_ROOT="$(mktmp)/with spaces & chars"
    mkdir -p "$PR_REVIEWER_ROOT"
    export PATH="$INSTALL_SOURCE/tests/fakes:$PATH"
    export PR_REVIEWER_PATH="$PATH"
    export LAUNCH_AGENTS_DIR="$(mktmp)"
    export FAKE_LOG="$PR_REVIEWER_ROOT/fake.log"
    : > "$FAKE_LOG"
}

test_install_idempotent_and_uninstall() {
    install_setup
    bash "$INSTALL_SOURCE/install.sh" > "$PR_REVIEWER_ROOT/install.stdout" || fail install
    assert_not_contains "$(cat "$PR_REVIEWER_ROOT/install.stdout")" 'bootout failed'
    local plist="$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer.plist" started
    [ -s "$plist" ] || fail plist
    started="$(cat "$PR_REVIEWER_ROOT/state/started-at")" || fail watermark
    printf '%s' "$started" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || fail watermark_format
    assert_contains "$(cat "$plist")" '<integer>120</integer>'
    assert_contains "$(cat "$plist")" 'with spaces &amp; chars/state/launchd.log'
    assert_contains "$(cat "$plist")" "$INSTALL_SOURCE/poll.sh"
    assert_contains "$(cat "$plist")" '<key>PR_REVIEWER_ROOT</key>'
    assert_contains "$(cat "$plist")" "$INSTALL_SOURCE/tests/fakes"
    assert_contains "$(cat "$FAKE_LOG")" 'launchctl bootstrap'
    started=2026-01-01T00:00:00Z
    printf '%s\n' "$started" > "$PR_REVIEWER_ROOT/state/started-at"
    printf '\n# Preserve user settings\n' >> "$PR_REVIEWER_ROOT/config.sh"
    bash "$INSTALL_SOURCE/install.sh" || fail reinstall
    assert_eq "$started" "$(cat "$PR_REVIEWER_ROOT/state/started-at")"
    assert_contains "$(cat "$PR_REVIEWER_ROOT/config.sh")" 'Preserve user settings'
    : > "$FAKE_LOG"
    bash "$INSTALL_SOURCE/uninstall.sh" > "$PR_REVIEWER_ROOT/uninstall.stdout" 2>&1 || fail uninstall
    assert_not_contains "$(cat "$PR_REVIEWER_ROOT/uninstall.stdout")" 'bootout failed'
    assert_contains "$(cat "$PR_REVIEWER_ROOT/uninstall.stdout")" 'Uninstalled.'
    assert_contains "$(cat "$FAKE_LOG")" 'launchctl bootout'
    [ ! -e "$plist" ] || fail left_plist
    assert_eq "$started" "$(cat "$PR_REVIEWER_ROOT/state/started-at")"
}

test_install_explains_missing_dependency() {
    install_setup
    local bin="$(mktmp)" output="$PR_REVIEWER_ROOT/install-error"
    ln -s /usr/bin/dirname "$bin/dirname"
    if PR_REVIEWER_PATH="$bin" PATH="$bin" /bin/bash "$INSTALL_SOURCE/install.sh" > "$output" 2>&1; then fail missing_dependency; fi
    assert_contains "$(cat "$output")" 'Missing dependency: gh'
}

test_install_continues_and_uninstall_reports_bootout_failure() {
    install_setup
    export FAKE_BOOTOUT_EXIT=1
    bash "$INSTALL_SOURCE/install.sh" > "$PR_REVIEWER_ROOT/install.stdout" || fail install
    assert_contains "$(cat "$PR_REVIEWER_ROOT/install.stdout")" 'Launchd bootout failed; continuing installation.'
    assert_contains "$(cat "$FAKE_LOG")" 'launchctl bootstrap'
    if FAKE_PRINT_EXIT=0 bash "$INSTALL_SOURCE/uninstall.sh" > "$PR_REVIEWER_ROOT/uninstall.stdout" 2>&1; then fail could_not_stop; fi
    assert_contains "$(cat "$PR_REVIEWER_ROOT/uninstall.stdout")" 'service may still be running'
    assert_not_contains "$(cat "$PR_REVIEWER_ROOT/uninstall.stdout")" 'Uninstalled.'
    [ ! -e "$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer.plist" ] || fail plist
}

test_uninstall_succeeds_when_service_already_absent() {
    install_setup
    FAKE_BOOTOUT_EXIT=1 FAKE_PRINT_EXIT=1 bash "$INSTALL_SOURCE/uninstall.sh" > "$PR_REVIEWER_ROOT/uninstall.stdout" 2>&1 || fail already_absent
    assert_contains "$(cat "$PR_REVIEWER_ROOT/uninstall.stdout")" 'Uninstalled.'
    assert_contains "$(cat "$FAKE_LOG")" 'launchctl print'
}

test_install_migrates_legacy_config_once() {
    install_setup
    printf 'REPOS=(o/r)\nTRUSTED_USERS=(alice)\n' > "$PR_REVIEWER_ROOT/config.sh"
    bash "$INSTALL_SOURCE/install.sh" > /dev/null || fail install
    assert_eq 'o/r' "$(jq -r '.repos[0].repo' "$PR_REVIEWER_ROOT/repos.json")"
    assert_eq 'alice' "$(jq -r '.repos[0].trusted_users[0]' "$PR_REVIEWER_ROOT/repos.json")"
    printf '{"repos":[{"repo":"o/edited"}]}\n' > "$PR_REVIEWER_ROOT/repos.json"
    bash "$INSTALL_SOURCE/install.sh" > /dev/null || fail reinstall
    assert_eq 'o/edited' "$(jq -r '.repos[0].repo' "$PR_REVIEWER_ROOT/repos.json")"
}

test_install_fresh_starts_from_the_example() {
    install_setup
    bash "$INSTALL_SOURCE/install.sh" > "$PR_REVIEWER_ROOT/install.stdout" || fail install
    assert_eq "$(jq -S . "$INSTALL_SOURCE/repos.example.json")" "$(jq -S . "$PR_REVIEWER_ROOT/repos.json")"
    assert_contains "$(cat "$PR_REVIEWER_ROOT/install.stdout")" 'repos.json'
}

test_install_failed_migration_leaves_no_repos_file() {
    install_setup
    printf 'REPOS=(\n' > "$PR_REVIEWER_ROOT/config.sh"
    if bash "$INSTALL_SOURCE/install.sh" > /dev/null 2>&1; then fail broken_config_installed; fi
    [ ! -e "$PR_REVIEWER_ROOT/repos.json" ] || fail partial_repos_json
    assert_eq '' "$(ls -A "$PR_REVIEWER_ROOT" | grep 'repos' || true)"
}

test_install_registers_the_dashboard_service() {
    install_setup
    export DASHBOARD_PORT=4888
    bash "$INSTALL_SOURCE/install.sh" > "$PR_REVIEWER_ROOT/install.stdout" || fail install
    local plist="$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer-dashboard.plist"
    [ -s "$plist" ] || fail dashboard_plist
    assert_contains "$(cat "$plist")" '<key>Label</key><string>com.jeanjacintho.pr-reviewer-dashboard</string>'
    assert_contains "$(cat "$plist")" "<string>$(command -v node)</string>"
    assert_contains "$(cat "$plist")" "$INSTALL_SOURCE/dashboard/server.js"
    assert_contains "$(cat "$plist")" '<key>KeepAlive</key><true/>'
    assert_not_contains "$(cat "$plist")" 'StartInterval'
    assert_contains "$(cat "$plist")" '<key>PR_REVIEWER_ROOT</key>'
    assert_contains "$(cat "$plist")" '<key>DASHBOARD_PORT</key><string>4888</string>'
    assert_contains "$(cat "$plist")" 'with spaces &amp; chars/state/dashboard.log'
    assert_contains "$(cat "$FAKE_LOG")" 'launchctl bootstrap gui/'"$UID"' '"$plist"
    assert_contains "$(cat "$PR_REVIEWER_ROOT/install.stdout")" 'http://127.0.0.1:4888'
    assert_not_contains "$(cat "$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer.plist")" 'DASHBOARD_PORT'
}

test_install_without_node_still_installs_the_bot() {
    install_setup
    unset DASHBOARD_PORT
    PR_REVIEWER_PATH="$INSTALL_SOURCE/tests/fakes:/usr/bin:/bin" bash "$INSTALL_SOURCE/install.sh" > "$PR_REVIEWER_ROOT/install.stdout" || fail install
    [ -s "$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer.plist" ] || fail bot_plist
    [ ! -e "$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer-dashboard.plist" ] || fail dashboard_plist
    assert_contains "$(cat "$PR_REVIEWER_ROOT/install.stdout")" 'Node not found; the dashboard was not installed.'
}

test_uninstall_removes_both_services() {
    install_setup
    bash "$INSTALL_SOURCE/install.sh" > /dev/null || fail install
    : > "$FAKE_LOG"
    bash "$INSTALL_SOURCE/uninstall.sh" > "$PR_REVIEWER_ROOT/uninstall.stdout" 2>&1 || fail uninstall
    assert_contains "$(cat "$FAKE_LOG")" 'launchctl bootout gui/'"$UID"'/com.jeanjacintho.pr-reviewer-dashboard'
    assert_contains "$(cat "$FAKE_LOG")" 'launchctl bootout gui/'"$UID"'/com.jeanjacintho.pr-reviewer'
    [ ! -e "$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer-dashboard.plist" ] || fail dashboard_plist
    [ ! -e "$LAUNCH_AGENTS_DIR/com.jeanjacintho.pr-reviewer.plist" ] || fail bot_plist
}

test_uninstall_reports_a_dashboard_that_keeps_running() {
    install_setup
    bash "$INSTALL_SOURCE/install.sh" > /dev/null || fail install
    # Only the dashboard stays loaded.
    printf '#!/bin/bash\nprintf "launchctl %%s\\n" "$*" >> "$FAKE_LOG"\ncase "$*" in "print "*dashboard) exit 0 ;; "print "*) exit 1 ;; esac\n' > "$PR_REVIEWER_ROOT/launchctl"
    chmod +x "$PR_REVIEWER_ROOT/launchctl"
    if PATH="$PR_REVIEWER_ROOT:$PATH" bash "$INSTALL_SOURCE/uninstall.sh" > "$PR_REVIEWER_ROOT/uninstall.stdout" 2>&1; then fail should_fail; fi
    assert_contains "$(cat "$PR_REVIEWER_ROOT/uninstall.stdout")" 'pr-reviewer-dashboard'
    assert_not_contains "$(cat "$PR_REVIEWER_ROOT/uninstall.stdout")" 'Uninstalled.'
}

test_install_rejects_an_unusable_dashboard_port() {
    install_setup
    local port
    for port in abc 1a 0 00 65536 123456 99999999999999999999; do
        if DASHBOARD_PORT=$port bash "$INSTALL_SOURCE/install.sh" > "$PR_REVIEWER_ROOT/install.stdout" 2>&1; then fail "accepted $port"; fi
        assert_contains "$(cat "$PR_REVIEWER_ROOT/install.stdout")" 'DASHBOARD_PORT must be a number from 1 to 65535.'
    done
    assert_eq '' "$(cat "$FAKE_LOG")"
    for port in 1 0080 65535; do
        DASHBOARD_PORT=$port bash "$INSTALL_SOURCE/install.sh" > /dev/null || fail "rejected $port"
    done
}
