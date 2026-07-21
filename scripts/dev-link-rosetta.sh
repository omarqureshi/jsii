#!/bin/bash
#------------------------------------------------------------------------
# Links the local Ruby-target jsii-rosetta fork into this repo for local dev.
#
# The committed self-publish branch pins jsii-rosetta to upstream + a stopgap
# patch that has no TargetLanguage.RUBY, so a clean `yarn build` of pacmak's
# ruby target fails to compile. That is deliberate: the real build happens in
# the blog `publish-packages` pipeline, which injects the fork rosetta at build
# time (resolutions["jsii-rosetta"] = file:.../jsii-rosetta-0.0.0.tgz).
#
# This does the same thing locally, so pacmak's ruby target compiles and the
# ruby-runtime fixtures can be regenerated (otherwise the compliance suite runs
# against stale, months-old generated code and reports phantom failures).
#
# It modifies package.json + yarn.lock -- DO NOT COMMIT them. Run
# scripts/dev-unlink-rosetta.sh to restore the committed pins.
#
# Usage: scripts/dev-link-rosetta.sh [path-to-jsii-rosetta-fork]
#        (default: ../jsii-rosetta, the sibling checkout the pipeline assumes)
#------------------------------------------------------------------------
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
fork="$(cd "${1:-$here/../jsii-rosetta}" && pwd)"
tgz_path="$fork/dist/js/jsii-rosetta-0.0.0.tgz"

echo "Fork rosetta: $fork"

# 1. Build + pack the fork. lib/ is a gitignored build artifact; only recompile
#    when it is missing or older than a source file, to keep the fork pristine.
( cd "$fork"
  if [ ! -f lib/index.js ] || [ -n "$(find src -name '*.ts' -newer lib/index.js -print -quit 2>/dev/null)" ]; then
    echo "Compiling fork rosetta..."
    [ -d node_modules ] || yarn install --no-immutable
    npx projen pre-compile
    npx projen compile
  else
    echo "Fork build is current; skipping compile."
  fi
  mkdir -p dist/js
  npm pack --pack-destination dist/js >/dev/null
  echo "Packed $(basename "$tgz_path")"
)

# 2. Point jsii-rosetta at the fork tgz and install. A ROOT resolution overrides
#    the stopgap patch for every consumer, pacmak included. Relative path so it
#    matches what the pipeline writes.
cd "$here"
rel="$(realpath --relative-to="$here" "$tgz_path")"
echo "Pinning jsii-rosetta -> file:$rel"
jq --arg t "file:$rel" '.resolutions["jsii-rosetta"] = $t' package.json > package.json.tmp
mv package.json.tmp package.json
yarn install --no-immutable

cat <<EOF

Linked. pacmak's ruby target now compiles against the fork.

Rebuild pacmak + get a trustworthy compliance run:
  (cd packages/jsii-pacmak && npx tsc --build)
  (cd packages/@jsii/ruby-runtime-test && bash generate.sh && bundle exec rspec)

Restore the committed pins when done:
  scripts/dev-unlink-rosetta.sh
EOF
