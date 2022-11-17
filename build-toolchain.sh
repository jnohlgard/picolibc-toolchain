#!/bin/sh
set -euo pipefail

cd "$(dirname "$0")"
export PATH="${PWD}/crosstool-ng:${PATH}"
if [ ! -d crosstool-ng ]; then
  git submodule update --init crosstool-ng
fi
if ! command -v "${PWD}/crosstool-ng/ct-ng" 2>/dev/null >/dev/null; then
  cd crosstool-ng && ./bootstrap && ./configure --enable-local && make -j9
fi
