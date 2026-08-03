FROM node:24.15.0-bookworm-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d AS node-runtime

FROM mcr.microsoft.com/dotnet/sdk:8.0-noble@sha256:72b30253425d2707ea1dda364477136003586a9bdab63a988a84d1710f940d35 AS minimax-builder

ARG MINIMAX_SKILLS_REF

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY patches/minimax-skills-openclaw.patch /tmp/minimax-skills-openclaw.patch

RUN git clone --filter=blob:none --no-checkout https://github.com/MiniMax-AI/skills.git /opt/minimax-skills \
    && git -C /opt/minimax-skills sparse-checkout init --cone \
    && git -C /opt/minimax-skills sparse-checkout set \
      skills/minimax-docx skills/minimax-pdf skills/minimax-xlsx skills/pptx-generator \
    && git -C /opt/minimax-skills checkout "${MINIMAX_SKILLS_REF}" \
    && git -C /opt/minimax-skills apply /tmp/minimax-skills-openclaw.patch \
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

FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/node \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    OPENCLAW_HOME=/home/node/.openclaw \
    OPENCLAW_STATE_DIR=/home/node/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    OPENCLAW_WORKSPACE_DIR=/home/node/.openclaw/workspace \
    XDG_CACHE_HOME=/home/node/.cache \
    NODE_PATH=/opt/node-tools/node_modules \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    OPENCLAW_DISABLE_BONJOUR=1

COPY --from=node-runtime /usr/local/ /usr/local/

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl dnsutils \
      fd-find fonts-liberation fonts-noto-cjk git gosu iproute2 iputils-ping \
      jq knot-dnsutils less libreoffice-calc libreoffice-core libreoffice-impress \
      libreoffice-writer openssh-client pandoc poppler-utils \
      python3 python3-venv ripgrep socat tini \
      unzip zip \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.lock /tmp/requirements.lock
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --requirement /tmp/requirements.lock \
    && rm /tmp/requirements.lock

COPY package.json package-lock.json /opt/node-tools/
RUN npm ci --prefix /opt/node-tools --omit=dev --no-audit --no-fund \
    && ln -s /opt/node-tools/node_modules/.bin/openclaw /usr/local/bin/openclaw \
    && ln -s /opt/node-tools/node_modules/.bin/clawhub /usr/local/bin/clawhub \
    && ln -s /opt/node-tools/node_modules/.bin/playwright /usr/local/bin/playwright \
    && npm cache clean --force

RUN playwright install chromium --with-deps --only-shell \
    && rm -rf /var/lib/apt/lists/*

COPY --from=minimax-builder /opt/minimax-skills /opt/minimax-skills
COPY --from=minimax-builder /opt/minimax-docx-cli /opt/minimax-docx-cli

RUN groupadd --gid 1001 node \
    && useradd --uid 1001 --gid node --groups root --home-dir /home/node --no-create-home --shell /bin/bash node \
    && install -d -m 0700 -o node -g node \
      /home/node/.openclaw /home/node/.openclaw/workspace /home/node/.cache \
    && chown -R node:node /home/node \
    && rm -rf /tmp/* /var/tmp/*

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /home/node
EXPOSE 18789

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "18789"]
