#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib/bootstrap.sh"
load_libs install migrate
LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PATH="${PR_REVIEWER_PATH:-/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin}"
export PATH
install_main
