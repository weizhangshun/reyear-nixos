# Installing Arch on a new runner box

A copy-paste walkthrough for taking an identical machine (Intel N100 mini PC,
~477 GB SATA SSD, UEFI) from the Arch ISO to the point where
`scripts/bootstrap-arch-runner.sh` takes over. It reproduces the layout of
`builder-linux1` with one simplification, explained at the end.

Target layout:

| Partition / volume | Size | Filesystem | Mount |
|---|---|---|---|
| `/dev/sda1` | 1 GB | FAT32 (EFI System) | `/boot` |
| `/dev/sda2` | rest of disk | LVM physical volume, volume group `volgroup0` | |
| `volgroup0/lv_root` | 100 GB | ext4 | `/` |
| `volgroup0/lv_home` | rest of the VG | ext4 | `/home` |

`builder-linux1` has a 70 GB root. `/nix` lives on root and 70 GB has needed
regular garbage collection, so 100 GB is the recommended size for the new box.
Adjust the `-L 100G` below if you want something else.

**Everything below runs as root from the Arch live ISO and wipes `/dev/sda`.**
Check `lsblk` first and make sure `/dev/sda` is the internal SSD, not the USB
stick.

## 1. Boot the ISO and get online

Boot the USB in UEFI mode. Ethernet comes up on its own.

```bash
cat /sys/firmware/efi/fw_platform_size   # must print 64
ping -c 2 archlinux.org
timedatectl                              # confirm NTP is synchronised
lsblk                                    # confirm /dev/sda is the SSD
reflector --country US --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
pacman -Sy archlinux-keyring
```

The last two lines matter. `pacstrap` copies the live ISO's mirrorlist into
the new system, so a bad list here follows you onto the disk, and an ISO
older than a few months carries stale signing keys. If `pacman -Sy` fails
with a download error, check `date` (a wrong clock breaks TLS) and
`ip -br addr` (no address means no network) before retrying.

The ISO shell is zsh with extended globbing. Quote any grep pattern that
starts with `^`, for example `grep '^HOOKS' file`, or zsh will try to expand
it as a glob and report "no matches found".

## 2. Partition, LVM, filesystems

```bash
DISK=/dev/sda
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:EFI "$DISK"
sgdisk -n2:0:0   -t2:8e00 -c2:LVM "$DISK"

pvcreate "${DISK}2"
vgcreate volgroup0 "${DISK}2"
lvcreate -L 100G     -n lv_root volgroup0
lvcreate -l 100%FREE -n lv_home volgroup0

mkfs.fat -F32 "${DISK}1"
mkfs.ext4 /dev/volgroup0/lv_root
mkfs.ext4 /dev/volgroup0/lv_home

mount /dev/volgroup0/lv_root /mnt
mount --mkdir "${DISK}1" /mnt/boot
mount --mkdir /dev/volgroup0/lv_home /mnt/home
```

## 3. Install the base system

Only what is needed to boot, get online, and clone this repo. The bootstrap
script installs the rest from `pkglist-native.txt`.

```bash
pacstrap -K /mnt base base-devel linux linux-headers linux-lts linux-lts-headers \
    linux-firmware intel-ucode lvm2 grub efibootmgr networkmanager sudo git nano
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
```

## 4. Configure inside the chroot

Change `HOSTNAME` to the next free `builder-linuxN`.

Before running `passwd` for root, generate a unique password in your password
manager and save it as an entry named `<hostname> root` (for example
`builder-linux2 root`). You will type it at the console, so turn off
ambiguous characters in the generator. Nothing else records this
password. Neither these steps nor any later provisioning sets it, and it is
the only way into emergency mode on a headless runner. Use a different
password on each runner so that a leak from one box doesn't expose the
others. If a runner's root password is ever lost, reset it with
`sudo passwd root` and update the password manager entry.

```bash
HOSTNAME=builder-linux2

ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
hwclock --systohc
readlink /etc/localtime    # must print /usr/share/zoneinfo/America/Chicago
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname

ls /boot   # must list vmlinuz-linux and vmlinuz-linux-lts; if not, run: pacman -S linux linux-lts
nano /etc/mkinitcpio.conf
```

In nano, replace the whole `HOOKS=(...)` line with the one below, then save
with Ctrl+O, Enter and exit with Ctrl+X. Same hook set as builder-linux1;
`lvm2` before `filesystems` is what matters. Without it the initramfs cannot
find the root volume and boot stops with "Timed out waiting for device
/dev/mapper/volgroup0-lv_root".

