{ pkgs ? import <nixpkgs> { } }:

let
  # 1. 显式传递 linkFarm，解决上一个参数缺失错误
  deps = pkgs.callPackage ./dependencies.nix {
    inherit (pkgs) linkFarm;
  };

  # zig 0.16（nixpkgs 没有 zig_0_16 时自动回退官方 tarball）
  zig_0_16 = import ./zig-0_16.nix { inherit pkgs; };
in
pkgs.stdenv.mkDerivation rec {
  pname = "starsheep";
  version = "0.1.1";
  src = ./.;

  nativeBuildInputs = [
    zig_0_16
    pkgs.pkg-config
  ];

  buildInputs = with pkgs; [
    libgit2
    openssl
    zlib
    libssh2
  ];

  # 2. 修正 buildPhase
  buildPhase = ''
    runHook preBuild

    # 设置并导出缓存目录
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
    mkdir -p $ZIG_GLOBAL_CACHE_DIR

    # 3. 极其重要：处理依赖链接
    # zig 0.16 默认将依赖拉取到项目本地的 zig-pkg/ 目录，
    # 直接把 linkFarm 里的哈希目录链接进去即可。
    # 先清掉源码里可能残留的本地 zig-pkg/，避免链接冲突。
    rm -rf zig-pkg
    mkdir zig-pkg
    ln -s ${deps}/* zig-pkg/

    # 4. 执行构建（nix 沙盒本身无网络，依赖已链接进 zig-pkg/）
    zig build -Doptimize=ReleaseSafe --prefix $out

    runHook postBuild
  '';
}
