# 天枢 fork 自建发行线

基于 `Tencent-Hunyuan/Hy-Memory` (Apache-2.0) 的自用 fork：远端 `MathDD/Hy-Memory-tianshu`，分支 `tianshu`，版本 `1.0.6+tianshu2`，`build_number` 对齐上游 base 的 **45**（不跟 47，避开单向迁移）。

- `origin`  = `https://github.com/MathDD/Hy-Memory-tianshu.git`（自己的）
- `upstream`= `https://github.com/Tencent-Hunyuan/Hy-Memory.git`（只 fetch，不 push）
- 工作区 `sparse-checkout = memhub plugins`（`plugins/` 是 host-bridge 构建必需，见下）

## 改动概览

| 层 | 文件 | 改动 |
|---|---|---|
| 后端 | `apps/core/src/one_memory/imports/sources/tianshu.py` | **新增**：descriptor + `RivetSourceAdapter` + parser（zstd 分帧 + `\|<hex>` 校验和剥离 + `.meta.json` 注入 meta）；`_is_zstd_framed` 嗅探 `28 b5 2f fd` 魔数；`file_predicate` 只认 `sessions/` 顶层 `<id>.jsonl`，跳过 `frames.jsonl` / `cache-log.jsonl` / `tool-result-trace.jsonl` / `*.claims.jsonl` |
| 后端 | `apps/core/src/one_memory/imports/readers.py` | `read_zstd_jsonl` 加 `decode` 回调；新增 `read_rivet_jsonl` |
| 后端 | `apps/core/src/one_memory/imports/sources/common.py` | `JsonlSourceAdapter` 加 `_is_zstd_framed` / `_reader_for` 钩子，三处 `.endswith(".zstd")` 改走钩子 |
| 后端 | `apps/core/src/one_memory/imports/sources/registry.py` | 注册 tianshu，candidate `~/.rivet/sessions`，verification=`real_replayed` |
| 后端 | `apps/core/src/one_memory/imports/access.py` | `_supports_descriptor_relative_open` 改运行时探测（stock macOS CPython 不在 `supports_dir_fd` 里广告 `os.open`） |
| 后端 | `apps/core/src/one_memory/call_event_recorder.py` | `HOSTS` 白名单加 `tianshu` |
| 后端 | `apps/core/src/one_memory/call_event_store.py` | `HostId` Literal 加 `tianshu` |
| 后端 | `apps/core/src/one_memory/workspace_resolution.py` | `PATH_WORKSPACE_SOURCES` 加 `tianshu`（adapter 原样存 cwd） |
| 宿主 | `packages/host-bridge/src/recall-installer.ts` | `RecallHostLayout.serversPath`（server map 不在顶层 `mcpServers` 时的路径）；`tianshuLayout`：`format:"json"`、`configPath=~/.rivet/config.json`、`serversPath=["mcp","servers"]` |
| 宿主 | `packages/host-bridge/src/installer-cli.ts` | `HOSTS` 与 `resolveLayout` 加 `tianshu` |
| 宿主 | `packages/runtime-control/src/recall-hosts.ts` | 注册 tianshu，支持 `RIVET_HOME`，presence `~/.rivet` |
| 前端 | `apps/web/src/app-mark.tsx` | 图标表加 `tianshu` / `rivet`；`SVG_ICONS` 集合决定后缀 |
| 前端 | `apps/web/src/call-history-client.ts` | `CALL_HOSTS` 加 `tianshu: "天枢"`（缺则调用记录页抛 `call_history_unavailable`） |
| 前端 | `apps/web/src/connection-hosts.ts` | `SOURCE_HOST` 加 `tianshu` |
| 前端 | `apps/web/public/r6/tianshu.png` | 图标，从 `/Applications/Tianshu.app/Contents/Resources/icon.icns` 导出 256×256 |
| 测试 | `apps/core/tests/test_tianshu_source.py` | **新增**：zstd 转录 / 明文转录 / sidecar 跳过 |
| 测试 | `test_call_event_recorder.py`、`test_source_registry_and_grants.py`、`core_test_classification.py` | 归属断言 + catalog pin + 测试清单指纹（**每次上游加测试文件都会在这挂**） |
| 版本 | 全部 `package.json` + `pyproject.toml` + `uv.lock` | `1.0.6` → `1.0.6+tianshu2` |
| 脚本 | `scripts/tianshu/{upstream-monitor,smoke}.sh` | 上游监控 / 升级后冒烟 |

