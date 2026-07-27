# Claw-Docker

面向单用户 OpenClaw 的 CUDA Docker 部署，包含本地文件检索和常用 Office 文档处理能力。

## 镜像包含

- OpenClaw（版本锁定在 `.env`）
- Node.js 24、CUDA 运行/编译环境
- QMD 本地检索，默认启用 CUDA 与适合中文的 Qwen3 Embedding
- Chromium / Playwright
- LibreOffice、Pandoc、Poppler、Python Office/PDF 库
- MiniMax 官方文档技能：`minimax-docx`、`minimax-pdf`、`minimax-xlsx`、`pptx-generator`

MiniMax 技能在构建时按 commit SHA 锁定，并在启动时链接到：

`/home/node/.openclaw/workspace/skills`

## 首次部署

先创建持久化目录：

```bash
sudo mkdir -p /data0/opt/claw/jarvis/.openclaw
sudo mkdir -p /data0/opt/claw/jarvis/.cache/qmd
sudo mkdir -p /data0/opt/claw/shared
# 如果智能体需要修改 shared 中的文件，确保 uid 1000 可写。
sudo chown -R 1000:1000 /data0/opt/claw/shared
```

复制环境模板并设置一个强随机网关令牌：

```bash
cp .env .env.local
TOKEN="$(openssl rand -hex 32)"
sed -i "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=$TOKEN/" .env.local
```

`.env.local` 已被忽略，不应提交到 Git。然后构建并初始化：

```bash
docker compose --env-file .env.local build --pull
docker compose --env-file .env.local run --rm openclaw-jarvis \
  openclaw onboard --mode local --no-install-daemon
docker compose --env-file .env.local up -d
```

查看状态：

```bash
docker compose --env-file .env.local ps
docker compose --env-file .env.local logs -f openclaw-jarvis
curl -fsS http://127.0.0.1:18789/healthz
```

控制界面默认只发布到宿主机 `127.0.0.1:18789`。远程访问建议使用 SSH 隧道或带认证的反向代理；不要直接把网关暴露到公网。

## 从旧容器升级

新版 Compose 直接复用原部署中的两个目录：

- `/data0/opt/claw/jarvis/.openclaw`：配置、工作区、会话和技能
- `/data0/opt/claw/jarvis/.cache/qmd`：QMD 索引和模型缓存

因此不需要重新构建一个空的 OpenClaw。旧 `/root` 挂载中的其他文件不会再整体映射；需要长期保留或供智能体处理的文件请移到 `/data0/opt/claw/shared`。

升级前建议备份：

```bash
sudo tar -C /data0/opt/claw/jarvis -czf openclaw-state-backup.tgz .openclaw .cache/qmd
```

## 验证文档技能

```bash
docker compose --env-file .env.local exec openclaw-jarvis \
  ls -l /home/node/.openclaw/workspace/skills
```

首次使用 QMD 时会下载模型，耗时取决于网络；模型和索引会保存在持久化缓存中。

## 更新版本

修改 `.env` 中的锁定版本或 MiniMax commit SHA，重新构建镜像后再启动。不要在运行中的容器里执行全局自更新，因为容器重建会覆盖这类修改。
