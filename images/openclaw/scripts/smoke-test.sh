#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh IMAGE}"
CONTAINER="openclaw-smoke-${GITHUB_RUN_ID:-local}-$$"

cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --rm --network none --entrypoint openclaw "${IMAGE}" --version
docker run --rm --network none --user node --entrypoint sh "${IMAGE}" -c '
  command -v flyai >/dev/null
  flyai --help >/dev/null
  test -f /opt/flyai-skill/LICENSE
  test -f /opt/flyai-skill/skills/flyai/SKILL.md
'
docker run --rm --network none --entrypoint bash "${IMAGE}" \
  /opt/minimax-skills/skills/minimax-docx/scripts/env_check.sh
docker run --rm --network none --entrypoint node "${IMAGE}" \
  -e 'require("playwright"); require("pptxgenjs")'

# Any future read-only workspace mount must remain outside entrypoint ownership repair.
docker run --rm --network none \
  --tmpfs /home/node/.openclaw:rw,size=128m,mode=0700 \
  --mount type=bind,source=/etc/hostname,target=/home/node/.openclaw/workspace/extra-readonly.txt,readonly \
  "${IMAGE}" sh -c '
    test -L /home/node/.openclaw/skills/flyai
    test -f /home/node/.openclaw/skills/flyai/SKILL.md
  '

docker run -d --name "${CONTAINER}" --network none \
  --tmpfs /home/node/.openclaw:rw,size=128m,mode=0700 \
  "${IMAGE}" openclaw gateway \
  --allow-unconfigured --auth none --bind loopback --port 18789 >/dev/null

for _ in $(seq 1 30); do
  status="$(docker inspect --format '{{.State.Status}}' "${CONTAINER}" 2>/dev/null || true)"
  health="$(docker inspect --format '{{.State.Health.Status}}' "${CONTAINER}" 2>/dev/null || true)"

  if [[ "${status}" == "running" && "${health}" == "healthy" ]]; then
    echo "Gateway smoke test: healthy"
    exit 0
  fi
  if [[ "${status}" == "exited" || "${health}" == "unhealthy" ]]; then
    break
  fi
  sleep 2
done

docker logs "${CONTAINER}" || true
exit 1