## 构建与安装

```sh
cd ~/Projects/Hy-Memory-tianshu/memhub

# 1. 依赖（首次或 lock 变动后）
uv sync --directory apps/core --python 3.12
pnpm install

# 2. 全部 JS 包（host-bridge 的 hermes provider assets 会读 plugins/，别把 plugins 从 sparse 里去掉）
NODE_OPTIONS= pnpm -r build

# 3. core 运行时（PyInstaller）——重建前必须把旧 dist 挪走，safe-delete 会拦批量删除
mv apps/core/dist/one-memory-runtime ~/om-dist-old-$(date +%H%M) 2>/dev/null
ONE_MEMORY_BUILD_NUMBER=45 pnpm build:core:mac

# 4. 打 app dir 包
NODE_OPTIONS= ONE_MEMORY_BUILD_NUMBER=45 bash scripts/run-desktop-package-mac-dir.sh
# 产物：apps/desktop/release/mac-arm64/MemHub.app

# 5. 安装（ditto 而非 cp -R，后者在 app.asar 上会 EPERM）
pkill -f "/Applications/MemHub.app/Contents/MacOS/MemHub"
ditto apps/desktop/release/mac-arm64/MemHub.app /Applications/MemHub-new.app
codesign --force --deep --sign - /Applications/MemHub-new.app
rm -rf /Applications/MemHub.app && mv /Applications/MemHub-new.app /Applications/MemHub.app
open -a /Applications/MemHub.app

# 6. 冒烟
bash scripts/tianshu/smoke.sh
```

**托管运行时缓存陷阱**：App 只在 `~/Library/Application Support/One Memory/versions/<hash>` 缺目录时才铺开 core。改了 core 但 hash 没变时，必须

```sh
cd "$HOME/Library/Application Support/One Memory"
mv "$(readlink current)" ~/om-old-managed-$(date +%H%M) && rm -f current
```

再重启 App，否则页面起来的还是旧 core。

## 上游升级 runbook

```sh
# 0. 先看上游动了什么，以及会不会撞车（只 fetch，不改工作区）
bash scripts/tianshu/upstream-monitor.sh
```

脚本给三件关键信息：

1. **冲突面** —— `git merge-tree` 预演的冲突文件。当前 base(v1.0.6) → upstream 的实测结果：
   - `.github/workflows/ci.yml`（我们为绕 workflow scope 同步过上游默认分支版本）
   - `apps/core/src/one_memory/imports/readers.py`（我们加了 `decode` 回调 + `read_rivet_jsonl`）
   - `apps/core/tests/core_test_classification.py`（测试文件清单指纹）
   - `packages/host-bridge/src/recall-installer.ts`（我们加了 `serversPath` + `tianshuLayout`）
2. **接线点是否被上游动过** —— `common.py` 钩子、`registry.py`、`call_event_recorder.py` 白名单、`recall-hosts.ts` 等。标 ⚠ 的必须人工复核。
3. **版本门** —— `build_number` 45→47 意味着跟随会触发**单向**数据迁移（`~/.one-memory` 前向升级、不能回退）。

### 跟随步骤

```sh
git fetch upstream --tags
git checkout tianshu
git rebase upstream/main      # 冲突只在上面那几处
```

冲突处理原则（**永远保住天枢这一侧**）：

| 文件 | 保留什么 |
|---|---|
| `readers.py` | 上游新逻辑 + 我们的 `decode` 回调形参和 `read_rivet_jsonl` |
| `recall-installer.ts` | 上游新 host 布局 + `serversPath` 字段 + `tianshuLayout` + `serverPath()` 里的分支 |
| `core_test_classification.py` | **直接取上游的指纹**（它不是逻辑，是防篡改计数），然后按脚本自报的新值改，别保留我们的旧值 |
| `ci.yml` | 取上游版本；若 push 报 workflow scope，`git checkout origin/main -- .github/workflows/ci.yml` |

