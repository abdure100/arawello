#!/usr/bin/env bash
# Create openclaw repo under abdure100 and push (requires: gh auth login first)
set -e
cd "$(dirname "$0")/.."
gh repo create openclaw --public --description "OpenClaw gateway and tools" --source=. --remote=github --push
echo "Done: https://github.com/abdure100/openclaw"
