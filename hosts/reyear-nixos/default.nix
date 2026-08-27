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

  # 当前 unstable 为 26.11pre, 最新稳定版 26.05; stateVersion 用最新稳定版最合适
  system.stateVersion = "26.05";
}
