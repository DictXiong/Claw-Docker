FROM mcr.microsoft.com/dotnet/sdk:8.0-noble@sha256:72b30253425d2707ea1dda364477136003586a9bdab63a988a84d1710f940d35 AS minimax-builder

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

FROM mcr.microsoft.com/dotnet/sdk:8.0-noble@sha256:72b30253425d2707ea1dda364477136003586a9bdab63a988a84d1710f940d35 AS flyai-skill-builder

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

FROM nousresearch/hermes-agent:latest@sha256:248024e18a05b0ee2d600a81538b1a3fd60653afa699814f68c2bdd928c19b47

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
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache --requirement /tmp/requirements.lock \
    && rm /tmp/requirements.lock

COPY package.json package-lock.json /opt/hermes/extra-node-tools/
RUN npm ci --prefix /opt/hermes/extra-node-tools --omit=dev --no-audit --no-fund \
    && ln -s /opt/hermes/extra-node-tools/node_modules/.bin/flyai /usr/local/bin/flyai \
    && npm cache clean --force \
    && usermod -aG root hermes

COPY --from=minimax-builder /opt/minimax-skills/skills/minimax-docx /opt/hermes/skills/minimax/minimax-docx
COPY --from=minimax-builder /opt/minimax-skills/skills/minimax-pdf /opt/hermes/skills/minimax/minimax-pdf
COPY --from=minimax-builder /opt/minimax-skills/skills/minimax-xlsx /opt/hermes/skills/minimax/minimax-xlsx
COPY --from=minimax-builder /opt/minimax-skills/skills/pptx-generator /opt/hermes/skills/minimax/pptx-generator
COPY --from=minimax-builder /opt/minimax-docx-cli /opt/minimax-docx-cli
COPY --from=flyai-skill-builder /opt/flyai-skill/skills/flyai /opt/hermes/skills/travel/flyai
COPY --from=flyai-skill-builder /opt/flyai-skill/LICENSE /opt/hermes/skills/travel/flyai/LICENSE

RUN install -d -m 0755 /opt/minimax-skills/skills \
    && for skill in minimax-docx minimax-pdf minimax-xlsx pptx-generator; do \
      ln -s "/opt/hermes/skills/minimax/${skill}" "/opt/minimax-skills/skills/${skill}"; \
    done

RUN grep -q 'log_level=lark.LogLevel.INFO,' /opt/hermes/plugins/platforms/feishu/adapter.py \
    && sed -i 's/log_level=lark.LogLevel.INFO,/log_level=lark.LogLevel.WARNING,/' \
      /opt/hermes/plugins/platforms/feishu/adapter.py \
    && ! grep -q 'log_level=lark.LogLevel.INFO,' /opt/hermes/plugins/platforms/feishu/adapter.py
