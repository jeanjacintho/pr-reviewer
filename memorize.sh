#!/bin/bash
set -Eeuo pipefail
. "$(dirname "$0")/lib/bootstrap.sh"
load_libs github validate prompt command codex lifecycle memorize
memorize_main "$@"
