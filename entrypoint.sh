#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/node}"
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-${HOME}/.openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-${OPENCLAW_STATE_DIR}/workspace}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

QMD_CACHE_DIR="${XDG_CACHE_HOME}/qmd"
SKILLS_DIR="${OPENCLAW_WORKSPACE_DIR}/skills"
MINIMAX_SKILLS_DIR="/opt/minimax-skills/skills"

bootstrap_runtime() {
  install -d -m 0700 "${OPENCLAW_STATE_DIR}" "${OPENCLAW_WORKSPACE_DIR}" "${QMD_CACHE_DIR}"
  install -d -m 0755 "${SKILLS_DIR}"

  for skill in minimax-docx minimax-pdf minimax-xlsx pptx-generator; do
    source_path="${MINIMAX_SKILLS_DIR}/${skill}"
    target_path="${SKILLS_DIR}/${skill}"

    if [[ ! -e "${target_path}" && ! -L "${target_path}" ]]; then
      ln -s "${source_path}" "${target_path}"
    fi
  done
}

bootstrap_runtime

if [[ "$(id -u)" == "0" ]]; then
  chown -R node:node "${OPENCLAW_STATE_DIR}" "${QMD_CACHE_DIR}"
  exec gosu node "$0" "$@"
fi

exec "$@"
