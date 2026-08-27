# 3N 主机入口: 汇聚所有模块 + 启用 home-manager (NixOS module 方式)
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    inputs.disko.nixosModules.disko   # 声明式磁盘布局 (fileSystems 由 disko 生成)
    ./disko.nix
    ./system.nix
    ./desktop.nix
    # ./snapshot.nix   # 可选: snapper 快照, 启用方法见文件头
  ];

  # ---- home-manager (跟随 NixOS 一起构建, 单一入口) ----
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users."reyear" = import ./home.nix;
    extraSpecialArgs = { inherit inputs; };
  };

  # 对应 nixos-unstable (2026-04 时点, 与用户现行配置一致); 升级大版本后按需上调
  system.stateVersion = "25.11";
}
