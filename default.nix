{ pkgs ? import <nixpkgs> { } }:

let
  # 1. 显式传递 linkFarm，解决上一个参数缺失错误
  deps = pkgs.callPackage ./dependencies.nix {
    inherit (pkgs) linkFarm;
  };
in
pkgs.stdenv.mkDerivation rec {
  pname = "starsheep";
  version = "0.1.1";
  src = ./.;

  nativeBuildInputs = with pkgs; [
    zig_0_15
    pkg-config
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
    mkdir -p $ZIG_GLOBAL_CACHE_DIR/p

    # 3. 极其重要：处理依赖链接
    # 如果 deps 是 linkFarm 生成的目录，它本身就是一个路径字符串
    # 我们直接把这个目录下所有的哈希文件夹链接到 Zig 的缓存中
    ln -s ${deps}/* $ZIG_GLOBAL_CACHE_DIR/p/

    # 4. 执行构建
    zig build -Doptimize=ReleaseSafe --prefix $out

    runHook postBuild
  '';
}
