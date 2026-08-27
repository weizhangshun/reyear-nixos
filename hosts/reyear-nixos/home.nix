# home-manager: 用户级程序与 dotfiles (niri 配置 / Rime 简体 / git ...)
{ config, lib, pkgs, inputs, ... }:

{
  # ============ Noctalia (home 模块: 声明式 settings) ============
  # 生成 ~/.config/noctalia/config.toml; 不想要声明式设置就把 settings 删掉
  imports = [ inputs.noctalia.homeModules.default ];
  programs.noctalia = {
    enable = true;
    settings = {
      # 也可直接给一个 .toml 文件路径
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };
      # wallpaper = { enabled = true; default.path = "/home/reyear/Pictures/wallpaper.jpg"; };
    };
  };

  home.username = "reyear";
  home.homeDirectory = "/home/reyear";
  home.stateVersion = "26.05";

  # ============ 用户级程序 (按需添加) ============
  home.packages = with pkgs; [
    # 例: gh
  ];

  programs.git = {
    enable = true;
    userName = "reyear";
    userEmail = "reyearocean@qq.com";
  };

  programs.kitty.enable = true;

  # ============ niri 配置 (kdl 语法) ============
  # 完整选项见 https://yalter.github.io/niri/Configuration/
  home.file.".config/niri/config.kdl".text = ''
    input {
        keyboard {
            xkb {
                layout "us"      # 中文输入交给 fcitx5, 键盘布局保持 us
            }
        }
        touchpad {
            tap
        }
    }

    # ---- 开机自启 ----
    spawn-at-startup "fcitx5" "-d"                 # 中文输入法
    spawn-at-startup "noctalia"                    # 桌面外壳 (compositor 启动是官方推荐, 勿用 systemd 服务)
    spawn-at-startup "swaybg" "-i" "/home/reyear/Pictures/wallpaper.jpg" "-m" "fill"

    # ---- 快捷键 ----
    binds {
        # 应用
        Mod+Enter        { spawn "kitty"; }
        Mod+D            { spawn "fuzzel"; }
        Mod+Shift+E      { quit; }
        Mod+L            { spawn "swaylock"; }

        # 截图 / 录屏
        Mod+P            { spawn "sh" "-c" "grim -g \"$(slurp)\" - | wl-copy"; }
        Mod+Shift+P      { spawn "sh" "-c" "grim - | wl-copy"; }

        # 窗口管理 (niri 是横向平铺)
        Mod+Q            { close-window; }
        Mod+F            { maximize-column; }
        Mod+Shift+F      { fullscreen-window; }
        Mod+J            { focus-column-left; }
        Mod+K            { focus-column-right; }
        Mod+Shift+J      { move-column-left; }
        Mod+Shift+K      { move-column-right; }
        Mod+1..9         { focus-workspace 1..9; }
        Mod+Shift+1..9   { move-column-to-workspace 1..9; }

        # 音量
        XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05+"; }
        XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05-"; }
        XF86AudioMute       { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }

        # 亮度
        XF86MonBrightnessUp   { spawn "brightnessctl" "set" "5%+"; }
        XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }
    }
  '';

  # ============ Rime 默认输出简体 (解决"全是繁体"问题) ============
  # 默认 schema 是朙月拼音(繁体输出), 这里切成 朙月拼音·简化字
  home.file.".local/share/fcitx5/rime/default.custom.yaml".text = ''
    patch:
      schema_list:
        - schema: luna_pinyin_simp
  '';
}
