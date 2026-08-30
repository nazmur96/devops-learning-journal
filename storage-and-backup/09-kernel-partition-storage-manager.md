# 09 — Automated Kernel Partition & Storage Manager

**Objective:** Handle growing storage needs by isolating structures with logical volumes.

**Tech:** LVM, Bash, Linux filesystem tools.

## Key points

- **The LVM stack.** Physical Volume (PV, a disk/partition) → Volume Group (VG, a pool
  of PVs) → Logical Volume (LV, carved from the VG, holds a filesystem). Understand this
  three-layer model — it's the whole mental picture.
- **Why LVM over raw partitions.** LVs can be **resized online**, span disks, and
  snapshot — things fixed partitions can't do. This flexibility is the point.
- **filesystem vs volume are separate layers.** Growing an LV (`lvextend`) does *not*
  grow the filesystem; you then run `resize2fs` (ext4) or `xfs_growfs` (XFS —
  **Fedora's default**, and XFS can only grow, never shrink). Confusing these two
  layers is the classic mistake.
- **Mounting & `/etc/fstab`.** How a filesystem gets mapped to a directory at boot;
  a bad fstab entry can prevent boot. Understand `UUID=` vs device names.
- **Capacity failover logic.** "Cleanup at 85%" = monitor usage (`df`), trigger a
  purge or an `lvextend` when crossed. Understand thresholds like project 02.

## When to use it

- Servers whose storage needs grow unpredictably (logs, databases).
- When you want to add a disk and expand a filesystem without downtime.

## Scenario

`/var/log` is on its own LV. It fills to 85%. Your script either extends the LV from
free VG space and grows the XFS filesystem online — or purges old logs — before it hits
100% and takes the service down. No reboot, no repartitioning.

## Where AI misleads

- **Forgetting the filesystem-grow step.** AI runs `lvextend` and calls it done, leaving
  the filesystem the old size. You must also `xfs_growfs`/`resize2fs`. Huge, common trap.
- **ext4 assumptions on Fedora (XFS).** AI suggests `resize2fs`; Fedora root is usually
  **XFS**, needing `xfs_growfs`. And XFS **cannot shrink** — AI may claim it can.
- **Destructive commands.** `pvcreate`, `mkfs`, `lvremove`, editing partition tables can
  wipe data instantly. AI issues these without dry-run/backup warnings. Extreme caution.
- **fstab mistakes that block boot.** A wrong entry can drop you to emergency mode. AI
  rarely warns to test with `mount -a` before rebooting.
- **Confusing the three layers.** AI mixes PV/VG/LV terminology, producing commands
  aimed at the wrong layer.

> ⚠️ This project touches real disks. Practice on a **loopback file or spare VM disk**,
> never your live root, until you can explain every command.
