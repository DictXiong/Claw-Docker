#!/bin/bash
set -e

TARGET_DIR="/root"
INIT_DIR="/root_init"

if [ -z "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
    echo "[Init] Initializing $TARGET_DIR ..."
    cp -a "$INIT_DIR"/. "$TARGET_DIR"/
    echo "[Init] Done！"
else
    echo "[Init]$TARGET_DIR already exists; skip initialization"
fi

exec "$@"
