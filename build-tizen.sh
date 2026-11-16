#!/usr/bin/env bash
set -euo pipefail

# Local build only: this script never discovers, connects to, or installs on TVs.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
if [[ -f build-tizen.private.env ]]; then
  source build-tizen.private.env
fi
FLUTTER_TIZEN_BIN="${FLUTTER_TIZEN_BIN:-flutter-tizen}"
if ! command -v "$FLUTTER_TIZEN_BIN" >/dev/null 2>&1; then
  printf '%s\n' 'Set FLUTTER_TIZEN_BIN to the flutter-tizen executable.' >&2
  exit 1
fi
args=(build tpk --release --device-profile tv --target-arch arm
  --dart-define=MOONFIN_TIZEN=true --dart-define=MOONFIN_FORCE_TV=true)
if [[ -n "${MOONFIN_TIZEN_SECURITY_PROFILE:-}" ]]; then
  args+=(--security-profile "$MOONFIN_TIZEN_SECURITY_PROFILE")
fi
exec "$FLUTTER_TIZEN_BIN" "${args[@]}" "$@"
