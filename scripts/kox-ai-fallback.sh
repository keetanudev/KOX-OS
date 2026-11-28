#!/usr/bin/env bash
# kox-ai-fallback: probe the NVIDIA NIM free endpoint and say whether to wait,
# retry, or switch to a local model.
#
# Why: the NVIDIA NIM free tier (~40 RPM) shares GPU capacity with everyone
# else. A cold start can take 30-90 s and the queue can stall for minutes, so a
# hung OpenCode request usually means "not yet", not "broken".
#
# If requests hang: retry after 30 seconds before changing anything. If the
# stall repeats, switch model in /models to a local Ollama/LM Studio model or
# another provider.
#
# Usage:
#   kox-ai-fallback           cheap reachability probe (GET /v1/models)
#   kox-ai-fallback --deep    one-token chat completion (uses a little quota)
#   kox-ai-fallback --help
#
# The API key is read from $NVIDIA_API_KEY, then $NVIDIA_KEY_FILE, then
# ~/.config/opencode/nvidia.key (the same file opencode.json reads). The key is
# never printed.
#
# Exit codes: 0 responsive, 1 slow/queued/unreachable, 2 misconfigured.
set -u

BASE_URL="${NVIDIA_BASE_URL:-https://integrate.api.nvidia.com/v1}"
MODEL="${NVIDIA_MODEL:-z-ai/glm-5.3-flash}"
KEY_FILE="${NVIDIA_KEY_FILE:-$HOME/.config/opencode/nvidia.key}"
PROBE_TIMEOUT="${NVIDIA_PROBE_TIMEOUT:-15}"
DEEP_TIMEOUT="${NVIDIA_DEEP_TIMEOUT:-120}"
MODE="quick"

usage() {
    cat <<'EOF'
Usage: kox-ai-fallback [--deep] [--help]

  (no flags)  cheap reachability probe: GET /v1/models
  --deep      one-token chat completion; the only probe that sees the GPU queue
  --help      this text

Environment:
  NVIDIA_API_KEY       API key (takes precedence)
  NVIDIA_KEY_FILE      key file, default ~/.config/opencode/nvidia.key
  NVIDIA_BASE_URL      default https://integrate.api.nvidia.com/v1
  NVIDIA_MODEL         default z-ai/glm-5.3-flash
  NVIDIA_PROBE_TIMEOUT quick-probe timeout in seconds, default 15
  NVIDIA_DEEP_TIMEOUT  deep-probe timeout in seconds, default 120

If requests hang, retry after 30 seconds: the free tier queues for shared GPU
capacity. If it keeps stalling, switch to a local model in /models.

Exit codes: 0 responsive, 1 slow/queued/unreachable, 2 misconfigured.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --deep) MODE="deep" ;;
        --quick) MODE="quick" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "kox-ai-fallback: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

if ! command -v curl >/dev/null 2>&1; then
    echo "kox-ai-fallback: curl is required" >&2
    exit 2
fi

KEY="${NVIDIA_API_KEY:-}"
if [ -z "$KEY" ] && [ -r "$KEY_FILE" ]; then
    KEY="$(tr -d '\r\n' < "$KEY_FILE")"
fi
if [ -z "$KEY" ]; then
    echo "kox-ai-fallback: no API key." >&2
    echo "  Set NVIDIA_API_KEY or write the key to $KEY_FILE (chmod 600)." >&2
    exit 2
fi

advice_retry() {
    cat <<EOF
Next steps:
  1. Retry in 30 seconds. The free tier queues for shared GPU capacity and a
     cold start can take 30-90 s, so a stalled request often just needs another try.
  2. If it stalls again, switch model in /models: pick a local Ollama/LM Studio
     model or another provider.
  3. OpenCode retries a timed-out request up to 3 times by itself. This provider
     allows 180 s to the first byte and 600 s total per request.
EOF
}

advice_rate_limit() {
    cat <<EOF
The free tier allows roughly 40 requests per minute. Wait about 60 seconds,
then retry. If you are running subagents in parallel, lower the concurrency.
EOF
}

