default: build

# libgit2 的 search-prefix：macOS 用 brew 前缀，其他环境（如 nix）由 pkg-config 兜底
search_prefix := env_var_or_default("LIBGIT2_PREFIX", "/opt/homebrew")

test:
    @echo "Running tests..."
    @zig build test --search-prefix {{search_prefix}} --summary all

build:
    @echo "Building project..."
    @zig build --search-prefix {{search_prefix}}

run:
    @echo "Running starsheep..."
    @zig build run --search-prefix {{search_prefix}} -- "${@:-prompt}"
