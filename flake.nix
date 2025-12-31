{
  description = "A customizable shell prompt generator written in Zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # 1. 提取共用的依赖项，避免在 packages 和 devShells 中重复写两遍
          commonBuildInputs = with pkgs; [
            libgit2
            openssl
            zlib
            libssh2
          ];

          commonNativeBuildInputs = with pkgs; [
            zig_0_15 # 开发和构建统一使用 0.15 版本
            pkg-config
          ];

          # 导入依赖
          deps = pkgs.callPackage ./dependencies.nix {
            inherit (pkgs) linkFarm;
          };
        in
        {
          packages.default = pkgs.stdenv.mkDerivation rec {
            pname = "starsheep";
            version = "0.1.1";
            src = ./.;

            # 直接引用上面定义的列表
            nativeBuildInputs = commonNativeBuildInputs;
            buildInputs = commonBuildInputs;

            buildPhase = ''
              runHook preBuild
              export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
              mkdir -p $ZIG_GLOBAL_CACHE_DIR/p
              ln -s ${deps}/* $ZIG_GLOBAL_CACHE_DIR/p/

              zig build -Doptimize=ReleaseSafe --prefix $out
              runHook postBuild
            '';

            # 简化：既然 buildPhase 已经安装了，直接禁用默认 installPhase
            dontInstall = true;

            meta = with pkgs.lib; {
              description = "A customizable shell prompt generator written in Zig";
              homepage = "https://github.com/Crescent617/starsheep";
              license = licenses.mit;
              platforms = platforms.all;
            };
          };

          # 2. 简化开发 Shell，直接引用 package 的属性
          devShells.default = pkgs.mkShell {
            # 继承 package 已有的输入，并额外增加开发工具（如 zls）
            inputsFrom = [ self.packages.${system}.default ];

            nativeBuildInputs = with pkgs; [ zon2nix ]; # 增加语言服务器

            shellHook = ''
              echo "󱐋󱐋󱐋 Zig $(zig version) 开发环境 󱐋󱐋󱐋"
            '';
          };

          # 3. 简化 app 定义，利用变量引用
          apps.default = flake-utils.lib.mkApp {
            drv = self.packages.${system}.default;
          };
        }
      ) // {
      overlays.default = final: prev: {
        starsheep = self.packages.${prev.system}.default;
      };
    };
}
