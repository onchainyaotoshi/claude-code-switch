:memo: Add a new direct provider to Claude Code Switch (ccm).

Use this skill when the user wants to add a new provider (e.g., "add provider X" or "integrate API Y").

## Pre-flight

1. Ask the user for the provider name/alias, base URL, default model, and auth env var name if they haven't provided them.
2. Check if the provider needs region handling (global/china). Most don't.
3. Verify the **exact model ID** with the provider's dashboard/documentation — including casing. Some gateways are **case-sensitive**: on HCNSEC, `DeepSeek-V4-Pro` is accepted but `deepseek-v4-pro` returns `model_not_found` (HTTP 503). Copy the ID character-for-character.
4. The default model ID must be **byte-identical in every site** that references it, or you ship a latent bug that only bites users whose `PROVIDER_MODEL` is unset. When you set or correct the ID, update **all** of these in `ccm.sh` together:
   - `load_config()` template · `create_default_config()` template
   - `get_provider_config()` fallback (`${PROVIDER_MODEL:-<id>}`)
   - `emit_env_exports()` fallback (`${PROVIDER_MODEL:-<id>}`) ← **most commonly missed**
   - `ensure_model_override_defaults()` pair
   - `show_help()` provider line
   A partial fix is the exact failure mode that bit HCNSEC: commit `80ebb7b` corrected five sites but left the `emit_env_exports()` fallback lowercase, which only surfaced when a user's `HCNSEC_MODEL` was empty.
5. Confirm the design in chat before editing — this is a bounded, multi-file change.

## Files to edit

Update in this order:

1. **`ccm.sh`**
   - Add `PROVIDER_API_KEY=your-provider-api-key` and `PROVIDER_MODEL=<default>` placeholders to both `load_config()` and `create_default_config()` templates.
   - Add a branch in `emit_env_exports()` that exports `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, and default models.
   - Add a branch in `get_provider_config()` for `ccm user <provider>` / `ccm project <provider>`.
   - Add the API key to `show_status()`.
   - Add to `show_help()`, `project_show_usage()`, and `user_show_usage()`.
   - Add `PROVIDER_MODEL=<default>` to `ensure_model_override_defaults()`.
   - Add the provider to `main()` router and to the provider lists inside the `project` and `user` subcommands.

2. **`ccc`** (repo-local launcher)
   - Add the provider to `is_known_model()`.
   - Update the usage model list.

3. **`install.sh`**
   - Add the provider to every `_is_known_model()` / `is_known_model()` case list (there are multiple injection sites).
   - Update every usage model list in the generated `ccc()` function.

4. **`README.md` and `README_CN.md`**
   - Add to quick-start, first-time config, basic usage, providers table, user/project examples, full config example, and What's New.

5. **`CHANGELOG.md`**
   - Add a version entry (usually patch bump) describing the new provider.

6. **Bump version** in `ccm.sh` if appropriate (e.g., `v2.3.0` → `v2.3.1`).

## Verification

Run these before committing:

```bash
bash -n ccm.sh
bash -n ccc
bash -n install.sh
export PROVIDER_API_KEY="sk-test123"
eval "$(./ccm <provider>)"
echo "BASE_URL=$ANTHROPIC_BASE_URL MODEL=$ANTHROPIC_MODEL"
./ccm help | grep <provider>
./ccm project help | grep <provider>
./ccm user help | grep <provider>
```

**Exercise the fallback in isolation.** The `eval` test above can pull `PROVIDER_MODEL` from your own `~/.ccm_config` and never hit the `${PROVIDER_MODEL:-<id>}` fallback — which is how the HCNSEC casing bug hid through a release. Force the fallback to fire with the config out of the way, and check the emitted ID character-for-character:

```bash
TMPHOME=$(mktemp -d)
PROVIDER_API_KEY=sk-test PROVIDER_MODEL="" HOME="$TMPHOME" bash ccm.sh <provider> 2>/dev/null | grep ANTHROPIC_MODEL
# Expect: export ANTHROPIC_MODEL='<exact-id>'  — wrong casing here = broken fallback.
rm -rf "$TMPHOME"
```

With a **real** key, send a live Anthropic-format request to `${ANTHROPIC_BASE_URL}/v1/messages` using that fallback model ID. A `model_not_found` (503) means the ID is wrong even though the emit looked correct — this is the definitive check (it's what caught the HCNSEC bug).

## Reinstall, then test the installed copy

`git pull` alone is not enough — `install.sh` does two things, and both are required for a change to go live:

1. **It copies `ccm.sh` into the data dir** (`~/.local/share/ccm/ccm.sh`). The installed `ccm()`/`ccc()` functions run **that copy, not the repo file** — so a change that lives entirely inside `ccm.sh` (e.g., a model-ID fix) is invisible to the installed `ccm` until you reinstall. This is the trap that let the HCNSEC bug persist: the repo was fixed in commit `80ebb7b`, but the user's data-dir copy stayed stale, so `ccm hcnsec` kept failing until reinstall.
2. **It re-injects the `ccm()`/`ccc()` function definitions** into shell rc files. Changes to the launcher itself (e.g., a new provider in `ccc`'s `is_known_model()`) need this — the in-memory function isn't updated by a `git pull`.

Offer to run the reinstall, or ask the user to:

```bash
cd /path/to/claude-code-switch
./install.sh
source ~/.bashrc     # bash — or open a new terminal
source ~/.zshrc      # zsh
```

Then **test the installed copy**. The pre-commit verification above tested the *repo* file; this confirms the *data-dir* copy (the one actually used) matches and responds live — it's the only way to catch a stale installed copy:

```bash
# Installed ccm.sh emits the right model:
bash ~/.local/share/ccm/ccm.sh <provider> 2>/dev/null | grep ANTHROPIC_MODEL
# With a real key, fire a live Anthropic-format request end-to-end through the installed path:
eval "$(bash ~/.local/share/ccm/ccm.sh <provider>)" && \
  curl -s -w '\n[HTTP %{http_code}]\n' "${ANTHROPIC_BASE_URL}/v1/messages" \
    -H "x-api-key: ${ANTHROPIC_AUTH_TOKEN}" -H 'anthropic-version: 2023-06-01' \
    -d "{\"model\":\"${ANTHROPIC_MODEL}\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}"
```

A `model_not_found` (503) here means the installed copy is still wrong (stale data dir) — re-run `./install.sh`.

## Post-change notes for the user

Tell the user they must:
1. **Reinstall and reload shell** as shown above.
2. Manually add the new API key to `~/.ccm_config` (or delete the file and run `ccm config` to regenerate it).
3. Use the **exact model ID** shown in the provider's dashboard; wrong casing may cause channel/model errors.
4. `ccm update-config` only auto-adds missing model overrides, not API key placeholders.
5. If previous `~/.ccm_config` contained stale `ANTHROPIC_*` or `OLLAMA_*` exports, remove them — CCM exports these vars, the config should only hold keys and model overrides.
