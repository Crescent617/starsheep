{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  # nativeBuildInputs 包含编译时需要的工具（运行在构建主机上的工具）
  nativeBuildInputs = with pkgs; [
    zig # 确保你的 nixpkgs 已经更新到包含 0.15.2 的版本
    pkg-config # 极度重要：Zig 靠它在 NixOS 中找到 libgit2 的头文件和库路径
  ];

  # buildInputs 包含程序链接时需要的库
  buildInputs = with pkgs; [
    libgit2
    openssl # libgit2 的核心依赖
    zlib # libgit2 的核心依赖
    libssh2 # 如果你需要支持 git+ssh 协议
  ];

  # 环境变量设置
  shellHook = ''
    echo "↯󱐋󱐋󱐋 Zig $(zig version) 󱐋󱐋󱐋"
  '';
}
