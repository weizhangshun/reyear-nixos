# 声明式磁盘布局: GPT + LUKS2 全盘加密 + btrfs 子卷
# 磁盘: install.sh 会自动把 device 替换为所选磁盘; 若用 nixos-anywhere 方式需手动改成 by-id
# 签名必须是 { ... }: 而不是 { config, lib, ... }: — disko CLI 调用本文件时
# 只传 lib/mode/pkgs 等参数, 声明 config 会导致 "called without required argument 'config'"
{ ... }:

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
                # 虚拟机镜像: 挂在 libvirt 默认存储路径; 关压缩关 CoW
                # (镜像是大块随机写, 压缩白耗 CPU, CoW 拖出碎片; nodatacow 是
                #  btrfs 放 VM 磁盘的标准姿势, 内核 4.13+ 起各子卷挂载选项独立生效)
                "@vm" =       { mountpoint = "/var/lib/libvirt/images"; mountOptions = [ "nodatacow" "compress=no" "noatime" ]; };
                # Docker 数据 (镜像层/容器可写层/volumes): 高频变动且可再生,
                # 不参与快照; 镜像层一次写入多次读, 保留压缩与 CoW 反而省空间
                "@docker" =   { mountpoint = "/var/lib/docker";          mountOptions = [ "compress=zstd" "noatime" ]; };
                # 本机数据库 (PostgreSQL 默认数据路径): WAL 随机写 + fsync 密集,
                # CoW 造成写放大与碎片 -> nodatacow (dev 库可重建, 舍校验换性能;
                # 容器里的数据库落 @docker, 不在此)
                "@db" =       { mountpoint = "/var/lib/postgresql";      mountOptions = [ "nodatacow" "compress=no" "noatime" ]; };
              };
            };
          };
        };
      };
    };
  };
}
