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

## Tool Preferences

### Ripgrep

Use `ripgrep` (rg) instead of `grep` (always) and `git grep` (nearly always)

- `git grep` can be used for searching git history
- see docs/RIPGREP.md for some extensive examples of in-project usage (as needed)

### Curl

For web downloads, use the following options as appropriate.
Follow redirects by default.

- `-L` follow redirects
- `-s` silent
- `-S` show errors
- `-O` dump to filename.html (from the URL) rather than STDOUT

### Git

Use git history to understand the project.  Treat git as read-only.

### Github

The Github website can present navigation headaches.

- `gh` github client is available
- Raw github: https://raw.githubusercontent.com/owner/repo/branch/path/to/file.py

## schnorr-platform/tmp dir

- place scratch files in within the project root: schnorr-platform/tmp/
- temp files placed outside the project root will have difficulty finding their platform
