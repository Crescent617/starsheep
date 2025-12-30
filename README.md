# ⭐ Starsheep

<img src="assets/logo.png" alt="Starsheep Logo" width="200" style="border-radius: 20px;"/>

A blazingly fast, customizable shell prompt generator written in Zig. Starsheep creates beautiful, informative prompts for zsh shells with built-in modules for git status, language versions, and system information.

## ✨ Features

- **🚀 Blazing Fast**: Written in Zig for maximum performance
- **🔧 Highly Customizable**: TOML-based configuration with tmux-style formatting
- **📦 Rich Built-in Modules**: Git status, language versions (Python, Node, Zig, Go, Rust), environment info
- **🎯 Smart Display**: Conditional commands that only show when relevant
- **🌈 Beautiful Colors**: Full terminal color support with chameleon library
- **🔌 Shell Integration**: Native zsh support with command duration tracking

<img src="assets/starsheep.png" alt="Starsheep Demo" width="600" style="border-radius: 20px;"/>

## 🚀 Quick Start

> NOTE: better to install a nerd font for proper symbol rendering. (e.g. [Maple Font](https://github.com/subframe7536/Maple-font))

### Installation

#### Option 1: Homebrew (macOS/Linux)

```bash
brew install --HEAD crescent617/tap/starsheep

# Initialize starsheep
eval "$(starsheep init zsh)"
```

#### Option 2: Build from Source

**Prerequisites**

- Zig 0.15.2 or higher
- zsh shell
- Git (for git module features)

```bash
# Build the project
zig build -Doptimize=ReleaseSafe

# Add starsheep to your PATH
export PATH="$PATH:/path/to/starsheep/zig-out/bin"

# Initialize starsheep
eval "$(starsheep init zsh)"
```

## 📖 Usage

### Basic Usage

```bash
# Generate a prompt
starsheep prompt

# Initialize shell integration
starsheep init zsh
```

### Configuration

Starsheep uses a TOML configuration file located at `~/.config/starsheep.toml`. Here's an example:

```toml
[[cmds]]
name = "time"
cmd = "date +'%H:%M:%S'"
format = "#[fg=green]$output"
```

### Built-in Commands

Starsheep includes many built-in commands:

- **System**: `user`, `host`, `cwd`, `duration`
- **Git**: `git_branch`, `git_status`
- **Languages**: `python`, `node`, `zig`, `go`, `rust`
- **Environment**: `nix`, `http_proxy`

## 🛠️ Development

### Building from Source

```bash
# Clone the repository
git clone https://github.com/Crescent617/starsheep.git
cd starsheep

# Run tests
zig build test

# Run the application
zig build run -- prompt
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 🙏 Acknowledgments

- Inspired by [starship](https://starship.rs/)
- Built with [Zig](https://ziglang.org/)
- Terminal colors powered by [chameleon](https://github.com/tr1ckydev/chameleon)
- TOML parsing with [zig-toml](https://github.com/sam701/zig-toml)
- CLI parsing with [yazap](https://github.com/prajwalch/yazap)
