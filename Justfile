default: build

test:
    @echo "Running tests..."
    @zig build test --summary all

build:
    @echo "Building project..."
    @zig build

run:
    @echo "Running starsheep..."
    @zig build run -- "${@:-prompt}"
