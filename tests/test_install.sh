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
