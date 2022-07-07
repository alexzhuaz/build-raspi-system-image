#!/usr/bin/bash

# Configurable parameters
ARCH=arm64                       # For Aarch64
#ARCH=arm                         # For Aarch32
KERNEL=kernel8                   # For Aarch64, RPi4
#KERNEL=kernel7l                  # For Aarch32, PRi4
DEFCONFIG=bcm2711_defconfig      # For RPi4
KERNEL_PATH_NAME=rasp-kernel
GCC_PATH_NAME=gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu    # For Aarch64
#GCC_PATH_NAME=gcc-arm-11.2-2022.02-x86_64-arm-none-linux-gnueabihf  # For Aarch32
GLIBC_PATH_NAME=glibc-2.35
BUSYBOX_PATH_NAME=busybox-1.33.2

# Input from CLI
usage() {
    echo "Usage: $0 [-a|--all] [-r|--rebuild] [-k|--kernel] [-f|--filesystem] [-g|--glibc] [-b|--busybox] [-c|--clean]" 1>&2
    exit 1
}

if [[ $# -eq 0 ]]; then
    BUILD_ALL=yes
else
    while [[ $# -gt 0 ]]; do
	  key=$1
	  case $key in
	      -a|--all)
		  BUILD_ALL=yes
		  shift
		  ;;
	      -r|--rebuild)
		  REBUILD=yes
		  shift
		  ;;
	      -k|--kernel)
		  BUILD_KERNEL=yes
		  shift
		  ;;
	      -f|--filesystem)
		  BUILD_FS=yes
		  shift
		  ;;
	      -g|--glibc)
		  BUILD_GLIBC=yes
		  shift
		  ;;
	      -b|--busybox)
		  BUILD_BUSYBOX=yes
		  shift
		  ;;
	      -c|--clean)
		  BUILD_CLEAN=yes
		  shift
		  ;;
	      *)
		  usage
		  shift
		  ;;
	  esac
    done
fi

# Build script for raspi-kernel
NCPU=`nproc`
JOBS=`expr $NCPU - 2`
PWD=$(realpath "$(dirname "$0")")
KERNEL_PATH="$PWD/../$KERNEL_PATH_NAME"
GCC="$PWD/../$GCC_PATH_NAME/bin"
GLIBC="$PWD/../$GLIBC_PATH_NAME"
BUSYBOX="$PWD/../$BUSYBOX_PATH_NAME"

if [ $ARCH == 'arm64' ]; then
    CROSS_PREFIX='aarch64-none-linux-gnu'
    BUILD_HOST='aarch64-linux-gnueabi'
elif [ $ARCH == 'arm' ]; then
    CROSS_PREFIX='arm-none-linux-gnueabihf'
    BUILD_HOST='arm-linux-gnueabihf'
fi

OUT=$PWD/out
KERNEL_OUT=$OUT/kernel
ARGS="-j$JOBS -C $KERNEL_PATH O=$KERNEL_OUT ARCH=$ARCH CROSS_COMPILE=$CROSS_PREFIX-"
CMD="make $ARGS"
TARGET="Image modules dtbs"
PATH=$PATH:$GCC

INSTALL="$OUT/mnt"
INSTALL_FAT32="$INSTALL/fat32"
INSTALL_EXT4="$INSTALL/ext4"

echo "Building using $JOBS cpus..."

build_kernel() {
    if [[ $REBUILD == 'yes' ]]; then
	rm -rf $KERNEL_OUT
    fi

    echo "Building $DEFCONFIG..."
    $CMD $DEFCONFIG

    echo "Building $TARGET..."
    $CMD KBUILD_KCONFIG=$KERNEL_OUT/.config $TARGET
}

build_glibc() {
    echo "Building GLIBC..."
    GLIBC_OUT=$OUT/glibc
    mkdir -p $GLIBC_OUT
    pushd $GLIBC_OUT
    if [[ ! -e libc.so || $REBUILD == 'yes' ]]; then
	$GLIBC/configure --prefix=$INSTALL_EXT4 CC=$CROSS_PREFIX-gcc CXX=$CROSS_PREFIX-g++ AR=$CROSS_PREFIX-ar AS=$CROSS_PREFIX-as LD=$CROSS_PREFIX-ld RANLIB=$CROSS_PREFIX-ranlib --host=$BUILD_HOST --enable-obsolete-rpc
	make CFLAGS+="-w -O1" -j$JOBS
    fi
    make install
    popd
}

