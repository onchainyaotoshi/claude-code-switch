#!/usr/bin/env bash
# Tests for `ccm open <provider|model-id>` passthrough (issue: arbitrary OpenRouter model IDs)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
CCM="$ROOT/ccm.sh"
CCC="$ROOT/ccc"
TEST_HOME="$(mktemp -d)"
export HOME="$TEST_HOME"
export OPENROUTER_API_KEY=test-key
# Pre-seed config: otherwise ccm.sh's first run creates ~/.ccm_config from the
# template, whose placeholder OPENROUTER_API_KEY assignment would shadow the
# exported env var when the config is sourced inside the eval'd exports.
cat >"$TEST_HOME/.ccm_config" <<'EOF'
OPENROUTER_API_KEY=test-key
EOF

trap 'rm -rf "$TEST_HOME"' EXIT

failures=0
passes=0

# Clear any env left over by the parent session (this test may run inside
# a harness with ANTHROPIC_* exported). Without this, a failing ccm.sh
# leaves stale values behind and asserts can pass for the wrong reason.
clean_env() {
    unset ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_BASE_URL \
        ANTHROPIC_API_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY \
        ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL \
        ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL
}

fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

pass() {
    passes=$((passes + 1))
}

# -----------------------------------------------
# Test 1: raw model slug in `open` sets every model slot verbatim
# Production change that makes this fail: ccm.sh errors "unknown option"
# on args containing '/'; the `*/*` passthrough branch is missing.
# -----------------------------------------------
test_raw_slug_sets_all_model_slots() {
    clean_env
    eval "$(bash "$CCM" open anthropic/claude-opus-5)"
    local slug="anthropic/claude-opus-5"
    assert_env "ANTHROPIC_MODEL" "$slug"
    assert_env "ANTHROPIC_SMALL_FAST_MODEL" "$slug"
    assert_env "ANTHROPIC_DEFAULT_SONNET_MODEL" "$slug"
    assert_env "ANTHROPIC_DEFAULT_OPUS_MODEL" "$slug"
    assert_env "ANTHROPIC_DEFAULT_HAIKU_MODEL" "$slug"
    assert_env "CLAUDE_CODE_SUBAGENT_MODEL" "$slug"
    assert_env "ANTHROPIC_BASE_URL" "https://openrouter.ai/api"
    assert_env "ANTHROPIC_API_KEY" ""
    assert_env "ANTHROPIC_AUTH_TOKEN" "$OPENROUTER_API_KEY"
    clean_env
}

# -----------------------------------------------
# Test 2 (regression): existing preset keyword still works unchanged
# -----------------------------------------------
test_preset_deepseek_unaffected() {
    clean_env
    eval "$(bash "$CCM" open deepseek)"
    assert_env "ANTHROPIC_MODEL" "deepseek-v4-pro"
    assert_env "ANTHROPIC_BASE_URL" "https://openrouter.ai/api"
    clean_env
}

# -----------------------------------------------
# Test 3 (regression): unknown word without '/' still errors out
# -----------------------------------------------
test_unknown_word_without_slash_errors() {
    if bash "$CCM" open badword >/dev/null 2>&1; then
        fail "open badword: expected non-zero exit"
        return
    fi
    pass
}

# -----------------------------------------------
# Test 4 (ccc passthrough): ccc forwards the slug and claude args
# A fake `claude` shim on PATH stands in for the external CLI.
# -----------------------------------------------
test_ccc_forwards_slug_and_args() {
    local shim_dir
    shim_dir="$(mktemp -d)"
    cat >"$shim_dir/claude" <<'EOF'
#!/usr/bin/env bash
echo "SHIM_ARGS:$*"
EOF
    chmod +x "$shim_dir/claude"
    local out
    out="$(env -i PATH="$shim_dir:$PATH" HOME="$TEST_HOME" OPENROUTER_API_KEY=test-key \
        bash "$CCC" open anthropic/claude-opus-5 --dangerously-skip-permissions 2>&1)" || true
    rm -rf "$shim_dir"
    if ! grep -q "anthropic/claude-opus-5" <<<"$out"; then
        fail "ccc open <slug>: slug not in output: $out"
        return
    fi
    if ! grep -q "SHIM_ARGS:--dangerously-skip-permissions" <<<"$out"; then
        fail "ccc open <slug>: claude args not forwarded: $out"
        return
    fi
    pass
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

test_raw_slug_sets_all_model_slots
test_preset_deepseek_unaffected
test_unknown_word_without_slash_errors
test_ccc_forwards_slug_and_args

echo ""
echo "Tests: $passes passed, $failures failed"
[[ $failures -eq 0 ]]
