#!/usr/bin/env bash
# =============================================================================
# tokenize-export.sh — Convert Auth0 Dashboard exports to tokenized files
# =============================================================================
#
# When you export a Form from the Auth0 Dashboard, it contains real resource
# IDs (af_xxx for flows, ac_xxx for vault connections). These IDs are
# environment-specific and must be replaced with placeholder tokens before
# the JSON is committed to git.
#
# This script:
#   1. Reads an exported form JSON
#   2. Finds all flow IDs (af_*) and vault connection IDs (ac_*)
#   3. Replaces them with #FLOW-1#, #FLOW-2#, #CONN-1#, etc.
#   4. Outputs a token map so you know which token = which original ID
#   5. Splits the export into separate form and flow files
#
# Usage:
#   ./scripts/tokenize-export.sh <exported-form.json> <output-dir>
#
# Example:
#   ./scripts/tokenize-export.sh ~/Downloads/progressive-profiling-export.json \
#       environments/dev/forms/
#
# Output:
#   environments/dev/forms/progressive-profiling.form.json    (tokenized form)
#   environments/dev/forms/progressive-profiling.flow-1.json  (flow #FLOW-1#)
#   environments/dev/forms/progressive-profiling.flow-2.json  (flow #FLOW-2#)
#   environments/dev/forms/progressive-profiling.tokens.json  (token map)
#
# After running, update your forms.json to map tokens to Terraform resources.
# =============================================================================
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <exported-form.json> <output-dir>"
  echo ""
  echo "Example:"
  echo "  $0 ~/Downloads/progressive-profiling-export.json environments/dev/forms/"
  exit 1
fi

INPUT_FILE="$1"
OUTPUT_DIR="$2"
BASENAME=$(basename "$INPUT_FILE" .json | sed 's/_/-/g' | tr '[:upper:]' '[:lower:]')

if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required. Install with: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Processing: $INPUT_FILE"
echo "Output dir: $OUTPUT_DIR"
echo ""

# Read the full export
EXPORT=$(cat "$INPUT_FILE")

# Extract flow IDs and build token map
FLOW_COUNTER=0
CONN_COUNTER=0
TOKEN_MAP="{}"
TOKENIZED="$EXPORT"

# Find all unique flow IDs (af_*) referenced in the form nodes
FLOW_IDS=$(echo "$EXPORT" | jq -r '
  .. | objects | select(has("flow_id")) | .flow_id // empty
' 2>/dev/null | sort -u)

for flow_id in $FLOW_IDS; do
  if [[ "$flow_id" == af_* ]]; then
    FLOW_COUNTER=$((FLOW_COUNTER + 1))
    TOKEN="#FLOW-${FLOW_COUNTER}#"
    echo "  Flow: $flow_id → $TOKEN"
    TOKENIZED=$(echo "$TOKENIZED" | sed "s|$flow_id|$TOKEN|g")
    TOKEN_MAP=$(echo "$TOKEN_MAP" | jq --arg token "$TOKEN" --arg id "$flow_id" '. + {($token): $id}')
  fi
done

# Find all unique vault connection IDs (ac_*) referenced in flows
CONN_IDS=$(echo "$EXPORT" | jq -r '
  .. | objects | select(has("connection_id")) | .connection_id // empty
' 2>/dev/null | sort -u)

for conn_id in $CONN_IDS; do
  if [[ "$conn_id" == ac_* ]]; then
    CONN_COUNTER=$((CONN_COUNTER + 1))
    TOKEN="#CONN-${CONN_COUNTER}#"
    echo "  Conn: $conn_id → $TOKEN"
    TOKENIZED=$(echo "$TOKENIZED" | sed "s|$conn_id|$TOKEN|g")
    TOKEN_MAP=$(echo "$TOKEN_MAP" | jq --arg token "$TOKEN" --arg id "$conn_id" '. + {($token): $id}')
  fi
done

# Extract and write the form (without flows/connections metadata)
echo "$TOKENIZED" | jq '{
  name: .name,
  languages: .languages,
  translations: .translations,
  nodes: .nodes,
  start: .start,
  ending: .ending,
  style: .style
}' > "$OUTPUT_DIR/${BASENAME}.form.json"
echo ""
echo "  Wrote: ${BASENAME}.form.json"

# Extract and write each flow separately
FLOW_COUNTER=0
for flow_id in $FLOW_IDS; do
  if [[ "$flow_id" == af_* ]]; then
    FLOW_COUNTER=$((FLOW_COUNTER + 1))
    # Get the flow from the original export, then tokenize connection IDs
    FLOW_JSON=$(echo "$EXPORT" | jq --arg id "$flow_id" '
      if .flows then .flows[$id]
      elif .actions then .
      else empty end
    ' 2>/dev/null)

    if [ -n "$FLOW_JSON" ] && [ "$FLOW_JSON" != "null" ]; then
      # Apply connection tokenization to the flow
      FLOW_TOKENIZED="$FLOW_JSON"
      for conn_id in $CONN_IDS; do
        if [[ "$conn_id" == ac_* ]]; then
          CONN_TOKEN=$(echo "$TOKEN_MAP" | jq -r --arg id "$conn_id" 'to_entries[] | select(.value == $id) | .key')
          FLOW_TOKENIZED=$(echo "$FLOW_TOKENIZED" | sed "s|$conn_id|$CONN_TOKEN|g")
        fi
      done
      echo "$FLOW_TOKENIZED" | jq '.' > "$OUTPUT_DIR/${BASENAME}.flow-${FLOW_COUNTER}.json"
      echo "  Wrote: ${BASENAME}.flow-${FLOW_COUNTER}.json"
    fi
  fi
done

# Write token map
echo "$TOKEN_MAP" | jq '.' > "$OUTPUT_DIR/${BASENAME}.tokens.json"
echo "  Wrote: ${BASENAME}.tokens.json"

echo ""
echo "Done! Next steps:"
echo "  1. Review the tokenized files in $OUTPUT_DIR"
echo "  2. Add flow entries to your environment's flows.json"
echo "  3. Map #CONN-N# tokens to vault connection Terraform resource names in flows.json"
echo "  4. Run: terragrunt run --all -- plan"
