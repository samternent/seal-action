#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

workspace="$tmp_dir/workspace"
bin_dir="$tmp_dir/bin"
mkdir -p "$workspace/dist/assets" "$bin_dir"
workspace="$(cd "$workspace" && pwd -P)"
bin_dir="$(cd "$bin_dir" && pwd -P)"

cat > "$workspace/dist/index.html" <<'EOF'
<!doctype html>
<html><body>seal smoke test</body></html>
EOF

cat > "$workspace/dist/assets/app.js" <<'EOF'
console.log("seal smoke test");
EOF

cat > "$bin_dir/seal" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

command_name="${1:-}"
shift || true

parse_value() {
  local flag="$1"
  shift
  while (($#)); do
    if [[ "$1" == "$flag" ]]; then
      echo "$2"
      return 0
    fi
    shift
  done
  return 1
}

case "$command_name" in
  manifest)
    subcommand="${1:-}"
    shift || true
    if [[ "$subcommand" != "create" ]]; then
      exit 1
    fi
    input_dir="$(parse_value --input "$@")"
    out_file="$(parse_value --out "$@")"
    cat > "$out_file" <<JSON
{"version":"1","type":"seal-manifest","root":"$(basename "$input_dir")","files":{"index.html":"sha256:test"}}
JSON
    ;;
  sign)
    input_file="$(parse_value --input "$@")"
    out_file="$(parse_value --out "$@")"
    cat > "$out_file" <<JSON
{"version":"1","type":"seal-proof","subject":{"path":"$(basename "$input_file")","hash":"sha256:test"},"signer":{"publicKey":"BASE64","keyId":"smoke"},"signature":"signature"}
JSON
    ;;
  public-key)
    if [[ "${1:-}" != "--json" ]]; then
      exit 1
    fi
    cat <<JSON
{"algorithm":"ECDSA-P256-SHA256","publicKey":"BASE64","keyId":"smoke"}
JSON
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "$bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "exec" ]]; then
  echo "expected npm exec" >&2
  exit 1
fi
shift

while (($#)); do
  case "$1" in
    --yes|--package=*)
      shift
      ;;
    --)
      shift
      ;;
    seal)
      shift
      exec seal "$@"
      ;;
    *)
      echo "unexpected npm exec argument: $1" >&2
      exit 1
      ;;
  esac
done

echo "missing seal command" >&2
exit 1
EOF

chmod +x "$bin_dir/seal" "$bin_dir/npm"

run_case() {
  (
    cd "$workspace"
    PATH="$bin_dir:$PATH" \
    GITHUB_OUTPUT="$tmp_dir/github-output.txt" \
    SEAL_PRIVATE_KEY="test-private-key" \
    "$@"
  )
}

export SEAL_ACTION_ASSETS_DIRECTORY="dist"
export SEAL_ACTION_MANIFEST_NAME="dist-manifest.json"
export SEAL_ACTION_PROOF_NAME="proof.json"
export SEAL_ACTION_PUBLIC_KEY_NAME="public-key.json"
export SEAL_ACTION_PACKAGE_NAME="@ternent/seal-cli"
export SEAL_ACTION_PACKAGE_VERSION="latest"
export SEAL_ACTION_CLI_COMMAND=""

: > "$tmp_dir/github-output.txt"
run_case "$repo_root/scripts/run.sh"

test -f "$workspace/dist/dist-manifest.json"
test -f "$workspace/dist/proof.json"
test -f "$workspace/dist/public-key.json"
grep -Fx "manifest-path=$workspace/dist/dist-manifest.json" "$tmp_dir/github-output.txt" >/dev/null
grep -Fx "proof-path=$workspace/dist/proof.json" "$tmp_dir/github-output.txt" >/dev/null
grep -Fx "public-key-path=$workspace/dist/public-key.json" "$tmp_dir/github-output.txt" >/dev/null

export SEAL_ACTION_MANIFEST_NAME="custom-manifest.json"
export SEAL_ACTION_PROOF_NAME="custom-proof.json"
export SEAL_ACTION_PUBLIC_KEY_NAME="custom-public-key.json"
export SEAL_ACTION_CLI_COMMAND="$bin_dir/seal"

: > "$tmp_dir/github-output-override.txt"
(
  cd "$workspace"
  PATH="$bin_dir:$PATH" \
  GITHUB_OUTPUT="$tmp_dir/github-output-override.txt" \
  SEAL_PRIVATE_KEY="test-private-key" \
  "$repo_root/scripts/run.sh"
)

test -f "$workspace/dist/custom-manifest.json"
test -f "$workspace/dist/custom-proof.json"
test -f "$workspace/dist/custom-public-key.json"

if (
  cd "$workspace"
  PATH="$bin_dir:$PATH" \
  GITHUB_OUTPUT="$tmp_dir/github-output-missing-key.txt" \
  SEAL_PRIVATE_KEY="" \
  "$repo_root/scripts/run.sh"
); then
  echo "expected missing-key check to fail" >&2
  exit 1
fi

export SEAL_ACTION_ASSETS_DIRECTORY="missing-dist"
if (
  cd "$workspace"
  PATH="$bin_dir:$PATH" \
  GITHUB_OUTPUT="$tmp_dir/github-output-missing-dir.txt" \
  SEAL_PRIVATE_KEY="test-private-key" \
  "$repo_root/scripts/run.sh"
); then
  echo "expected missing-directory check to fail" >&2
  exit 1
fi

echo "smoke test passed"
