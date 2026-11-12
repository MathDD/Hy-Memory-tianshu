# 天枢 fork 自建发行线

基于 `Tencent-Hunyuan/Hy-Memory` (Apache-2.0) 的自用 fork，分支 `tianshu`，版本 `1.0.6+tianshu2`（build_number 保持 45，与上游 v1.0.6 base 对齐，避免 schema 迁移歧义）。

## 改动概览

| 层 | 文件 | 改动 |
|---|---|---|
| 后端 | `apps/core/src/one_memory/imports/sources/tianshu.py` | 新增：descriptor + `RivetSourceAdapter` + parser（zstd 分帧 + `\|<hex>` 校验和剥离 + `.meta.json` 注入） |
| 后端 | `apps/core/src/one_memory/imports/readers.py` | `read_zstd_jsonl` 加 `decode` 回调；新增 `read_rivet_jsonl` |
| 后端 | `apps/core/src/one_memory/imports/sources/registry.py` | 注册 tianshu，candidate `~/.rivet/sessions` |
| 后端 | `apps/core/src/one_memory/imports/sources/common.py` | `JsonlSourceAdapter` 加 `_is_zstd_framed` / `_reader_for` 钩子，三处 `.endswith(".zstd")` 改走钩子 |
| 后端 | `apps/core/src/one_memory/imports/access.py` | `_supports_descriptor_relative_open` 加运行时探测，绕过 stock macOS CPython 不广告 `dir_fd` 的静态集合问题 |
| 宿主 | `packages/host-bridge/src/recall-installer.ts` | 新增 `tianshuLayout`：`format:"json"` + `serversPath:["mcp","servers"]`，目标 `~/.rivet/config.json`（与 Claude Code / Codex 同一条原生安装链） |
| 宿主 | `packages/host-bridge/src/recall-installer.ts` | `RecallHostLayout.serversPath`：JSON 配置里 server map 不在顶层 `mcpServers` 时的路径；`serverPath()` 优先读它 |
| 宿主 | `packages/host-bridge/src/installer-cli.ts` | `HOSTS` 与 `resolveLayout` 加 `tianshu` |
| 后端 | `apps/core/src/one_memory/imports/sources/tianshu.py` | `_is_zstd_framed` 改为嗅探 `28 b5 2f fd` 魔数；`file_predicate` 只认 `sessions/` 顶层的 `<id>.jsonl`，跳过每会话子目录里的 `frames.jsonl` / `cache-log.jsonl` / `tool-result-trace.jsonl` 等宿主工作文件 |
| 宿主 | `packages/runtime-control/src/recall-hosts.ts` | 注册 tianshu，`RIVET_HOME` 覆盖，presence `~/.rivet` |
| 前端 | `apps/web/src/app-mark.tsx` | 图标表加 `tianshu` / `rivet` |
| 前端 | `apps/web/src/call-history-client.ts` | `CALL_HOSTS` 加 `tianshu: "天枢"` |
| 前端 | `apps/web/src/connection-hosts.ts` | `SOURCE_HOST` 加 `tianshu` |
| 前端 | `apps/web/public/r6/tianshu.svg` | 图标 |
| 版本 | 全部 `package.json` + `pyproject.toml` + `uv.lock` | `1.0.6` → `1.0.6+tianshu1` |

## 自用构建（免签名 dir 包）

```sh
cd ~/Projects/Hy-Memory-tianshu/memhub

# 1. 装依赖（首次）
uv sync --directory apps/core --python 3.12
pnpm install --frozen-lockfile

# 2. 打 core + web + desktop → 免签名 .app dir 包
pnpm package:mac:dev
# 产物：apps/desktop/dist/<...>.app（未签名，本机可跑）
```

dir 包不签名、不公证，仅本机自用。要替换 managed install：

```sh
# 停掉官方 runtime
memhub stop

# 把 dir 包里的 runtime 拷到 managed 位置（备份原 current）
CUR=$(readlink "/Users/apple/Library/Application Support/One Memory/current")
mv "/Users/apple/Library/Application Support/One Memory/$CUR" \
   "/Users/apple/Library/Application Support/One Memory/$CUR.bak"
cp -R apps/desktop/dist/<...>.app/Contents/Resources/core \
     "/Users/apple/Library/Application Support/One Memory/$CUR"

memhub start
```

`memhub upgrade` 会覆盖自建版本——升级时先 `git pull upstream` + 重新 `package:mac:dev` 再手动替换。

## 上游监控

```sh
# 拉取上游，列出 base 以来的新提交 + 版本/schema 变化
bash scripts/tianshu/upstream-monitor.sh
```

输出：
- upstream/main 自 `v1.0.6` 以来的提交数与标题
- `apps/core` 的 schema_version / build_number 是否变化（决定能否平滑跟随）
- 建议的 rebase 或 cherry-pick 动作

跟随上游：

```sh
git fetch upstream
git checkout tianshu
git rebase upstream/main   # 或 git merge upstream/main
# 解冲突后重跑：uv sync --directory apps/core --python 3.12 && pnpm package:mac:dev
```

## 验证记录（本机）

- `/api/v1/sources` 含 `tianshu`，display_name=「天枢」，candidate=`~/.rivet/sessions`，location_state=found
- adapter probe：detected=true，session_count=15328，ready=true
- 单文件 `adapter.scan()` 全链路：6 条 evidence（user/assistant/tool），role/written_by/workspace/created_at 全部正确解析自 `.meta.json`
- 18 个顶层会话 / 201 条记录独立解析通过，0 skip

## 已知限制

- **dir_fd**：本机 stock CPython 不广告 `os.open in os.supports_dir_fd`，已用运行时探测绕过（`access.py`）。若用 python.org 3.12 构建 core，静态集合本身就为真，探测自动短路。
- **recall install**：`~/.rivet/config.json` 的 `mcp.servers` 已被证实是宿主自己也会写的普通 JSON 段，因此 tianshu 现在与原生 host 一样由 MemHub 写入 `one-memory` 条目（带 `tianshu` 身份凭据）。写入后需重启天枢（或新开一个会话）才会拉起新的 MCP 进程。
- **历史误归类**：此前用「自定义应用」发放的 `custom-<hash>` 凭据写入的记忆，来源会被记成 `default`（页面显示「未识别来源」），换成 `tianshu` 凭据后只对**新写入**生效，旧条目不会自动改写。
- **harness preamble**：天枢会话首条 user 消息常是 harness 注入的团队指令（origin 非 `hook`），会被当作 person 消息入库。后续可在 parser 加首条检测，或交给抽取层过滤。
