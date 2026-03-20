# Analysis: claude-plugins-official Repository

**Repository:** https://github.com/anthropics/claude-plugins-official
**Date:** 2026-03-20

## Overview

This is Anthropic's official curated marketplace/directory for **Claude Code plugins**. It provides a centralized registry where users can discover, install, and manage plugins that extend Claude Code's functionality. The repo has 13.6k stars, 1.3k forks, 23 contributors, and 154 commits.

## Repository Structure

```
claude-plugins-official/
├── .claude-plugin/
│   └── marketplace.json        # Central registry of ALL plugins (internal + external + remote)
├── .github/
│   ├── workflows/
│   │   ├── close-external-prs.yml
│   │   ├── validate-marketplace.yml
│   │   └── validate-frontmatter.yml
│   └── scripts/
│       ├── check-marketplace-sorted.ts
│       ├── validate-frontmatter.ts
│       └── validate-marketplace.ts
├── plugins/                    # 33 internal plugins (by Anthropic)
├── external_plugins/           # 16 external plugins (third-party)
├── README.md
└── .gitignore
```

## Plugin Architecture

Each plugin follows a standardized structure:

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json       # Plugin metadata (name, description, author) — REQUIRED
├── .mcp.json             # MCP server configuration (optional)
├── skills/               # Model-invoked or user-invoked skills (preferred format)
│   └── skill-name/
│       └── SKILL.md      # Skill definition with YAML frontmatter
├── commands/             # Legacy slash commands (*.md with frontmatter)
├── agents/               # Agent definitions (*.md)
└── README.md
```

### Key Extension Points

| Type | Location | Invocation | Purpose |
|------|----------|------------|---------|
| **Skills** | `skills/<name>/SKILL.md` | Model-invoked (contextual) or user-invoked (`/command`) | Contextual guidance or slash commands |
| **Commands** | `commands/*.md` (legacy) | User-invoked (`/command`) | Slash commands (legacy format) |
| **Agents** | `agents/*.md` | Spawned by Claude | Specialized sub-agents |
| **MCP Servers** | `.mcp.json` | Automatic (tool integration) | External tool integration via Model Context Protocol |
| **LSP Servers** | Defined in marketplace.json | Automatic | Language server protocol integration |

### Skill Frontmatter Options

```yaml
---
name: skill-name                    # Required: identifier
description: Trigger conditions     # Required: when Claude should use this
argument-hint: <arg1> [optional]    # For user-invoked skills
allowed-tools: [Read, Glob, Grep]   # Pre-approved tools (reduces permission prompts)
model: haiku|sonnet|opus            # Optional model override
version: 1.0.0                      # Optional semantic version
---
```

## Plugin Categories

### Internal Plugins (33 — by Anthropic)

| Category | Plugins |
|----------|---------|
| **LSP/Language Support (13)** | typescript-lsp, pyright-lsp, gopls-lsp, rust-analyzer-lsp, clangd-lsp, jdtls-lsp (Java), kotlin-lsp, php-lsp, ruby-lsp, swift-lsp, csharp-lsp, lua-lsp, elixir-ls-lsp (external) |
| **Development Workflow (7)** | feature-dev, plugin-dev, mcp-server-dev, agent-sdk-dev, skill-creator, playground, ralph-loop |
| **Code Quality (5)** | code-review, code-simplifier, pr-review-toolkit, commit-commands, security-guidance |
| **Productivity (4)** | claude-code-setup, claude-md-management, hookify, frontend-design |
| **Learning (2)** | explanatory-output-style, learning-output-style |
| **Meta (2)** | example-plugin, math-olympiad |

### External Plugins (16 — third-party, hosted in repo)

| Category | Plugins |
|----------|---------|
| **Productivity/Integrations** | asana, slack, linear, github, gitlab, discord, telegram |
| **Databases** | firebase, supabase |
| **Development** | context7, laravel-boost, playwright, serena, stripe, greptile |
| **Testing** | fakechat |

### Remote Plugins (50+ — referenced by URL in marketplace.json)

Sourced from external Git repositories via three mechanisms:
1. **`url`** — Full repository clone (e.g., `https://github.com/org/repo.git`)
2. **`git-subdir`** — Specific subdirectory from a repo (e.g., `awslabs/agent-plugins` → `plugins/deploy-on-aws`)
3. **`github`** — GitHub repo shorthand (e.g., `browserbase/agent-browse`)

Notable remote plugins: Figma, Notion, Vercel, Sentry, Stripe, Terraform, AWS Serverless, Playwright, Postman, Neon, PlanetScale, Railway, Zapier, and many more.

## Marketplace Registry (marketplace.json)

The central `marketplace.json` file contains **100+ plugin entries** with:
- **name**: Plugin identifier
- **description**: Detailed description
- **source**: Either a local path (`./plugins/...`) or remote source (`url`, `git-subdir`, `github`)
- **category**: development, productivity, database, security, deployment, monitoring, etc.
- **homepage**: Link to plugin documentation
- **author**: Creator information
- **lspServers**: LSP configuration (for language server plugins)
- **tags**: e.g., `community-managed`
- **sha**: Pinned commit hash for reproducible installs

## Installation Methods

1. **CLI**: `/plugin install {plugin-name}@claude-plugins-official`
2. **UI**: Browse via `/plugin > Discover`

## CI/CD & Quality Gates

Three GitHub Actions workflows:
1. **validate-marketplace.yml** — Validates marketplace.json schema and integrity
2. **validate-frontmatter.yml** — Validates SKILL.md/command frontmatter syntax
3. **close-external-prs.yml** — Auto-closes PRs from external contributors (directs to submission form)

## Key Takeaways

1. **Plugin system is file-based**: Plugins are defined entirely through Markdown files with YAML frontmatter — no compiled code required for skills/commands/agents.

2. **MCP is the integration layer**: External tools connect via Model Context Protocol (`.mcp.json`), supporting HTTP-based remote servers.

3. **LSP integration is first-class**: 13+ language servers are available as plugins, providing code intelligence for major languages.

4. **Three-tier source model**: Plugins can be internal (in `plugins/`), external (in `external_plugins/`), or remote (referenced by Git URL in marketplace.json).

5. **Skills are the preferred format**: The `skills/<name>/SKILL.md` format supersedes the legacy `commands/*.md` format. Skills can be either model-invoked (contextual) or user-invoked (slash commands).

6. **Curated but extensible**: Anthropic manages the marketplace centrally, but third parties can submit plugins via a submission form. External PRs are auto-closed.

7. **Security is user's responsibility**: Anthropic explicitly disclaims control over plugin contents — users must verify trustworthiness before installing.

## Relevance to This Project

For the `openbao-pki-ra-interface` project, the Claude Code plugin system could be leveraged to:
- Create custom skills for PKI/RA workflow automation
- Build MCP server integrations with OpenBao Vault
- Define specialized agents for certificate management tasks
- Add slash commands for common PKI operations
