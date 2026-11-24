#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf '::error::ZRAM multicomp audit: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '::notice::ZRAM multicomp audit: %s\n' "$*"
}

KERNEL_ROOT="${1:-}"
MODE="${2:-}"
[[ -n "$KERNEL_ROOT" && -d "$KERNEL_ROOT" ]] || fail "kernel source directory argument is missing or invalid"
[[ "$MODE" == "prebuild" || "$MODE" == "postbuild" ]] || fail "mode must be prebuild or postbuild"

KERNEL_ROOT="$(cd "$KERNEL_ROOT" && pwd)"
OUT_DIR="$KERNEL_ROOT/out"
CONFIG_FILE="$OUT_DIR/.config"
AUDIT_DIR="$OUT_DIR/zram-multicomp-audit"
EXPECTED_BRANCH="${KERNEL_SOURCE_BRANCH:-experimental/zram-multicomp}"
EXPECTED_DEVICE="${DEVICE:-merlin}"
EXPECTED_ARCH="${KERNEL_ARCH:-arm64}"
EXPECTED_REMOTE="${KERNEL_SOURCE:-https://github.com/a03corerooted-dev-ctrl/Hysteris_kernel_xiaomi_mt6768}"
EXPECTED_IMAGE="${KERNEL_IMAGE_NAME:-Image.gz-dtb}"

# Feature eligibility is content-based, not branch-name-based. The checks below
# require the complete multicomp + auto-recompression source, ABI, config and objects.
# This permits any descendant branch (e.g. BORE/SPF) that retains those features.
[[ "$EXPECTED_DEVICE" == "merlin" ]] || fail "device is '$EXPECTED_DEVICE', this audit profile targets merlin/MT6768"
[[ "$EXPECTED_ARCH" == "arm64" ]] || fail "architecture is '$EXPECTED_ARCH', expected arm64"

normalize_remote() {
    printf '%s' "$1" |
        sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##'
}

ACTUAL_BRANCH="$(git -C "$KERNEL_ROOT" branch --show-current)"
ACTUAL_COMMIT="$(git -C "$KERNEL_ROOT" rev-parse HEAD)"
ACTUAL_TREE="$(git -C "$KERNEL_ROOT" rev-parse 'HEAD^{tree}')"
ACTUAL_REMOTE="$(git -C "$KERNEL_ROOT" remote get-url origin)"
[[ "$ACTUAL_BRANCH" == "$EXPECTED_BRANCH" ]] || fail "checked out source branch is '$ACTUAL_BRANCH', expected '$EXPECTED_BRANCH'"
[[ "$(normalize_remote "$ACTUAL_REMOTE")" == "$(normalize_remote "$EXPECTED_REMOTE")" ]] ||
    fail "source remote '$ACTUAL_REMOTE' does not match '$EXPECTED_REMOTE'"

require_file() {
    [[ -s "$KERNEL_ROOT/$1" ]] || fail "required source file is missing or empty: $1"
}

require_text() {
    local file="$1"
    local pattern="$2"
    grep -Fq -- "$pattern" "$KERNEL_ROOT/$file" ||
        fail "expected source marker '$pattern' is missing from $file"
}

require_config() {
    local symbol="$1"
    grep -qx "${symbol}=y" "$CONFIG_FILE" ||
        fail "resolved .config does not contain ${symbol}=y"
}

require_config_value() {
    local symbol="$1"
    local expected="$2"
    grep -qx "${symbol}=${expected}" "$CONFIG_FILE" ||
        fail "resolved .config does not contain ${symbol}=${expected}"
}

require_file "drivers/block/zram/Kconfig"
require_file "drivers/block/zram/zram_drv.c"
require_file "drivers/block/zram/zram_drv.h"
require_file "drivers/block/zram/zcomp.c"
require_file "include/linux/zsmalloc.h"
require_file "mm/zsmalloc.c"
require_file "Documentation/ABI/testing/sysfs-block-zram"
require_file "Documentation/blockdev/zram.txt"

