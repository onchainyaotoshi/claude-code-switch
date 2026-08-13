:memo: Add a new direct provider to Claude Code Switch (ccm).

Use this skill when the user wants to add a new provider (e.g., "add provider X" or "integrate API Y").

## Pre-flight

1. Ask the user for the provider name/alias, base URL, default model, and auth env var name if they haven't provided them.
2. Check if the provider needs region handling (global/china). Most don't.
3. Verify the **exact model ID casing** with the provider's dashboard/documentation (e.g., `DeepSeek-V4-Pro` vs `deepseek-v4-pro`).
4. Confirm the design in chat before editing — this is a bounded, multi-file change.

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

If the user can provide a real API key, also test a live request (e.g. `curl` the provider's `/v1/models` or chat endpoint) to confirm the exact model ID works.

## Post-change notes for the user

Tell the user they must:
1. Reinstall: `git pull`, `./install.sh`, then `source ~/.bashrc` / `source ~/.zshrc` (or start a new shell).
2. Manually add the new API key to `~/.ccm_config` (or delete the file and run `ccm config` to regenerate it).
3. Use the **exact model ID** shown in the provider's dashboard; wrong casing may cause channel/model errors.
4. `ccm update-config` only auto-adds missing model overrides, not API key placeholders.
5. If previous `~/.ccm_config` contained stale `ANTHROPIC_*` or `OLLAMA_*` exports, remove them — CCM exports these vars, the config should only hold keys and model overrides.