rebase 完成后：

```sh
# 单测（隔离目录，别污染真实数据）
rm -rf /tmp/om-up && mkdir -p /tmp/om-up/{home,data,tmp}
cd apps/core && env ONE_MEMORY_TEST_ISOLATED=1 HOME=/tmp/om-up/home \
  ONE_MEMORY_DATA_DIR=/tmp/om-up/data TMPDIR=/tmp/om-up/tmp \
  .venv/bin/python -m pytest tests/test_tianshu_source.py tests/test_call_event_recorder.py \
  tests/test_source_registry_and_grants.py -q

# 版本号跟上游，但 build_number 自己定
#   version = <上游 version>+tianshu<N>，build_number = <本次决定的 build>
#   改完所有 package.json / pyproject.toml / uv.lock

# 重打 + 安装 + 冒烟（见上一节）
bash scripts/tianshu/smoke.sh
```

### build_number 要不要跟

| 选择 | 代价 |
|---|---|
| **跟（45→47）** | 拿到上游全部修复；但 `~/.one-memory` 会被迁移到新 schema，**旧版 App 回不去**。跟之前先把 `~/.one-memory` 整目录复制一份 |
| **不跟（保 45）** | 数据目录不动，随时能退回官方 b45；但上游 46/47 修的东西拿不到，且后续改动可能依赖新 schema |

建议：先在隔离数据目录验证——`HOME=/tmp/om-check ONE_MEMORY_DATA_DIR=/tmp/om-check/data` 起一次新 core，跑 `sources connect tianshu --import`，确认导入数与 `host status` 正常，再决定是否在真实目录上升。

## 接入步骤（与原生 host 同一条链）

```sh
# 1. 安装：MemHub 写 ~/.rivet/config.json 的 mcp.servers.one-memory（tianshu 身份凭据）
memhub host install --host tianshu            # 先预览 fingerprint
memhub host install --host tianshu --approve <fingerprint>

# 2. 授权 + 导入历史 + 开启持续同步
memhub sources connect tianshu --import --json

# 3. 重启天枢（或新开会话），让它拉起新的 MCP 进程
```

`应用详情` 里的「已冻结」来自「没有读授权 / 安装未完成」；两步做完即变成 `处理中`。

## 验证记录（本机，2026-11-12）

- `host status --host tianshu` → `approved`，scopes 含 `source:tianshu`
- `sources connect tianshu --import` → `committed`；history job `stored=172`、`errors=0`、`skipped=29`
- `memories list` 出现 12 条 `source=tianshu`，页面 `来源` 下拉出现「天枢」，「未识别来源」桶为空
- 用安装产出的凭据手动拉起 `mcp.cjs`，`tools/list` + `MemHub_recall` 正常；`call_events.host_id = tianshu`（修复前为 null）
- `sources list` 里 `capabilities.verification = real_replayed`
- `smoke.sh` 5 项全过

## 已知限制

- **dir_fd**：本机 stock CPython 不广告 `os.open in os.supports_dir_fd`，已用运行时探测绕过（`access.py`）。python.org 3.12 构建时静态集合本身为真，探测自动短路。
- **旧托管运行时**：换 build 后 App 只在 `versions/<hash>` 缺目录时铺开；见上「托管运行时缓存陷阱」。
- **历史误归类**：此前用「自定义应用」发放的 `custom-<hash>` 凭据写入的记忆，来源记为 `default`（「未识别来源」），换 `tianshu` 凭据只对**新写入**生效。
- **harness preamble**：天枢会话首条 user 消息常是 harness 注入的团队指令，会被当作 person 消息入库；可在 parser 加首条检测或交给抽取层过滤。
- **测试清单指纹**：`core_test_classification.py` 里的 `EXPECTED_TEST_FILE_COUNT` / `EXPECTED_TEST_FILES_SHA256` 每加一个测试文件就失效，升级时按报错自报的新值更新。
