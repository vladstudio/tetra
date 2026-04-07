#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../scripts/build-kit.sh
build_app "Tetra" \
  --binary tetra \
  --bundle .build/release/tetra_tetra.bundle
