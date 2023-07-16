#!/bin/bash
# set -e
# set -x

# Load variables and functions
. ./libs/variables.sh
. ./libs/functions.sh

# Ensure running as root
check_user_id

# Install necessary packages
log "Updating the package list..."
check_required_packages

# Create the work directory
log "Creating the work directory..."
mkdir -p "${WORK_DIR}"

# Create the chroot environment
log "Creating the chroot environment..."
debootstrap --arch="${ARCH}" "${DEBIAN_VERSION}" "${WORK_DIR}/chroot" "${DEBIAN_MIRROR}"

# Mount necessary filesystems
manage_mounts mount

# Read the packages from the configuration file and install them
log "Reading the packages from the configuration file and installing them..."
chroot "${WORK_DIR}/chroot" /bin/bash -c "apt update -y && apt install -y $(tr '\n' ' ' < ${PACKAGES_FILE})"

# Update initramfs
log "Updating initramfs..."
chroot "${WORK_DIR}/chroot" /bin/bash -c "update-initramfs -u"

# Cleanup the environment
log "Cleaning up the environment..."
chroot "${WORK_DIR}/chroot" /bin/bash -c "apt clean && rm -rf /var/lib/apt/lists/*"

# Unmount filesystems
manage_mounts umount

# Create the ISO image
prepare_fs_struct_for_iso

# Create ISOLINUX configuration file
create_isolinux_config_file

# Create the ISO
create_iso_image
