{ pkgs }:

# 优先使用 nixpkgs 自带的 zig_0_16；nixpkgs 尚未提供时，
# 回退到 ziglang.org 官方二进制包。
let
  zigVersion = "0.16.0";
  zigTarballs = {
    "aarch64-darwin" = {
      name = "zig-aarch64-macos-${zigVersion}";
      hash = "sha256-sj1w3qqHm1wtSG7TMW9+qlPoSs9vycx0feFSRQ1AFIk=";
    };
    "x86_64-darwin" = {
      name = "zig-x86_64-macos-${zigVersion}";
      hash = "sha256-A4dVftGHe8ai4YAsg5GVO63bp2CBh2MBxSL1KXe1K6c=";
    };
    "x86_64-linux" = {
      name = "zig-x86_64-linux-${zigVersion}";
      hash = "sha256-cOSWZKdDdLSLUebz/fv0N/Y5XUJQkFBYi9SavlK6PQA=";
    };
    "aarch64-linux" = {
      name = "zig-aarch64-linux-${zigVersion}";
      hash = "sha256-6ksJv7IuxvbGzqxXq2PvtrRuF6sI0h9p86SLOOFTTxc=";
    };
  };
  system = pkgs.stdenv.hostPlatform.system;
  zigTarball = zigTarballs.${system} or (throw "unsupported system for zig ${zigVersion} tarball fallback: ${system}");
  zigFromTarball = pkgs.stdenvNoCC.mkDerivation {
    pname = "zig";
    version = zigVersion;
    src = pkgs.fetchurl {
      url = "https://ziglang.org/download/${zigVersion}/${zigTarball.name}.tar.xz";
      inherit (zigTarball) hash;
    };
    sourceRoot = zigTarball.name;
    installPhase = ''
      mkdir -p $out/bin
      cp zig $out/bin/zig
      cp -R lib $out/lib
    '';
  };
in
pkgs.zig_0_16 or zigFromTarball
