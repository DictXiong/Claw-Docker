# Hermes Agent image

Isolated Hermes Agent trial deployment. It runs alongside OpenClaw with a
separate state directory and container name, and publishes no network ports.

The image is based on the official Hermes Agent v0.21.5 image and adds the
runtime dependencies required by its bundled DOCX, PDF, XLSX, and PowerPoint
skills. It also bundles MiniMax's `minimax-docx`, `minimax-pdf`,
`minimax-xlsx`, and `pptx-generator` skills, plus the FlyAI travel-search
skill and its `flyai` CLI. Both upstream skill repositories are pinned by
commit SHA.

MiniMax skills are placed under `/opt/hermes/skills/minimax` and use Hermes'
official bundled-skill synchronizer. Pristine copies update with the image;
user-modified persistent copies are preserved. The DOCX CLI is precompiled in
a separate build stage. PDF cover rendering uses Hermes' existing Chromium
Headless Shell directly, so no additional Playwright package or browser is
installed.

FlyAI is placed under `/opt/hermes/skills/travel/flyai` and synchronized by
the same bundled-skill mechanism.

## Build and run

```bash
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes build hermes
images/hermes/scripts/smoke-test.sh hermes-agent-local:0.21.5
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes up -d hermes
```

To update the MiniMax or FlyAI skills, change `MINIMAX_SKILLS_REF` or
`FLYAI_SKILL_REF` in the repository root `.env`, rebuild, and rerun the smoke
test. The Hermes-specific MiniMax patch must be reviewed whenever that upstream
commit changes. Update the pinned FlyAI CLI version and package lock separately
when required.

Persistent state is mounted at `/opt/data` inside the container. The writable
workspace and its `outputs` directory live inside that single state root.

Python dependencies are locked for Python 3.13 with a package publication
cutoff. To update them, review and advance the cutoff date before rebuilding:

```bash
cd images/hermes
docker run --rm --entrypoint uv -v "$PWD:/work" -w /work \
  nousresearch/hermes-agent:v2026.9.24 pip compile --upgrade --no-cache \
  --exclude-newer 2026-09-25T00:00:00Z --python-version 3.13 \
  requirements.in --output-file requirements.lock
```

Keep the `--exclude-newer` value in this command aligned with the install step
in the Dockerfile. The upstream Hermes image has its own earlier default cutoff.

## Use

```bash
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes exec --user hermes hermes hermes status
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes exec --user hermes hermes hermes --tui
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes exec --user hermes hermes hermes -z \
  "Reply with exactly: Hermes is ready"
```

The container working directory is `/opt/data/workspace`. The image does not
seed an `AGENTS.md`; this matches the Hermes default. The user or Hermes may
create and update one later with `/init`, and it will persist in the state
directory.

Agent behavior, approvals, memory and skill writes, LSP support, and lazy
installation use the upstream Hermes defaults. Compose only defines the
container identity, persistent home, timezone, and host mounts.

Do not connect this trial to the same Weixin or Telegram bot credentials used
by OpenClaw. Polling credentials must have only one active gateway.
