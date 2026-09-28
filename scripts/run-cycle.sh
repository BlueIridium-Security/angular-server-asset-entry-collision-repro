#!/usr/bin/env bash
set -Eeuo pipefail

evidence_dir=${1:-/evidence}
repro_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
app_dir="$repro_root/app"
archive_dir=$(mktemp -d)

mkdir -p "$evidence_dir/logs" "$evidence_dir/outputs"
exec > >(tee "$evidence_dir/run.log") 2>&1

cleanup() {
  rm -rf -- "$archive_dir"
}
trap cleanup EXIT

echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "platform=$(uname -a)"
echo "node=$(node --version)"
echo "npm=$(npm --version)"

node <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const forbidden = ['scripts', 'main', 'exports', 'bin', 'imports'];
for (const state of ['clean', 'attack']) {
  const manifestPath = path.join('/repro/packages', state, 'package.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  for (const key of forbidden) {
    if (Object.hasOwn(manifest, key)) {
      throw new Error(`${state} dependency manifest unexpectedly contains ${key}`);
    }
  }
}
NODE

clean_archive_name=$(cd "$repro_root/packages/clean" && npm pack --silent --pack-destination "$archive_dir")
attack_archive_name=$(cd "$repro_root/packages/attack" && npm pack --silent --pack-destination "$archive_dir")
clean_archive="$archive_dir/$clean_archive_name"
attack_archive="$archive_dir/$attack_archive_name"

{
  echo "archive sha256"
  sha256sum "$clean_archive" "$attack_archive"
  echo "fixed input sha256 before"
  sha256sum \
    "$app_dir/angular.json" \
    "$app_dir/src/main.server.ts" \
    "$repro_root/packages/clean/assets/data.json" \
    "$repro_root/packages/attack/assets/data.json" \
    "$repro_root/packages/attack/assets/main.js"
} | tee "$evidence_dir/input-hashes-before.txt"

printf 'state\tpackage_version\toutput_bytes\toutput_sha256\tstartup\tmarker\n' > "$evidence_dir/summary.tsv"

declare -a clean_hashes=()
declare -a attack_hashes=()

run_state() {
  local label=$1
  local kind=$2
  local archive=$3
  local marker="$app_dir/independent-validation-marker.txt"
  local output="$app_dir/dist/server/main.js"
  local output_copy="$evidence_dir/outputs/${label}-main.js"
  local build_log="$evidence_dir/logs/${label}-build.log"
  local startup_log="$evidence_dir/logs/${label}-startup.log"
  local package_version
  local output_bytes
  local output_hash
  local startup_result
  local marker_result

  rm -f -- "$marker"

  (
    cd "$app_dir"
    npm install \
      --ignore-scripts \
      --no-audit \
      --no-fund \
      --package-lock=false \
      --no-save \
      --offline \
      --omit=optional \
      --legacy-peer-deps \
      "$archive"
  )

  package_version=$(node -p "require('$app_dir/node_modules/@independent/server-data-assets/package.json').version")
  echo "state=$label package_version=$package_version"
  find "$app_dir/node_modules/@independent/server-data-assets" -type f -print | sort

  (
    cd "$app_dir"
    node node_modules/@angular/cli/bin/ng.js run repro:server:production
  ) 2>&1 | tee "$build_log"

  test -f "$output"
  cp "$output" "$output_copy"
  output_bytes=$(wc -c < "$output" | tr -d ' ')
  output_hash=$(sha256sum "$output" | awk '{print $1}')

  echo "state=$label output_bytes=$output_bytes output_sha256=$output_hash"

  if [[ "$kind" == "attack" ]]; then
    cmp "$app_dir/node_modules/@independent/server-data-assets/assets/main.js" "$output"
    echo "state=$label copied_asset_matches_output=true"
  elif grep -q 'INDEPENDENT DEPENDENCY ASSET EXECUTED' "$output"; then
    echo "clean output unexpectedly contains the attack payload" >&2
    return 1
  fi

  (
    cd "$app_dir"
    node dist/server/main.js
  ) 2>&1 | tee "$startup_log"

  if [[ "$kind" == "attack" ]]; then
    grep -q 'INDEPENDENT DEPENDENCY ASSET EXECUTED' "$startup_log"
    test -f "$marker"
    cp "$marker" "$evidence_dir/outputs/${label}-marker.txt"
    startup_result=dependency-asset-executed
    marker_result=present
    attack_hashes+=("$output_hash")
  else
    grep -q 'GENUINE SERVER BUNDLE EXECUTED' "$startup_log"
    test ! -f "$marker"
    startup_result=genuine-bundle-executed
    marker_result=absent
    clean_hashes+=("$output_hash")
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$label" "$package_version" "$output_bytes" "$output_hash" \
    "$startup_result" "$marker_result" >> "$evidence_dir/summary.tsv"
}

run_state clean-1 clean "$clean_archive"
run_state attack-1 attack "$attack_archive"
run_state clean-2 clean "$clean_archive"
run_state attack-2 attack "$attack_archive"

test "${clean_hashes[0]}" = "${clean_hashes[1]}"
test "${attack_hashes[0]}" = "${attack_hashes[1]}"
test "${clean_hashes[0]}" != "${attack_hashes[0]}"

{
  echo "fixed input sha256 after"
  sha256sum \
    "$app_dir/angular.json" \
    "$app_dir/src/main.server.ts" \
    "$repro_root/packages/clean/assets/data.json" \
    "$repro_root/packages/attack/assets/data.json" \
    "$repro_root/packages/attack/assets/main.js"
  echo "installed versions"
  node -e "console.log(JSON.stringify({cli:require('$app_dir/node_modules/@angular/cli/package.json').version,builder:require('$app_dir/node_modules/@angular-devkit/build-angular/package.json').version,core:require('$app_dir/node_modules/@angular/core/package.json').version,typescript:require('$app_dir/node_modules/typescript/package.json').version},null,2))"
} | tee "$evidence_dir/input-hashes-after.txt"

touch "$evidence_dir/protocol-complete.txt"
echo "PROTOCOL_COMPLETE"
