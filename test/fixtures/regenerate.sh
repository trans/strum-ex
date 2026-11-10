#!/bin/sh
# Regenerates the compatibility fixtures: what this strum writes (elixir/),
# then what Crystal strum writes and reads (crystal/). Needs Crystal, and
# Crystal strum checked out next to this project, at ../strum.
set -e
cd "$(dirname "$0")/../.."
mix run test/fixtures/generate.exs
crystal run test/fixtures/generate.cr
