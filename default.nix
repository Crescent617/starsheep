{ pkgs ? import <nixpkgs> { } }:

pkgs.stdenv.mkDerivation rec {
  pname = "starsheep";
  version = "0.1.0";

  # 源代码路径：如果是当前目录则使用 .
  src = ./.;

  # 编译时需要的工具
  nativeBuildInputs = with pkgs; [
    zig # 注意：Nixpkgs 目前稳定版多为 0.13，如果一定要 0.15 需要指向特定 overlay
    pkg-config
  ];

  # 运行时/链接时依赖
  buildInputs = with pkgs; [
    libgit2
    openssl
    zlib
    libssh2
    zstd # 你之前问过的 zst 格式，如果链接了 libzstd
  ];

  # Zig 特有的构建阶段
  buildPhase = ''
    runHook preBuild
    # -Doptimize=ReleaseSafe 类似于普通软件的 --release
    # --prefix 指定安装路径
    zig build -Doptimize=ReleaseSafe --prefix $out
    runHook postBuild
  '';

  # 允许 Zig 访问网络（如果 build.zig 中有依赖下载，但在 Nix 中建议离线构建）
  # 如果你的项目有外部依赖，通常需要使用 fetchGit 或指定 hash

  meta = with pkgs.lib; {
    description = "A customizable shell prompt generator written in Zig";
    homepage = "https://github.com/Crescent617/starsheep";
    license = licenses.mit;
    platforms = platforms.all;
    mainProgram = "starsheep";
  };
}
