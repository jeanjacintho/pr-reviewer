# Resolve implementation files independently of the configurable state root.
SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$SOURCE_ROOT/lib/common.sh"
LIB_ROOT="$SOURCE_ROOT"

load_libs() {
    local library
    for library in "$@"; do . "$LIB_ROOT/lib/$library.sh"; done
}
