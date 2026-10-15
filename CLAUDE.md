# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Starsheep is a customizable shell prompt generator written in Zig, designed for zsh shells. It generates dynamic prompts with built-in modules for git status, language versions, and system information.

## Development Commands

```bash
# Build the project
just build

# show prompt
just run

# Run tests
just test
```

## Architecture

### Core Structure
- **src/main.zig**: CLI entry point using yazap for argument parsing
- **src/root.zig**: Core library with prompt generation logic
- **src/Cmd.zig**: Command execution system supporting both shell commands and Zig functions
- **src/conf.zig**: TOML configuration file handling
- **src/fmt.zig**: Terminal formatting with chameleon library

### Built-in Modules (src/builtin/)
Each module is a separate Zig file that implements a prompt segment:
- user, host, cwd, git_branch, git_status
- Language version modules: python, zig, go, rust, node
- Environment modules: nix, http_proxy

### Shell Integration
- **src/shell/**: Zsh-specific implementation
- **src/shell/init-zsh.sh**: Shell initialization script that tracks command duration, exit codes, and job count

## Key Design Patterns

1. **Command System**: Commands can be either shell strings or Zig functions, with optional `when` conditions for conditional execution
2. **Tmux-style Formatting**: Uses `#[fg=red,bg=black,bold]` syntax for colors and styling
3. **Variable Substitution**: `$output` in format strings gets replaced with command output
4. **Configuration**: User config at `~/.config/starsheep.toml` overrides built-in commands

## Dependencies

- Zig 0.17.0+ (check build.zig.zon for exact version requirements)
- External Zig packages: chameleon (colors, Crescent617 fork 的 zig-0.17 分支，上游未适配), toml (config), yazap (CLI), translate-c (官方 C 翻译包，libgit2 头文件经 src/git2_shim.h 翻译；0.17 已移除 @cImport)
- System library: libgit2（brew install libgit2；构建时 --search-prefix 指向其 prefix）
- Development uses Nix (flake.nix, dependencies.nix); nixpkgs 的 zig 滞后，0.17 走 zig-overlay

## Testing

Tests are located throughout the codebase using Zig's built-in test blocks. Run with `zig build test`.
