# Dtagnan Mods 1.1

This release replaces the original single-platform installer with a safer,
portable Linux and Steam installer for No More Heroes.

## Highlights

- Native Steam and Steam Flatpak support.
- Steam Deck and SteamOS detection without modifying the immutable system
  image.
- Internal storage, additional Steam libraries and Steam Deck microSD support.
- Fedora (`dnf`), Debian/Ubuntu (`apt`), Arch (`pacman`) and openSUSE
  (`zypper`) dependency routing.
- NVIDIA hybrid, NVIDIA-only, AMD and Intel launch-option profiles.
- Live system status in the interactive menu.
- Atomic file replacement and automatic rollback after interruption or failed
  installation.
- Byte-for-byte restoration of pre-existing game DLLs and vkBasalt profiles.
- Safe uninstall that keeps user-modified files instead of deleting them.
- Current and legacy `libraryfolders.vdf` parsing.
- Flatpak-specific persistent paths and i386 vkBasalt runtime detection.
- User-local 32-bit vkBasalt detection for Steam Deck.

## Validation

- 107 crash, rollback, path, backup, dependency and lifecycle tests passed.
- Full Podman matrices passed on Fedora, Ubuntu, Arch Linux and openSUSE
  Tumbleweed.
- Actual container package tests confirmed:
  - Fedora: `vulkan-loader.i686` and `vkBasalt.i686` are available.
  - Ubuntu: `libvulkan1:i386` is available; `vkbasalt:i386` was unavailable.
  - Arch: the Vulkan loader is available from `[multilib]`; a standard
    `lib32-vkbasalt` package was unavailable.
  - openSUSE: `libvulkan1-32bit` is available; `vkBasalt-32bit` was
    unavailable.

## Steam Deck safety

The installer does not call `steamos-readonly`, does not unlock the SteamOS
filesystem and does not install packages into the immutable system image. If a
required 32-bit component is missing, it stops before changing the game.

A physical Steam Deck test remains recommended because containers cannot
reproduce the Deck GPU, Steam client and immutable host exactly.

## Source and integrity

The release contains the exact DXVK source patch, upstream revision,
reproduction instructions and DXVK licence under `Source-patch/`. Verify the
release with:

```bash
sha256sum -c SHA256SUMS
```
