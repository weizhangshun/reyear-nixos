{
  description = "3N 桌面: NixOS + Niri + Noctalia (nixos-unstable / btrfs / 中文 / 最新内核)";

  inputs = {
    # 非稳定通道
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      # 让 home-manager 与 nixpkgs 同源，避免两套 nixpkgs 版本冲突
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      # 用 cachix 分支: 始终指向已缓存的最新提交
      # ⚠️ 不要 follow nixpkgs: 会改变 derivation hash, 导致二进制缓存全部失效
      url = "github:noctalia-dev/noctalia/cachix";
    };

    noctalia-greeter = {
      # 官方登录器 (greetd greeter): 独立仓库, 自带 NixOS 模块
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # 装机机/构建机上的 flake 级缓存设置
  # ⚠️ nixConfig 只接受字符串列表 ({ url; priority } attrset 会被 nix 直接拒绝)。
  # 优先级由列表顺序决定: TUNA 首要, USTC 兜底。
  nixConfig = {
    extra-substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"   # 清华 TUNA (首要)
      "https://mirrors.ustc.edu.cn/nix-channels/store"            # 中国科大 (兜底)
      "https://nix-community.cachix.org"
      "https://noctalia.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  outputs = { self, nixpkgs, home-manager, disko, noctalia, ... }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations."reyear-nixos" = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };   # 让 host 模块能拿到 disko / noctalia 等 input
        modules = [
          ./hosts/reyear-nixos/default.nix
          home-manager.nixosModules.home-manager
        ];
      };

      # 供装机时使用: sudo nix run .#disko -- --mode destroy,format,mount ./hosts/reyear-nixos/disko.nix
      packages.${system}.disko = disko.packages.${system}.disko;

      # nix fmt 格式化
      formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;
    };
}
