#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../scripts/release-kit.sh
release_app "Tetra"
