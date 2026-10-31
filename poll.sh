#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/lib/bootstrap.sh"
load_libs state github repos poll
poll_main
