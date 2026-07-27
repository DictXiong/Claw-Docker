ARG NODE_VERSION=24.15.0
FROM node:${NODE_VERSION}-bookworm-slim AS node-runtime

ARG CUDA_VERSION=13.1.1
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu24.04

ARG OPENCLAW_VERSION=2026.7.1-2
ARG QMD_VERSION=2.5.3
ARG CLAWHUB_VERSION=0.23.1
ARG PPTXGENJS_VERSION=4.0.1
ARG MINIMAX_SKILLS_REF=60aaae52bb2af8162732751a4332f62a5fef518b

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/node \
    OPENCLAW_HOME=/home/node/.openclaw \
    OPENCLAW_STATE_DIR=/home/node/.openclaw \
    OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
    OPENCLAW_WORKSPACE_DIR=/home/node/.openclaw/workspace \
    XDG_CACHE_HOME=/home/node/.cache \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    QMD_LLAMA_GPU=cuda \
    OPENCLAW_DISABLE_BONJOUR=1

COPY --from=node-runtime /usr/local/ /usr/local/

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates cmake curl dnsutils dotnet-sdk-8.0 \
      fd-find fonts-liberation fonts-noto-cjk git gosu iproute2 iputils-ping \
      jq knot-dnsutils less libreoffice-calc libreoffice-core libreoffice-impress \
      libreoffice-writer libsqlite3-dev make openssh-client pandoc pkg-config \
      poppler-utils python3 python3-dev python3-venv ripgrep socat sqlite3 tini \
      unzip wget zip \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir \
      certifi lxml markitdown numpy openpyxl pandas pillow playwright \
      pybind11 pymupdf pypdf python-docx python-pptx reportlab scipy \
    && /opt/venv/bin/python -m playwright install chromium --with-deps \
    && npm install --global \
      "openclaw@${OPENCLAW_VERSION}" \
      "@tobilu/qmd@${QMD_VERSION}" \
      "clawhub@${CLAWHUB_VERSION}" \
      "pptxgenjs@${PPTXGENJS_VERSION}" \
    && npm cache clean --force \
    && git clone --filter=blob:none --no-checkout https://github.com/MiniMax-AI/skills.git /opt/minimax-skills \
    && git -C /opt/minimax-skills sparse-checkout init --cone \
    && git -C /opt/minimax-skills sparse-checkout set \
      skills/minimax-docx skills/minimax-pdf skills/minimax-xlsx skills/pptx-generator \
    && git -C /opt/minimax-skills checkout "${MINIMAX_SKILLS_REF}" \
    && bash /opt/minimax-skills/skills/minimax-docx/scripts/setup.sh --minimal --skip-verify \
    && groupadd --gid 1000 node \
    && useradd --uid 1000 --gid node --create-home --shell /bin/bash node \
    && install -d -m 0700 -o node -g node \
      /home/node/.openclaw /home/node/.openclaw/workspace /home/node/.cache/qmd \
    && install -d -m 0755 -o node -g node /persist \
    && chown -R node:node /opt/minimax-skills /opt/venv /ms-playwright \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /home/node
EXPOSE 18789

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "18789"]
