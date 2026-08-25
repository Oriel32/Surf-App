#!/usr/bin/env bash
# Run SurfCore's Swift toolchain from WSL against this repo.
#
#   ./scripts/wsl-swift.sh test                  # unit suite (hermetic, fixtures)
#   ./scripts/wsl-swift.sh build
#   ./scripts/wsl-swift.sh run smoke hadera      # LIVE smoke test, hits real APIs
#
# Requires the userspace toolchain described in claude.md ("Building the backend
# on Windows"). Nothing here needs sudo.
set -uo pipefail

SWIFT_HOME="${SWIFT_HOME:-$HOME/swift}"
LOCAL_DEPS="${LOCAL_DEPS:-$HOME/localdeps}"

if [ ! -x "$SWIFT_HOME/usr/bin/swift" ]; then
  echo "No Swift toolchain at $SWIFT_HOME/usr/bin/swift" >&2
  echo "See claude.md -> 'Building the backend on Windows (no Mac required)'" >&2
  exit 1
fi

export PATH="$SWIFT_HOME/usr/bin:$PATH"
export LD_LIBRARY_PATH="$LOCAL_DEPS/usr/lib/x86_64-linux-gnu:$LOCAL_DEPS/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

# Resolve the package relative to this script, so the repo can live anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$SCRIPT_DIR/../SurfCore"

# Build artifacts MUST live on ext4. Left on the /mnt/c 9p mount this goes from
# an 8-second build to an unusable one.
SCRATCH="${SWIFT_SCRATCH:-$HOME/build/surfcore}"
mkdir -p "$SCRATCH"

# Flags must sit between the subcommand and its arguments, otherwise
# `swift run smoke <args> --package-path ...` hands the flags to the program.
SUBCOMMAND="${1:-build}"
shift || true
exec swift "$SUBCOMMAND" --package-path "$PKG" --scratch-path "$SCRATCH" "$@"
