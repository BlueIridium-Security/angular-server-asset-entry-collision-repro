#!/usr/bin/env bash
set -Eeuo pipefail

repro_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
run_id=${1:-run-$(date -u +%Y%m%dT%H%M%SZ)}

if [[ ! "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "invalid run identifier: $run_id" >&2
  exit 64
fi

evidence_dir="$repro_root/evidence/$run_id"
if [[ -e "$evidence_dir" ]]; then
  echo "evidence directory already exists: $evidence_dir" >&2
  exit 73
fi

mkdir -p "$evidence_dir"
export EVIDENCE_DIR="$evidence_dir"

cd "$repro_root"
docker compose build --pull validator
docker compose run --rm validator

test -f "$evidence_dir/protocol-complete.txt"
echo
echo "Validation evidence: $evidence_dir"
column -t -s $'\t' "$evidence_dir/summary.tsv" 2>/dev/null || cat "$evidence_dir/summary.tsv"