build_busybox() {
    echo "Building busybox..."
    BUSYBOX_OUT=$OUT/busybox
    BUSYBOX_ARGS="ARCH=$ARCH CROSS_COMPILE=$CROSS_PREFIX-"
    BUSYBOX_CONFIG=$PWD/busybox_config
    mkdir -p $BUSYBOX_OUT
    pushd $BUSYBOX_OUT
    if [[ ! -e .config || $REBUILD == 'yes' ]]; then
	make $BUSYBOX_ARGS KBUILD_SRC=$BUSYBOX -f $BUSYBOX/Makefile allnoconfig
	cp $BUSYBOX_CONFIG .config
	make $BUSYBOX_ARGS -j$JOBS
    fi
    make $BUSYBOX_ARGS CONFIG_PREFIX=$INSTALL_EXT4 install
    popd
}

build_fs() {
    echo "Installing kernel files..."
    mkdir -p $INSTALL_EXT4/proc
    mkdir -p $INSTALL_EXT4/dev
    mkdir -p $INSTALL_EXT4/sys
    mkdir -p $INSTALL_EXT4/lib
    mkdir -p $INSTALL_EXT4/lib64
    mkdir -p $INSTALL_FAT32/overlays
    $CMD INSTALL_MOD_PATH=$INSTALL_EXT4 modules_install
    if [ $ARCH == 'arm64' ]; then
	cp $KERNEL_OUT/arch/arm64/boot/Image $INSTALL_FAT32/$KERNEL.img
	cp $KERNEL_OUT/arch/arm64/boot/dts/broadcom/*.dtb $INSTALL_FAT32
	cp $KERNEL_OUT/arch/arm64/boot/dts/overlays/*.dtb* $INSTALL_FAT32/overlays/
	cp -P $GCC/../$CROSS_PREFIX/libc/lib/* $INSTALL_EXT4/lib/
	cp -P $GCC/../$CROSS_PREFIX/libc/lib64/* $INSTALL_EXT4/lib64/
    elif [ $ARCH == 'arm' ]; then
	cp $KERNEL_OUT/arch/arm/boot/Image $INSTALL_FAT32/$KERNEL.img
	cp $KERNEL_OUT/arch/arm/boot/dts/*.dtb $INSTALL_FAT32
	cp $KERNEL_OUT/arch/arm/boot/dts/overlays/*.dtb* $INSTALL_FAT32/overlays/
	cp -P $GCC/../$CROSS_PREFIX/libc/lib/* $INSTALL_EXT4/lib/
    fi

    echo "Making bootfs..."
    dd if=/dev/zero of=$OUT/boot.img bs=1M count=50
    mkfs.vfat -F 32 $OUT/boot.img
    mcopy -s -p -m -i $OUT/boot.img $INSTALL_FAT32/* ::

    echo "Making rootfs..."
    dd if=/dev/zero of=$OUT/root.img bs=1M count=512
    mkfs.ext4 $OUT/root.img -d $INSTALL_EXT4

    echo "Boot image built at: $OUT/boot.img"
    echo "System image built at: $OUT/root.img"
    echo "Write the image into a SD card and insert into the RPi to boot."
}

build_clean() {
    rm -rf $OUT
}

if [[ $BUILD_ALL == 'yes' ]]; then
    build_kernel
    build_glibc
    build_busybox
    build_fs
else
    if [[ $BUILD_KERNEL == 'yes' ]]; then
	build_kernel
    fi
    
    if [[ $BUILD_GLIBC == 'yes' ]]; then
	build_glibc
    fi
    
    if [[ $BUILD_BUSYBOX == 'yes' ]]; then
	build_busybox
    fi
    
    if [[ $BUILD_FS == 'yes' ]]; then
	build_fs
    fi
    
    if [[ $BUILD_CLEAN == 'yes' ]]; then
	build_clean
    fi
fi

