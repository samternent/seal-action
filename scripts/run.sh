#!/usr/bin/env bash

set -euo pipefail

assets_dir_input="${SEAL_ACTION_ASSETS_DIRECTORY:-}"
manifest_name="${SEAL_ACTION_MANIFEST_NAME:-dist-manifest.json}"
proof_name="${SEAL_ACTION_PROOF_NAME:-proof.json}"
public_key_name="${SEAL_ACTION_PUBLIC_KEY_NAME:-public-key.json}"
package_name="${SEAL_ACTION_PACKAGE_NAME:-@ternent/seal-cli}"
package_version="${SEAL_ACTION_PACKAGE_VERSION:-latest}"
cli_command="${SEAL_ACTION_CLI_COMMAND:-}"
working_root="$(pwd -P)"

if [[ -z "$assets_dir_input" ]]; then
  echo "::error::assets-directory is required." >&2
  exit 1
fi

if [[ -z "${SEAL_PRIVATE_KEY:-}" ]]; then
  echo "::error::SEAL_PRIVATE_KEY must be set." >&2
  exit 1
fi

if [[ "$assets_dir_input" = /* ]]; then
  assets_dir="${assets_dir_input%/}"
else
  assets_dir="${working_root}/${assets_dir_input}"
  assets_dir="${assets_dir%/}"
fi

if [[ ! -d "$assets_dir" ]]; then
  echo "::error::assets-directory '$assets_dir_input' does not exist or is not a directory." >&2
  exit 1
fi

manifest_path="${assets_dir}/${manifest_name}"
proof_path="${assets_dir}/${proof_name}"
public_key_path="${assets_dir}/${public_key_name}"

run_packaged_cli() {
  npm exec --yes "--package=${package_name}@${package_version}" seal "$@"
}

run_cli_override() {
  local escaped_command=()
  local arg

  for arg in "$@"; do
    printf -v arg "%q" "$arg"
    escaped_command+=("$arg")
  done

  bash -lc "set -euo pipefail; ${cli_command} ${escaped_command[*]}"
}

if [[ -z "$cli_command" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "::error::npm is required when cli-command is empty." >&2
    exit 1
  fi

  run_packaged_cli manifest create --input "$assets_dir" --out "$manifest_path" --quiet
  run_packaged_cli sign --input "$manifest_path" --out "$proof_path" --quiet
  run_packaged_cli public-key --json > "$public_key_path"
else
  run_cli_override manifest create --input "$assets_dir" --out "$manifest_path" --quiet
  run_cli_override sign --input "$manifest_path" --out "$proof_path" --quiet
  run_cli_override public-key --json > "$public_key_path"
fi

if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
  echo "::error::GITHUB_OUTPUT must be set by GitHub Actions." >&2
  exit 1
fi

{
  echo "manifest-path=$manifest_path"
  echo "proof-path=$proof_path"
  echo "public-key-path=$public_key_path"
} >> "$GITHUB_OUTPUT"
