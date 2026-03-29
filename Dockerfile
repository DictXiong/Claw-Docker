ARG CUDA_VERSION=13.1.1

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu24.04

ARG CUDA_ARCH=75
ARG VERSION=latest

# Base env
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && yes | unminimize && apt-get install -y \
    # Essentials
    curl \
    wget \
    git \
    vim \
    less \
    zsh \
    ca-certificates \
    gettext-base \
    # Network tools
    iproute2 \
    iputils-ping \
    socat \
    dnsutils \
    knot-dnsutils \
    # Search & text processing
    ripgrep \
    fd-find \
    jq \
    # Database (for qmd)
    sqlite3 \
    libsqlite3-dev \
    # Build essentials (for node-llama-cpp, pybind11)
    build-essential \
    python3 \
    python3-pip \
    python3-dev \
    # Playwright browser dependencies
    libnss3 \
    libatk-bridge2.0-0 \
    libxss1 \
    libgtk-3-0 \
    libgbm1 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libpangocairo-1.0-0 \
    libpango-1.0-0 \
    libcairo2 \
    libatspi2.0-0 \
    libxrandr2 \
    libxi6 \
    libxcursor1 \
    libxtst6 \
    libglib2.0-0 \
    libnspr4 \
    libdrm2 \
    libdbus-1-3 \
    libexpat1 \
    libxcb1 \
    libxkbcommon0 \
    libcurl4 \
    libxshmfence1 \
    libegl1 \
    supervisor \
    nodejs \
    nvtop \
    # Miniax Office
    dotnet-sdk-8.0 \
    libreoffice-calc

RUN pip3 install --break-system-packages \
    numpy \
    scipy \
    pybind11 \
    certifi \
    reportlab \
    pypdf \
    pandas \
    openpyxl \
    playwright \
    markitdown \
    python-pptx \
    && python3 -m playwright install chromium --with-deps

RUN curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --npm --version ${VERSION}

RUN npm install -g \
    clawhub \
    @tobilu/qmd \
    pptxgenjs

RUN npx playwright install chromium
RUN npx playwright install-deps chromium

# qmd CUDA fix
RUN cd /opt && git clone --depth 1 https://github.com/ggml-org/llama.cpp.git && \
    cd llama.cpp && \
    ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 && \
    cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} -DCMAKE_BUILD_TYPE=Release -DCMAKE_LIBRARY_PATH="/usr/local/cuda/lib64/stubs" && \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs:$LD_LIBRARY_PATH cmake --build build -j$(nproc) && \
    NLLCPP_VER=$(grep -oP '"release":\s*"\K[^"]+' \
        /usr/lib/node_modules/@tobilu/qmd/node_modules/node-llama-cpp/llama/binariesGithubRelease.json \
        2>/dev/null || echo "unknown") && \
    echo "Detected node-llama-cpp version: ${NLLCPP_VER}" && \
    QMD_CUDA=/usr/lib/node_modules/@tobilu/qmd/node_modules/@node-llama-cpp/linux-x64-cuda/bins/linux-x64-cuda && \
    cp build/bin/libggml-base.so ${QMD_CUDA}/libggml-base.so && \
    cp build/bin/libggml.so ${QMD_CUDA}/libggml.cuda.${NLLCPP_VER}.so && \
    cp build/bin/libllama.so ${QMD_CUDA}/libllama.cuda.${NLLCPP_VER}.so && \
    cp build/bin/libggml-cuda.so ${QMD_CUDA}/libggml-cuda.so

RUN touch /.dockerenv && NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

RUN curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | bash -s - --daemon

RUN curl dotfiles.cn | bash -s && \
    chsh -s /bin/zsh root

# Post build
RUN apt clean && rm -rf /var/lib/apt/lists/*
RUN mv /root /root_init && mkdir /root && chmod 700 /root
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Metadata
WORKDIR /root
# Expose OpenClaw gateway port (default: 18789)
EXPOSE 18789
# Expose OpenClaw Browser Agent port (default: 18793)
EXPOSE 18793
HEALTHCHECK --interval=3m --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Start command
CMD ["/usr/bin/supervisord", "-n"]
