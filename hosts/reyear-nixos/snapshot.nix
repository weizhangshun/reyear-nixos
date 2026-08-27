# 可选: btrfs 快照 (snapper) —— 默认未启用, 启用后再 import
#
# 依赖: disko.nix 里的 @snapshots 子卷 (挂载在 /.snapshots), 满足 snapper 对
#       SUBVOLUME 内 .snapshots 子卷的要求
#
# 已对照 nixpkgs 源码 (nixos/modules/services/misc/snapper.nix) 核验:
#   - 没有 services.snapper.enable 选项: configs 非空即自动启用
#     (自动装 snapper 命令行工具 + snapperd + timeline/cleanup 定时器)
#   - 选项名是 snapper 配置文件的**大写键名** (SUBVOLUME / FSTYPE / TIMELINE_*)
#   - NixOS 方式不需要手动 `snapper create-config` (模块直接写 /etc/snapper/configs/root)
#
# 启用: 在 default.nix 的 imports 里加入 ./snapshot.nix, 然后 rebuild
# 验证: sudo snapper list
# 回滚: 救援环境下 sudo snapper rollback, 或参考 btrfs-system-restore 脚本
{ config, lib, pkgs, ... }:

{
  services.snapper.configs.root = {
    SUBVOLUME = "/";
    FSTYPE = "btrfs";               # 默认即 btrfs, 显式写出更清晰
    ALLOW_USERS = [ "reyear" ];     # 允许用户直接跑 snapper 命令 (可选)
    TIMELINE_CREATE = true;         # 按时生成快照
    TIMELINE_CLEANUP = true;        # 按保留策略清理
    TIMELINE_LIMIT_HOURLY = 5;
    TIMELINE_LIMIT_DAILY = 7;
    TIMELINE_LIMIT_WEEKLY = 4;
    TIMELINE_LIMIT_MONTHLY = 3;
  };
  # 更多键名见 man snapper-configs(5), 如 FREE_LIMIT / SPACE_CHECK / NO_CPU_THROTTLING
}
