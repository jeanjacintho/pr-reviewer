#!/bin/bash
set -Eeuo pipefail
. "$(dirname "$0")/lib/bootstrap.sh"
load_libs state github decide validate workspace prompt command codex lifecycle review
review_main "$@"
