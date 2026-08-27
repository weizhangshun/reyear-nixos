# 声明式磁盘布局: GPT + LUKS2 全盘加密 + btrfs 子卷
# 磁盘: install.sh 会自动把 device 替换为所选磁盘; 若用 nixos-anywhere 方式需手动改成 by-id
{ config, lib, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";   # 占位: install.sh 自动替换; nixos-anywhere 方式需手动改

    content = {
      type = "gpt";
      partitions = {
        # EFI 引导分区
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };

        # LUKS2 加密根分区 (TPM 自动解锁见 README)
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              # attrsOf 形式 (已对照 disko 源码 lib/types/btrfs.nix): 键 = 子卷名, 值 = { mountpoint, mountOptions }
              subvolumes = {
                # 系统根: 回滚对象
                "@" =          { mountpoint = "/";           mountOptions = [ "compress=zstd" "noatime" ]; };
                # nix store 单独子卷, 快照不膨胀
                "@nix" =       { mountpoint = "/nix";        mountOptions = [ "compress=zstd" "noatime" ]; };
                "@home" =      { mountpoint = "/home";       mountOptions = [ "compress=zstd" "noatime" ]; };
                "@var" =       { mountpoint = "/var";        mountOptions = [ "compress=zstd" "noatime" ]; };
                "@log" =       { mountpoint = "/var/log";    mountOptions = [ "compress=zstd" "noatime" ]; };
                # 快照挂载点 (后续接 snapper / btrbk)
                "@snapshots" = { mountpoint = "/.snapshots"; mountOptions = [ "compress=zstd" "noatime" ]; };
              };
            };
          };
        };
      };
    };
  };
}
