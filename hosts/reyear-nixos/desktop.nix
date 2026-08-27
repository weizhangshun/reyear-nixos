# 桌面层: niri + Noctalia + Wayland 配套
{ config, lib, pkgs, inputs, ... }:

{
  # ================= niri (Wayland 合成器) =================
  programs.niri.enable = true;
  programs.xwayland.enable = true;   # XWayland 应用 (微信/QQ 等)

  # ================= Noctalia 桌面外壳 (官方 NixOS 模块) =================
  # 文档: https://docs.noctalia.dev/noctalia/getting-started/nixos/
  # 说明: 启动由 niri 的 spawn-at-startup 负责 (compositor 启动是官方推荐方式);
  #       声明式 settings (主题/壁纸) 在 home.nix 的 home 模块里
  imports = [ inputs.noctalia.nixosModules.default ];
  programs.noctalia = {
    enable = true;
    # 自动启用 NetworkManager / Bluetooth / UPower / 电源配置服务 (与 system.nix 一致, 幂等)
    recommendedServices.enable = true;
    # 可选: 用户级 systemd 服务 (默认不开; 若开启建议同时设 launch_apps_as_systemd_services)
    # systemd.enable = true;
  };

  # ================= xdg-desktop-portal (屏幕共享/文件选择) =================
  # 注: niri 会话的 portal 配置 (gnome+gtk) 由 programs.niri 模块自动生成, 无需手动设置
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # Chromium/Electron 系应用默认走 Wayland (VS Code / 微信等)
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # ================= 显示管理器 =================
  services.displayManager.sddm.enable = true;
  # 备选: greetd + tuigreet, 或 Noctalia Greeter (https://docs.noctalia.dev/greeter/)

  programs.dconf.enable = true;

  # ================= 桌面配套工具 =================
  environment.systemPackages = with pkgs; [
    # 基础应用
    firefox
    unzip
    ripgrep
    fd
    btop
    # kitty / git 由 home-manager 管理 (home.nix), 这里不重复装

    # Wayland 工具链 (niri 不自带, 需自己拼)
    wl-clipboard          # 剪贴板
    cliphist              # 剪贴板历史
    grim slurp            # 截图
    wf-recorder           # 录屏
    mako                  # 通知
    swaylock              # 锁屏
    swaybg                # 壁纸
    fuzzel                # 应用启动器
    swayidle              # 息屏
    brightnessctl         # 屏幕亮度
    pavucontrol           # 音量控制面板
    networkmanagerapplet  # 托盘网络管理
    xdg-utils
  ];
}
