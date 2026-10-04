FROM mcr.microsoft.com/dotnet/sdk:8.0-noble@sha256:2e171ed9da38a01abb2005b8b2ce9df0c40e583a815e977a2c84d47778005dde AS minimax-builder

ARG MINIMAX_SKILLS_REF

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY patches/minimax-skills-hermes.patch /tmp/minimax-skills-hermes.patch
COPY scripts/render-cover-hermes.js /tmp/render-cover-hermes.js

RUN git clone --filter=blob:none --no-checkout https://github.com/MiniMax-AI/skills.git /opt/minimax-skills \
    && git -C /opt/minimax-skills sparse-checkout init --cone \
    && git -C /opt/minimax-skills sparse-checkout set \
      skills/minimax-docx skills/minimax-pdf skills/minimax-xlsx skills/pptx-generator \
    && git -C /opt/minimax-skills checkout "${MINIMAX_SKILLS_REF}" \
    && git -C /opt/minimax-skills apply /tmp/minimax-skills-hermes.patch \
    && install -m 0755 /tmp/render-cover-hermes.js \
      /opt/minimax-skills/skills/minimax-pdf/scripts/render_cover.js \
    && chmod +x /opt/minimax-skills/skills/minimax-docx/scripts/*.sh \
    && dotnet publish --configuration Release --runtime linux-x64 --self-contained true \
      -p:PublishSingleFile=true --output /opt/minimax-docx-cli \
      /opt/minimax-skills/skills/minimax-docx/scripts/dotnet/MiniMaxAIDocx.Cli/MiniMaxAIDocx.Cli.csproj \
    && rm -rf \
      /opt/minimax-skills/.git \
      /opt/minimax-skills/skills/minimax-docx/scripts/dotnet/MiniMaxAIDocx.Cli/bin \
      /opt/minimax-skills/skills/minimax-docx/scripts/dotnet/MiniMaxAIDocx.Cli/obj \
      /opt/minimax-skills/skills/minimax-docx/scripts/dotnet/MiniMaxAIDocx.Core/bin \
      /opt/minimax-skills/skills/minimax-docx/scripts/dotnet/MiniMaxAIDocx.Core/obj \
      /opt/minimax-docx-cli/*.pdb

FROM mcr.microsoft.com/dotnet/sdk:8.0-noble@sha256:2e171ed9da38a01abb2005b8b2ce9df0c40e583a815e977a2c84d47778005dde AS flyai-skill-builder

ARG FLYAI_SKILL_REF

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --filter=blob:none --no-checkout https://github.com/alibaba-flyai/flyai-skill.git /opt/flyai-skill \
    && git -C /opt/flyai-skill sparse-checkout init --cone \
    && git -C /opt/flyai-skill sparse-checkout set skills/flyai \
    && git -C /opt/flyai-skill checkout "${FLYAI_SKILL_REF}" \
    && test -f /opt/flyai-skill/LICENSE \
    && test -f /opt/flyai-skill/skills/flyai/SKILL.md \
    && rm -rf /opt/flyai-skill/.git

FROM mcr.microsoft.com/dotnet/sdk:8.0-noble@sha256:2e171ed9da38a01abb2005b8b2ce9df0c40e583a815e977a2c84d47778005dde AS lark-skill-builder

# Match the fixed @larksuite/cli version in package.json (upstream v1.0.97).
ARG LARK_CLI_SKILLS_REF=72579c80027c863ca51d5f9affda72a70ab0d8a6

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --filter=blob:none --no-checkout https://github.com/larksuite/cli.git /opt/lark-cli \
    && git -C /opt/lark-cli sparse-checkout init --cone \
    && git -C /opt/lark-cli sparse-checkout set skills \
    && git -C /opt/lark-cli checkout "${LARK_CLI_SKILLS_REF}" \
    && for skill in /opt/lark-cli/skills/lark-*; do \
      test -f "$skill/SKILL.md" || exit 1; \
      cp /opt/lark-cli/LICENSE "$skill/LICENSE" || exit 1; \
    done \
    && rm -rf /opt/lark-cli/.git

FROM nousresearch/hermes-agent:v2026.9.24@sha256:fca358f12efd65bfaaca05884166f15c0e2788375ca30d77061ac1ebc96452b7

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NODE_PATH=/opt/hermes/extra-node-tools/node_modules:/opt/hermes/node_modules

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      dnsutils fd-find fonts-liberation fonts-noto-cjk ghostscript iputils-ping jq less \
      libreoffice-calc libreoffice-core libreoffice-impress libreoffice-writer \
      openssh-client pandoc poppler-utils qpdf socat unzip zip \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.lock /tmp/requirements.lock
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache \
      --exclude-newer 2026-09-25T00:00:00Z --requirement /tmp/requirements.lock \
    && uv pip check --python /opt/hermes/.venv/bin/python \
    && rm /tmp/requirements.lock

COPY --from=lark-skill-builder /opt/lark-cli/package.json /opt/hermes/lark-cli-skills-package.json
COPY package.json package-lock.json /opt/hermes/extra-node-tools/
RUN npm ci --prefix /opt/hermes/extra-node-tools --omit=dev --no-audit --no-fund \
    && node -e 'const cli = require("/opt/hermes/extra-node-tools/node_modules/@larksuite/cli/package.json"); const skills = require("/opt/hermes/lark-cli-skills-package.json"); if (cli.version !== skills.version) throw new Error("lark-cli and bundled skills versions differ");' \
    && node /opt/hermes/extra-node-tools/node_modules/@larksuite/cli/scripts/install.js \
    && test -x /opt/hermes/extra-node-tools/node_modules/@larksuite/cli/bin/lark-cli \
    && ln -s /opt/hermes/extra-node-tools/node_modules/.bin/flyai /usr/local/bin/flyai \
    && ln -s /opt/hermes/extra-node-tools/node_modules/.bin/lark-cli /usr/local/bin/lark-cli \
    && npm cache clean --force \
    && usermod -aG root hermes

COPY --from=minimax-builder /opt/minimax-skills/skills/minimax-docx /opt/hermes/skills/minimax/minimax-docx
COPY --from=minimax-builder /opt/minimax-skills/skills/minimax-pdf /opt/hermes/skills/minimax/minimax-pdf
COPY --from=minimax-builder /opt/minimax-skills/skills/minimax-xlsx /opt/hermes/skills/minimax/minimax-xlsx
COPY --from=minimax-builder /opt/minimax-skills/skills/pptx-generator /opt/hermes/skills/minimax/pptx-generator
COPY --from=minimax-builder /opt/minimax-docx-cli /opt/minimax-docx-cli
COPY --from=flyai-skill-builder /opt/flyai-skill/skills/flyai /opt/hermes/skills/travel/flyai
COPY --from=flyai-skill-builder /opt/flyai-skill/LICENSE /opt/hermes/skills/travel/flyai/LICENSE
COPY --from=lark-skill-builder /opt/lark-cli/skills /opt/hermes/skills/feishu

RUN install -d -m 0755 /opt/minimax-skills/skills \
    && for skill in minimax-docx minimax-pdf minimax-xlsx pptx-generator; do \
      ln -s "/opt/hermes/skills/minimax/${skill}" "/opt/minimax-skills/skills/${skill}"; \
    done

RUN grep -q 'log_level=lark.LogLevel.INFO,' /opt/hermes/plugins/platforms/feishu/adapter.py \
    && sed -i 's/log_level=lark.LogLevel.INFO,/log_level=lark.LogLevel.WARNING,/' \
      /opt/hermes/plugins/platforms/feishu/adapter.py \
    && ! grep -q 'log_level=lark.LogLevel.INFO,' /opt/hermes/plugins/platforms/feishu/adapter.py
