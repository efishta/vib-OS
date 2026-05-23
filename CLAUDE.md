# vib-OS Project & Agent Guidelines

## Project Overview
A minimal, educational operating system built via conversational prompting and autonomous agentic workflows ("vibe coding").
- **Repository:** https://github.com/viralcode/vib-OS
- **Target Architecture:** ARM64 (Primary) and x86_64 running inside QEMU.
- *Note: The x86_64 port is notoriously buggy. Features like the TCP/IP stack, file manager directory creation, and Doom port will require extensive debugging.*

## Architecture & Bare-Metal Constraints
- **Languages:** Assembly for the bootloader; C (C11 standard) for the kernel and userspace.
- **NO LIBC in kernel:** This is a bare-metal environment. You CANNOT use `<stdio.h>`, `<stdlib.h>`, `malloc()`, or `printf()`. Do not attempt to include standard user-space headers.
- **Memory Management:** Use custom physical/virtual memory managers (e.g., block/inode bitmaps for the EXT4 implementation).
- **I/O:** Use direct framebuffer access for graphics, and custom `kprint()` mapping for text buffers.
- **Userspace** uses musl libc compiled for `aarch64-linux-musl`.

## Build & Emulation Commands
Stop and verify your work using the repository's native toolchain scripts. Do not invent custom build commands.
- **Initial Setup:** `./scripts/setup-toolchain-linux.sh`
- **Build Everything:** `make clean && make all`
- **Run Emulation (Terminal Mode):** `make run` or `make qemu`
- **Run Emulation (GUI Mode):** `make run-gui`
- **Network/GDB Debugging:** `make qemu-debug`

## Project Structure

```
kernel/       → OS kernel (134K lines C/asm)
  arch/       → ARM64 boot.S, GICv3, timer, context switch; x86_64/86 variants
  core/       → main.c (kernel_main entry), process.c, printk.c
  mm/         → PMM (bitmap allocator), VMM (4-level paging), kmalloc, ASLR
  fs/         → VFS layer + RamFS, EXT4 (R/W), FAT32, APFS (read-only)
  net/        → TCP/IP stack (Eth/ARP/IP/ICMP/UDP/TCP), sockets, DNS
  sched/      → Preemptive scheduler, fork, signals
  sync/       → IRQ-safe spinlocks
  gui/        → Window manager (4899 lines), desktop compositor, terminal emu, font
  syscall/    → Syscall dispatcher
  loader/     → ELF binary loader
  sandbox/    → Fault-isolated decoder sandbox
  ipc/        → Pipes
  apps/       → File manager, Doom, media player, launcher
  drivers/    → PCI bus, Intel HDA audio
  media/      → JPEG decoder (picojpeg), wallpaper assets
drivers/      → External device drivers
  network/    → virtio_net.c
  input/      → virtio_input.c (keyboard, tablet)
  gpu/        → virtio_gpu.c, agx.c (Apple GPU)
  video/      → ramfb.c, bochs.c, fb.c
  nvme/       → ans.c (NVMe controller)
  usb/        → xhci.c, usb_hid.c, usb_msd.c
  bluetooth/  → hci.c
  uart/       → uart.c
  platform/   → rpi.c
libc/         → musl-based C library for userspace
userspace/    → init (PID 1), shell, login
boot/         → Bootloader configs (BIOS, EFI, GRUB)
vendor/       → MicroPython, Nanolang (embedded runtimes)
scripts/      → Build scripts, toolchain setup
vib-os-x86_64/→ Standalone x86_64 UEFI variant
```

## Key File Paths
- Kernel entry: `kernel/core/main.c` (line 560)
- ARM64 boot asm: `kernel/arch/arm64/boot.S` (515 lines)
- Linker script: `kernel/linker.ld`
- Makefile: `Makefile`
- TCP/IP stack: `kernel/net/tcp_ip.c` (982 lines)
- EXT4: `kernel/fs/ext4.c` (1233 lines)
- Window manager: `kernel/gui/window.c` (4889 lines)
- VMM: `kernel/mm/vmm.c`
- Scheduler: `kernel/sched/sched.c`
- Image creation: `scripts/create-boot-image.sh`

## Boot Flow
1. UEFI/Limine → `boot.S` → detect EL2→EL1, set vectors, kernel stack
2. `kernel_main()` in 5 phases:
   - Phase 1: GICv3 interrupt controller, ARM generic timer
   - Phase 2: PMM → VMM (MMU enabled) → kmalloc heap
   - Phase 3: Preemptive scheduler, process subsystem
   - Phase 4: VFS + RamFS (root mount), EXT4/FAT32/APFS
   - Phase 5: PCI bus scan, framebuffer, GUI desktop, networking
3. Spawn `/sbin/init` → enter scheduler

## Known Issues
- **Init process stalls after ELF load:** `/sbin/init` loads successfully (`[ELF] Loading EXEC at 0x667a0000 (7 program headers)`), but the loader (or init itself) hangs/crashes before producing more output. Possibly segment vaddr overlap with kernel identity-mapped region, or PIE/EXEC mismatch.
- **x86_64 port:** Buggy, especially TCP/IP stack, file manager directory creation, Doom port.
- **RamFB config:** `RAMFB: Config file not found` warning on boot (non-fatal).
- **No virtio-gpu:** Falls back to software rendering (ramfb).
- **vfs_read_compat RAMFS bug fixed** (2026-05-22): `node->internal` stores raw data buffer, not `ramfs_inode` pointer. Fixed to read buffer directly.

## The Agentic Development Loop
- **Test-Driven Design:** Outline C structures or Assembly routines required before bulk-writing code. Write automated tests or verification checks where possible.
- **Fail Gracefully:** If `make` fails, analyze GCC/Clang/NASM error output and attempt a fix up to 3 times. If still fails, pause and explain.
- **Atomic Commits:** Create a Git commit with a descriptive message after every successfully implemented and verified feature.

## Code Style
- **Standard:** Follow kernel coding style (K&R braces, C11).
- **Indentation:** 4 spaces (no tabs).
- **Naming:** `snake_case` for variables and functions. `UPPER_SNAKE_CASE` for macros.
- **Documentation:** Every function must have a brief block comment explaining parameters, especially when executing pointer arithmetic or hardware I/O.