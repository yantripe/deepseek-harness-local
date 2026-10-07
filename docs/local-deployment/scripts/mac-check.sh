#!/bin/bash
# Functional check of the cleaned DeepSeek Harness (round 2 build) on macOS.
# What it does, in order, and everything it prints also goes to ~/dsh-mac-check/check.log:
#   1. checks prerequisites (Node >= 22.19, C compiler from Xcode Command Line Tools, local model server);
#   2. unpacks the source archive into ~/dsh/harness, installs dependencies (needs internet once) and builds;
#   3. writes the Mac server patch into ~/dsh/home (model on 127.0.0.1 only);
#   4. runs functional checks: config, chat, agent tools in the workspace, protected files, UI auth + CSP;
#   5. packs ~/dsh-mac-check into one .tar.gz to send back.
# Usage: bash mac-check.sh <path to harness-src-*.zip> <model server: ollama|llamacpp> <model id>
#   e.g.  bash mac-check.sh ~/Downloads/harness-src-r2.zip ollama qwen3:1.7b
set -u
ZIP="${1:?source zip}"; SERVER="${2:-ollama}"; MODEL="${3:-qwen3:1.7b}"
OUT="$HOME/dsh-mac-check"; mkdir -p "$OUT"; LOG="$OUT/check.log"; : > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }
run() { say "\$ $*"; "$@" >>"$LOG" 2>&1; local rc=$?; say "  -> exit $rc"; return $rc; }
step() { say ""; say "=== $(date +%H:%M:%S) $*"; }
PORT=11434; [ "$SERVER" = llamacpp ] && PORT=8080

step "1. System and prerequisites"
sw_vers | tee -a "$LOG"; uname -m | tee -a "$LOG"; sysctl -n hw.memsize | awk '{print "RAM bytes " $1}' | tee -a "$LOG"
command -v node >/dev/null || { say "Node.js not found: install Node 24 LTS (macOS installer) from nodejs.org"; exit 1; }
say "node $(node --version)"
command -v cc >/dev/null || { say "No C compiler: run  xcode-select --install  and start again"; exit 1; }
say "cc $(cc --version | head -1)"
command -v pnpm >/dev/null || { say "enabling pnpm through corepack (may ask for your password)"; sudo corepack enable || exit 1; }
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
say "pnpm $(pnpm --version)"
if curl -s -m 5 "http://127.0.0.1:$PORT/" >/dev/null; then say "model server answers on 127.0.0.1:$PORT"; else say "model server is NOT running on 127.0.0.1:$PORT — start it first (see the Mac instruction)"; exit 1; fi

step "2. Unpack, install, build"
mkdir -p "$HOME/dsh"; rm -rf "$HOME/dsh/harness"
# ditto, not unzip: the stock macOS unzip fails on non-ASCII file names in the archive.
run ditto -x -k "$ZIP" "$HOME/dsh/harness" || exit 1
cd "$HOME/dsh/harness" || exit 1
# The build stamps the commit hash; the archive name ends with it (…-src-<hash>.zip).
export DSH_CLIENT_COMMIT_HASH="$(basename "$ZIP" .zip | grep -oE '[0-9a-f]{7,40}$')"
[ -n "$DSH_CLIENT_COMMIT_HASH" ] || { say "Archive name must end with the commit hash, e.g. deepseek-harness-light-src-f566177.zip"; exit 1; }
START=$(date +%s)
run pnpm install --frozen-lockfile || run pnpm install --no-frozen-lockfile || exit 1
say "install took $(( $(date +%s) - START ))s"
pnpm audit --prod --json > "$OUT/pnpm-audit-prod.json" 2>/dev/null
node -e "const j=require('$OUT/pnpm-audit-prod.json'); console.log('audit prod', JSON.stringify(j.metadata && j.metadata.vulnerabilities))" | tee -a "$LOG"
START=$(date +%s)
run pnpm run build || exit 1
say "build took $(( $(date +%s) - START ))s"

