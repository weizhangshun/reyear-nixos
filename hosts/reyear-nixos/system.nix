# 系统基础: 内核 / 引导 / 硬件 / 网络 / 音频 / 时区语言输入法 / 字体 / Nix 设置
{ config, lib, pkgs, ... }:

{
  # ================= 内核: 最新 =================
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # 可选: 追求低延迟换 pkgs.linuxPackages_xanmod / pkgs.linuxPackages_cachyos
  # ⚠️ 最新内核 + 系统更新后若起不来: 在 boot 菜单选上一个条目, 再 nixos-rebuild switch --rollback

  # ================= 引导: systemd-boot + systemd initrd =================
  # systemd initrd 是 LUKS + TPM 自动解锁的前提
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [ "nvme" "ahci" "usb_storage" "sd_mod" ];

  # ================= 硬件 (Intel Core Ultra 7 155H / Arc iGPU) =================
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [ intel-media-driver ];   # VA-API 硬解
  hardware.cpu.intel.updateMicrocode = true;                             # 别忘微码

  # ================= 网络 =================
  networking.hostName = "reyear-nixos";
  networking.networkmanager.enable = true;

  # ================= 音频 (pipewire) =================
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # ================= 蓝牙 =================
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ================= 电源 / 性能 =================
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;                 # noctalia 电池/电量显示依赖
  zramSwap.enable = true;                 # 内存压缩替代 swap
  zramSwap.memoryPercent = 50;
  zramSwap.algorithm = "zstd";

  # 可选: 自动更新 (unstable 有风险, 默认关闭; 启用前确保有回滚手段)
  # system.autoUpgrade = {
  #   enable = true;
  #   flake = "github:OceanReyear/reyear-nixos";   # 需推到 GitHub, 本地路径不适用
  #   dates = "weekly";
  #   allowReboot = false;
  # };

  # ================= 时区 / 语言 / 中文输入 =================
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.supportedLocales = [ "zh_CN.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];
  i18n.inputMethod = {
    type = "fcitx5";                      # 新版 nixpkgs 用 type (enabled 已弃用)
    fcitx5.addons = with pkgs; [
      fcitx5-chinese-addons               # 拼音 (默认简体, 开箱即用)
      fcitx5-rime                         # Rime 引擎 (已预置简体 schema, 见 home.nix)
    ];
  };

  # ================= 字体 (中文必需, 否则方块字) =================
  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji   # unstable 已由 noto-fonts-emoji 更名
    sarasa-gothic        # 更纱黑体: 中英文等宽, 终端利器
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Noto Sans CJK SC" "Sarasa UI SC" ];
    monospace = [ "Sarasa Mono SC" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # ================= Nix 设置 =================
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix/store"   # 清华 TUNA 镜像 (首要, 国内加速; 与 cache.nixos.org 同签名)
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://noctalia.cachix.org"   # noctalia 官方二进制缓存, 见官方文档
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };
  nixpkgs.config.allowUnfree = true;

  # ================= 用户 =================
  users.users.reyear = {
    isNormalUser = true;
    # 密码以 sha512crypt 哈希存储 (passlib 生成); 建议装机后 passwd 更换 (曾短暂公开, 仓库已转私密)
    hashedPassword = "$6$rounds=656000$kWnXXPCaFTnHgfa.$RJIwCzNOBVhtgJw8ZcBzb98y2fxC5AG.JyoY6.i7IFE.m1gc0f9K/UtPw2F.3bLTr8OUk3INuhMxjNasAYQ56.";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

  # 远程管理 (nixos-anywhere 装机依赖 SSH)
  services.openssh.enable = true;
}
