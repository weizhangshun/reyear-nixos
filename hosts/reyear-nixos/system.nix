# 系统基础: 内核 / 引导 / 硬件 / 网络 / 音频 / 时区语言输入法 / 字体 / Nix 设置
{ config, lib, pkgs, ... }:

{
  # ================= 内核: 最新 =================
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ================= 引导: systemd-boot + systemd initrd =================
  # systemd initrd 是 LUKS + TPM 自动解锁的前提
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [ "nvme" "ahci" "usb_storage" "sd_mod" ];

  # ================= 硬件 (Intel Core Ultra 7 155H / Arc iGPU) =================
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [ intel-media-driver ];  
  hardware.cpu.intel.updateMicrocode = true;                            

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

  # ================= 虚拟化: KVM / libvirt (镜像存 @vm 子卷) =================
  # OVMF (UEFI 固件) 已随 QEMU 自动分发, 无需配置 (qemu.ovmf 选项已在新 nixpkgs 移除)
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;     # 只带 KVM 硬件加速, 闭包小; 需模拟别的架构时换 qemu_full
      swtpm.enable = true;         # vTPM, Windows 11 虚拟机必需
    };
  };
  programs.virt-manager.enable = true;   # 图形管理器 (GUI)

  # ================= Docker (容器; 数据落 @docker 子卷) =================
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;   # 每周自动清理无容器引用的镜像/构建缓存, 防膨胀
  };
  # 本机原生数据库 (数据库课程/毕设): 开启即用, 数据自动落在 @db 子卷 (nodatacow)
  # services.postgresql.enable = true;
  # 其他原生 DB (mysql/mongo) 建议跑 docker (落 @docker), 或自设 dataDir 指进 @db

  # 可选: 自动更新 (unstable 有风险, 默认关闭; 启用前确保有回滚手段)
  # system.autoUpgrade = {
  #   enable = true;
  #   flake = "github:OceanReyear/reyear-nixos";
  #   dates = "weekly";
  #   allowReboot = false;
  # };

  # ================= 时区 / 语言 / 中文输入 =================
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.supportedLocales = [ "zh_CN.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      qt6Packages.fcitx5-chinese-addons    
      fcitx5-rime                         
    ];
  };

  # ================= 字体 (中文必需, 否则方块字) =================
  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
    sarasa-gothic
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Noto Sans CJK SC" "Sarasa UI SC" ];
    serif = [ "Noto Serif CJK SC" ];
    monospace = [ "Sarasa Mono SC" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # ================= Nix 设置 =================
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"   # 清华 TUNA
      "https://mirrors.ustc.edu.cn/nix-channels/store"            # 中国科大
      "https://cache.nixos.org"                                   # 官方源
      "https://nix-community.cachix.org"
      "https://noctalia.cachix.org"                               # noctalia 官方缓存
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpUxNFQsBRglJzxWPp3dkU4="
    ];
  };
  nixpkgs.config.allowUnfree = true;

  # ================= 用户 =================
  users.users.reyear = {
    isNormalUser = true;
    hashedPassword = "$6$rounds=656000$kWnXXPCaFTnHgfa.$RJIwCzNOBVhtgJw8ZcBzb98y2fxC5AG.JyoY6.i7IFE.m1gc0f9K/UtPw2F.3bLTr8OUk3INuhMxjNasAYQ56.";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "libvirtd" "docker" ];  # libvirtd/docker: 免 sudo 管虚拟机与容器
  };

  # 远程管理 (nixos-anywhere 装机依赖 SSH)
  services.openssh.enable = true;
}
