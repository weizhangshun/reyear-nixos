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
#
#  安装过程中只需交互 2 次:
#    1. 选择目标磁盘 (默认选最大的那块, 自动转 by-id)
#    2. 输入 LUKS 加密密码 (两次确认)
# ============================================================
set -euo pipefail

cd "$(dirname "$0")"

# ---------- 0. 环境检查 ----------
if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行: sudo ./install.sh"
  exit 1
fi

# live 环境可能没开 flakes, 全局开启
export NIX_CONFIG="experimental-features = nix-command flakes"

echo "=== 3N 桌面 (NixOS + Niri + Noctalia) 一键安装 ==="

# ---------- 0.5 预检: flake 可求值性 (首次较慢, 需联网) ----------
echo ""
echo "=== 预检: nix flake check (首次较慢, 需联网) ==="
nix flake check
echo "预检通过 ✅"

# ---------- 1. 选择磁盘 ----------
# ⚠️ 双盘用户注意: 目标盘必须是【专门给 NixOS 用的盘】, Windows 盘绝不能被选中!
echo ""
echo "可用磁盘:"
lsblk -d -o NAME,SIZE,MODEL,TRAN

DEFAULT_DISK="$(lsblk -dno NAME,SIZE | sort -k2 -h | tail -1 | awk '{print "/dev/"$1}')"
while :; do
  read -r -p "要安装的磁盘 [默认 ${DEFAULT_DISK}]: " choice
  DISK="${choice:-$DEFAULT_DISK}"
  [[ "$DISK" == /dev/* ]] || DISK="/dev/$DISK"
  if lsblk -d "$DISK" >/dev/null 2>&1; then break; fi
  echo "无效磁盘: $DISK, 请重新输入"
done

# 换成 by-id, 避免重启后设备名变化导致无法引导
BY_ID="$(lsblk -no ID-LINK "$DISK" 2>/dev/null | head -1)"
if [ -n "$BY_ID" ]; then
  DISK="/dev/disk/by-id/$BY_ID"
fi

echo ""
echo "⚠️  即将【完全清空】并全新安装到以下磁盘:"
lsblk -d -o NAME,SIZE,MODEL "$DISK"
echo "   目标: $DISK"
echo "   请再次确认这是【专门给 NixOS 的盘】, Windows 盘被清空将无法恢复!"
read -r -p "输入 yes 继续: " confirm
[ "$confirm" = "yes" ] || { echo "已取消"; exit 1; }

# ---------- 2. 生成带真实磁盘路径的 disko 配置 ----------
sed "s|/dev/nvme0n1|$DISK|" hosts/reyear-nixos/disko.nix > /tmp/3n-disko.nix

# ---------- 3. 分区 / 格式化 / 挂载到 /mnt ----------
# 先 dry-run 验证生成的 disko 配置 (不会动磁盘)
echo ""
echo "=== disko 配置 dry-run 验证 ==="
nix run .#disko -- --mode disko --dry-run /tmp/3n-disko.nix

# 正式执行 (此处会提示输入两次 LUKS 加密密码)
echo ""
echo "=== 开始分区与格式化 (disko) ==="
nix run .#disko -- --mode disko /tmp/3n-disko.nix

# ---------- 4. 安装系统 ----------
# --no-root-passwd: 锁住 root; reyear 的密码在下一步交互设置
echo ""
echo "=== 开始安装系统 (nixos-install, 首次构建较久) ==="
nixos-install --flake .#reyear-nixos --root /mnt --no-root-passwd

# ---------- 4.5 设置 reyear 登录密码 (不写入仓库, 不落盘明文) ----------
echo ""
echo "=== 设置 reyear 的登录密码 ==="
read -r -s -p "新密码: " pw1; echo
read -r -s -p "再次输入确认: " pw2; echo
if [ -z "$pw1" ] || [ "$pw1" != "$pw2" ]; then
  echo "输入为空或两次不一致! 装好后可用: sudo nixos-enter --root /mnt passwd reyear 补救"
  exit 1
fi
echo "reyear:$pw1" | chroot /mnt /run/current-system/sw/bin/chpasswd
unset pw1 pw2
echo "密码已设置 ✅"

# ---------- 5. 完成提示 ----------
cat <<'EOF'

============================================================
安装完成!
  1. 重启进入新系统:  reboot
  2. 登录:  用户 reyear (装机时设置的密码)
  3. (可选) 注册 TPM 自动解锁, 之后开机免输密码:
       sudo systemd-cryptenroll --tpm2-device=auto /dev/disk/by-id/<你的盘>-part2
     撤销: sudo systemd-cryptenroll --wipe-slot=tpm2 <luks分区>
  4. 更新系统:  sudo nixos-rebuild switch --flake /etc/nixos
============================================================
EOF
