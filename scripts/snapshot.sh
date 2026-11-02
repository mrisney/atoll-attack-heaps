#!/usr/bin/env bash
# Thin wrapper: ./scripts/snapshot.sh --style=inkmap --walk
exec node "$(dirname "$0")/snapshot.mjs" "$@"
