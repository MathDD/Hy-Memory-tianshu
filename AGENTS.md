# AGENTS.md — 这个 fork 的约束（先读再改）

仓库 `MathDD/Hy-Memory-tianshu` 是基于 `Tencent-Hunyuan/Hy-Memory` (Apache-2.0) 的自用 fork，分支 `tianshu`，相对上游多了一条原生来源 + 宿主：**天枢 (Rivet)**。

- 上游：`upstream` = `Tencent-Hunyuan/Hy-Memory`，**只 fetch 不 push**
- 自建发行线全流程：`memhub/scripts/tianshu/README.md`
- 版本：`<上游 version>+tianshu<N>`，`build_number` 与上游 base 对齐（当前 45）

> 改任何代码之前，先扫一眼下面「接线段清单」。天枢不是一处开关，是四条链路。

## 四条链路，断一条就出症状

```
读取  zstd 会话解析      imports/sources/tianshu.py + readers.py + common.py 钩子
  ↓
注册  source catalog    imports/sources/registry.py  (candidate ~/.rivet/sessions)
  ↓
安装  MCP 配置写入      host-bridge recall-installer.ts + installer-cli.ts + recall-hosts.ts
  ↓
归因  调用/记忆归属      call_event_recorder.HOSTS + call_event_store.HostId + web 两处映射
```

| 断掉的链路 | 用户看到的现象 |
|---|---|
| 读取 | `sources connect` 报 500 `zstd: Unknown frame descriptor`，导入 0 条 |
| 注册 | 应用列表里没有「天枢」，「来源」下拉没有这一项 |
| 安装 | 应用详情显示「已冻结 / 读取授权已失效 / 一键接入未完成」 |
| 归因 | 记忆显示「未识别来源」，调用记录 `host_id` 为 null |

## 接线段清单（改这些文件会伤到天枢）

| 文件 | 天枢在此加了什么 | 删了/覆盖了的后果 |
|---|---|---|
| `apps/core/src/one_memory/imports/sources/tianshu.py` | **fork 独有**：descriptor、`RivetSourceAdapter`、`parse_rivet_record`、zstd 魔数嗅探、sidecar 过滤 | 整条链路消失 |
| `imports/readers.py` | `read_zstd_jsonl(..., decode=)` 回调、`read_rivet_jsonl`、`\|<hex>` 校验后缀剥离 | 会话解析失败 |
| `imports/sources/common.py` | `JsonlSourceAdapter._is_zstd_framed()` / `_reader_for()` 两个钩子；三处 `.endswith(".zstd")` 改走钩子 | 明文 `.jsonl` sidecar 被当 zstd 读，整个扫描崩 |
| `imports/sources/registry.py` | `default_source_registrations()` 里 tianshu 条目，`verification=real_replayed` | 源目录里没有天枢 |
| `imports/access.py` | `_supports_descriptor_relative_open()` 运行时探测（stock macOS CPython 不广告 `os.open` 的 `dir_fd`） | 本机所有源读取失败 |
| `call_event_recorder.py` | `HOSTS` 白名单加 `tianshu` | 调用 `host_id` 恒为 null |
| `call_event_store.py` | `HostId` Literal 加 `tianshu` | 同上，写入被拒 |
| `workspace_resolution.py` | `PATH_WORKSPACE_SOURCES` 加 `tianshu`（adapter 原样存 cwd） | workspace 被误归一 |
| `packages/host-bridge/src/recall-installer.ts` | `RecallHostLayout.serversPath` 字段、`tianshuLayout()`、`serverPath()` 分支 | 安装器找不到 `mcp.servers`，安装永不完成 |
| `packages/host-bridge/src/installer-cli.ts` | `HOSTS` 数组与 `resolveLayout()` 加 `tianshu` | CLI 不认这个 host |
| `packages/runtime-control/src/recall-hosts.ts` | host 条目、`RIVET_HOME` 覆盖、presence `~/.rivet` | 页面看不到天枢连接状态 |
| `apps/web/src/app-mark.tsx` | `APP_ICON_BY_ID` 加 `tianshu`/`rivet`，`SVG_ICONS` 决定后缀 | 图标退化成首字母 |
| `apps/web/src/call-history-client.ts` | `CALL_HOSTS` 加 `tianshu: "天枢"` | 调用记录页抛 `call_history_unavailable` |
| `apps/web/src/connection-hosts.ts` | `SOURCE_HOST` 加 `tianshu` | 连接页归属错乱 |
| `apps/core/tests/core_test_classification.py` | 测试清单指纹（计数 + sha256） | 加/删测试文件后全量测试直接拒跑 |

## 三条硬约束

