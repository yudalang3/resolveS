#!/bin/bash
# A wrapper script that calls count_sam_unique.sh by default.
# For primary alignment mode, use count_sam_primary.sh directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/count_sam_unique.sh" "$@"
