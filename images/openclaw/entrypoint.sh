#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/node}"
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-${HOME}/.openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-${OPENCLAW_STATE_DIR}/workspace}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

MANAGED_SKILLS_DIR="${OPENCLAW_STATE_DIR}/skills"
LEGACY_SKILLS_DIR="${OPENCLAW_WORKSPACE_DIR}/skills"
OUTPUTS_DIR="${OPENCLAW_WORKSPACE_DIR}/outputs"
MINIMAX_SKILLS_DIR="/opt/minimax-skills/skills"
FLYAI_SKILLS_DIR="/opt/flyai-skill/skills"

bootstrap_runtime() {
  install -d -m 0700 \
    "${OPENCLAW_STATE_DIR}" "${OPENCLAW_WORKSPACE_DIR}" "${OUTPUTS_DIR}" "${XDG_CACHE_HOME}"
  install -d -m 0755 "${MANAGED_SKILLS_DIR}"

  for source_path in \
    "${MINIMAX_SKILLS_DIR}/minimax-docx" \
    "${MINIMAX_SKILLS_DIR}/minimax-pdf" \
    "${MINIMAX_SKILLS_DIR}/minimax-xlsx" \
    "${MINIMAX_SKILLS_DIR}/pptx-generator" \
    "${FLYAI_SKILLS_DIR}/flyai"; do
    skill="$(basename "${source_path}")"
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
  chown -h node:node \
    "${OPENCLAW_STATE_DIR}" "${OPENCLAW_WORKSPACE_DIR}" \
    "${MANAGED_SKILLS_DIR}" "${OUTPUTS_DIR}" "${XDG_CACHE_HOME}"
  exec gosu node "$0" "$@"
fi

exec "$@"
