WORK_DIR="/opt/livecd"
ARCH="amd64"
DEBIAN_VERSION="bullseye"
DEBIAN_MIRROR="http://deb.debian.org/debian"
PACKAGES_FILE="packages.conf"
packages=("debootstrap" "syslinux" "isolinux" "xorriso" "xinit" "qemu-system")
bind_mounts=("/dev" "/run")