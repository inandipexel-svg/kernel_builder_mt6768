# ZRAM multicomp build profile

This branch is a dedicated build-and-audit profile for Hysteris Kernel's
experimental ZRAM multi-compressor integration on the Redmi Note 9 (merlin,
MT6768, ARM64).

## Source and backend

- Builder branch: `zram-multicomp`
- Build backend: `config-xxksu.env`
- Kernel repository: `a03corerooted-dev-ctrl/Hysteris_kernel_xiaomi_mt6768`
- Kernel branch: `experimental/zram-multicomp`
- Device: `merlin`
- Compiler: the Clang toolchain configured by `config-xxksu.env`

The kernel implementation lives in the kernel repository. The builder does
not re-apply a duplicate source patch on top of it.

## Configuration

The normal `vendor/mt6768_defconfig` and `vendor/merlin.config` are merged
first. When `ZRAM_MULTICOMP_AUDIT=true`, the workflow also merges the
source-branch fragment:

`arch/arm64/configs/vendor/mt6768_multicomp.config`

That fragment enables `CONFIG_ZRAM_MULTI_COMP=y` and
`CONFIG_CRYPTO_ZSTD=y`. The normal device defconfig remains unchanged.
LZO-RLE continues to be the primary runtime compressor; secondary compressor
selection and recompression remain user-space controlled.

## Audit coverage

The workflow runs `audit-zram-multicomp.sh` in two phases.

**Pre-build** checks:
- The cloned source remote and checked-out branch match the profile.
- The expected multicomp Kconfig, compressor selection, per-page priority,
  recompression sysfs paths, zsmalloc class lookup, ABI and documentation
  markers exist.
- The resolved `out/.config` still enables ARM64, 64-bit, ZRAM, zsmalloc,
  multicomp and ZSTD after `olddefconfig`.

**Post-build** checks:
- `zram_drv.o`, `zcomp.o` and `mm/zsmalloc.o` were produced and are
  non-empty.
- The configured `Image.gz-dtb` kernel image exists and is non-empty.
- SHA-256 hashes are recorded for the source files, compiled objects and
  kernel image.

The audit report, resolved kernel config, source metadata and checksums are
uploaded as a separate GitHub Actions artifact named
`zram-multicomp-audit-merlin-<timestamp>`.

A successful audit confirms that the expected source, configuration and
build outputs are present. Runtime recompression and memory-savings behavior
still require device-side testing and are not inferred from a successful
compile.
