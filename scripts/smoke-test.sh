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
identity_file_path="$workspace/identity.json"

identity_inline='{"format":"ternent-identity","version":"2","algorithm":"Ed25519","publicKey":"inline-public-key","keyId":"inline-key","material":{"kind":"seed","seed":"inline-seed"}}'
identity_file_payload='{"format":"ternent-identity","version":"2","algorithm":"Ed25519","publicKey":"file-public-key","keyId":"file-key","material":{"kind":"seed","seed":"file-seed"}}'

cat > "$workspace/dist/index.html" <<'EOF'
<!doctype html>
<html><body>seal smoke test</body></html>
EOF

cat > "$workspace/dist/assets/app.js" <<'EOF'
console.log("seal smoke test");
EOF

printf '%s\n' "$identity_file_payload" > "$identity_file_path"

cat > "$bin_dir/seal" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

command_name="${1:-}"
shift || true

resolve_identity() {
  if [[ -n "${SEAL_IDENTITY:-}" ]]; then
    printf '%s' "$SEAL_IDENTITY"
    return 0
  fi

  if [[ -n "${SEAL_IDENTITY_FILE:-}" ]]; then
    cat "$SEAL_IDENTITY_FILE"
    return 0
  fi

  echo "Missing SEAL_IDENTITY or SEAL_IDENTITY_FILE environment variable." >&2
  exit 1
}

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
    identity_payload="$(resolve_identity)"
    if [[ -n "${SEAL_STUB_IDENTITY_LOG:-}" ]]; then
      printf 'sign:%s\n' "$identity_payload" >> "$SEAL_STUB_IDENTITY_LOG"
    fi
    input_file="$(parse_value --input "$@")"
    out_file="$(parse_value --out "$@")"
    cat > "$out_file" <<JSON
{"version":"2","type":"seal-proof","algorithm":"Ed25519","createdAt":"2026-03-16T00:00:00.000Z","subject":{"kind":"manifest","path":"$(basename "$input_file")","hash":"sha256:test"},"signer":{"publicKey":"oaLMsjJ4_hS16vgr_PSDTgHLmlbdrwG-2ctm4rolUUk","keyId":"smoke"},"signature":"signature"}
JSON
    ;;
  public-key)
    identity_payload="$(resolve_identity)"
    if [[ -n "${SEAL_STUB_IDENTITY_LOG:-}" ]]; then
      printf 'public-key:%s\n' "$identity_payload" >> "$SEAL_STUB_IDENTITY_LOG"
    fi
    if [[ "${1:-}" != "--json" ]]; then
      exit 1
    fi
    cat <<JSON
{"version":"2","type":"seal-public-key","algorithm":"Ed25519","publicKey":"oaLMsjJ4_hS16vgr_PSDTgHLmlbdrwG-2ctm4rolUUk","keyId":"smoke"}
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

assert_contains() {
  local file="$1"
  local text="$2"
  grep -F "$text" "$file" >/dev/null
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  if grep -F "$text" "$file" >/dev/null; then
    echo "unexpected text '$text' found in $file" >&2
    exit 1
  fi
}

run_action() {
  local output_file="$1"
  shift
  (
    cd "$workspace"
    PATH="$bin_dir:$PATH" \
    GITHUB_OUTPUT="$output_file" \
    env "$@" "$repo_root/scripts/run.sh"
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
run_action "$tmp_dir/github-output.txt" \
  SEAL_IDENTITY="$identity_inline" \
  SEAL_STUB_IDENTITY_LOG="$tmp_dir/identity-inline.log"

test -f "$workspace/dist/dist-manifest.json"
test -f "$workspace/dist/proof.json"
test -f "$workspace/dist/public-key.json"
grep -Fx "manifest-path=$workspace/dist/dist-manifest.json" "$tmp_dir/github-output.txt" >/dev/null
grep -Fx "proof-path=$workspace/dist/proof.json" "$tmp_dir/github-output.txt" >/dev/null
grep -Fx "public-key-path=$workspace/dist/public-key.json" "$tmp_dir/github-output.txt" >/dev/null
assert_contains "$workspace/dist/proof.json" '"version":"2"'
assert_contains "$workspace/dist/proof.json" '"algorithm":"Ed25519"'
assert_contains "$workspace/dist/public-key.json" '"type":"seal-public-key"'
assert_contains "$workspace/dist/public-key.json" '"publicKey":"oaLMsjJ4_hS16vgr_PSDTgHLmlbdrwG-2ctm4rolUUk"'
assert_contains "$tmp_dir/identity-inline.log" "sign:$identity_inline"
assert_contains "$tmp_dir/identity-inline.log" "public-key:$identity_inline"

export SEAL_ACTION_MANIFEST_NAME="custom-manifest.json"
export SEAL_ACTION_PROOF_NAME="custom-proof.json"
export SEAL_ACTION_PUBLIC_KEY_NAME="custom-public-key.json"
export SEAL_ACTION_CLI_COMMAND="$bin_dir/seal"

: > "$tmp_dir/github-output-override.txt"
run_action "$tmp_dir/github-output-override.txt" \
  SEAL_IDENTITY_FILE="$identity_file_path" \
  SEAL_STUB_IDENTITY_LOG="$tmp_dir/identity-file.log"

test -f "$workspace/dist/custom-manifest.json"
test -f "$workspace/dist/custom-proof.json"
test -f "$workspace/dist/custom-public-key.json"
assert_contains "$tmp_dir/identity-file.log" "sign:$identity_file_payload"
assert_contains "$tmp_dir/identity-file.log" "public-key:$identity_file_payload"

: > "$tmp_dir/github-output-precedence.txt"
run_action "$tmp_dir/github-output-precedence.txt" \
  SEAL_IDENTITY="$identity_inline" \
  SEAL_IDENTITY_FILE="$identity_file_path" \
  SEAL_STUB_IDENTITY_LOG="$tmp_dir/identity-precedence.log"

assert_contains "$tmp_dir/identity-precedence.log" "sign:$identity_inline"
assert_contains "$tmp_dir/identity-precedence.log" "public-key:$identity_inline"
assert_not_contains "$tmp_dir/identity-precedence.log" "$identity_file_payload"

if run_action "$tmp_dir/github-output-missing-env.txt" >"$tmp_dir/missing-env.log" 2>&1; then
  echo "expected missing-env check to fail" >&2
  exit 1
fi
assert_contains "$tmp_dir/missing-env.log" "SEAL_IDENTITY or SEAL_IDENTITY_FILE"
assert_not_contains "$tmp_dir/missing-env.log" "SEAL_PRIVATE_KEY must be set"

export SEAL_ACTION_ASSETS_DIRECTORY="missing-dist"
if run_action "$tmp_dir/github-output-missing-dir.txt" \
  SEAL_IDENTITY="$identity_inline" >"$tmp_dir/missing-dir.log" 2>&1; then
  echo "expected missing-directory check to fail" >&2
  exit 1
fi
assert_contains "$tmp_dir/missing-dir.log" "assets-directory 'missing-dist' does not exist or is not a directory"

echo "smoke test passed"
