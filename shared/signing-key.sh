#!/usr/bin/env bash
# Materialize the cosign private key from CI into a PEM file cosign can read.
#
# cosign's `env://COSIGN_PRIVATE_KEY` reads the raw secret and dies with a
# cryptic "reading key: invalid pem block" whenever the value is empty,
# whitespace-mangled, or stored base64-encoded (e.g. `base64 -w0 cosign.key`).
# This helper normalizes those cases and fails with an actionable message
# pointing at the SIGNING_SECRET repository secret.
set -euo pipefail

key_file="${COSIGN_KEY_FILE:-/tmp/cosign.key}"

if [[ -z "${COSIGN_PRIVATE_KEY:-}" ]]; then
  echo "::error::COSIGN_PRIVATE_KEY is empty." >&2
  echo "::error::Set the SIGNING_SECRET repository secret to the full contents of one of:" >&2
  echo "::error::  - 'cosign generate-key-pair' -> cosign.key (raw PEM)" >&2
  echo "::error::  - base64 -w0 cosign.key (this script decodes it automatically)" >&2
  exit 1
fi

# Keep the exact bytes first, then strip stray whitespace and blank padding
# lines that shell/CI pipelines sometimes introduce around secrets.
printf '%s' "${COSIGN_PRIVATE_KEY}" > "${key_file}.raw"
awk '{$1=$1} NF' "${key_file}.raw" > "${key_file}.clean"

# Some setups import the secret as base64(PEM); decode it if so.
if ! grep -q -- '-----BEGIN' "${key_file}.clean"; then
  if base64 -d "${key_file}.clean" > "${key_file}.decoded" 2>/dev/null &&
    grep -q -- '-----BEGIN' "${key_file}.decoded"; then
    mv "${key_file}.decoded" "${key_file}.clean"
  fi
fi

if ! grep -q -- '-----BEGIN' "${key_file}.clean"; then
  {
    echo "::error::COSIGN_PRIVATE_KEY does not contain a PEM private key."
    echo "::error::Import the *raw* key file contents as the SIGNING_SECRET repo secret."
    echo "::error::First bytes received: $(head -c 80 "${key_file}.clean" | tr -c '[:print:]\n\t' '?')"
  } >&2
  exit 1
fi

mv "${key_file}.clean" "${key_file}"
echo "Prepared cosign signing key at ${key_file}" >&2
printf '%s\n' "${key_file}"