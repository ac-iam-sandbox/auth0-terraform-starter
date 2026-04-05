#!/usr/bin/env python3
"""
Cleans an Auth0 form export for Terraform consumption.

Strips metadata that Terraform does not use and that contains
environment-specific values (like hardcoded vault connection IDs).
Keeps only 'form' and 'flows' — the sections Terraform reads.

Usage:
  python clean-export.py <exported_file.json>
  python clean-export.py <exported_file.json> --output <cleaned_file.json>

Without --output, overwrites the input file in place.

What gets removed:
  - 'version'      Auth0 export format version (metadata, not used by Terraform)
  - 'connections'   Vault connection metadata with env-specific IDs
                    (Terraform injects real IDs via the manifest's conn_refs)

What stays:
  - 'form'          Form definition (nodes, start, ending, style, translations)
  - 'flows'         Flow definitions with #CONN-N# placeholders
"""

import json
import sys
import os

KEEP_KEYS = {"form", "flows"}


def clean(data):
    """Return a new dict with only the keys Terraform consumes."""
    cleaned = {}
    for key in KEEP_KEYS:
        if key in data:
            cleaned[key] = data[key]
    return cleaned


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        sys.exit(0)

    input_path = sys.argv[1]
    output_path = input_path

    if "--output" in sys.argv:
        idx = sys.argv.index("--output")
        if idx + 1 < len(sys.argv):
            output_path = sys.argv[idx + 1]
        else:
            print("Error: --output requires a file path", file=sys.stderr)
            sys.exit(1)

    if not os.path.exists(input_path):
        print(f"Error: file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    removed = [k for k in data if k not in KEEP_KEYS]
    cleaned = clean(data)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(cleaned, f, indent=2, ensure_ascii=False)
        f.write("\n")

    if removed:
        print(f"Cleaned: removed {', '.join(removed)}")
    else:
        print("Already clean: no metadata to remove")

    print(f"Output: {output_path}")


if __name__ == "__main__":
    main()
