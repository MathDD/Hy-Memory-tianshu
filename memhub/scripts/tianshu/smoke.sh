#!/usr/bin/env bash
# 升级后冒烟：确认天枢的支持没被上游改动冲掉。
# 用法：bash scripts/tianshu/smoke.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="/Applications/MemHub.app/Contents/Resources/cli/one-memory.cjs"
PY="${ROOT}/apps/core/.venv/bin/python"
fails=0
cd "$ROOT"

ok()  { printf '  \033[32m+\033[0m %s\n' "$1"; }
bad() { printf '  \033[31mx\033[0m %s\n' "$1"; fails=$((fails+1)); }

echo "== 1. 运行时 =="
V=$(curl -s --max-time 5 http://127.0.0.1:8765/api/v1/health 2>/dev/null \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["version"])' 2>/dev/null)
if [[ -n "$V" ]]; then ok "服务在线，版本 ${V}"; else bad "服务不可达（8765），先启动 MemHub"; fi

echo "== 2. 源目录里有天枢 =="
SRC=$("$CLI" sources list --json 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("MISSING|"); raise SystemExit
src = [s for s in d.get("sources", []) if s.get("source_id") == "tianshu"]
if not src:
    print("MISSING|"); raise SystemExit
s = src[0]
cap = s.get("capabilities", {}) or {}
print("OK|%s authorized=%s sync=%s messages=%s verification=%s" % (
    s.get("display_name"), s.get("authorized"), s.get("sync_enabled"),
    s.get("imported_messages"), cap.get("verification")))
')
if [[ "${SRC%%|*}" == "OK" ]]; then ok "${SRC#*|}"; else bad "源目录里没有 tianshu（registry 注册被冲掉？）"; fi

echo "== 3. 宿主清单里有天枢 =="
if "$CLI" host list 2>/dev/null | grep -q "天枢"; then
  ok "host list 出现「天枢」"
else
  bad "host list 没有天枢（recall-hosts / installer-cli 被冲掉？）"
fi

echo "== 4. zstd 会话仍能解析 =="
if [[ -x "$PY" ]]; then
  OUT=$("$PY" -B - <<'PY'
import sys, glob
from pathlib import Path
sys.path.insert(0, "apps/core/src")
try:
    from one_memory.imports.sources.tianshu import RivetSourceAdapter
    from one_memory.imports.readers import read_rivet_jsonl

    class FakeFile:
        def __init__(self, p):
            self.path = Path(p)
            self.relative_path = Path(p).name
        def open_binary(self):
            return open(self.path, "rb")

    files = [f for f in sorted(glob.glob(str(Path.home() / ".rivet/sessions/*.jsonl")))
             if not f.endswith(".meta.json")]
    if not files:
        print("SKIP|~/.rivet/sessions 下没有会话")
        raise SystemExit
    sample = FakeFile(files[-1])
    # 不用 __init__：这里只需要那两个方法，避免构造一份 grant
    adapter = object.__new__(RivetSourceAdapter)
    framed = adapter._is_zstd_framed(sample)
    reader = adapter._reader_for(sample)
    n = 0
    for _ in read_rivet_jsonl(sample):
        n += 1
        if n >= 3:
            break
    print("OK|framed=%s reader=%s events=%d sample=%s" % (
        framed, reader.__name__, n, sample.relative_path))
except Exception as exc:
    print("FAIL|%s: %s" % (type(exc).__name__, exc))
PY
)
  case "${OUT%%|*}" in
    OK)   ok "${OUT#*|}" ;;
    SKIP) echo "  - ${OUT#*|}" ;;
    FAIL) bad "读取链路断了 —— ${OUT#*|}" ;;
    *)    bad "未预期输出：${OUT}" ;;
  esac
else
  echo "  - 无 core venv，跳过（uv sync --directory apps/core --python 3.12 后再跑）"
fi

echo "== 5. 调用归属仍是 tianshu =="
H=$(sqlite3 ~/.one-memory/one-memory.sqlite3 \
    "select coalesce(host_id,'<null>') from call_events order by occurred_at desc limit 1;" 2>/dev/null)
case "${H:-}" in
  tianshu) ok "最近一次调用 host_id=tianshu" ;;
  "")      echo "  - 还没有调用记录，跳过" ;;
  *)       bad "最近一次调用 host_id=${H}（HOSTS / HostId 白名单被冲掉？）" ;;
esac

echo
if [[ $fails -eq 0 ]]; then echo "冒烟通过：天枢接线完好"; else echo "有 ${fails} 项失败，按提示回看对应文件"; fi
exit $((fails > 0))
