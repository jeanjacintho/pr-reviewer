#!/bin/bash
set -Eeuo pipefail
. "$(dirname "$0")/lib/bootstrap.sh"
load_libs state github repos decide validate workspace prompt command codex claude engine stages deep lifecycle review
review_main "$@"
