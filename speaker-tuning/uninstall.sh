#!/usr/bin/env bash
# Remove the speaker tuning filter-chain installed by install.sh.
set -euo pipefail
cd "$(dirname "$0")"
. ./common.sh

[ -d "$CONVERTER/.git" ] || die "converter not found in $CONVERTER; nothing was installed by install.sh"
run_converter --uninstall --no-activate "$@"
restart_audio
