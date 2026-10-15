# zig 包依赖（build.zig.zon + translate-c 的嵌套依赖 aro）
# 格式与 zon2nix (https://github.com/nix-community/zon2nix) 输出一致；
# name 必须等于 build.zig.zon 里的包 hash。
# 注意：当前 nixpkgs 的 zon2nix(0.1.3) 不支持 tarball 依赖与嵌套依赖，
# 本文件手工维护；升级依赖时用 `nix store prefetch-file --unpack <url>` 重算 hash。

{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "chameleon-2.0.1-ZOxajXd7AAB1ITCufcm2t6ZCkWwnwnKyW7jv-XY7IoIV";
    path = fetchzip {
      url = "https://github.com/Crescent617/chameleon/archive/8c48d2c58f6796a0c11a3c227e0476b83a3fa3f2.tar.gz";
      hash = "sha256-IWcINzVLiKxGqcwDFfe+ZzxK4MuKVOxbPhoeTCk7snM=";
    };
  }
  {
    name = "toml-0.3.0-bV14BRmkAQDSILPPyXc31aAXPtJa1Uh8Frug3i6InAUc";
    path = fetchzip {
      url = "https://github.com/sam701/zig-toml/archive/c661327bd9f02f774426c4fe78f60621411b7173.tar.gz";
      hash = "sha256-dS6b8nkpU54W3adoxKuGSgqkpkJ2pwktRfLABzuvBd8=";
    };
  }
  {
    name = "yazap-0.7.0-Z1t-EiT6AQDpbgaDQ1i_oBfnvmeH4AUM3WmiuTuXuQMN";
    path = fetchzip {
      url = "https://github.com/prajwalch/yazap/archive/82edda4aa180cc3aebf00b2c39a37975969eba0a.tar.gz";
      hash = "sha256-5cqzpwcU7gRM+eH9EJMmCxL5XjmahtNVZ8jO1mvXdHE=";
    };
  }
  {
    name = "translate_c-2.0.1-Q_BUWmpOBwCIhy--up1q6cl3OlIQE86iJU8R-bZ01aPj";
    path = fetchzip {
      url = "https://codeberg.org/ziglang/translate-c/archive/2.0.1.tar.gz";
      hash = "sha256-RwdfkwG6KLQ+kSw6yB5lJJOdyk+0F/ruUXbo1ROq1ao=";
    };
  }
  {
    name = "aro-0.0.0-JSD1QqKGNwALqBes402gHE7CP3Ga6xHS1J4mjThB3ro4";
    path = fetchzip {
      url = "https://codeberg.org/ziglang/arocc/archive/ffddc972f7a208bd6e254c27465407270fd8b60c.tar.gz";
      hash = "sha256-tuGdFncT5/t5SoyASLtfc+VxKk3xZ6zKVaY6FY2BemY=";
    };
  }
]
