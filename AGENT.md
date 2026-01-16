# LLM Agent Instructions

This file provides guidance to any LLM agents (claude, gemini, codex, etc) when working with code in this repository.

## Project Documentation

**User-facing documentation is in [README.md](README.md)**, including:
- Project overview and features
- Installation and quick start
- API reference and usage examples
- Architecture details
- Build commands

Refer to README.md for:
- General project questions
- API documentation
- Build instructions
- Project structure

## Agent-Specific Instructions

### Build Commands

**Workflows:**
```bash
just setup            # one-time setup
just build            # rebuild C host
just run              # roc run --linker=legacy main.roc
just dev              # build + run
just fresh            # clean + build + run
```

### Tool Preferences

- Use `ripgrep` (rg) instead of `grep`
- Use `just` instead of `make`
- Use `curl -sL` for downloads (silent + follow redirects, e.g., Roc docs redirect)
- Use `curl -sSL` when you need error output too

### Git usage

- Use git history to understand the project
- Treat git as read-only

### Roc Language Reference

#### Local references preferred

- docs/roc-tutorial.txt - Condensed tutorial (12KB)
- docs/stdlib.txt - Condensed stdlib (24KB)
- docs/stdlib-full.txt - With examples and additional information (132KB)

#### Online resources available

- Tutorial: https://www.roc-lang.org/llms.txt (HTML tag soup, 128KB)
- Stdlib: https://www.roc-lang.org/builtins/llms.txt (Markdown, 156KB)
