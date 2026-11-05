#!/usr/bin/env bash
# Tests for DeepSeek Flash/Pro alias mapping and settings writers.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
CCM="$ROOT/ccm.sh"
TEST_HOME="$(mktemp -d)"
export HOME="$TEST_HOME"

trap 'rm -rf "$TEST_HOME"' EXIT

failures=0
passes=0

fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

pass() {
    passes=$((passes + 1))
}

assert_env() {
    local name="$1" expected="$2"
    local actual="${!name:-}"
    if [[ "$actual" != "$expected" ]]; then
        fail "env $name: expected '$expected', got '$actual'"
        return
    fi
    pass
}

clean_env() {
    unset ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_BASE_URL \
        ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY \
        ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL \
        ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL_NAME \
        ANTHROPIC_DEFAULT_OPUS_MODEL_NAME ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME \
        CLAUDE_CODE_SUBAGENT_MODEL
}

write_config() {
    cat >"$TEST_HOME/.ccm_config"
}

# -----------------------------------------------
# Test 1: legacy config (only DEEPSEEK_MODEL) keeps that model in the
# flash/sonnet slot and maps Pro to the opus slot. Generic Claude
# OPUS_MODEL/HAIKU_MODEL must not leak into DeepSeek.
# Production change that makes this fail: deepseek branch falls back to
# ${OPUS_MODEL:-$ds_model} / ${HAIKU_MODEL:-$ds_model}.
# -----------------------------------------------
test_legacy_config_maps_flash_and_pro() {
    clean_env
    write_config <<'EOF'
DEEPSEEK_API_KEY=sk-test
DEEPSEEK_MODEL=deepseek-v4-flash-vision-exp
OPUS_MODEL=claude-opus-4-6
HAIKU_MODEL=claude-haiku-4-5-20251001
EOF
    eval "$(bash "$CCM" deepseek)"
    assert_env "ANTHROPIC_MODEL" "deepseek-v4-flash-vision-exp"
    assert_env "ANTHROPIC_DEFAULT_SONNET_MODEL" "deepseek-v4-flash-vision-exp"
    assert_env "ANTHROPIC_DEFAULT_OPUS_MODEL" "deepseek-v4-pro"
    assert_env "ANTHROPIC_DEFAULT_HAIKU_MODEL" "deepseek-v4-flash-vision-exp"
    assert_env "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME" "DeepSeek Flash"
    assert_env "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME" "DeepSeek Pro"
    assert_env "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME" "DeepSeek Flash (fast)"
    assert_env "CLAUDE_CODE_SUBAGENT_MODEL" "deepseek-v4-flash-vision-exp"
    clean_env
}

# -----------------------------------------------
# Test 2: explicit DEEPSEEK_FLASH_MODEL / DEEPSEEK_PRO_MODEL drive the slots.
# -----------------------------------------------
test_explicit_flash_and_pro_models() {
    clean_env
    write_config <<'EOF'
DEEPSEEK_API_KEY=sk-test
DEEPSEEK_MODEL=deepseek-v4-pro
DEEPSEEK_FLASH_MODEL=deepseek-flash
DEEPSEEK_PRO_MODEL=deepseek-v4-pro
EOF
    eval "$(bash "$CCM" deepseek)"
    assert_env "ANTHROPIC_MODEL" "deepseek-v4-pro"
    assert_env "ANTHROPIC_DEFAULT_SONNET_MODEL" "deepseek-flash"
    assert_env "ANTHROPIC_DEFAULT_OPUS_MODEL" "deepseek-v4-pro"
    assert_env "ANTHROPIC_DEFAULT_HAIKU_MODEL" "deepseek-flash"
    assert_env "CLAUDE_CODE_SUBAGENT_MODEL" "deepseek-flash"
    clean_env
}

