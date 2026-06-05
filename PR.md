Title: feat(ci): piano kernel build and rootfs/boot image packaging

Summary:
- Add `scripts/piano-kernel_build.sh` to build the sm8750 kernel (clang + ccache), produce `zImage_piano` and package into `boot_piano.img` using `mkbootimg`.
- Add `scripts/package_images.sh` to create `boot.img` (via `mkbootimg`/`abootimg`) and `rootfs.img` (ext4 raw -> sparse via `img2simg` when available), plus `system_a.img`/`system_b.img`.
- Update CI (`.github/workflows/ci.yml`) to:
  - clone the kernel repo (default: `https://github.com/cctv18/oppo_oplus_realme_sm8750`)
  - build `img2simg` and `mkbootimg` on runner if not present
  - pass `BOOT_CMDLINE`/`BOOT_BASE`/`RAMDISK_PATH`/`KERNEL_REPO`/`KERNEL_BRANCH`/`KERNEL_PATH` as inputs/env
  - run build and package steps and upload artifacts to a Release
- Update `scripts/build.sh` to call the piano kernel build and packaging steps.
- Update `README.md` with fastboot test instructions and CI defaults.

How to test locally:
1. Create and switch to branch (already done locally in this repo):
   - `git checkout -b piano/ci-packaging`
2. Build locally (requires clang, ccache, mkbootimg or abootimg):
   - `./scripts/piano-kernel_build.sh`
   - `./scripts/package_images.sh`
3. Inspect `out/` and `out/artifacts/` for `boot_piano.img`, `boot.img`, `rootfs.img`, `system_a.img`.
4. Use `fastboot boot out/artifacts/boot.img` to test kernel boot (device must be unlocked).

CI notes:
- Runner builds `img2simg` and `mkbootimg` from upstream sources; builds may take extra time.
- Default `BOOT_CMDLINE`/`BOOT_BASE` values are set in workflow inputs; override them when running the workflow if needed.

Risks & next steps:
- Produced images are not AVB-signed; if target device requires signed images, add signing steps and secrets.
- Recommend running a single CI build and testing `fastboot boot` before attempting to flash.