require_text "drivers/block/zram/Kconfig" "config ZRAM_MULTI_COMP"
require_text "drivers/block/zram/Kconfig" "depends on ZRAM && 64BIT"
require_text "drivers/block/zram/Kconfig" "config ZRAM_AUTO_RECOMP"
require_text "drivers/block/zram/Kconfig" "config ZRAM_AUTO_RECOMP_ALGORITHM"
require_text "drivers/block/zram/Kconfig" "config ZRAM_AUTO_RECOMP_INTERVAL"
require_text "drivers/block/zram/Kconfig" "config ZRAM_AUTO_RECOMP_PAGES"
require_text "drivers/block/zram/Kconfig" "config ZRAM_AUTO_RECOMP_MAX_PAGES"
require_file "arch/arm64/configs/vendor/mt6768_multicomp.config"
require_text "arch/arm64/configs/vendor/mt6768_multicomp.config" "CONFIG_ZRAM_MULTI_COMP=y"
require_text "arch/arm64/configs/vendor/mt6768_multicomp.config" "CONFIG_CRYPTO_ZSTD=y"
require_text "arch/arm64/configs/vendor/mt6768_multicomp.config" "CONFIG_ZRAM_AUTO_RECOMP=y"
require_text "arch/arm64/configs/vendor/mt6768_multicomp.config" "CONFIG_ZRAM_AUTO_RECOMP_ALGORITHM=\"zstd\""
require_text "arch/arm64/configs/vendor/mt6768_multicomp.config" "CONFIG_ZRAM_AUTO_RECOMP_INTERVAL=120"
require_text "arch/arm64/configs/vendor/mt6768_multicomp.config" "CONFIG_ZRAM_AUTO_RECOMP_PAGES=16384"
require_text "arch/arm64/configs/vendor/mt6768_multicomp.config" "CONFIG_ZRAM_AUTO_RECOMP_MAX_PAGES=256"
require_text "arch/arm64/configs/vendor/mt6768_multicomp.config" "# CONFIG_ZRAM_WRITEBACK is not set"
require_text "drivers/block/zram/zram_drv.h" "ZRAM_MAX_COMPS"
require_text "drivers/block/zram/zram_drv.h" "ZRAM_COMP_PRIORITY_BIT1"
require_text "drivers/block/zram/zram_drv.h" "ZRAM_COMP_PRIORITY_BIT2"
require_text "drivers/block/zram/zram_drv.c" "static ssize_t recomp_algorithm_store"
require_text "drivers/block/zram/zram_drv.c" "static ssize_t recompress_store"
require_text "drivers/block/zram/zram_drv.c" "static int zram_recompress"
require_text "drivers/block/zram/zram_drv.c" "static void zram_auto_recompress_work"
require_text "drivers/block/zram/zram_drv.c" "zcomp_available_algorithm(CONFIG_ZRAM_AUTO_RECOMP_ALGORITHM)"
require_text "drivers/block/zram/zram_drv.c" "zram->comp_algs[ZRAM_SECONDARY_COMP]"
require_text "drivers/block/zram/zram_drv.c" "ZRAM_RECOMP_CANDIDATE"
require_text "drivers/block/zram/zram_drv.c" "cancel_delayed_work_sync(&zram->recomp_work);"
require_text "drivers/block/zram/zram_drv.h" "struct delayed_work recomp_work"
require_text "drivers/block/zram/zram_drv.h" "auto_recomp_scans"
require_text "drivers/block/zram/zram_drv.c" "zram->comps[ZRAM_PRIMARY_COMP]"
require_text "drivers/block/zram/zram_drv.c" "ZRAM_INCOMPRESSIBLE"
require_text "drivers/block/zram/zram_drv.c" "default_compressor = \"lzo-rle\""
require_text "drivers/block/zram/zram_drv.c" "zram_get_priority"
require_text "drivers/block/zram/zram_drv.c" "zram_set_priority(zram, index, 0)"
require_text "drivers/block/zram/zram_drv.c" "class_index_new >= class_index_old"
require_text "drivers/block/zram/zram_drv.c" "alloced_pages > zram->limit_pages"
require_text "drivers/block/zram/zcomp.c" "\"zstd\""
require_text "drivers/block/zram/zcomp.c" "#if IS_ENABLED(CONFIG_CRYPTO_ZSTD)"
require_text "include/linux/zsmalloc.h" "zs_lookup_class_index"
require_text "mm/zsmalloc.c" "zs_lookup_class_index("
require_text "Documentation/ABI/testing/sysfs-block-zram" "/recomp_algorithm"
require_text "Documentation/ABI/testing/sysfs-block-zram" "/recompress"
require_text "Documentation/ABI/testing/sysfs-block-zram" "/auto_recomp_stat"
require_text "Documentation/blockdev/zram.txt" "CONFIG_ZRAM_MULTI_COMP"
require_text "Documentation/blockdev/zram.txt" "Automatic cold-page recompression"

