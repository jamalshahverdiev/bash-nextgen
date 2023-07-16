check_required_packages() {
    # Check required pachages installed
    apt update -y
    for package in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            echo "$package is already installed"
        else
            echo "$package is not installed, installing..."
            apt install -y "$package"
        fi
    done
}

check_user_id() {
    # Check user is `root`
    if [ "$(id -u)" -ne "0" ]; then
        echo "This script must be run as root"
        exit 1
    fi
}

log() {
    # Print a message along with a timestamp
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

manage_mounts() {
    # Check the number of arguments
    if [ "$#" -ne 1 ]; then
        log "Invalid number of arguments to manage_mounts"
        exit 1
    fi
    
    # Check the argument
    if [ "$1" != "mount" ] && [ "$1" != "umount" ]; then
        log "Invalid argument to manage_mounts: $1"
        exit 1
    fi
    
    # Perform the mount/unmount operation
    if [ "$1" == "mount" ]; then
        for dir in "${bind_mounts[@]}"; do
            log "Mounting $dir..."
            mount --bind "$dir" "${WORK_DIR}/chroot$dir"
        done
    elif [ "$1" == "umount" ]; then
        for dir in "${bind_mounts[@]}"; do
            log "Unmounting $dir..."
            umount "${WORK_DIR}/chroot$dir"
        done
    fi
}

prepare_fs_struct_for_iso(){
    # Prepare File system structure for ISO
    log "Creating the ISO image..."
    mkdir -p ${WORK_DIR}/image/{live,isolinux}
    
    # Check for kernel file
    KERNEL_FILE=$(ls ${WORK_DIR}/chroot/boot/vmlinuz-* 2> /dev/null | head -n 1)
    if [[ ! -e "${KERNEL_FILE}" ]]; then
        log "Kernel file not found in ${WORK_DIR}/chroot/boot/"
        exit 1
    else
        log "Copying kernel file ${KERNEL_FILE} to ${WORK_DIR}/image/live/vmlinuz"
        cp "${KERNEL_FILE}" "${WORK_DIR}/image/live/vmlinuz"
    fi
    
    # Check for initrd file
    INITRD_FILE=$(ls ${WORK_DIR}/chroot/boot/initrd.img-* 2> /dev/null | head -n 1)
    if [[ ! -e "${INITRD_FILE}" ]]; then
        log "Initrd file not found in ${WORK_DIR}/chroot/boot/"
        exit 1
    else
        log "Copying initrd file ${INITRD_FILE} to ${WORK_DIR}/image/live/initrd"
        cp "${INITRD_FILE}" "${WORK_DIR}/image/live/initrd"
    fi
    
    # Copy isolinux.bin and other required files into the image directory
    log "Copying isolinux files..."
    cp /usr/lib/ISOLINUX/isolinux.bin ${WORK_DIR}/image/isolinux/
    cp /usr/lib/syslinux/modules/bios/{menu.c32,hdt.c32,libutil.c32,libcom32.c32,ldlinux.c32} ${WORK_DIR}/image/isolinux/
}

create_isolinux_config_file() {
    log "Creating ISOLINUX configuration file..."
cat > "${WORK_DIR}/image/isolinux/isolinux.cfg" << EOF
UI menu.c32

PROMPT 0
MENU TITLE Boot Menu
TIMEOUT 300

LABEL live
  MENU LABEL Start Debian Live
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live toram

EOF
}

create_iso_image() {
    log "Creating the ISO..."
    xorriso -as mkisofs -r -J -joliet-long -l -cache-inodes -iso-level 3 \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -partition_offset 16 \
    -A "Debian Live"  \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -output "${WORK_DIR}/debian-live.iso" \
    "${WORK_DIR}/image"
    log "ISO image is ready: ${WORK_DIR}/debian-live.iso"
}
