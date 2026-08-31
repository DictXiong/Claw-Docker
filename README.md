# Agent Docker Monorepo

This repository builds two independent agent images:

| Agent | Build context | Container state root | Published image |
| --- | --- | --- | --- |
| OpenClaw | `images/openclaw` | `/home/node/.openclaw` | `ghcr.io/dictxiong/claw-docker` |
| Hermes Agent | `images/hermes` | `/opt/data` | `ghcr.io/dictxiong/hermes-docker` |

The images are intentionally independent. They use different base images,
entrypoints, browser integrations, dependency locks, and skill synchronization
mechanisms. The repository only shares version metadata, maintenance policy,
local orchestration, and CI conventions.

## Layout

```text
images/openclaw/   OpenClaw image, entrypoint, locks, patches, and smoke tests
images/hermes/     Hermes image, locks, patches, renderer, and smoke tests
.github/workflows/ Independent build and publish workflows for both images
compose.example.yaml  Variable-driven sample Compose configuration
compose.env.example   Non-secret example values for the sample Compose file
.env               Tracked, non-secret shared versions and local defaults
```

Agent credentials and model API keys remain in the existing persistent state
directories. Do not add them to this repository or `.env`.

## Build and test

Build one image at a time:

```bash
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile openclaw build openclaw
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes build hermes
```

Run the image-specific smoke tests:

```bash
images/openclaw/scripts/smoke-test.sh openclaw-jarvis:local
images/hermes/scripts/smoke-test.sh hermes-agent-local:0.20.0
```

The sample Compose file defines both services behind profiles. Supply your own
host paths without committing them to the repository:

```bash
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile openclaw up -d openclaw
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile hermes up -d hermes
```

The sample is not a production deployment manifest. Production paths,
credentials, DNS servers, and other host-specific settings belong in the
deployment system.

## Shared storage

Both agents run as numeric UID/GID `1001:1001`, with the `root` supplementary
group, and mount the same Obsidian and public shared storage directories
read-write. OneDrive is mounted read-only. Host ownership and permissions must
be prepared outside the containers.

## Updating

`MINIMAX_SKILLS_REF` in `.env` is shared by both builds. Updating it requires
reviewing both agent-specific patches and running both smoke tests. Other
dependencies remain independently locked because OpenClaw and Hermes use
different language runtimes and base images.

See `images/openclaw/README.md` and `images/hermes/README.md` for agent-specific
details.

## Publishing

The two GitHub Actions workflows build and test independently. Changes under
one image directory only rebuild that image; changes to `.env` rebuild both.
Default-branch builds publish `latest`, a full Git SHA tag, and an
agent-version-plus-SHA tag. Production should retain the previous digest before
switching so rollback does not depend on the mutable `latest` tag.
