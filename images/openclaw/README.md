# OpenClaw image

面向单用户 OpenClaw 的 Docker 部署，包含本地文件检索和常用 Office 文档处理能力。

## 镜像包含

- OpenClaw、ClawHub、Playwright 和 PptxGenJS（锁定在 `package-lock.json`）
- Node.js 24、Python 3
- `fd`、`ripgrep`、`jq` 等文件查找和文本处理工具
- Chromium / Playwright
- LibreOffice、Pandoc、Poppler、Python Office/PDF 库
- MiniMax 官方文档技能：`minimax-docx`、`minimax-pdf`、`minimax-xlsx`、`pptx-generator`

MiniMax 技能在构建时按 commit SHA 锁定，并在启动时链接到：

`/home/node/.openclaw/skills`

技能文件本体位于镜像的 `/opt/minimax-skills/skills`。持久化目录中只保存符号链接，因此重新构建镜像即可更新技能内容，不会复制或覆盖 workspace 文件。

`minimax-docx` CLI 会在独立构建阶段发布为自包含可执行文件，运行镜像不包含 .NET SDK，也不会在运行时编译源码。容器专用说明由 `patches/minimax-skills-openclaw.patch` 应用，上游 commit 更新后需要重新检查该补丁。

基础镜像按 registry digest 固定，Python 依赖锁定在 `requirements.lock`。仓库根目录的 `.env` 只保存共享版本和 Compose 非敏感默认值。

## 运行方式

生产实例应由外部容器编排系统管理。完整 Git SHA 标签用于审计和回退，`latest` 是可变标签。

> [!WARNING]
> 仓库根目录的 `compose.yaml` 不用于生产部署。它仅为临时构建、验证和紧急回退而保留。

以下命令对两种运行方式都适用：

```bash
docker inspect openclaw-jarvis
docker logs -f openclaw-jarvis
docker exec --user node openclaw-jarvis openclaw channels status --json
```

## Docker Compose（已弃用）

仓库只提供变量驱动的 `compose.example.yaml`。先创建自行选择的持久化目录并填写本机专用环境文件；不要提交真实路径或凭据。示例目录：

```bash
sudo mkdir -p /srv/agents/openclaw
```

然后构建并初始化：

```bash
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile openclaw build --pull openclaw
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile openclaw run --rm openclaw \
  openclaw onboard --mode local --no-install-daemon
docker compose --env-file .env --env-file compose.env.example \
  -f compose.example.yaml --profile openclaw up -d openclaw
```

首次 onboarding 选择 token 认证时，如果没有提供现有令牌，OpenClaw 会自动生成随机令牌并写入持久化的 `/home/node/.openclaw/openclaw.json`。Compose 不再另行传入 `OPENCLAW_GATEWAY_TOKEN`，避免环境变量与配置文件出现两套来源。

DuckDuckGo 是无需 API Key 的实验性搜索 provider，OpenClaw 不会自动选择无密钥 provider。启动后需要显式启用一次：

```bash
docker exec --user node openclaw-jarvis \
  openclaw config set tools.web.search.provider '"duckduckgo"' --strict-json
docker exec --user node openclaw-jarvis \
  openclaw capability web search --query "OpenClaw official documentation" --json
```

查看状态：

```bash
docker inspect openclaw-jarvis --format '{{.State.Status}} {{.State.Health.Status}}'
docker logs -f openclaw-jarvis
curl --noproxy '*' -fsS http://HOST:18789/healthz
```

网关应启用 token 认证；不要把该端口直接暴露到公网。

## 旧 Compose 容器迁移（已弃用）

该兼容配置直接复用原部署中的状态目录：

- `/srv/agents/openclaw`：示例中的配置、工作区、会话和技能目录

已有部署可以直接复用原状态目录，不需要重新初始化一个空的 OpenClaw。

启动脚本只调整镜像自己管理的目录，不再递归修改整个状态目录，因此新增任意只读 bind mount 都不会被 `chown`。如果迁移来的状态文件属主不正确，应在没有挂载 workspace 外部目录的临时容器中执行一次修复：

```bash
docker run --rm --entrypoint chown \
  --mount type=bind,source=/srv/agents/openclaw,target=/state \
  openclaw-jarvis:local -R 1001:1001 /state
```

不要把旧 `workspace/skills` 整体复制到新 workspace。同名 workspace skill 的优先级高于镜像提供的 managed skill 和 OpenClaw bundled skill，会导致新版被旧副本覆盖。

升级前建议备份：

```bash
sudo tar -C /srv/agents -czf openclaw-state-backup.tgz openclaw
```

## 验证文档技能

```bash
docker exec openclaw-jarvis \
  ls -l /home/node/.openclaw/skills
```

## 更新版本

更新 Node.js 或基础发行版时，修改 `images/openclaw/Dockerfile` 中的版本并同步刷新 registry digest；更新 MiniMax skills 时修改仓库根目录的 `.env`。更新 OpenClaw、ClawHub、Playwright 或 PptxGenJS 时修改 `images/openclaw/package.json`，然后重新生成 lock：

```bash
cd images/openclaw
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

更新 Python 依赖时重新生成并审查 `requirements.lock`。重新构建镜像后再启动；不要在运行中的容器里执行全局自更新，因为容器重建会覆盖这类修改。

## 发布镜像

`main` 分支中的镜像相关文件发生变化时，GitHub Actions 会先构建并执行 runtime smoke tests，通过后再将 `linux/amd64` 镜像推送到 `ghcr.io/dictxiong/claw-docker`。每次构建发布以下标签：

- `<OpenClaw version>-<full Git commit SHA>`
- `sha-<full Git commit SHA>`
- `latest`（仅默认分支，可变）

生产部署需要回退时应改用完整 Git SHA 标签或 digest。私有 package 在拉取前需要先登录 GHCR。
