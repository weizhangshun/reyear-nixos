#!/usr/bin/env bash
# ============================================================
#  注册 TPM 自动解锁 (开机免输 LUKS 密码)
#  用法: 装好系统首次登录后, 在系统里运行:  sudo ./tpm-enroll.sh
#  自动检测 LUKS 设备, 无需手填 UUID / 盘符
#  撤销:  sudo systemd-cryptenroll --wipe-slot=tpm2 <luks分区>
# ============================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行: sudo ./tpm-enroll.sh"
  exit 1
fi

# 从正在运行的系统自动找到 LUKS 底层分区 (例如 nvme0n1p2)
LUKS_DEV="/dev/$(lsblk -no PKNAME /dev/mapper/cryptroot 2>/dev/null | head -1)"

if [ -z "$LUKS_DEV" ] || [ "$LUKS_DEV" = "/dev/" ]; then
  echo "未能自动检测 LUKS 设备, 请手动执行:"
  echo "  lsblk -o NAME,TYPE | grep -i luks"
  echo "  sudo systemd-cryptenroll --tpm2-device=auto <上面查到的分区>"
  exit 1
fi

echo "检测到 LUKS 设备: $LUKS_DEV"
echo "正在注册 TPM2 自动解锁 (需主板开启 TPM)..."
systemd-cryptenroll --tpm2-device=auto "$LUKS_DEV"

echo ""
echo "✅ 完成! 重启验证免密解锁:  reboot"
echo "   (若重启仍需密码: sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 $LUKS_DEV)"