if [[ "$MODE" == "prebuild" ]]; then
    [[ -s "$CONFIG_FILE" ]] || fail "resolved kernel config is missing: $CONFIG_FILE"

    require_config "CONFIG_ARM64"
    require_config "CONFIG_64BIT"
    require_config "CONFIG_ZRAM"
    require_config "CONFIG_ZSMALLOC"
    require_config "CONFIG_ZRAM_MULTI_COMP"
    require_config "CONFIG_CRYPTO_ZSTD"
    require_config "CONFIG_ZRAM_AUTO_RECOMP"
    require_config_value "CONFIG_ZRAM_AUTO_RECOMP_ALGORITHM" '"zstd"'
    require_config_value "CONFIG_ZRAM_AUTO_RECOMP_INTERVAL" "120"
    require_config_value "CONFIG_ZRAM_AUTO_RECOMP_PAGES" "16384"
    require_config_value "CONFIG_ZRAM_AUTO_RECOMP_MAX_PAGES" "256"
    grep -qx '# CONFIG_ZRAM_WRITEBACK is not set' "$CONFIG_FILE" ||
        fail "resolved .config must keep CONFIG_ZRAM_WRITEBACK disabled"

    rm -rf "$AUDIT_DIR"
    mkdir -p "$AUDIT_DIR"
    cp "$CONFIG_FILE" "$AUDIT_DIR/kernel.config"

    {
        echo "ZRAM multicomp build audit"
        echo "phase=prebuild"
        echo "device=$EXPECTED_DEVICE"
        echo "arch=$EXPECTED_ARCH"
        echo "source_remote=$ACTUAL_REMOTE"
        echo "source_branch=$ACTUAL_BRANCH"
        echo "source_commit=$ACTUAL_COMMIT"
        echo "source_tree=$ACTUAL_TREE"
        echo "source_commit_subject=$(git -C "$KERNEL_ROOT" log -1 --format=%s)"
        echo "builder_commit=${GITHUB_SHA:-unknown}"
        echo "workflow_run_id=${GITHUB_RUN_ID:-unknown}"
        echo "workflow_attempt=${GITHUB_RUN_ATTEMPT:-unknown}"
        echo "utc_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$AUDIT_DIR/source-metadata.txt"

    grep -E '^(CONFIG_(ARM64|64BIT|ZRAM|ZRAM_MULTI_COMP|CRYPTO_ZSTD|CRYPTO_LZO|ZSMALLOC|ZRAM_AUTO_RECOMP|ZRAM_AUTO_RECOMP_ALGORITHM|ZRAM_AUTO_RECOMP_INTERVAL|ZRAM_AUTO_RECOMP_PAGES|ZRAM_AUTO_RECOMP_MAX_PAGES|ZRAM_WRITEBACK|ZRAM_MEMORY_TRACKING)=|# CONFIG_(ZRAM_WRITEBACK|ZRAM_MEMORY_TRACKING) is not set)' \
        "$CONFIG_FILE" > "$AUDIT_DIR/zram-config-summary.txt" || true

    sha256sum \
        "$KERNEL_ROOT/arch/arm64/configs/vendor/mt6768_multicomp.config" \
        "$KERNEL_ROOT/drivers/block/zram/Kconfig" \
        "$KERNEL_ROOT/drivers/block/zram/zram_drv.c" \
        "$KERNEL_ROOT/drivers/block/zram/zram_drv.h" \
        "$KERNEL_ROOT/drivers/block/zram/zcomp.c" \
        "$KERNEL_ROOT/include/linux/zsmalloc.h" \
        "$KERNEL_ROOT/mm/zsmalloc.c" \
        "$KERNEL_ROOT/Documentation/ABI/testing/sysfs-block-zram" \
        "$KERNEL_ROOT/Documentation/blockdev/zram.txt" \
        > "$AUDIT_DIR/source-files.sha256"

    {
        echo "PASS: approved source branch and remote retain the ZRAM multicomp implementation"
        echo "PASS: multi-compressor Kconfig and source interfaces are present"
        echo "PASS: resolved ARM64 config enables ZRAM, zsmalloc, multicomp, ZSTD and bounded auto recompression"
        echo "PASS: zstd is configured as the secondary cold-page compressor"
        echo "PASS: resolved config disables ZRAM writeback"
        echo "PASS: sysfs ABI and user documentation are present"
    } | tee "$AUDIT_DIR/prebuild-checks.txt"

    info "prebuild checks passed for source commit $ACTUAL_COMMIT"
    exit 0
fi

[[ -s "$AUDIT_DIR/source-metadata.txt" ]] || fail "prebuild audit report is missing; prebuild audit did not run"
[[ -s "$AUDIT_DIR/kernel.config" ]] || fail "prebuild .config snapshot is missing"

for object in \
    "drivers/block/zram/zram_drv.o" \
    "drivers/block/zram/zcomp.o" \
    "mm/zsmalloc.o"
do
    [[ -s "$OUT_DIR/$object" ]] || fail "expected compiled object is missing or empty: out/$object"
done

IMAGE_PATH="$OUT_DIR/arch/$EXPECTED_ARCH/boot/$EXPECTED_IMAGE"
[[ -s "$IMAGE_PATH" ]] || fail "expected kernel image is missing or empty: $IMAGE_PATH"

{
    echo "ZRAM multicomp build audit"
    echo "phase=postbuild"
    echo "result=PASS"
    echo "device=$EXPECTED_DEVICE"
    echo "arch=$EXPECTED_ARCH"
    echo "source_branch=$ACTUAL_BRANCH"
    echo "source_commit=$ACTUAL_COMMIT"
    echo "kernel_image=$IMAGE_PATH"
    echo "utc_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Compiled ZRAM objects:"
    stat -c '%n %s bytes' \
        "$OUT_DIR/drivers/block/zram/zram_drv.o" \
        "$OUT_DIR/drivers/block/zram/zcomp.o" \
        "$OUT_DIR/mm/zsmalloc.o"
    echo
    echo "Kernel image:"
    stat -c '%n %s bytes' "$IMAGE_PATH"
} | tee "$AUDIT_DIR/build-audit.txt"

sha256sum \
    "$OUT_DIR/drivers/block/zram/zram_drv.o" \
    "$OUT_DIR/drivers/block/zram/zcomp.o" \
    "$OUT_DIR/mm/zsmalloc.o" \
    "$IMAGE_PATH" \
    > "$AUDIT_DIR/build-artifacts.sha256"

if [[ -s "$OUT_DIR/System.map" ]]; then
    cp "$OUT_DIR/System.map" "$AUDIT_DIR/System.map"
    sha256sum "$OUT_DIR/System.map" >> "$AUDIT_DIR/build-artifacts.sha256"
fi

info "postbuild checks passed; audit artifacts are in $AUDIT_DIR"
