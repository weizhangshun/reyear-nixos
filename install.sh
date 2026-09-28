#!/usr/bin/env bash
# ============================================================
#  3N 桌面 (NixOS + Niri + Noctalia) 一键安装脚本
#
#  用法 (NixOS 安装盘 live 环境):
#    git clone https://github.com/OceanReyear/reyear-nixos && cd reyear-nixos
#    sudo ./install.sh
#
#  分区方案 (已提前定好, 见 hosts/reyear-nixos/disko.nix):
#    ESP 1G (vfat, /boot) + LUKS2 全盘加密 + btrfs 子卷:
#    @ -> /   @nix -> /nix   @home -> /home
#    @var -> /var   @log -> /var/log   @snapshots -> /.snapshots
#    @vm -> /var/lib/libvirt/images  @db -> /var/lib/postgresql   (nodatacow)
#    @docker -> /var/lib/docker   (保留压缩)
#
#  运行时输出一律使用英文: NixOS 安装盘的裸 TTY 字体不含 CJK 字形,
#  中文会显示为方块 (豆腐块), 英文保证任何控制台可读。
#
#  交互点共 3 处:
#    1. 选择目标磁盘 (默认最大物理盘, 自动转 by-id)
#    2. 输入 yes 确认清盘
#    3. LUKS 加密密码输两次 (由 disko 提示; 不一致可整步重试)
#
#  流程 (关键设计: 真实磁盘路径就地写入仓库的 disko.nix,
#  让 disko 分区与 nixos-install 求值用同一份配置, 装出来的系统
#  boot.initrd.luks.devices / fileSystems 指向真实 by-id 设备):
#    flake check -> 选盘 -> 就地 sed -> disko dry-run
#    -> disko destroy,format,mount -> nixos-install
#    -> 复制本仓库到 /mnt/etc/nixos (重启后才能 nixos-rebuild)
# ============================================================
set -euo pipefail

cd "$(dirname "$0")"

# ---------- 0. 环境检查 ----------
if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo ./install.sh"
  exit 1
fi

# ---------- 0.1 内存预检 ----------
# live ISO 的 /nix/store 可写部分是内存 tmpfs: 每个下载的包都占 RAM,
# 内存不足会在下载工具闭包或 nixos-install 时报 No space left on device
MEM_AVAIL_KB="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
if [ "${MEM_AVAIL_KB:-0}" -lt 6000000 ]; then
  echo "WARNING: only $((MEM_AVAIL_KB / 1024)) MiB RAM available."
  echo "  The live ISO store is RAM-backed; low RAM causes 'No space left on"
  echo "  device' while downloading packages. Give this VM >= 8 GB RAM, or run:"
  echo "    mount -o remount,size=6G /nix/.rw-store"
  read -r -p "Continue anyway? [y/N]: " lowram
  [ "$lowram" = "y" ] || exit 1
fi

# live 环境可能没开 flakes, 全局开启
export NIX_CONFIG="experimental-features = nix-command flakes"

echo "=== 3N Desktop (NixOS + Niri + Noctalia) Installer ==="

# ---------- 0.5 预检: flake 可求值性 (首次较慢, 需联网) ----------
# 放在动磁盘之前: 配置求值失败就中止, 避免清完盘才发现问题
echo ""
echo "=== Precheck: nix flake check (first run is slow, needs network) ==="
nix flake check
echo "Precheck passed."

# ---------- 1. 选择磁盘 ----------
# ⚠️ 双盘用户注意: 目标盘必须是【专门给 NixOS 用的盘】, Windows 盘绝不能被选中!
echo ""
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL,TRAN

