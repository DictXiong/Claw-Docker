# Claw-Docker

面向单用户 OpenClaw 的 Docker 部署，包含本地文件检索和常用 Office 文档处理能力。

## 镜像包含

- OpenClaw（版本锁定在 `.env`）
- Node.js 24、Python 3
- `fd`、`ripgrep`、`jq` 等文件查找和文本处理工具
- Chromium / Playwright
- LibreOffice、Pandoc、Poppler、Python Office/PDF 库
- MiniMax 官方文档技能：`minimax-docx`、`minimax-pdf`、`minimax-xlsx`、`pptx-generator`

MiniMax 技能在构建时按 commit SHA 锁定，并在启动时链接到：

`/home/node/.openclaw/skills`

技能文件本体位于镜像的 `/opt/minimax-skills/skills`。持久化目录中只保存符号链接，因此重新构建镜像即可更新技能内容，不会复制或覆盖 workspace 文件。

`minimax-docx` CLI 会在独立构建阶段发布为自包含可执行文件，运行镜像不包含 .NET SDK，也不会在运行时编译源码。容器专用说明由 `patches/minimax-skills-openclaw.patch` 应用，上游 commit 更新后需要重新检查该补丁。

## 首次部署

先创建持久化目录：

```bash
sudo mkdir -p /data0/opt/claw/jarvis/.openclaw
```

Obsidian 双向同步目录以可写方式挂载。镜像中的 `node` 用户（UID/GID 1001）属于 `root` 附加组，因此宿主机目录保持 `root:root`，只需授予组读写和遍历权限：

```bash
sudo chown root:root /tank1/entity.backup1/Obsidian
sudo chmod 0770 /tank1/entity.backup1/Obsidian
```

Obsidian 中已有的子目录和文件也必须允许 `root` 组写入；同步程序新建内容时同样需要保留组写权限。不要对该目录执行递归 `chown`，启动脚本也会跳过此 bind mount。`node` 的附加组不会赋予 root 用户身份，只会应用普通的组权限。

不使用 ACL 时，应确保同步程序以 `umask 0002`（或等效设置）创建内容，使新目录和文件继续保留组写权限。

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

因此不需要重新构建一个空的 OpenClaw。旧的 `/data0/opt/claw/shared` 挂载不再使用。

不要把旧 `workspace/skills` 整体复制到新 workspace。同名 workspace skill 的优先级高于镜像提供的 managed skill 和 OpenClaw bundled skill，会导致新版被旧副本覆盖。

宿主机的双向同步 Obsidian 目录以可写方式挂载到 agent workspace：

`/home/node/.openclaw/workspace/obsidian`

OneDrive 的 download-only 副本也以只读方式挂载：

`/home/node/.openclaw/workspace/onedrive-readonly`

智能体可以直接查找、发送和修改 `obsidian` 中的文件；修改和删除会通过同步程序传播到其他设备。`onedrive-readonly` 中的原文件仍不可修改。启动脚本会创建可写的输出目录：

`/home/node/.openclaw/workspace/outputs`

需要修改 OneDrive 文件时，先把原文件复制到 `outputs`，再修改并发送副本。

完成 onboarding 后，在 workspace 的 `AGENTS.md` 中加入：

```markdown
## File locations

- `obsidian/` is the writable, bidirectionally synced Obsidian vault.
- You may search, read, create, and edit files in `obsidian/` when requested.
- Changes, moves, and deletions in `obsidian/` sync to other devices. Confirm before destructive or bulk operations.
- `onedrive-readonly/` is the read-only view of the OneDrive download-only backup.
- Search, read, and send files directly from `onedrive-readonly/`, but never modify, move, or delete them there.
- To modify a OneDrive file, copy it to `outputs/`, edit the copy, and send the copy.
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

## 发布镜像

`main` 分支中的镜像相关文件发生变化时，GitHub Actions 会构建 `linux/amd64` 镜像并推送到 `ghcr.io/dictxiong/claw-docker`。每次构建发布 OpenClaw 版本、完整 Git commit SHA 和 `latest` 三类标签；也可以在 Actions 页面手动触发。私有 package 在拉取前需要先登录 GHCR。
