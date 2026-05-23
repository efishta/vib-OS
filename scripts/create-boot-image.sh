#!/bin/bash
# Create bootable disk image for UnixOS
# Creates a GPT-partitioned disk image with EFI and root partitions
# Supports both Linux and macOS

set -e

BUILD_DIR="$(cd "${1:-build}" 2>/dev/null && pwd || echo "$(pwd)/${1:-build}")"
IMAGE_DIR="${2:-image}"
IMAGE_NAME="unixos.img"
IMAGE_SIZE="1G"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[IMAGE]${NC} $1"
}

# Install boot files into the EFI partition mount point
install_kernel() {
    local mount_point="$1"
    local build_dir="$2"
    mkdir -p "$mount_point/EFI/BOOT"

    if [ -f "$build_dir/kernel/unixos.efi" ]; then
        cp "$build_dir/kernel/unixos.efi" "$mount_point/EFI/BOOT/BOOTAA64.EFI"
        log "Copied kernel EFI stub"
    elif [ -f "$build_dir/kernel/unixos.elf" ]; then
        log "Creating boot configuration..."
        cat > "$mount_point/EFI/BOOT/startup.nsh" << 'EOF'
@echo -off
echo UnixOS Boot Loader
echo Loading kernel...
\EFI\BOOT\kernel.elf
EOF
        cp "$build_dir/kernel/unixos.elf" "$mount_point/EFI/BOOT/kernel.elf" 2>/dev/null || {
            log "Kernel not yet built, creating placeholder..."
            echo "UnixOS kernel placeholder" > "$mount_point/EFI/BOOT/kernel.txt"
        }
    else
        log "Kernel not yet built, creating boot structure only..."
        echo "UnixOS - Kernel not yet built" > "$mount_point/EFI/BOOT/README.txt"
    fi

    cat > "$mount_point/EFI/BOOT/boot.json" << EOF
{
    "name": "UnixOS",
    "version": "0.1.0",
    "arch": "arm64",
    "kernel": "kernel.elf",
    "cmdline": "console=serial0 root=/dev/nvme0n1p2"
}
EOF
}

# Create image directory
mkdir -p "$IMAGE_DIR"

IMAGE_PATH="$IMAGE_DIR/$IMAGE_NAME"

log "Creating disk image: $IMAGE_PATH ($IMAGE_SIZE)"

# Create empty disk image
dd if=/dev/zero of="$IMAGE_PATH" bs=1M count=1024 2>/dev/null

log "Creating GPT partition table..."

case "$(uname -s)" in
Darwin)
    # macOS path using hdiutil/diskutil
    DISK=$(hdiutil attach -nomount "$IMAGE_PATH" | head -1 | awk '{print $1}')

    if [ -z "$DISK" ]; then
        log "Failed to attach disk image"
        exit 1
    fi

    log "Attached disk image as $DISK"

    diskutil partitionDisk "$DISK" GPT \
        FAT32 EFI 500M \
        "Free Space" ROOT R \
        2>/dev/null || {
        log "Using fallback partition method..."
        diskutil eraseDisk GPT UnixOS "$DISK"
    }

    EFI_PART="${DISK}s1"

    EFI_MOUNT=$(mktemp -d)
    mount -t msdos "$EFI_PART" "$EFI_MOUNT" 2>/dev/null || {
        diskutil mount "$EFI_PART"
        EFI_MOUNT="/Volumes/EFI"
    }

    log "EFI mounted at $EFI_MOUNT"
    install_kernel "$EFI_MOUNT" "$BUILD_DIR"
    sync

    log "Unmounting partitions..."
    umount "$EFI_MOUNT" 2>/dev/null || diskutil unmount "$EFI_PART" 2>/dev/null || true

    hdiutil detach "$DISK" 2>/dev/null || {
        log "Disk may be in use, force detaching..."
        hdiutil detach "$DISK" -force
    }
    ;;
Linux)
    # Linux path using parted directly on image file + loop device for mount
    log "Creating GPT partition table..."

    parted -s "$IMAGE_PATH" mklabel gpt
    parted -s "$IMAGE_PATH" mkpart primary fat32 1MiB 501MiB
    parted -s "$IMAGE_PATH" set 1 esp on
    parted -s "$IMAGE_PATH" mkpart primary 501MiB 100%

    log "Setting up loop device for EFI partition..."
    EFI_OFFSET=$((1 * 1024 * 1024))  # 1MiB offset
    EFI_SIZE=$((500 * 1024 * 1024))  # 500MiB

    LOOP_DEV=$(sudo losetup -f --show -o "$EFI_OFFSET" --sizelimit "$EFI_SIZE" "$IMAGE_PATH")
    log "Using loop device: $LOOP_DEV (offset: $EFI_OFFSET, size: $EFI_SIZE)"

    log "Formatting EFI partition..."
    sudo mkfs.vfat -F 32 -n "EFI" "$LOOP_DEV"

    EFI_MOUNT=$(mktemp -d)
    sudo mount "$LOOP_DEV" "$EFI_MOUNT"
    log "EFI mounted at $EFI_MOUNT"

    # Copy kernel into EFI partition (running as root since mount is root-owned)
    sudo bash -c "$(declare -f install_kernel log); install_kernel \"$EFI_MOUNT\" \"$BUILD_DIR\""
    sync

    log "Unmounting partitions..."
    sudo umount "$EFI_MOUNT"

    log "Detaching loop device..."
    sudo losetup -d "$LOOP_DEV"
    ;;
*)
    log "Unsupported OS: $(uname -s)"
    exit 1
    ;;
esac

log "Boot image created successfully: $IMAGE_PATH"
ls -lh "$IMAGE_PATH"

echo ""
log "To test in QEMU: make qemu"
log "To write to USB: sudo dd if=$IMAGE_PATH of=/dev/sdX bs=4M"