error_message() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.error.message // .message // empty' "$1" 2>/dev/null | head -1
    else
        head -c 300 "$1" | tr '\n' ' '
    fi
}

printf 'Endpoint: %s\nModel:    %s\n\n' "$BASE_URL" "$MODEL"

if [ "$MODE" = "quick" ]; then
    resp="$(curl -sS -o /dev/null --max-time "$PROBE_TIMEOUT" \
        -w '%{http_code} %{time_total}' \
        -H "Authorization: Bearer $KEY" \
        "$BASE_URL/models" 2>&1)"
    rc=$?

    if [ "$rc" -ne 0 ]; then
        case "$rc" in
            28) echo "TIMEOUT: no answer within ${PROBE_TIMEOUT}s." ;;
            6)  echo "DNS failure: cannot resolve the endpoint." ;;
            7)  echo "Connection refused: the endpoint is not reachable." ;;
            *)  echo "curl failed (exit $rc): $resp" ;;
        esac
        advice_retry
        exit 1
    fi

    code="${resp%% *}"
    secs="${resp##* }"
    case "$code" in
        200)
            echo "OK: /models answered in ${secs}s."
            echo "Reachability is fine. This does not test the GPU queue; run"
            echo "with --deep to measure a real completion."
            exit 0
            ;;
        401|403)
            echo "AUTH: the endpoint rejected the API key (HTTP $code)."
            echo "Re-check $KEY_FILE or regenerate the key at build.nvidia.com."
            exit 2
            ;;
        404)
            echo "HTTP 404: base URL looks wrong: $BASE_URL"
            exit 2
            ;;
        429)
            echo "RATE LIMIT: HTTP 429 after ${secs}s."
            advice_rate_limit
            exit 1
            ;;
        5*)
            echo "SERVER ERROR: HTTP $code after ${secs}s. NVIDIA-side problem."
            advice_retry
            exit 1
            ;;
        *)
            echo "UNEXPECTED: HTTP $code after ${secs}s."
            advice_retry
            exit 1
            ;;
    esac
fi

# --deep: one-token completion, the only probe that sees the GPU queue.
tmp="$(mktemp)" || exit 2
trap 'rm -f "$tmp"' EXIT

resp="$(curl -sS -o "$tmp" --max-time "$DEEP_TIMEOUT" \
    -w '%{http_code} %{time_total}' \
    -H "Authorization: Bearer $KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with OK\"}],\"max_tokens\":1,\"stream\":false}" \
    "$BASE_URL/chat/completions" 2>&1)"
rc=$?

if [ "$rc" -eq 28 ]; then
    echo "TIMEOUT: no completion from $MODEL within ${DEEP_TIMEOUT}s."
    echo "The request is still queued or the model is cold-starting."
    advice_retry
    exit 1
fi
if [ "$rc" -ne 0 ]; then
    echo "TRANSPORT: curl failed (exit $rc): $resp"
    advice_retry
    exit 1
fi

code="${resp%% *}"
secs="${resp##* }"
if [ "$code" = "200" ]; then
    echo "OK: completion in ${secs}s."
    if awk -v s="$secs" 'BEGIN { exit !(s < 10) }'; then
        echo "Responsive right now."
        exit 0
    elif awk -v s="$secs" 'BEGIN { exit !(s < 30) }'; then
        echo "Usable but slow: likely a cold start. Expect short waits."
        exit 0
    else
        echo "Very slow: the queue is busy. Expect timeouts on long prompts."
        advice_retry
        exit 1
    fi
fi

msg="$(error_message "$tmp")"
echo "FAILED: HTTP $code after ${secs}s${msg:+ — $msg}"
case "$code" in
    401|403) echo "Re-check the API key in $KEY_FILE."; exit 2 ;;
    404)     echo "Model '$MODEL' was not found on this endpoint. Check the exact NVIDIA model id."; exit 2 ;;
    429)     advice_rate_limit; exit 1 ;;
    *)       advice_retry; exit 1 ;;
esac
