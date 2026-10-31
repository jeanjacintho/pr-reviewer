# Shared configuration and process boundaries. Bash 3.2 compatible.
ROOT="${PR_REVIEWER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CMD_PREFIX="${CMD_PREFIX:-jeanjacintho}"
REVIEW_TIMEOUT_SECS="${REVIEW_TIMEOUT_SECS:-1200}"
TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-900}"
CODEX_MODEL="${CODEX_MODEL:-}"
if [ -f "${PR_REVIEWER_CONFIG:-$ROOT/config.sh}" ]; then
    . "${PR_REVIEWER_CONFIG:-$ROOT/config.sh}"
fi
STATE_DIR="$ROOT/state"
WORK_DIR="$ROOT/work"
MARKER="<!-- ${CMD_PREFIX}-reviewer -->"

log() {
    mkdir -p "$STATE_DIR"
    if [ -f "$STATE_DIR/poll.log" ]; then
        [ "$(wc -c < "$STATE_DIR/poll.log")" -le 1048576 ] || mv "$STATE_DIR/poll.log" "$STATE_DIR/poll.log.1"
    fi
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$STATE_DIR/poll.log"
}

run_with_timeout() {
    perl -MPOSIX=setpgid -e '
        my $seconds = shift;
        my $pid = fork(); defined $pid or die "fork: $!";
        if (!$pid) { setpgid(0,0); exec @ARGV; exit 127; }
        setpgid($pid,$pid);
        $SIG{ALRM} = sub { kill "TERM", -$pid; select undef,undef,undef,0.1;
            kill "KILL", -$pid; waitpid($pid,0); exit 124; };
        $SIG{TERM} = $SIG{INT} = $SIG{ALRM};
        alarm $seconds;
        waitpid($pid,0);
        my $status = $?; alarm 0;
        exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);
    ' "$@"
}
