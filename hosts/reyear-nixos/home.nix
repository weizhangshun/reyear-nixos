# home-manager: 用户级程序与 dotfiles (niri 配置 / Rime 简体 / git ...)
{ config, lib, pkgs, inputs, ... }:

let
  # 壁纸库部署位置: 仓库 background/ 经 home.file 链接到这里
  wallpaperDir = "${config.home.homeDirectory}/.local/share/backgrounds";
  # 默认壁纸 misty-forest (晨雾山林, 偏暗色调配 Catppuccin dark); 可在 Noctalia 壁纸面板随时换
  defaultWallpaper = "misty-forest.png";
in
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
      # 壁纸: Noctalia 自带模块 (替代 swaybg), 图形面板可浏览/切换/收藏/轮换
      wallpaper = {
        enabled = true;
        fill_mode = "crop";                 # 铺满裁边, 等价原 swaybg -m fill
        directory = wallpaperDir;           # 面板浏览目录 = 部署出来的壁纸库
        default.path = "${wallpaperDir}/${defaultWallpaper}";
      };
    };
  };

  home.username = "reyear";
  home.homeDirectory = "/home/reyear";
  home.stateVersion = "26.05";

  # ============ 壁纸库: 仓库 background/ -> ~/.local/share/backgrounds ============
  # 整目录 store 符号链接 (只读, 跨代去重); Noctalia 壁纸面板浏览的就是这里
  home.file.".local/share/backgrounds".source = ../../background;

  # ============ XDG 用户目录: 全小写 (声明式替代 ~/Documents 等大写默认) ============
  # 生成 ~/.config/user-dirs.dirs; GLib/GTK/Noctalia/Firefox 等应用读它定位
  # documents/pictures 等目录, 而不是各自硬编码 ~/Documents。
  # createDirectories: 激活时自动补建缺失目录。
  # 注意: 老系统上已存在的大写目录 (~/Documents 等) 不会自动迁移, 数据需手动 mv;
  # publicShare/templates 极少用到, 保持 home-manager 默认值不在此声明。
  xdg.enable = true;
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/desktop";
    documents = "${config.home.homeDirectory}/documents";
    download = "${config.home.homeDirectory}/downloads";
    music = "${config.home.homeDirectory}/music";
    pictures = "${config.home.homeDirectory}/pictures";
    videos = "${config.home.homeDirectory}/videos";
  };

  # ============ 用户级程序 (按需添加) ============
  home.packages = with pkgs; [
    # 例: gh
  ];

  programs.git = {
    enable = true;
    # userName/userEmail 已弃用, 改用 settings (生成 .gitconfig)
    settings.user = {
      name = "reyear";
      email = "reyearocean@qq.com";
    };
  };

  programs.kitty.enable = true;

  # ============ Shell: bash (HM 托管 .bashrc) + Starship 提示符 ============
  # Starship: git 分支/状态, nix dev shell, python venv 等状态一目了然;
  # 配置避开 Nerd Font 字形 (分支符号置空), 系统字体即可完整渲染
  programs.bash.enable = true;
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;              # 提示符间不留空行, 更紧凑
      git_branch.symbol = "";            # 分支只显示名字
      directory.truncation_length = 3;   # 路径最多 3 级
    };
  };

  # ============ direnv: 项目级开发环境 ============
  # 项目里放 shell.nix / flake.nix, cd 进入自动加载 (python/node/gcc 版本隔离);
  # nix-direnv 带缓存, 重复进入秒开
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ============ niri 配置 (kdl 语法) ============
  # 完整选项见 https://yalter.github.io/niri/Configuration/
  # ⚠️ KDL 注释是 //, 不支持 # (home.nix 里的 # 只能出现在 nix 层, KDL 文本内必须用 //)
  home.file.".config/niri/config.kdl".text = ''
    input {
        keyboard {
            xkb {
                // 中文输入交给 fcitx5, 键盘布局保持 us
                layout "us"
            }
        }
        touchpad {
            tap
        }
    }

    // ---- 开机自启 ----
    // 壁纸已交给 Noctalia 壁纸模块 (settings.wallpaper), 不再 swaybg 自启
    spawn-at-startup "fcitx5" "-d"                 // 中文输入法
    spawn-at-startup "noctalia"                    // 桌面外壳 (compositor 启动是官方推荐, 勿用 systemd 服务)

    // ---- 快捷键 ----
    binds {
        // 应用 (⚠️ 键名必须是 xkbcommon keysym: 回车是 Return 不是 Enter)
        Mod+Return        { spawn "kitty"; }
        Mod+D            { spawn "fuzzel"; }
        Mod+Shift+E      { quit; }
        Mod+L            { spawn "swaylock"; }

        // 截图 / 录屏
        Mod+P            { spawn "sh" "-c" "grim -g \"$(slurp)\" - | wl-copy"; }
        Mod+Shift+P      { spawn "sh" "-c" "grim - | wl-copy"; }

        // 窗口管理 (niri 是横向平铺)
        Mod+Q            { close-window; }
        Mod+F            { maximize-column; }
        Mod+Shift+F      { fullscreen-window; }
        Mod+J            { focus-column-left; }
        Mod+K            { focus-column-right; }
        Mod+Shift+J      { move-column-left; }
        Mod+Shift+K      { move-column-right; }
        // 工作区绑定必须逐键展开: niri 不支持 "Mod+1..9" / "1..9" 范围语法 (解析报 unexpected token)
        Mod+1            { focus-workspace 1; }
        Mod+2            { focus-workspace 2; }
        Mod+3            { focus-workspace 3; }
        Mod+4            { focus-workspace 4; }
        Mod+5            { focus-workspace 5; }
        Mod+6            { focus-workspace 6; }
        Mod+7            { focus-workspace 7; }
        Mod+8            { focus-workspace 8; }
        Mod+9            { focus-workspace 9; }
        Mod+Shift+1      { move-column-to-workspace 1; }
        Mod+Shift+2      { move-column-to-workspace 2; }
        Mod+Shift+3      { move-column-to-workspace 3; }
        Mod+Shift+4      { move-column-to-workspace 4; }
        Mod+Shift+5      { move-column-to-workspace 5; }
        Mod+Shift+6      { move-column-to-workspace 6; }
        Mod+Shift+7      { move-column-to-workspace 7; }
        Mod+Shift+8      { move-column-to-workspace 8; }
        Mod+Shift+9      { move-column-to-workspace 9; }

        // 音量
        XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05+"; }
        XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05-"; }
        XF86AudioMute       { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }

        // 亮度
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
