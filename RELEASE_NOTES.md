# Dtagnan Mods 1.1.1

Release tag: `v1.1.1`

This final maintenance release hardens the portable Linux and Steam installer
for No More Heroes and completes automatic Steam configuration.

## Highlights

- Automatic Launch Options injection with no custom Steam command or
  copy/paste required.
- Command inspector that preserves `gamemoderun`, `mangohud`, Gamescope and
  unrelated user arguments while deduplicating variables managed by the mod.
- Safe removal of only Dtagnan Mods variables when Launch Options were edited
  after installation.
- Steam account selection prefers `loginusers.vdf`'s `MostRecent` account and
  falls back to the newest valid profile.
- Per-user operation locking prevents concurrent install, update and restore
  processes from racing; stale locks recover automatically.
- Steam process detection is restricted to the current Linux user.
- Transaction ordering is hardened for interruptions while Steam is running.
- Custom external Steam Flatpak libraries can be selected with
  `DTAGNAN_STEAM_FLATPAK=1` and an explicit game path.

- Native Steam and Steam Flatpak support.
- Steam Deck and SteamOS detection without modifying the immutable system
  image.
- Internal storage, additional Steam libraries and Steam Deck microSD support.
- Fedora (`dnf`), Debian/Ubuntu (`apt`), Arch (`pacman`) and openSUSE
  (`zypper`) dependency routing.
- NVIDIA hybrid, NVIDIA-only, AMD and Intel per-game launch-option profiles.
- Automatic Steam configuration: no Launch Options copy/paste is required, and the previous value is restored on uninstall. If Steam is running, the installer pauses and waits for the user to close it and confirm with `y` instead of aborting.
- Transactional Steam shutdown handling: installation and removal now wait for
  Steam before changing files, while signal rollback remains non-interactive
  and preserves recovery metadata instead of blocking.
- Live system status in the interactive menu.
- Atomic file replacement and automatic rollback after interruption or failed
  installation.
- Byte-for-byte restoration of pre-existing game DLLs and vkBasalt profiles.
- Safe uninstall that keeps user-modified files instead of deleting them.
- Current and legacy `libraryfolders.vdf` parsing.
- Flatpak-specific persistent paths and i386 vkBasalt runtime detection.
- User-local 32-bit vkBasalt detection for Steam Deck.

## Validation

- Expanded crash, rollback, path, backup, dependency and lifecycle validation
  passed, including interrupted Steam-wait scenarios.
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
