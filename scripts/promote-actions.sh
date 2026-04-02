#!/usr/bin/env bash
# =============================================================================
# promote-actions.sh — Copy compiled action JS to target environment
# =============================================================================
# Usage:
#   ./scripts/promote-actions.sh <environment>
#   ./scripts/promote-actions.sh dev        # copies actions/dist/*.js → environments/dev/actions/
#   ./scripts/promote-actions.sh all        # copies to all environments
#
# This is the manual promotion step. Run after 'cd actions && npm run build'.
# Only the target environment gets the new code.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$ROOT_DIR/actions/dist"

if [ ! -d "$DIST_DIR" ] || [ -z "$(ls -A "$DIST_DIR"/*.js 2>/dev/null)" ]; then
  echo "ERROR: No compiled actions in actions/dist/. Run 'cd actions && npm run build' first."
  exit 1
fi

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "Usage: $0 <environment|all>"
  echo "  environments: dev, qa, val, prod, all"
  exit 1
fi

promote_to() {
  local env="$1"
  local env_dir="$ROOT_DIR/environments/$env/actions"
  mkdir -p "$env_dir"
  cp "$DIST_DIR"/*.js "$env_dir/"
  echo "  ✓ $env ($(ls "$env_dir"/*.js | wc -l | tr -d ' ') files)"
}

echo "Promoting compiled actions from actions/dist/..."

if [ "$TARGET" = "all" ]; then
  for env in dev qa val prod; do
    promote_to "$env"
  done
else
  if [ ! -d "$ROOT_DIR/environments/$TARGET" ]; then
    echo "ERROR: Environment '$TARGET' not found"
    exit 1
  fi
  promote_to "$TARGET"
fi

echo ""
echo "Done. Commit the updated files and create a PR."