1. **白名单三处必须同步**：`call_event_recorder.HOSTS`、`call_event_store.HostId`、`workspace_resolution.PATH_WORKSPACE_SOURCES`。只加一处 = 半残，报错还很隐蔽（`host_id` 静默为 null）。
2. **`.jsonl` 不等于 zstd**：读之前嗅探 `28 b5 2f fd`。天枢的 `~/.rivet/sessions/` 顶层是 zstd 帧，每个会话子目录里却是明文 sidecar（`frames.jsonl`、`cache-log.jsonl`、`tool-result-trace.jsonl`、`*.claims.jsonl`），`tianshu.py` 的 `file_predicate` 只认顶层 `<id>.jsonl`。
3. **`build_number` 是单向门**：`~/.one-memory` 会按它前向迁移、不可回退。不要顺手加一；要动先在隔离目录验证（见下）。

## 改完必须验证

```sh
# 1. 单测（隔离目录，绝不碰真实 ~/.one-memory）
cd ~/Projects/Hy-Memory-tianshu/memhub/apps/core
rm -rf /tmp/om-up && mkdir -p /tmp/om-up/{home,data,tmp}
env ONE_MEMORY_TEST_ISOLATED=1 HOME=/tmp/om-up/home \
    ONE_MEMORY_DATA_DIR=/tmp/om-up/data TMPDIR=/tmp/om-up/tmp \
    .venv/bin/python -m pytest tests/test_tianshu_source.py \
      tests/test_call_event_recorder.py tests/test_source_registry_and_grants.py -q

# 2. 端到端冒烟（重打完 app 之后）
cd ~/Projects/Hy-Memory-tianshu/memhub && bash scripts/tianshu/smoke.sh
```

`smoke.sh` 五项：服务在线、sources 含天枢、host list 含「天枢」、真实 zstd 会话可解析、最近一次调用 `host_id=tianshu`。**五项全过才算没弄坏。**

## 上游更新时（核心问题）

```sh
cd ~/Projects/Hy-Memory-tianshu/memhub
bash scripts/tianshu/upstream-monitor.sh    # 冲突预演 + 接线点是否被改 + build_number 门
git fetch upstream --tags
git checkout tianshu
git rebase upstream/main                    # 不 merge
```

冲突解决原则，**永远保天枢这一侧**：

| 冲突文件 | 怎么解 |
|---|---|
| `imports/readers.py` | 上游新逻辑 + 我们的 `decode` 回调形参和 `read_rivet_jsonl` |
| `host-bridge/src/recall-installer.ts` | 上游新 host 布局 + `serversPath` + `tianshuLayout` + `serverPath()` 分支 |
| `tests/core_test_classification.py` | **取上游值**（它不是逻辑，是防篡改计数），再按测试报错自报的新值改 |
| `.github/workflows/ci.yml` | 取上游版；push 报 workflow scope 时 `git checkout origin/main -- .github/workflows/ci.yml` |

`upstream-monitor.sh` 会明确列出「上游动过的接线点」，那些文件 rebase 后**必须逐行复核**，不是解完冲突就完事。完整流程与 build_number 取舍见 `memhub/scripts/tianshu/README.md`。

## 不要做

- 不要 `git merge upstream/main`——历史会变成一堆巨型 merge commit，后续 rebase 无法定位天枢改动。
- 不要为了跑测试去动真实的 `~/.one-memory`；一律用上面的隔离 env。
- 不要把 `plugins/` 从 sparse-checkout 去掉——`host-bridge` 的 `build-hermes-provider-assets.mjs` 要读 `plugins/hermes`，缺了 `pnpm -r build` 直接失败。
- 重建 core 前先 `mv apps/core/dist/one-memory-runtime <别处>`——批量删除会被 safe-delete 拦。
- 改了 core 但托管目录 hash 没变时，App 仍起旧 core；必须把 `~/Library/Application Support/One Memory/current` 指向的目录挪走再重启。
- 别把 `~/.rivet/config.json` 的 `mcp.servers.one-memory` 手写成 `format:"none"` 那套（Pi 的形状）——天枢有配置文件，安装器必须走 `json` 格式才能完成。

## 排查顺序（症状 → 先看哪）

| 症状 | 先看 |
|---|---|
| 「已冻结」 | `one-memory host status --host tianshu`，再看 `recall-installer.ts` 的 `tianshuLayout` |
| 「未识别来源」 | `sqlite3 ~/.one-memory/one-memory.sqlite3 "select host_id,count(*) from call_events group by 1"`，null 就是白名单问题 |
| 导入 500 | `~/.one-memory/logs/service-error.log` 里的 `zstd` 字样，查 `_is_zstd_framed` 与 `file_predicate` |
| 页面没天枢 | `curl /api/v1/sources`，没有就是 `registry.py` |
