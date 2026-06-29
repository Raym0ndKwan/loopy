#!/usr/bin/env bash
# Downloads the AGenUI HarmonyOS HAR from the latest GitHub release.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARMONY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIBS_DIR="${HARMONY_DIR}/libs"
OUTPUT="${LIBS_DIR}/agenui.har"

RELEASE_TAG="AGenUI-1.1.0.beta1"
ASSET_URL="https://github.com/AGenUI/AGenUI/releases/download/${RELEASE_TAG}/AGenUI-1.1.0-harmony.har"

mkdir -p "${LIBS_DIR}"

echo "Fetching AGenUI HAR (${RELEASE_TAG})..."
curl -L -o "${OUTPUT}" "${ASSET_URL}"
echo "Saved to ${OUTPUT}"
