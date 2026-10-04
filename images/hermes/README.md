# Hermes Agent image

Isolated Hermes Agent trial deployment. It runs alongside OpenClaw with a
separate state directory and container name, and publishes no network ports.

The image is based on the official Hermes Agent v0.21.5 image and adds the
runtime dependencies required by its bundled DOCX, PDF, XLSX, and PowerPoint
skills. It also bundles MiniMax's `minimax-docx`, `minimax-pdf`,
`minimax-xlsx`, and `pptx-generator` skills, plus the FlyAI travel-search
skill and its `flyai` CLI. It also includes the official `lark-cli` 1.0.97
and its matching Feishu/Lark skills. All upstream skill repositories are
pinned by commit SHA; both CLIs are pinned in the npm lock.

MiniMax skills are placed under `/opt/hermes/skills/minimax` and use Hermes'
official bundled-skill synchronizer. Pristine copies update with the image;
user-modified persistent copies are preserved. The DOCX CLI is precompiled in
a separate build stage. PDF cover rendering uses Hermes' existing Chromium
Headless Shell directly, so no additional Playwright package or browser is
installed.

FlyAI is placed under `/opt/hermes/skills/travel/flyai` and synchronized by
the same bundled-skill mechanism.

The complete upstream Lark skill bundle lives under `/opt/hermes/skills/feishu`
and uses the same synchronizer. Keeping the bundle together preserves its
cross-skill references, including document, wiki, message, event, and shared
authentication guidance. Installation does not grant any Feishu permissions.
The CLI's precompiled binary is downloaded and checksum-verified during the
image build, so normal invocation works without a runtime download.

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

To update Lark, change `@larksuite/cli` in `package.json` and regenerate
`package-lock.json`, then advance `LARK_CLI_SKILLS_REF` in the Dockerfile to the
matching upstream release commit. The build rejects mismatched CLI/skill
versions. Rebuild the image rather than running `lark-cli update` inside a
container. The smoke test checks CLI execution as the `hermes` user without
network access and verifies that every bundled Lark skill is synchronized.

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

Review `constraints.txt` against the new base image's Hermes package metadata
when upgrading that image. Add-on tools share its Python environment and must
not override core dependency pins. The protobuf bound preserves compatibility
with its Google/OpenTelemetry packages; MSAL 1.39 replaces the base image's
older release, which rejects Hermes' required cryptography version. Both the
build and smoke test run `uv pip check` over the complete environment.

Keep `lark-oapi` and `qrcode` aligned with the exact `platform.feishu` pins in
Hermes' `tools/lazy_deps.py`. Newer versions can import successfully but still
fail the gateway's dependency check and disable Feishu. The smoke test checks
both that dependency gate and the SDK's lazy initialization.

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

## Feishu / Lark CLI

After rebuilding, configure and authorize the CLI at runtime as the same user
that runs Hermes:

```bash
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes exec --user hermes hermes lark-cli --version
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes exec --user hermes hermes lark-cli config init
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes exec --user hermes hermes lark-cli auth login
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes exec --user hermes hermes lark-cli auth status
```

Choose only the scopes required for your workflow. Feishu gateway chat setup
and CLI user authorization are separate integrations; installing the CLI does
not authorize document or message access.

With this image's default `HOME=/opt/data` and `HERMES_HOME=/opt/data`, the CLI
selects its Hermes workspace and stores configuration under
`/opt/data/.lark-cli/hermes`. On Linux, encrypted credentials and their master
key live under `/opt/data/.local/share/lark-cli`. Both locations are inside the
persistent state mount. Keep the complete state directory when recreating or
backing up a container; retaining only `config.json` does not retain credentials.
No credentials or login state are included in the image.

Agent behavior, approvals, memory and skill writes, LSP support, and lazy
installation use the upstream Hermes defaults. Compose only defines the
container identity, persistent home, timezone, and host mounts.

Do not connect this trial to the same Weixin or Telegram bot credentials used
by OpenClaw. Polling credentials must have only one active gateway.
