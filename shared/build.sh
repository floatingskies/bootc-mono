#!/usr/bin/env bash

set -xeuo pipefail

git clone "https://github.com/bootc-dev/bootc.git" .

# bindgen (via selinux-sys) needs libclang.so; point LIBCLANG_PATH at it so
# the crate can build without a globally installed clang on PATH. Use
# -print -quit instead of piping to head: under `set -o pipefail` the SIGPIPE
# from head closing the pipe aborts the whole script.
if command -v find >/dev/null 2>&1; then
  libclang="$(find /usr/lib /usr/lib64 /usr/local/lib -name 'libclang*.so*' -print -quit 2>/dev/null)"
  if [[ -n "${libclang}" ]]; then
    export LIBCLANG_PATH="$(dirname "${libclang}")"
  fi
fi

make bin install-all DESTDIR=/output

