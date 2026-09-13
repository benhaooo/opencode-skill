# OpenCode Skill

这是一个供 Codex/其他 Agent 加载的 Skill：当用户明确选择 OpenCode 时，通过 `scripts/ask_opencode.sh` 调用本机 OpenCode CLI，并把 JSON 事件整理成 Markdown handoff。

## 依赖

- OpenCode CLI：`opencode --version`
- 已配置的 OpenCode provider/model：`opencode providers` 或 `opencode auth`
- `jq`
- macOS/Linux Bash

## 安装到 Agent 的 Skill 目录

将本目录复制或链接到 Agent 的 skills 目录。例如：

```bash
mkdir -p "$AGENT_SKILLS_DIR"
ln -s "/absolute/path/to/opencode" "$AGENT_SKILLS_DIR/opencode"
```

随后重新加载 Agent，并用 `Use $opencode ...` 明确触发。

## 直接调用

```bash
./scripts/ask_opencode.sh \
  "检查这个仓库并实现请求的修改" \
  --workspace "/path/to/repository" \
  --file "src/App.tsx"
```

成功时会打印 `output_path` 和可选的 `session_id`。将该 ID 传给 `--session` 可继续会话；`--continue` 会继续目标工作区最近的会话。

## 校验

```bash
bash -n scripts/ask_opencode.sh
python3 -m json.tool evals/evals.json >/dev/null
```

`skill-creator` 的完整校验器还需要安装 PyYAML。
