#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/node}"
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-${HOME}/.openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-${OPENCLAW_STATE_DIR}/workspace}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

MANAGED_SKILLS_DIR="${OPENCLAW_STATE_DIR}/skills"
LEGACY_SKILLS_DIR="${OPENCLAW_WORKSPACE_DIR}/skills"
SHARED_READONLY_DIR="${OPENCLAW_WORKSPACE_DIR}/shared-readonly"
ONEDRIVE_READONLY_DIR="${OPENCLAW_WORKSPACE_DIR}/onedrive-readonly"
OUTPUTS_DIR="${OPENCLAW_WORKSPACE_DIR}/outputs"
MINIMAX_SKILLS_DIR="/opt/minimax-skills/skills"

bootstrap_runtime() {
  install -d -m 0700 \
    "${OPENCLAW_STATE_DIR}" "${OPENCLAW_WORKSPACE_DIR}" "${OUTPUTS_DIR}" "${XDG_CACHE_HOME}"
  install -d -m 0755 "${MANAGED_SKILLS_DIR}"

  for skill in minimax-docx minimax-pdf minimax-xlsx pptx-generator; do
    source_path="${MINIMAX_SKILLS_DIR}/${skill}"
    target_path="${MANAGED_SKILLS_DIR}/${skill}"
    legacy_path="${LEGACY_SKILLS_DIR}/${skill}"

    if [[ -L "${legacy_path}" && "$(readlink "${legacy_path}")" == "${source_path}" ]]; then
      unlink "${legacy_path}"
    fi

    if [[ ! -e "${target_path}" && ! -L "${target_path}" ]]; then
      ln -s "${source_path}" "${target_path}"
    fi
  done
}

bootstrap_runtime

if [[ "$(id -u)" == "0" ]]; then
  find "${OPENCLAW_STATE_DIR}" \
    -path "${SHARED_READONLY_DIR}" -prune -o \
    -path "${ONEDRIVE_READONLY_DIR}" -prune -o \
    -exec chown -h node:node {} +
  chown -R node:node "${XDG_CACHE_HOME}"
  exec gosu node "$0" "$@"
fi

exec "$@"
