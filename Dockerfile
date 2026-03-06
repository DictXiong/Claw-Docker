FROM ubuntu:latest


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
    # Network tools
    iproute2 \
    iputils-ping \
    socat \
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
    supervisor

RUN touch /.dockerenv && NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

RUN curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | bash -s - --daemon

# Install Python packages (for local models, embeddings)
RUN pip3 install --break-system-packages \
    numpy \
    pybind11 \
    certifi

# Install OpenClaw
RUN curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard

# Install additional global npm packages
RUN npm install -g \
    clawhub \
    @tobilu/qmd

# Install Playwright browsers
RUN npx playwright install chromium
RUN npx playwright install-deps chromium

# Set working directory
WORKDIR /root

# Configure zsh as default shell
RUN curl dotfiles.cn | bash -s && \
    chsh -s /bin/zsh root

RUN apt clean && rm -rf /var/lib/apt/lists/*

RUN mv /root /root_init && mkdir /root && chmod 700 /root
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Expose OpenClaw gateway port (default: 18789)
EXPOSE 18789
# Expose OpenClaw Browser Agent port (default: 18793)
EXPOSE 18793

# Health check
HEALTHCHECK --interval=3m --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Start command
CMD ["/usr/bin/supervisord", "-n"]
