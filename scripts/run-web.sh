#!/usr/bin/env bash
# Build the WebGL version and serve it at http://localhost:8080
set -euo pipefail
cd "$(dirname "$0")/.."
haxe build-js.hxml
echo "Serving on http://localhost:8080  (Ctrl+C to stop)"
( sleep 1; command -v open >/dev/null && open http://localhost:8080 ) &
cd bin && python3 -m http.server 8080
