#!/bin/bash
# build_all.sh - 本地构建全部架构的 encrypt 二进制
# 用法: bash build_all.sh   (需能访问 musl.cc 下载工具链)
set -e
cd "$(dirname "$0")"
mkdir -p dist

DL=https://musl.cc

get_tc() {
    local tc=$1
    [ -d "toolchain/$tc" ] || {
        echo "== 下载 $tc =="
        mkdir -p toolchain
        curl -sL -o toolchain/$tc.tgz $DL/$tc.tgz
        tar -xzf toolchain/$tc.tgz -C toolchain
    }
}

compile() {  # $1=toolchain $2=gcc $3=cflags $4=outname
    local tc=$1 gcc=$2 cflags=$3 out=$4
    echo "== 编译 $out =="
    get_tc "$tc"
    ./toolchain/$tc/bin/$gcc -static -O2 -no-pie $cflags \
        -o "dist/$out" src/encrypt.c src/tommath.c
}

# x86_64
compile x86_64-linux-musl-cross x86_64-linux-musl-gcc "" encrypt_x86_64

# aarch64 (一份覆盖全 cortex, 复制别名)
compile aarch64-linux-musl-cross aarch64-linux-musl-gcc "" encrypt_aarch64_cortex-a53
cp dist/encrypt_aarch64_cortex-a53 dist/encrypt_aarch64_cortex-a72
cp dist/encrypt_aarch64_cortex-a53 dist/encrypt_aarch64_cortex-a76
cp dist/encrypt_aarch64_cortex-a53 dist/encrypt_aarch64_generic

# armv7 32位 (FPU 不同, 分别编译; 仅用 -mcpu 隐含 -march, 避免与 -march 冲突)
compile arm-linux-musleabihf-cross arm-linux-musleabihf-gcc "-mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard" encrypt_arm_cortex-a7_neon-vfpv4
compile arm-linux-musleabihf-cross arm-linux-musleabihf-gcc "-mcpu=cortex-a15 -mfpu=neon-vfpv4 -mfloat-abi=hard" encrypt_arm_cortex-a15_neon-vfpv4
compile arm-linux-musleabihf-cross arm-linux-musleabihf-gcc "-mcpu=cortex-a9 -mfpu=vfpv3-d16 -mfloat-abi=hard" encrypt_arm_cortex-a9_vfpv3-d16

# MIPS 24Kc 大小端
compile mipsel-linux-musl-cross mipsel-linux-musl-gcc "-march=24kc" encrypt_mipsel_24kc
compile mips-linux-musl-cross mips-linux-musl-gcc "-march=24kc" encrypt_mips_24kc

echo "== 全部完成 =="
ls -la dist/
