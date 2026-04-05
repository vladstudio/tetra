#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../mac-scripts/build-kit.sh
build_app "Tetra" \
  --binary tetra \
  --resources "AppIcon.icns" \
  --bundle .build/release/tetra_tetra.bundle