```
HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap sd-vconsole block lvm2 filesystems fsck)
```

```bash
grep '^HOOKS' /etc/mkinitcpio.conf      # confirm the edit saved
mkinitcpio -P
lsinitcpio /boot/initramfs-linux.img | grep -c lvm   # must be greater than 0

passwd                                   # root password from your password manager; needed to log in to emergency mode
useradd -m -G wheel kourtni
passwd kourtni
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

systemctl enable NetworkManager systemd-timesyncd

# Boot the LTS kernel by default. Without this, grub-mkconfig chooses the
# top-level entry by sorting the vmlinuz-* filenames, so which kernel boots
# depends on which kernels happened to exist when grub.cfg was last
# generated. That is how builder-linux1 ended up on mainline and
# builder-linux2 on LTS from the same package set. Mainline stays installed
# and bootable under "Advanced options" as a recovery kernel.
echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-lts"' >> /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
grep -m1 -A15 "^menuentry" /boot/grub/grub.cfg | grep vmlinuz   # must show vmlinuz-linux-lts
exit
```

## 5. Reboot

```bash
umount -R /mnt
reboot
```

Pull the USB stick when the screen goes blank. Log in as `kourtni`. The
prompt should read `kourtni@builder-linux2`; if it says `archlinux`, the
hostname step in the chroot was missed, and the runner would register under
the wrong name. Fix it before running the bootstrap script:

```bash
sudo hostnamectl set-hostname builder-linux2
```

Then check that you are online with `ping -c 2 archlinux.org`. If not:

```bash
sudo systemctl enable --now NetworkManager
nmcli device status
nmcli device wifi list                   # only if you need Wi-Fi for now
nmcli device wifi connect "<SSID>" --ask
```

Then continue from step 2 of [README.md](README.md). The bootstrap script
asks for your sudo password once at the start and keeps it alive, so it runs
unattended after that.

## If the first boot lands in emergency mode

- **"Timed out waiting for device /dev/mapper/volgroup0-lv_root"**: the
  initramfs has no LVM support. Boot the ISO, `vgchange -ay`, mount root at
  `/mnt` and the EFI partition at `/mnt/boot`, `arch-chroot /mnt`, then redo
  the mkinitcpio part of step 4.
- **"Cannot open access to console, the root account is locked"**: this
  appears alongside the real error; it just means the rescue shell has no
  password to accept. Fix the real error above. If it happens after root is
  mounted, the `passwd` step in the chroot was skipped.
- **A mount unit fails**: `fstab` is stale. From the ISO, mount everything
  under `/mnt` as in step 2 and run `genfstab -U /mnt > /mnt/etc/fstab`
  (single `>` to overwrite).

## How this differs from builder-linux1

`builder-linux1` was installed by hand with three partitions: a 1 GB FAT32
partition holding only the GRUB EFI binary, a separate 1 GB ext4 `/boot`, and
the LVM volume. The EFI partition is not in its `fstab` and is not flagged as
an EFI System Partition, which works but makes `grub-install` reruns awkward.
The layout above merges the two into one properly flagged EFI partition
mounted at `/boot`, which is the Arch wiki's standard arrangement. Nothing in
this repo depends on the difference.

`builder-linux1` also has no `intel-ucode` installed. The new box gets it in
`pacstrap`; run `sudo pacman -S intel-ucode && sudo grub-mkconfig -o
/boot/grub/grub.cfg` on the old box to match.

## Keeping the boxes identical

Both boxes install `linux` and `linux-lts` and **boot LTS**. Nothing above is
a one-time step: `scripts/bootstrap-arch-runner.sh` re-applies the timezone,
the time sync service and the `GRUB_TOP_LEVEL` kernel pin on every run, so
re-running it on an older box brings it in line. A box that was already
running mainline needs a reboot after that run to land on LTS.

Two things the bootstrap script cannot make identical:

- **Kernel and package versions.** Arch is rolling, so boxes built weeks
  apart differ until they are upgraded together. `sudo pacman -Syu` on both
  in the same sitting is the only way to line them up, and the runners
  should be idle when you do it.
- **The disk layout**, which is fixed at install time (see above).

`hostnamectl` and `timedatectl` on both boxes are the quickest check that a
pair has not drifted apart.
