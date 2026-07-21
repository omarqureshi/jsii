#!/bin/bash
#------------------------------------------------------------------------
# Reverts scripts/dev-link-rosetta.sh: restores the committed jsii-rosetta pin
# (upstream + stopgap patch) and reinstalls, leaving the branch clean.
#
# After this, pacmak's ruby target will no longer compile locally -- that is the
# committed state by design; the real build happens in the publish pipeline.
#------------------------------------------------------------------------
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

git checkout -- package.json yarn.lock
yarn install --no-immutable

echo "Restored committed jsii-rosetta pin; working tree clean."
