#!/usr/bin/env bash

set -xeuo pipefail

git clone "https://github.com/bootc-dev/bootc.git" .

# bindgen (via selinux-sys) needs libclang.so; point LIBCLANG_PATH at it so
# the crate can build without a globally installed clang on PATH.
if command -v find >/dev/null 2>&1; then
  libclang="$(find /usr/lib /usr/lib64 /usr/local/lib -name 'libclang*.so*' 2>/dev/null | head -n1)"
  if [[ -n "${libclang}" ]]; then
    export LIBCLANG_PATH="$(dirname "${libclang}")"
  fi
fi

make bin install-all DESTDIR=/output

