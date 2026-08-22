#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd) || exit 1
exec sh "$SCRIPT_DIR/src/rjeportal.sh" "$@"
