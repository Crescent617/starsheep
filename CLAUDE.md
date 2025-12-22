# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Starsheep is a customizable shell prompt generator written in Zig, designed for zsh shells. It generates dynamic prompts with built-in modules for git status, language versions, and system information.

## Development Commands

```bash
# Build the project
zig build

# Run tests
zig build test

# Run the application
zig build run

# Install to zig-out/
zig build install
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

- Zig 0.15.2+ (check build.zig for exact version requirements)
- External Zig packages: chameleon (colors), toml (config), yazap (CLI), libgit2 (git operations)
- Development uses Nix (shell.nix, default.nix, dependencies.nix)

## Testing

Tests are located throughout the codebase using Zig's built-in test blocks. Run with `zig build test`.