# Seal Action

Seal Action is a publishable GitHub Marketplace action for generating Seal artifacts for a pre-built static site directory.

It creates:

- a manifest describing the signed assets
- a Seal v2 proof JSON signed with your exported Seal identity
- a Seal v2 public key JSON artifact for offline verification

The action is intentionally narrow. Your workflow is still responsible for checking out the repo, setting up Node.js, and building the static directory you want to sign.

## Prerequisites

- A checked-out repository via `actions/checkout`
- Node.js on the runner via `actions/setup-node`
- A built static asset directory, such as `dist`
- A Seal v2 identity JSON available in the workflow environment via `SEAL_IDENTITY` or `SEAL_IDENTITY_FILE`

## Quick Start

```yaml
name: Sign static site

on:
  workflow_dispatch:

jobs:
  sign:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Build site
        run: npm ci && npm run build

      - name: Generate Seal artifacts
        uses: <owner>/seal-action@v2
        env:
          SEAL_IDENTITY: ${{ secrets.SEAL_IDENTITY }}
        with:
          assets-directory: dist
```

By default the action runs:

```bash
npm exec --yes --package=@ternent/seal-cli@latest -- seal
```

## Advanced Usage

If you already have `seal` available in the workspace, you can bypass npm installation and invoke a trusted command directly with `cli-command`.

```yaml
- name: Generate Seal artifacts with local CLI
  uses: <owner>/seal-action@v2
  env:
    SEAL_IDENTITY: ${{ secrets.SEAL_IDENTITY }}
  with:
    assets-directory: apps/proof/.vercel/output/static
    cli-command: node packages/seal-cli/bin/seal
```

`cli-command` is intentionally an advanced escape hatch. It is executed by the shell, so only pass commands you fully trust.

## Environment Contract

The action passes identity configuration through to `@ternent/seal-cli` without parsing it.

- `SEAL_IDENTITY`: inline exported Seal identity JSON secret
- `SEAL_IDENTITY_FILE`: path to an exported Seal identity JSON file on disk

Rules:

- at least one of `SEAL_IDENTITY` or `SEAL_IDENTITY_FILE` must be set
- if both are set, `SEAL_IDENTITY` is used
- legacy `SEAL_PRIVATE_KEY` and `SEAL_PUBLIC_KEY` are no longer supported

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `assets-directory` | Yes |  | Directory containing the built static site assets to sign. |
| `working-directory` | No | `.` | Base working directory used before resolving `assets-directory`. |
| `manifest-name` | No | `dist-manifest.json` | Output filename for the generated manifest. |
| `proof-name` | No | `proof.json` | Output filename for the generated proof. |
| `public-key-name` | No | `public-key.json` | Output filename for the generated public-key artifact. |
| `package-name` | No | `@ternent/seal-cli` | Published npm package name used when `cli-command` is empty. |
| `package-version` | No | `latest` | npm version or dist-tag used when `cli-command` is empty. |
| `cli-command` | No | empty | Optional trusted command prefix used to invoke Seal directly. |

## Outputs

All outputs are absolute paths within the runner workspace.

| Output | Description |
| --- | --- |
| `manifest-path` | Absolute path to the generated manifest file. |
| `proof-path` | Absolute path to the generated proof file. |
| `public-key-path` | Absolute path to the generated public-key file. |

## Artifact Contract

Seal Action generates three files in the asset directory.

`dist-manifest.json`

```json
{
  "version": "1",
  "type": "seal-manifest",
  "root": "dist",
  "files": {
    "assets/index.js": "sha256:..."
  }
}
```

`proof.json`

```json
{
  "version": "2",
  "type": "seal-proof",
  "algorithm": "Ed25519",
  "createdAt": "2026-03-13T00:00:00.000Z",
  "subject": {
    "kind": "manifest",
    "path": "dist-manifest.json",
    "hash": "sha256:..."
  },
  "signer": {
    "publicKey": "BASE64URL-RAW-ED25519-PUBLIC-KEY",
    "keyId": "..."
  },
  "signature": "..."
}
```

`public-key.json`

```json
{
  "version": "2",
  "type": "seal-public-key",
  "algorithm": "Ed25519",
  "publicKey": "BASE64URL-RAW-ED25519-PUBLIC-KEY",
  "keyId": "..."
}
```

`publicKey` is the raw base64url Ed25519 public key emitted by Seal v2, not PEM or SPKI text.

## Migration

This is a breaking change from the legacy Seal v1 action contract.

- Replace `SEAL_PRIVATE_KEY` / `SEAL_PUBLIC_KEY` workflow secrets with a single `SEAL_IDENTITY` secret containing the exported Seal web app identity JSON.
- If you prefer file-based configuration, write that JSON to disk in the workflow and set `SEAL_IDENTITY_FILE` instead.
- Release this action as a new major version such as `v2` so existing `v1` workflows keep the old contract until they migrate.

## Local Smoke Test

This repo intentionally contains no GitHub workflow files. For a local pre-release check, run:

```bash
./scripts/smoke-test.sh
```

The smoke test uses stub `seal` and `npm` binaries to verify:

- the default npm-backed path
- the `cli-command` override path
- `SEAL_IDENTITY` success
- `SEAL_IDENTITY_FILE` success
- `SEAL_IDENTITY` precedence when both env vars are set
- custom output filenames
- missing identity env failure
- missing asset directory failure

## Maintainer Notes

GitHub Marketplace action repositories must stay minimal. This repository should remain:

- public before the first Marketplace release
- limited to a single root `action.yml`
- free of `.github/workflows`

Manual release flow:

1. Run `./scripts/smoke-test.sh`.
2. Commit and push the release commit.
3. Create a Git tag such as `v2.0.0` for this breaking contract change.
4. Create the GitHub Release from the tag.
5. In the release flow, publish the action to GitHub Marketplace.
6. Move the major tag such as `v2` to the latest compatible release.

Recommended Marketplace categories:

- Security
- Utilities
