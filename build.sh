#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ARCH="arm64"
DEFCONFIG="${DEFCONFIG:-selene_defconfig}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"
CLANG_DIR="${CLANG_DIR:-$ROOT_DIR/clang}"
CLANG_URL="${CLANG_URL:-https://github.com/ZyCromerZ/Clang/releases/download/14.0.6-20261022-release/Clang-14.0.6-20261022.tar.gz}"
ANYKERNEL_REPO="${ANYKERNEL_REPO:-https://github.com/osm0sis/AnyKernel3.git}"
ANYKERNEL_REF="${ANYKERNEL_REF:-master}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)}"
BUILD_DATE="$(date -u +%Y%m%d)"
SOURCE_REV="$(git rev-parse --short=12 HEAD 2>/dev/null || printf 'local')"
ZIP_NAME="${ZIP_NAME:-GROWL-KERNEL-2.0-selene-${BUILD_DATE}-${SOURCE_REV}.zip}"
BUILD_LOG="${BUILD_LOG:-$OUT_DIR/build.log}"
ZIP_PATH="$OUT_DIR/target/$ZIP_NAME"

mkdir -p "$OUT_DIR/target"
: > "$BUILD_LOG"

log() {
	echo "[build] $*" | tee -a "$BUILD_LOG"
}

fail() {
	log "ERROR: $*"
	exit 1
}

for tool in make bc bison flex git curl tar python3 zip; do
	command -v "$tool" >/dev/null 2>&1 || fail "Required tool '$tool' is missing."
done

if [[ ! -x "$CLANG_DIR/bin/clang" ]]; then
	log "Downloading pinned Clang toolchain..."
	mkdir -p "$CLANG_DIR"
	CLANG_ARCHIVE="$OUT_DIR/clang-toolchain.tar.gz"
	curl -fL --retry 3 "$CLANG_URL" -o "$CLANG_ARCHIVE" 2>&1 | tee -a "$BUILD_LOG"
	tar -xzf "$CLANG_ARCHIVE" -C "$CLANG_DIR" 2>&1 | tee -a "$BUILD_LOG"
	rm -f "$CLANG_ARCHIVE"
fi

[[ -x "$CLANG_DIR/bin/clang" ]] || fail "Clang was not found under $CLANG_DIR/bin."
[[ -x "$CLANG_DIR/bin/ld.lld" ]] || fail "ld.lld was not found under $CLANG_DIR/bin."

export PATH="$CLANG_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$CLANG_DIR/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-GROWL}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github-actions}"
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(date -u '+%a %b %d %H:%M:%S UTC %Y')}"
log "Building $DEFCONFIG with Clang $($CLANG_DIR/bin/clang --version | head -n 1)"
log "Source revision: $SOURCE_REV"

make O="$OUT_DIR" ARCH="$ARCH" "$DEFCONFIG" 2>&1 | tee -a "$BUILD_LOG"

make -j"$BUILD_JOBS" O="$OUT_DIR" \
	ARCH="$ARCH" \
	CC=clang \
	LD=ld.lld \
	LLVM=1 \
	LLVM_IAS=1 \
	CLANG_TRIPLE=aarch64-linux-gnu- \
	CROSS_COMPILE=aarch64-linux-gnu- \
	CROSS_COMPILE_ARM32=arm-linux-gnueabihf- \
	KBUILD_BUILD_USER="$KBUILD_BUILD_USER" \
	KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST" \
	KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
	Image.gz-dtb 2>&1 | tee -a "$BUILD_LOG"

KERNEL_IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
[[ -s "$KERNEL_IMAGE" ]] || fail "Kernel image was not produced: $KERNEL_IMAGE"

AK_WORK="$(mktemp -d "$OUT_DIR/anykernel.XXXXXX")"
trap 'rm -rf "$AK_WORK"' EXIT
AK_REPO_DIR="$AK_WORK/AnyKernel3"
AK_PACKAGE_DIR="$AK_WORK/package"

log "Preparing AnyKernel3 installer..."
git clone --depth 1 --branch "$ANYKERNEL_REF" "$ANYKERNEL_REPO" "$AK_REPO_DIR" 2>&1 | tee -a "$BUILD_LOG"
mkdir -p "$AK_PACKAGE_DIR"
cp -a "$AK_REPO_DIR/." "$AK_PACKAGE_DIR/"
cp "$ROOT_DIR/anykernel/anykernel.sh" "$AK_PACKAGE_DIR/anykernel.sh"
cp "$KERNEL_IMAGE" "$AK_PACKAGE_DIR/Image.gz-dtb"

rm -f "$ZIP_PATH"
(cd "$AK_PACKAGE_DIR" && zip -qr9 "$ZIP_PATH" . -x '.git' '.git/*' '.github' '.github/*' 'README.md')

log "Flashable ZIP: $ZIP_PATH"
