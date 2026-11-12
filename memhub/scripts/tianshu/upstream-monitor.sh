#!/usr/bin/env bash
# 天枢 fork 上游监控：拉取 upstream，对比 fork 基线，报告版本/契约变化与 rebase 冲突面。
# 用法：bash scripts/tianshu/upstream-monitor.sh [base_ref]
#   base_ref 默认 v1.0.6（本 fork 的 base tag）；也可传上次跟随的 tag
set -euo pipefail

BASE_REF="${1:-v1.0.6}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # …/memhub
REPO="$(cd "${ROOT}/.." && pwd)"                              # 仓库根
# 仓库根下的应用全栈都在 memhub/ 里，git show 必须带这个前缀
PREFIX="memhub"
cd "$REPO"

UPSTREAM="upstream/main"
BRANCH="$(git branch --show-current)"

echo "== 拉取 upstream =="
git fetch upstream --tags 2>/dev/null || git fetch upstream

echo
echo "== ${UPSTREAM} 自 ${BASE_REF} 以来的提交 =="
echo "新增提交数：$(git rev-list --count "${BASE_REF}..${UPSTREAM}" 2>/dev/null || echo '?')"
git log --oneline --no-decorate "${BASE_REF}..${UPSTREAM}" 2>/dev/null | head -20

echo
echo "== 契约字段（决定能不能平滑跟随）=="
field() {
  local label="$1" rel="$2" pattern="$3"
  printf '  %-16s base=%-22s upstream=%-22s fork=%s\n' "$label" \
    "$(git show "${BASE_REF}:${PREFIX}/${rel}" 2>/dev/null | grep -Eo "${pattern}" | head -1 | tr -d ' ' || echo '(缺失)')" \
    "$(git show "${UPSTREAM}:${PREFIX}/${rel}" 2>/dev/null | grep -Eo "${pattern}" | head -1 | tr -d ' ' || echo '(缺失)')" \
    "$(grep -Eo "${pattern}" "${ROOT}/${rel}" 2>/dev/null | head -1 | tr -d ' ' || echo '(缺失)')"
}

field "root version"  "package.json"     '"version":[[:space:]]*"[^"]+"'
field "build_number"  "package.json"     '"build_number":[[:space:]]*[0-9]+'
field "hy-memory pin" "apps/core/pyproject.toml" 'hy-memory==[0-9.]+'
field "test files"    "apps/core/tests/core_test_classification.py" 'EXPECTED_TEST_FILE_COUNT[[:space:]]*=[[:space:]]*[0-9]+'

echo
echo "== rebase 冲突面 =="
if git merge-tree --write-tree "$BRANCH" "$UPSTREAM" >/tmp/mt-$$ 2>/dev/null; then
  echo "  无冲突：git rebase ${UPSTREAM} 可干净应用"
else
  echo "  冲突文件："
  grep -E '^(CONFLICT|Auto-merging)' /tmp/mt-$$ 2>/dev/null | sed 's/^/    /' | head -20
fi
rm -f /tmp/mt-$$

echo
echo "== 上游是否动过天枢的接线点 =="
# 这些是 fork 必须手工续接的地方：上游一改，天枢就得跟着改
for probe in \
  "apps/core/src/one_memory/imports/sources/common.py:JsonlSourceAdapter 钩子" \
  "apps/core/src/one_memory/imports/readers.py:zstd reader" \
  "apps/core/src/one_memory/imports/sources/registry.py:源注册表" \
  "apps/core/src/one_memory/call_event_recorder.py:宿主白名单" \
  "apps/core/src/one_memory/call_event_store.py:HostId 字面量" \
  "packages/host-bridge/src/recall-installer.ts:安装器布局" \
  "packages/runtime-control/src/recall-hosts.ts:宿主清单" ; do
  f="${probe%%:*}"; label="${probe#*:}"
  if git diff --quiet "${BASE_REF}" "${UPSTREAM}" -- "${PREFIX}/${f}" 2>/dev/null; then
    echo "  · ${label}：未变"
  else
    echo "  ⚠ ${label}：上游已改，需复核 —— ${f}"
  fi
done

echo
echo "== 版本门 =="
BN_BASE=$(git show "${BASE_REF}:${PREFIX}/package.json" 2>/dev/null | grep -Eo '"build_number":[[:space:]]*[0-9]+' | grep -Eo '[0-9]+' | head -1)
BN_UP=$(git show "${UPSTREAM}:${PREFIX}/package.json" 2>/dev/null | grep -Eo '"build_number":[[:space:]]*[0-9]+' | grep -Eo '[0-9]+' | head -1)
if [[ -n "${BN_BASE}" && -n "${BN_UP}" && "${BN_BASE}" != "${BN_UP}" ]]; then
  echo "  ⚠ build_number ${BN_BASE} → ${BN_UP}：跟随会触发一次性迁移（$HOME/.one-memory 会前向升级、不可回退）"
  echo "    先在隔离数据目录验证：HOME=/tmp/om-upstream-check ONE_MEMORY_DATA_DIR=/tmp/om-upstream-data"
else
  echo "  build_number 未变，数据目录不受影响"
fi

cat <<'ADVICE'
== 下一步 ==
  1) 看上面「冲突面」和「接线点」，只有这几类需要手工续接
  2) 跟随：git checkout tianshu && git rebase upstream/main
  3) 重打：uv sync --directory apps/core --python 3.12 && pnpm install && pnpm -r build
           ONE_MEMORY_BUILD_NUMBER=<上游 build> pnpm build:core:mac
           bash scripts/run-desktop-package-mac-dir.sh
  4) 冒烟：bash scripts/tianshu/smoke.sh
ADVICE
