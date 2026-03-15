# Seal Action

Seal Action is a publishable GitHub Marketplace action for generating Seal artifacts for a pre-built static site directory.

It creates:

- a manifest describing the signed assets
- a proof JSON signed with your Seal private key
- a public key JSON artifact for offline verification

The action is intentionally narrow. Your workflow is still responsible for checking out the repo, setting up Node.js, and building the static directory you want to sign.

## Prerequisites

- A checked-out repository via `actions/checkout`
- Node.js on the runner via `actions/setup-node`
- A built static asset directory, such as `dist`
- `SEAL_PRIVATE_KEY` available in the workflow environment
- Optionally `SEAL_PUBLIC_KEY` if you want Seal CLI to verify the key pair before signing

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
        uses: <owner>/seal-action@v1
        env:
          SEAL_PRIVATE_KEY: ${{ secrets.SEAL_PRIVATE_KEY }}
          SEAL_PUBLIC_KEY: ${{ secrets.SEAL_PUBLIC_KEY }}
        with:
          assets-directory: dist
```

By default the action runs:

```bash
npm exec --yes --package=@ternent/seal-cli@latest seal
```

## Advanced Usage

If you already have `seal` available in the workspace, you can bypass npm installation and invoke a trusted command directly with `cli-command`.

```yaml
- name: Generate Seal artifacts with local CLI
  uses: <owner>/seal-action@v1
  env:
    SEAL_PRIVATE_KEY: ${{ secrets.SEAL_PRIVATE_KEY }}
    SEAL_PUBLIC_KEY: ${{ secrets.SEAL_PUBLIC_KEY }}
  with:
    assets-directory: apps/proof/.vercel/output/static
    cli-command: node packages/seal-cli/bin/seal
```

`cli-command` is intentionally an advanced escape hatch. It is executed by the shell, so only pass commands you fully trust.

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
  "version": "1",
  "type": "seal-proof",
  "algorithm": "ECDSA-P256-SHA256",
  "createdAt": "2026-03-13T00:00:00.000Z",
  "subject": {
    "kind": "manifest",
    "path": "dist-manifest.json",
    "hash": "sha256:..."
  },
  "signer": {
    "publicKey": "BASE64-SPKI",
    "keyId": "..."
  },
  "signature": "..."
}
```

`public-key.json`

```json
{
  "algorithm": "ECDSA-P256-SHA256",
  "publicKey": "BASE64-SPKI",
  "keyId": "..."
}
```

## Local Smoke Test

This repo intentionally contains no GitHub workflow files. For a local pre-release check, run:

```bash
./scripts/smoke-test.sh
```

The smoke test uses stub `seal` and `npm` binaries to verify:

- the default npm-backed path
- the `cli-command` override path
- custom output filenames
- missing `SEAL_PRIVATE_KEY` failure
- missing asset directory failure

## Maintainer Notes

GitHub Marketplace action repositories must stay minimal. This repository should remain:

- public before the first Marketplace release
- limited to a single root `action.yml`
- free of `.github/workflows`

Manual release flow:

1. Run `./scripts/smoke-test.sh`.
2. Commit and push the release commit.
3. Create a Git tag such as `v1.0.0`.
4. Create the GitHub Release from the tag.
5. In the release flow, publish the action to GitHub Marketplace.
6. Move the major tag such as `v1` to the latest compatible release.

Recommended Marketplace categories:

- Security
- Utilities
