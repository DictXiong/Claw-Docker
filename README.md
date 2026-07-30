# Claw-Docker

面向单用户 OpenClaw 的 CUDA Docker 部署，包含本地文件检索和常用 Office 文档处理能力。

## 镜像包含

- OpenClaw（版本锁定在 `.env`）
- Node.js 24、CUDA 运行/编译环境
- `fd`、`ripgrep`、`jq` 等文件查找和文本处理工具
- Chromium / Playwright
- LibreOffice、Pandoc、Poppler、Python Office/PDF 库
- MiniMax 官方文档技能：`minimax-docx`、`minimax-pdf`、`minimax-xlsx`、`pptx-generator`

MiniMax 技能在构建时按 commit SHA 锁定，并在启动时链接到：

`/home/node/.openclaw/skills`

技能文件本体位于镜像的 `/opt/minimax-skills/skills`。持久化目录中只保存符号链接，因此重新构建镜像即可更新技能内容，不会复制或覆盖 workspace 文件。

`minimax-docx` 会在构建时恢复依赖并完成一次 Debug 编译。运行时仍按 skill 的说明使用 `dotnet run`；只有两个 .NET 项目的 `bin/`、`obj/` 对 `node` 可写，skill 源码保持只读。容器专用说明由 `patches/minimax-skills-openclaw.patch` 应用，上游 commit 更新后需要重新检查该补丁。

## 首次部署

先创建持久化目录：

```bash
sudo mkdir -p /data0/opt/claw/jarvis/.openclaw
sudo mkdir -p /data0/opt/claw/shared
# 只把明确允许智能体读取的目录交给 root 组。
sudo chown root:root /data0/opt/claw/shared
sudo chmod 0750 /data0/opt/claw/shared
```

镜像中的 `node` 用户（UID/GID 1001）属于 `root` 附加组，因此能读取宿主机上归 `root` 组所有、且授予组读取/遍历权限的内容。这不会赋予 `node` root 用户身份；共享目录仍由 Compose 以 `:ro` 挂载，容器内无法写入。不要挂载不希望智能体读取的其他 `root` 组目录。

对于既有的 Obsidian 目录，只需按实际需要调整入口目录：

```bash
sudo chown root:root /data0/opt/claw/shared/Obsidian
sudo chmod 0770 /data0/opt/claw/shared/Obsidian
```

其下现有目录为 `0755`、文件为 `0644` 时无需递归改属主。若以后加入更严格权限的内容，需要单独授予 `root` 组读取权限；不要在不清楚同步工具属主要求时执行递归 `chown`。

然后构建并初始化：

```bash
docker compose build --pull
docker compose run --rm openclaw-jarvis \
  openclaw onboard --mode local --no-install-daemon
docker compose up -d
```

首次 onboarding 选择 token 认证时，如果没有提供现有令牌，OpenClaw 会自动生成随机令牌并写入持久化的 `/home/node/.openclaw/openclaw.json`。Compose 不再另行传入 `OPENCLAW_GATEWAY_TOKEN`，避免环境变量与配置文件出现两套来源。

DuckDuckGo 是无需 API Key 的实验性搜索 provider，OpenClaw 不会自动选择无密钥 provider。启动后需要显式启用一次：

```bash
docker compose exec --user node openclaw-jarvis \
  openclaw config set tools.web.search.provider '"duckduckgo"' --strict-json
docker compose exec --user node openclaw-jarvis \
  openclaw capability web search --query "OpenClaw official documentation" --json
```

查看状态：

```bash
docker compose ps
docker compose logs -f openclaw-jarvis
curl --noproxy '*' -fsS http://10.255.0.2:18789/healthz
```

Docker daemon 运行在独立网络命名空间中，Compose 在该命名空间发布 `18789:18789`，当前命名空间通过 `10.255.0.2:18789` 访问。网关启用 token 认证；不要把该端口继续转发到公网。

## 从旧容器升级

新版 Compose 直接复用原部署中的状态目录：

- `/data0/opt/claw/jarvis/.openclaw`：配置、工作区、会话和技能

因此不需要重新构建一个空的 OpenClaw。旧 `/root` 挂载中的其他文件不会再整体映射；需要长期保留或供智能体处理的文件请移到 `/data0/opt/claw/shared`。

不要把旧 `workspace/skills` 整体复制到新 workspace。同名 workspace skill 的优先级高于镜像提供的 managed skill 和 OpenClaw bundled skill，会导致新版被旧副本覆盖。

宿主机的 `/data0/opt/claw/shared` 以只读方式挂载到 agent workspace：

`/home/node/.openclaw/workspace/shared-readonly`

OneDrive 的 download-only 副本也以只读方式挂载：

`/home/node/.openclaw/workspace/onedrive-readonly`

智能体可以从这两个目录查找和发送文件，但不能修改原文件。启动脚本会创建可写的输出目录：

`/home/node/.openclaw/workspace/outputs`

需要轻量修改时，先把原文件复制到 `outputs`，再修改并发送副本。

完成 onboarding 后，在 workspace 的 `AGENTS.md` 中加入：

```markdown
## Read-only files

- `shared-readonly/` is the read-only view of files shared from the host.
- `onedrive-readonly/` is the read-only view of the OneDrive download-only backup.
- Search, read, and send files directly from either read-only directory.
- Never try to modify, move, or delete files in either read-only directory.
- To modify a file, copy it to `outputs/`, edit the copy, and send the copy.
```

升级前建议备份：

```bash
sudo tar -C /data0/opt/claw/jarvis -czf openclaw-state-backup.tgz .openclaw
```

## 验证文档技能

```bash
docker compose exec openclaw-jarvis \
  ls -l /home/node/.openclaw/skills
```

## 更新版本

修改 `.env` 中的锁定版本或 MiniMax commit SHA，重新构建镜像后再启动。不要在运行中的容器里执行全局自更新，因为容器重建会覆盖这类修改。
