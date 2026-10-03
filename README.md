# 3N 桌面: NixOS + Niri + Noctalia

[![CI](https://github.com/OceanReyear/reyear-nixos/actions/workflows/ci.yml/badge.svg)](https://github.com/OceanReyear/reyear-nixos/actions/workflows/ci.yml)

nixos-unstable / flake / home-manager / btrfs / LUKS+TPM / 最新内核 / 中文界面与输入。

> CI 会在每次推送时自动运行 `nix flake check` 验证配置可求值；每周一自动开 flake 输入更新 PR（`nix flake check` 验证通过后才创建），确认后合并即可小步升级。结果见仓库 Actions 页。

## 目录结构

```
├── flake.nix                    # 唯一入口 (inputs: nixpkgs-unstable, home-manager, disko, noctalia)
├── background/                  # 壁纸库 (部署到 ~/.local/share/backgrounds, Noctalia 壁纸面板切换)
├── install.sh                   # 一键安装脚本 (live 环境运行)
├── tpm-enroll.sh                # TPM 自动解锁注册 (自动检测, 无需填 UUID)
└── hosts/reyear-nixos/
    ├── default.nix              # 入口: 汇聚模块 + 启用 home-manager
    ├── disko.nix                # 磁盘: GPT + LUKS2 + btrfs 子卷 (声明式)
    ├── system.nix               # 内核/引导/硬件/时区/语言/输入法/字体/虚拟化/Docker/Nix
    ├── desktop.nix              # niri + Noctalia + Wayland 配套
    ├── home.nix                 # home-manager: niri 配置 / Rime 简体 / git
    └── snapshot.nix             # 可选: snapper 快照 (默认不启用)
```

## ⚠️ 已配置信息

| 项 | 值 |
|---|---|
| 主机名 | `reyear-nixos` |
| 用户名 | `reyear`（密码以 sha512crypt 哈希存于 `system.nix`）|
| git 身份 | `reyear <reyearocean@qq.com>` |
| 磁盘 | 安装时由 `install.sh` 交互选择；`disko.nix` 里的 `device` 只是占位符，脚本会自动替换 |

## 装机（全新安装）

方式 A — 一键脚本（推荐）：在 NixOS 安装盘 live 环境里

```bash
git clone https://github.com/OceanReyear/reyear-nixos && cd reyear-nixos
sudo ./install.sh
```

脚本流程：列出磁盘 -> 交互选择目标盘（默认最大物理盘，自动转 by-id）-> 确认清盘 -> 真实盘径就地写入 disko.nix（disko 分区与 nixos-install 求值共用同一份配置，装出的系统 initrd/挂载点指向真实 by-id 设备）-> disko dry-run 校验 -> disko 分区/格式化/挂载（此时输两次 LUKS 密码，输错可整步重试）-> nixos-install -> 复制本仓库到 /mnt/etc/nixos（保证重启后可 nixos-rebuild）。
分区方案已提前定好（见 `hosts/reyear-nixos/disko.nix`）：ESP 1G + LUKS2 全盘加密 + btrfs 九子卷（@/@nix/@home/@var/@log/@snapshots/@vm/@docker/@db），安装时无需再决定。大 IO 子卷单独调优：`@vm`→`/var/lib/libvirt/images`、`@db`→`/var/lib/postgresql` 均 nodatacow（关压缩/CoW）；`@docker`→`/var/lib/docker` 保留压缩；三者均不参与快照。

方式 B — nixos-anywhere（从任意 Linux 远程装机）：

```bash
nixos-anywhere --flake .#reyear-nixos root@<目标机IP>
```

> 方式 B 需先把 `hosts/reyear-nixos/disko.nix` 的 `device` 改成目标磁盘（方式 A 的脚本会自动替换，无需手改）。
> 两种方式首次运行都需联网拉取 nixpkgs 与依赖（耗时较长）。

## 首次开机后

```bash
passwd                                # 建议修改密码 (对应密码曾短暂公开, 仓库已转私密)
sudo ./tpm-enroll.sh                  # 注册 TPM2 自动解锁 (自动检测 LUKS 设备, 无需填 UUID)
```

> TPM 解锁依赖 `boot.initrd.systemd.enable = true`（已开启）。`tpm-enroll.sh` 会自动检测 LUKS 分区；撤销：`sudo systemd-cryptenroll --wipe-slot=tpm2 <luks分区>`。

## 日常更新 / 回滚

```bash
sudo nixos-rebuild switch --flake .#reyear-nixos          # 更新并切换
nix flake update                                 # 先升级锁定版本
# 翻车了:
#   1) 重启在 boot 菜单选上一个条目 (NixOS 自带回滚)
#   2) sudo nixos-rebuild switch --rollback --flake .#reyear-nixos
#   3) 文件层回滚: 后续接 snapper/btrbk 快照 @snapshots 已预留
```

## 已知注意事项

- 中文输入：fcitx5 在 niri 下走 Wayland text-input 协议；XWayland 应用（微信等）偶发失效，可用 `xwayland-satellite` 等方案排查。
- Rime 默认繁体：已用 `default.custom.yaml` 把默认 schema 切到 朙月拼音·简化字；不习惯 Rime 可直接删掉 `fcitx5-rime`，用 fcitx5 自带拼音。
- 最新内核 + unstable：翻车概率不低，boot 条目回滚是底线；N 卡用户注意兼容性（本机 Intel 核显无此问题）。
- `programs.niri` 选项：nixos-unstable（24.11+）自带；若 rebuild 报 "option does not exist"，说明 nixpkgs 过老，或改用 [sodiboo/niri-flake](https://deepwiki.com/sodiboo/niri-flake/2.1-nixos-module) 的模块。
- Noctalia 已接入：NixOS 模块（`nixosModules.default` + `recommendedServices`）+ home 模块（`homeModules.default` + 声明式 settings）；flake 用 **cachix 分支**保证缓存命中；启动走 niri `spawn-at-startup`（官方推荐 compositor 启动，勿用 systemd 服务）。
- Noctalia 主题：Stylix 对 noctalia 的支持还在 [issue #508](https://github.com/noctalia-dev/noctalia/issues/508)，先走它自己的主题机制。
- 可选进阶（后续加）：snapper 快照（见下）、impermanence 不可变根、Secure Boot（Lanzaboote）、sops-nix 密钥管理、stylix 统一配色。

## 可选：启用 snapper 快照

1. `hosts/reyear-nixos/default.nix` 的 imports 加入 `./snapshot.nix`
2. `sudo nixos-rebuild switch --flake .#reyear-nixos`（模块自动生成配置与定时器，无需手动 create-config）
3. `sudo snapper list` 验证快照
4. 回滚：救援环境下 `snapper rollback`，或参考 [btrfs-system-restore](https://github.com/viocost/btrfs-system-restore)

> ✅ 选项名已对照 nixpkgs 源码核验（大写键名如 SUBVOLUME / TIMELINE_CREATE；无 enable 选项）。

## 国内网络加速（TUNA 首要 + USTC 兜底）

二进制缓存首要源为**清华 TUNA 镜像**（`mirrors.tuna.tsinghua.edu.cn/nix-channels/store`，与官方 `cache.nixos.org` 同签名，内容一致），**中国科大镜像**（`mirrors.ustc.edu.cn/nix-channels/store`，priority=10）作为第二源兜底--两个镜像偶尔会临时 403/超时，互为备份。
> 注意生效层级：改 `system.nix` 的 substituters 要等 `nixos-rebuild switch` 激活后才写入 `/etc/nix/nix.conf`；想让**本次**重建立刻用新源，需直接改 `/etc/nix/nix.conf` 并 `sudo systemctl restart nix-daemon`。

可选：让 flake 输入（从 GitHub 拉取 nixpkgs 等源码）也走清华镜像：

```bash
git config --global url."https://mirrors.tuna.tsinghua.edu.cn/github/".insteadOf "https://github.com/"
```

> ⚠️ 该 git 配置全局生效；若以后访问 GitHub 异常，用 `git config --global --unset-all url.https://mirrors.tuna.tsinghua.edu.cn/github/.insteadOf` 撤销。

## 参考

- [Noctalia 官方 NixOS 文档](https://docs.noctalia.dev/noctalia/getting-started/nixos/) | [Noctalia GitHub](https://github.com/noctalia-dev/noctalia)
- [NixOS Wiki: Noctalia Shell](https://wiki.nixos.org/w/index.php?title=Noctalia_Shell)
- [CachyOS niri+noctalia 发行版（配置参考）](https://github.com/CachyOS/cachyos-niri-noctalia)
- [niri 官方文档](https://yalter.github.io/niri/) | [sodiboo/niri-flake（更新版 niri + Stylix）](https://deepwiki.com/sodiboo/niri-flake/6-reference)
