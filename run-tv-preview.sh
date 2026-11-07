#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
exec flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8788 \
  --dart-define=MOONFIN_FORCE_TV=true "$@"
