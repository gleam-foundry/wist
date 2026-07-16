#!/bin/bash

echo "Building and starting the Wist echo server on http://localhost:8080/..."
cd "$(dirname "$0")"
exec gleam run -m echo_server