# 默认盘: 只认物理磁盘 (TYPE=disk), 排除 zram/loop 等虚拟设备, 取容量最大者
DEFAULT_DISK="$(
  lsblk -dno NAME,SIZE,TYPE,TRAN \
    | awk '$3 == "disk" && $1 !~ /^zram/ {print $1, $2}' \
    | sort -k2 -h | tail -1 | awk '{print "/dev/"$1}'
)"
while :; do
  read -r -p "Disk to install to [default ${DEFAULT_DISK:-none}]: " choice
  DISK="${choice:-$DEFAULT_DISK}"
  [ -n "$DISK" ] || { echo "No disk selected, try again"; continue; }
  [[ "$DISK" == /dev/* ]] || DISK="/dev/$DISK"
  if lsblk -d "$DISK" >/dev/null 2>&1; then break; fi
  echo "Invalid disk: $DISK, try again"
done

# 换成 by-id, 避免重启后设备名变化导致无法引导
BY_ID="$(lsblk -no ID-LINK "$DISK" 2>/dev/null | head -1)"
if [ -n "$BY_ID" ]; then
  DISK="/dev/disk/by-id/$BY_ID"
fi

echo ""
echo "WARNING: this will COMPLETELY WIPE and install to the disk below:"
lsblk -d -o NAME,SIZE,MODEL "$DISK"
echo "   Target: $DISK"
echo "   Confirm this is the DEDICATED NixOS disk. Wiping a Windows disk is IRREVERSIBLE!"
read -r -p "Type yes to continue: " confirm
[ "$confirm" = "yes" ] || { echo "Cancelled"; exit 1; }

# ---------- 2. 把真实盘径【就地】写入仓库的 disko.nix ----------
# 不用 /tmp 副本: 第 4 步 nixos-install 求值的是本仓库 flake,
# 装好系统的 initrd LUKS 解锁配置与 fileSystems 都从这里生成,
# 必须指向真实 by-id 设备而不是占位符 /dev/nvme0n1。
DISKO_NIX="hosts/reyear-nixos/disko.nix"
# 重跑时先还原成仓库原始版本, 保证占位符存在 (live 环境的临时 clone, 安全)
git checkout -- "$DISKO_NIX" 2>/dev/null || true
sed -i "s|/dev/nvme0n1|$DISK|" "$DISKO_NIX"
grep -qF "$DISK" "$DISKO_NIX" || { echo "ERROR: failed to patch device in $DISKO_NIX"; exit 1; }
echo "Patched $DISKO_NIX -> $DISK"

# ---------- 3. 分区 / 格式化 / 挂载到 /mnt ----------
# 先 dry-run: 只构建 disko 脚本 (能捕获求值错误), 不动磁盘
echo ""
echo "=== disko config dry-run validation ==="
nix run .#disko -- --mode destroy,format,mount --dry-run "$DISKO_NIX"

# 正式执行: disko 会提示输入两次 LUKS 密码; 两次不一致 disko 会
# 直接中止 (其内部重试实现有缺陷), 这里包一层整步重试
echo ""
echo "=== Partitioning & formatting (disko) ==="
while ! nix run .#disko -- --mode destroy,format,mount "$DISKO_NIX"; do
  read -r -p "disko failed (passphrase mismatch aborts it). Retry from scratch? [y/N]: " retry
  [ "$retry" = "y" ] || { echo "Aborted"; exit 1; }
done

# ---------- 4. 安装系统 ----------
# --no-root-passwd: 锁住 root; reyear 的密码哈希在 system.nix (hashedPassword)
echo ""
echo "=== Installing system (nixos-install, first build takes a while) ==="
nixos-install --flake .#reyear-nixos --root /mnt --no-root-passwd

# ---------- 5. 把本仓库复制进目标系统 ----------
# nixos-install 不会复制 flake 源码; 不做这步, 重启后
# nixos-rebuild switch --flake /etc/nixos 无法执行
echo ""
echo "=== Copying this repo to /mnt/etc/nixos (so nixos-rebuild works) ==="
mkdir -p /mnt/etc/nixos
tar -cf - . | tar -xf - -C /mnt/etc/nixos
echo "Done."

# ---------- 6. 完成提示 ----------
cat <<'EOF'

============================================================
Installation complete!
  1. Reboot into the new system:      reboot
  2. Log in as user 'reyear' (password hash preconfigured in system.nix)
  3. (Optional) Enroll TPM auto-unlock to skip the LUKS passphrase at boot
     (auto-detects the LUKS device, no UUID needed):
         sudo ./tpm-enroll.sh
     To revoke:  sudo systemd-cryptenroll --wipe-slot=tpm2 <luks-partition>
  4. Update the system later:
         cd /etc/nixos && sudo nixos-rebuild switch --flake .#reyear-nixos
============================================================
EOF