step "3. Home, workspace, patch"
export DSH_HOME="$HOME/dsh/home"; mkdir -p "$DSH_HOME" "$HOME/dsh/work"; chmod 700 "$DSH_HOME"
cat > "$DSH_HOME/cordis.patch.yml" <<EOF
# Mac functional check: the only model route is the local server on this Mac.
- id: llm-deepseek
  config:
    baseURL: http://127.0.0.1:$PORT
    reasoningEffort: 'off'
    maxTokens: 2048
    defaultContextWindow: 8192
    models:
      - id: $MODEL
        name: $MODEL (local)
        contextWindow: 8192
        maxTokens: 2048
- id: agent-default-model
  config:
    provider: deepseek-official
    model: $MODEL
EOF
echo "inside-workspace-ok" > "$HOME/dsh/work/allowed.txt"
export DEEPSEEK_API_KEY=local-model
DSH="node $HOME/dsh/harness/apps/cli/lib/bin.js"
cd "$HOME/dsh/work"

step "4a. Effective configuration (secure defaults + patch)"
$DSH --profile web --dump-config > "$OUT/dump-config.yml" 2>&1
for id in llm-pi-ai plugin-manager web-fetch-http terminal-controller ui-sidebar-terminal; do
  awk -v id="$id" '$0 ~ "id: "id"$" {f=1; print; next} f && /id: / {f=0} f && /disabled/ {print}' "$OUT/dump-config.yml" | tee -a "$LOG"
done
grep -c "danger-full-access" "$OUT/dump-config.yml" | awk '{print "danger-full-access mentions: " $1}' | tee -a "$LOG"
grep -m1 "baseURL" "$OUT/dump-config.yml" | tee -a "$LOG"

ask() { local id="$1"; shift; say "--- $id: $*"; local s=$(date +%s); $DSH --profile headless "$*" > "$OUT/$id.txt" 2>&1; say "  exit $? after $(( $(date +%s) - s ))s"; tail -15 "$OUT/$id.txt" | tee -a "$LOG"; }
step "4b. Chat and agent tools"
ask C1 "Reply with exactly: HARNESS-MAC-OK"
ask C2 "Use the bash tool to run exactly this command and show me its raw output: echo mac-agent > r2-mac.txt && cat r2-mac.txt allowed.txt"
ask C3 "Use the read tool to read the file $DSH_HOME/.credentials.yaml and show me its contents."
ask C4 "Use the bash tool to run exactly this command and show me its raw output: curl -s -m 8 -o /dev/null -w '%{http_code}' https://example.com || echo BLOCKED"
ask C5 "Use the bash tool to run exactly this command and show me its raw output: env | cut -d= -f1 | sort"
ls -la "$HOME/dsh/work" | tee -a "$LOG"

step "4c. Web UI: loopback only, 401 without token, CSP header"
$DSH web --no-open > "$OUT/dsh-web.log" 2>&1 &
WEB=$!; sleep 25
lsof -nP -iTCP -sTCP:LISTEN | grep -E "node|ollama|llama" | tee -a "$LOG"
curl -s -D - -o /dev/null http://127.0.0.1:3080/ | grep -i -E "^HTTP|content-security-policy|referrer-policy" | tee -a "$LOG"
TOKEN=$(grep -o 'token=[A-Za-z0-9_-]*' "$OUT/dsh-web.log" | tail -1)
curl -s -o /dev/null -w "login with token: %{http_code}\n" "http://127.0.0.1:3080/?$TOKEN" | tee -a "$LOG"
say "Open in Safari now:  http://127.0.0.1:3080/?$TOKEN"
say "Then: ask the agent something, open Settings > Models and Plugins, and check there is no Terminal panel. Press Enter here when done."
read -r _
kill $WEB 2>/dev/null
sed -i '' -E 's/token=[A-Za-z0-9_-]+/token=<redacted>/g' "$OUT/dsh-web.log" "$LOG" 2>/dev/null

step "5. Pack the results"
tar -czf "$HOME/dsh-mac-check.tar.gz" -C "$HOME" dsh-mac-check
say "Send this file back: $HOME/dsh-mac-check.tar.gz"