# -----------------------------------------------
# Test 3: `ccm project deepseek` writes JSON with the same DeepSeek slots
# and display names, and must not inherit Claude model IDs.
# -----------------------------------------------
test_project_settings_deepseek() {
    local project_dir
    project_dir="$(mktemp -d)"
    write_config <<'EOF'
DEEPSEEK_API_KEY=sk-test
DEEPSEEK_MODEL=deepseek-v4-pro
DEEPSEEK_FLASH_MODEL=deepseek-flash
DEEPSEEK_PRO_MODEL=deepseek-v4-pro
OPUS_MODEL=claude-opus-4-6
HAIKU_MODEL=claude-haiku-4-5-20251001
EOF
    ( cd "$project_dir" && bash "$CCM" project deepseek ) >/dev/null 2>&1
    local settings="$project_dir/.claude/settings.local.json"
    if [[ ! -f "$settings" ]]; then
        fail "project settings not written: $settings"
        rm -rf "$project_dir"
        return
    fi
    if ! python3 -I - "$settings" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
env = data.get("env", {})
expected = {
    "ANTHROPIC_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-flash",
    "CLAUDE_CODE_SUBAGENT_MODEL": "deepseek-flash",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "DeepSeek Flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "DeepSeek Pro",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME": "DeepSeek Flash (fast)",
}
bad = {k: (v, env.get(k)) for k, v in expected.items() if env.get(k) != v}
if bad:
    print("mismatched:", bad, file=sys.stderr)
    sys.exit(1)
PY
    then
        fail "project settings env mismatched"
    else
        pass
    fi
    rm -rf "$project_dir"
}

# -----------------------------------------------
# Test 4: `ccm user deepseek` writes the same slots to user settings.
# -----------------------------------------------
test_user_settings_deepseek() {
    write_config <<'EOF'
DEEPSEEK_API_KEY=sk-test
DEEPSEEK_MODEL=deepseek-v4-pro
DEEPSEEK_FLASH_MODEL=deepseek-flash
DEEPSEEK_PRO_MODEL=deepseek-v4-pro
OPUS_MODEL=claude-opus-4-6
HAIKU_MODEL=claude-haiku-4-5-20251001
EOF
    bash "$CCM" user deepseek >/dev/null 2>&1
    local settings="$TEST_HOME/.claude/settings.json"
    if [[ ! -f "$settings" ]]; then
        fail "user settings not written: $settings"
        return
    fi
    if ! python3 -I - "$settings" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
env = data.get("env", {})
expected = {
    "ANTHROPIC_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-flash",
    "CLAUDE_CODE_SUBAGENT_MODEL": "deepseek-flash",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "DeepSeek Flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "DeepSeek Pro",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME": "DeepSeek Flash (fast)",
}
bad = {k: (v, env.get(k)) for k, v in expected.items() if env.get(k) != v}
if bad:
    print("mismatched:", bad, file=sys.stderr)
    sys.exit(1)
PY
    then
        fail "user settings env mismatched"
    else
        pass
    fi
    rm -f "$settings"
}

# -----------------------------------------------
# Test 5 (regression): `ccm claude` still honours OPUS_MODEL / HAIKU_MODEL.
# -----------------------------------------------
test_claude_provider_unaffected() {
    clean_env
    write_config <<'EOF'
CLAUDE_API_KEY=sk-test
CLAUDE_MODEL=claude-sonnet-4-5-20250929
OPUS_MODEL=claude-opus-4-6
HAIKU_MODEL=claude-haiku-4-5-20251001
EOF
    export CLAUDE_API_KEY=sk-test
    eval "$(bash "$CCM" claude)"
    assert_env "ANTHROPIC_MODEL" "claude-sonnet-4-5-20250929"
    assert_env "ANTHROPIC_DEFAULT_OPUS_MODEL" "claude-opus-4-6"
    assert_env "ANTHROPIC_DEFAULT_HAIKU_MODEL" "claude-haiku-4-5-20251001"
    assert_env "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME" ""
    clean_env
}

test_legacy_config_maps_flash_and_pro
test_explicit_flash_and_pro_models
test_project_settings_deepseek
test_user_settings_deepseek
test_claude_provider_unaffected

echo ""
echo "Tests: $passes passed, $failures failed"
[[ $failures -eq 0 ]]
