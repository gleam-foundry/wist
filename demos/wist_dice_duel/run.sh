#!/bin/bash
# Starts the Wist Dice Duel server on http://0.0.0.0:9987/.

echo "Building and starting Wist Dice Duel on http://0.0.0.0:9987/..."
cd "$(dirname "$0")"
exec gleam run
