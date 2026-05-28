# patterns

A personal scratchpad of infrastructure / tooling patterns I keep
re-implementing. Each entry is here so I can copy-paste a known-good shape
into a new project instead of re-deriving it.

Two shapes:

- **Folders** (`terraform/`, `ansible/`) — full structural patterns with
  multiple files. Open the folder and read its `README.md`.
- **Single `.md` files** — bite-sized tools whose entire footprint is one
  script or one shell snippet. The doc *is* the artifact; copy-paste the
  code block.

---

## Index

| Pattern | Shape | What it solves |
|---|---|---|
| [`terraform/`](terraform/README.md) | folder | AWS multi-account layout with Terragrunt orchestration. One account per (workload × env), plus foundation accounts (management / networking / ops-tooling / backup). A single `env_map` in `root.hcl` is the only place account ids live. |
| [`ansible/`](ansible/README.md) | folder | Deploy a containerized app to EC2 with **no SSH** (SSM Session Manager), dynamic inventory by EC2 tag, secrets from Secrets Manager, and a `docker compose config` validation playbook that runs in CI before any real host is touched. |
| [`claude-multi-account-workspace.md`](claude-multi-account-workspace.md) | tool | Per-client `CLAUDE_CONFIG_DIR` workspaces that share skills/agents/plugins/`CLAUDE.md` via symlinks. One toolkit, isolated sessions. |
| [`ci-slack-notification.md`](ci-slack-notification.md) | tool | Build a Slack release-notification payload from `CHANGELOG.md` at deploy-time. Fetches the latest changelog from `origin/main` so post-QA edits still surface in the prod message. Provider-agnostic. |

---

## House rules

- **Folders are structure**, files are tools. If a pattern has more than one
  file worth keeping around, it gets a folder. Otherwise it's a single `.md`.
- **Everything is genericized.** No real account ids, no real domains, no
  real customer or product names anywhere. Where I needed a name I used
  `acme` (company), `orbit` (a fictional web app), or `example.com`.
- **Minimal, not complete.** These are reference shapes, not production
  modules. They're meant to be *read* and copied, not vendored.
