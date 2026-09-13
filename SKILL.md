---
name: opencode
description: "将用户明确指定的代码实现、仓库探索、代码评审、前端/UI 迭代和本地文件分析委托给 OpenCode CLI。用户提到 OpenCode、$opencode、opencode run，或明确要求使用本机 OpenCode 时触发；不要因普通编码请求自动委托。支持新建与续接会话，但不用于图片生成或其他需要专用媒体工具的任务。"
compatibility: "需要本机可执行的 OpenCode CLI（opencode）、已配置的模型/Provider，以及 jq；wrapper 运行在 macOS 或 Linux 的 Bash 环境中。"
---

# OpenCode

Use this skill when the user explicitly asks to use OpenCode or selects `$opencode`. It is a delegation bridge to the local OpenCode CLI, not a replacement for reviewing the resulting changes.

## Core rules

- Use `scripts/ask_opencode.sh`; do not invoke `opencode run` directly. The wrapper normalizes paths, captures JSON events, streams compact progress, writes a Markdown handoff, and returns a session ID when OpenCode provides one.
- Run the wrapper once for a focused task. After it succeeds, read `output_path`, inspect the workspace diff, and run verification proportional to risk.
- Give OpenCode the goal, completion criteria, constraints, and relevant context. Keep the delegated prompt focused, normally under 500 words.
- Pass one to four priority files with `--file`. Use source files, tests, screenshots, or other local media that OpenCode should inspect first.
- Use `--session` only for a genuine follow-up; use `--continue` for the most recent session in that workspace.
- Non-interactive OpenCode execution may mutate files or run commands. Use it only in a trusted workspace when the request authorizes edits.
- Do not ask OpenCode to generate or edit raster image assets. It may inspect visual references and implement the corresponding UI; use a dedicated image tool for bitmap deliverables.

## Workflow

1. Read enough local context to state the actual goal and constraints.
2. Choose the workspace and one to four priority files.
3. Run `scripts/ask_opencode.sh` with one focused prompt.
4. Read the Markdown file printed as `output_path`.
5. Review the workspace diff and run tests, linters, or builds as appropriate.
6. For a true follow-up, call the wrapper with `--session <id>` or `--continue`.

## Examples

```bash
./scripts/ask_opencode.sh "Implement the requested change"
```

```bash
./scripts/ask_opencode.sh \
  "Review this page and implement a polished responsive layout" \
  --workspace "/path/to/app" \
  --file "src/App.tsx" \
  --file "references/current-ui.png"
```

```bash
./scripts/ask_opencode.sh \
  "Trace the failing request path and add a regression test" \
  --model "anthropic/claude-sonnet-4-5" \
  --agent "build"
```

```bash
./scripts/ask_opencode.sh "Now update the documentation" --session "SESSION_ID"
./scripts/ask_opencode.sh "Run the relevant tests" --continue
```

## Permissions and safety

The wrapper does not enable OpenCode's `--auto` by default. Add `--auto` only in a trusted, scoped workspace when unattended approval is explicitly wanted. For enforced no-write exploration, use an OpenCode plan/restricted workflow in the user's terminal; a prompt saying “do not edit” is not an enforcement boundary. Never put API keys in the delegated prompt.

## Output and failures

On success it prints `session_id=<id>` when available, `output_path=<absolute_markdown_path>`, and `elapsed=<seconds>s`. The Markdown file contains the final text, a compact tool summary, and elapsed time. A failed command returns non-zero with redacted stderr. If OpenCode or a provider is missing, check `opencode --version`, `opencode run --help`, and `opencode providers`/`opencode auth`.
