```text
 DDDD  TTTTT  AAA   GGG  N   N  AAA  N   N    M   M  OOO  DDDD  SSSS
 D   D   T   A   A G     NN  N A   A NN  N    MM MM O   O D   D S
 D   D   T   AAAAA G  GG N N N AAAAA N N N    M M M O   O D   D SSS
 D   D   T   A   A G   G N  NN A   A N  NN    M   M O   O D   D    S
 DDDD    T   A   A  GGG  N   N A   A N   N    M   M  OOO  DDDD  SSSS
```

<div align="center">

# Dtagnan Mods — No More Heroes

### Linux Enhancement Package

**Custom DXVK build · SMAA · Color LUT · Bloom · Vignette · CAS · Dithering**

**Version 1.1.1 · Release tag `v1.1.1`**

</div>

---

## Overview

This project improves the Linux experience of the Windows release of
**No More Heroes** running through Steam and Proton.

The package combines a game-specific 32-bit DXVK build with a restrained
vkBasalt post-processing chain. Its goal is to improve frame pacing, edge
quality, color reproduction and image clarity without replacing the visual
identity of the original game.

Linux is required. This is not a Windows mod or Windows installer.

## Before and after

<p align="center">
  <strong>Original presentation</strong>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <strong>Dtagnan Mods post-processing</strong>
</p>

<p align="center">
  <a href="./Comparison/Before.png">
    <img src="./Comparison/Before.png" alt="Original presentation" width="49%">
  </a>
  <a href="./Comparison/After.png">
    <img src="./Comparison/After.png" alt="Dtagnan Mods post-processing" width="49%">
  </a>
</p>

## What the mod installs

### Custom DXVK

The included 32-bit DXVK libraries translate the game's Direct3D 11 rendering
to Vulkan. The build contains a profile specifically matched to `nmh.exe`:

- maximum frame latency of one frame;
- four shader compiler threads;
- DXVK present timing enabled;
- implicit resolves enabled.

### vkBasalt post-processing

The final Vulkan image is processed in this order:

```text
SMAA → Color LUT → Bloom → Vignette → CAS → Dithering
```

| Effect | Purpose |
|---|---|
| SMAA | Smooths visible jagged edges. |
| Color LUT | Adjusts color, contrast and midtones for the game's presentation. |
| Bloom | Adds a subtle glow around bright areas. |
| Vignette | Slightly darkens the outer corners. |
| CAS | Restores fine detail and controlled sharpness. |
| Dithering | Reduces color banding in skies and gradients. |

Press **F10** while playing to enable or disable the complete post-processing
chain.

## Compatibility

The installer supports:

- native Steam for Linux;
- the standard Steam Flatpak installation;
- Steam Deck and SteamOS without disabling the read-only system image;
- Steam's primary library;
- additional libraries and Steam Deck microSD cards declared in
  `libraryfolders.vdf`, including current and legacy formats;
- NVIDIA hybrid graphics, NVIDIA-only, AMD and Intel systems;
- custom XDG data and configuration directories;
- installation paths containing spaces;
- installation paths containing Unicode characters and symbolic links;
- an explicitly supplied game directory.

Snap Steam is detected but intentionally refused because its confined
filesystem cannot currently be supported safely.

NVIDIA PRIME variables are added only when a hybrid NVIDIA system is detected.
AMD, Intel and NVIDIA-only systems receive vendor-appropriate per-game settings
without unnecessary PRIME variables. The installer writes the required Steam
configuration automatically; no Launch Options copy/paste is required.

## Automatic Steam Launch Options injection

Dtagnan Mods configures No More Heroes directly in Steam's per-user
`localconfig.vdf`. You do **not** need to paste a custom command into the
game's Launch Options field.

The installer safely inspects any options already configured for AppID
`1420290`:

- variables supplied by Dtagnan Mods are kept only once;
- obsolete or conflicting values managed by the mod are replaced;
- unrelated commands such as `gamemoderun`, `mangohud`, Gamescope options and
  game arguments are preserved and combined with the mod configuration;
- `%command%` is normalized to one correctly positioned entry;
- the original value is backed up for uninstallation;
- if the user changes Launch Options afterward, uninstallation removes only
  the variables managed by Dtagnan Mods and keeps the user's additions.

Steam must be fully closed while this file is written. If Steam is running,
the installer pauses before changing any game file and asks the user to close
it. No custom launch command or manual copy/paste step is required.

## Built-in functions

Everything needed for normal use is automated by `install.sh`:

| Function | What it does | Changes files? |
|---|---|---|
| **Installer / Updater** | Finds No More Heroes, checks all prerequisites, backs up the original state, installs DXVK and vkBasalt files, then configures Steam. Running it again safely updates the mod. | Yes |
| **Launch Options Inspector** | Reads the active Steam account's existing command, keeps unrelated user commands, replaces conflicting mod variables, removes exact duplicates and ensures a single `%command%`. | Only during install/update/restore |
| **System Doctor** | Reports the platform, Steam backend, game path, GPU, 32-bit Vulkan, 32-bit vkBasalt, write access and package integrity without installing the mod. | No |
| **Verifier** | Compares installed DLLs, shaders, LUT, configuration, dependencies and recovery metadata with the release. | No |
| **Automatic Recovery** | Rolls back a failed or interrupted installation and removes stale temporary files on the next run. | Only to restore a safe state |
| **Restore / Uninstaller** | Restores original game DLLs and the user's Steam settings. Commands added by the user after installation are retained. | Yes |
| **Operation Lock** | Prevents two installers from changing the same installation simultaneously and safely recovers a stale lock. | Temporary lock only |
| **Dependency Test** | Simulates missing dependencies and tests the distribution-specific installation path without installing packages. | No (dry run) |
| **Comparison Viewer** | Shows the supplied before/after images in a supported terminal or image viewer. | No |
| **About** | Displays an offline explanation of the mod and all its automated safety features. | No |

The **Inspector** does not cancel an entire custom command. It removes only
duplicate or conflicting parts managed by Dtagnan Mods. For example, a user's
`gamemoderun`, `mangohud`, Gamescope flags and game arguments remain in place,
while an existing identical `ENABLE_VKBASALT=1` is kept only once.

## Requirements

- A 64-bit Linux distribution
- Steam for Linux or Steam Flatpak
- No More Heroes on Steam — App ID `1420290`
- Proton or GE-Proton selected as the compatibility tool
- A Vulkan-capable GPU and working Vulkan driver
- 64-bit and 32-bit Vulkan userspace support
- vkBasalt with its 32-bit Vulkan layer
- Bash, Python 3 and standard GNU/Linux command-line tools
- Optional: `chafa` for terminal image previews

The executable `nmh.exe` is 32-bit. A system with only 64-bit Vulkan or
vkBasalt libraries is therefore incomplete. The installer verifies the 32-bit
Vulkan loader and vkBasalt layer before modifying the game.

### Fedora

```bash
sudo dnf install vkBasalt.i686 vulkan-loader.i686

# AMD or Intel with Mesa
sudo dnf install mesa-vulkan-drivers.x86_64 mesa-vulkan-drivers.i686

# NVIDIA with the RPM Fusion proprietary driver
sudo dnf install xorg-x11-drv-nvidia-libs.x86_64 xorg-x11-drv-nvidia-libs.i686

# Optional terminal image previews
sudo dnf install chafa
```

### Arch Linux

Enable the official `[multilib]` repository, then install the 32-bit Vulkan
loader and the matching 32-bit Vulkan driver for the GPU:

```bash
sudo pacman -S --needed lib32-vulkan-icd-loader
```

A compatible 32-bit vkBasalt build is also required. It is not provided by the
standard Arch repositories used by the automated container test.

### Debian and Ubuntu derivatives

Enable the `i386` architecture before installing the distribution's Vulkan and
vkBasalt packages:

```bash
sudo dpkg --add-architecture i386
sudo apt update
```

Package names and vkBasalt availability vary between releases. Confirm that a
32-bit `libvulkan.so.1`, 32-bit `libvkbasalt.so`, and the matching 32-bit GPU
driver are available.

The installer can configure `i386` and install `libvulkan1:i386`
automatically. A compatible 32-bit vkBasalt build may still require a manual
installation.

### openSUSE

The installer can install the 32-bit Vulkan loader automatically:

```bash
sudo zypper install libvulkan1-32bit
```

A compatible 32-bit vkBasalt build is also required. `vkBasalt-32bit` was not
available from the standard Tumbleweed repositories used by the automated
container test.

### Steam Deck and SteamOS

Steam Deck native Steam, internal storage and registered microSD libraries are
supported. The installer never disables SteamOS read-only mode and never
modifies the immutable system image.

If the required 32-bit Vulkan loader or vkBasalt layer is missing, installation
stops before changing the game. A user-local 32-bit vkBasalt installation is
detected in locations such as:

```text
~/.local/lib32/libvkbasalt.so
~/.local/lib/vkbasalt/libvkbasalt.so
~/.local/lib/libvkbasalt.so
```

For the most reliable Steam Deck installation:

1. Switch to **Desktop Mode**.
2. Start Steam once and confirm that No More Heroes appears in the Library.
3. If the game is on microSD, keep that library registered in Steam under
   **Settings → Storage**.
4. Exit Steam completely, including its tray process.
5. Run `./install.sh doctor`, followed by `./install.sh install`.
6. Reopen Steam and launch the game normally. Leave Launch Options alone; the
   required configuration has already been injected.

The installer never calls `steamos-readonly`, never unlocks the immutable
SteamOS image and never installs a system package automatically on SteamOS.
Internal storage and registered microSD libraries use the same installation
and recovery logic.

### Steam Flatpak

Steam Flatpak requires a vkBasalt Vulkan-layer extension inside its Flatpak
runtime, including its `i386` architecture. Installing vkBasalt only on the host
system is not sufficient for the Flatpak version of Steam.

External Steam libraries declared by Flatpak are detected automatically. For a
completely custom external layout, force Flatpak paths explicitly:

```bash
DTAGNAN_STEAM_FLATPAK=1 \
./install.sh install "/external/path/steamapps/common/No More Heroes"
```

## Installation

### Simple automatic installation

1. Download and extract the complete release.

2. Keep these items together:

   ```text
   Comparison/
   DXVK/
   vkBasalt/
   install.sh
   README.md
   SHA256SUMS
   ```

3. Open a terminal in the extracted directory.

4. Make the installer executable and start it:

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

5. Select **Install or update the mod**. If Steam is running, the installer pauses and asks you to close it. Once Steam is fully closed, type `y` and press Enter to continue.

   No game file or Steam setting is changed while this prompt is waiting. If
   the installer is interrupted, it can be started again safely.

6. The installer configures the required No More Heroes Steam Launch Options
   automatically. Existing custom commands are inspected, deduplicated and
   preserved. No copy/paste is required.

7. Start Steam and launch the game normally.

That is the complete installation. Do not add anything to Steam's **Launch
Options** field: the Inspector performs that step automatically and combines
the mod with any command already there.

Do not run the installer with `sudo`. It intentionally refuses root execution
to prevent files from being installed in root's home directory.

## Direct commands

```bash
./install.sh install
./install.sh verify
./install.sh restore
./install.sh options
./install.sh about
./install.sh compare
./install.sh doctor
./install.sh test-deps
```

Command details:

- `install`: automatic install or update, including inspection of Steam Launch
  Options and rollback on failure;
- `verify`: read-only verification of the installed mod;
- `restore`: safe uninstall and restoration of the original state;
- `options`: preview the exact automatic Steam configuration and Inspector
  behavior;
- `about`: explain the components and automated functions offline;
- `compare`: display the supplied before/after images;
- `doctor`: run the complete read-only system diagnostic;
- `test-deps`: dry-run the dependency installation logic without changing the
  system.

For an unusual Steam layout, provide the game directory explicitly:

```bash
./install.sh install "/path/to/steamapps/common/No More Heroes"
```

On distributions using nonstandard library locations, explicit paths can be
provided without modifying the installer:

```bash
VULKAN_LIBRARY="/path/to/32-bit/libvulkan.so.1" \
VKBASALT_LIBRARY="/path/to/32-bit/libvkbasalt.so" \
./install.sh install
```

## Verification

```bash
./install.sh verify
```

Verification checks:

- the known SHA-256 hashes of the custom DXVK DLLs;
- installed DLL contents;
- shader and LUT contents;
- effect order and runtime paths in `nmh.conf`;
- per-user restoration metadata;
- the 32-bit Vulkan and vkBasalt requirements.

The release manifest can also be checked independently:

```bash
sha256sum -c SHA256SUMS
```

## Transaction safety and crash recovery

The installer stages every DLL, configuration and backup as a temporary file
in the destination directory, then commits it with an atomic rename. This
prevents a failed copy from truncating a working file.

Additional safeguards include:

- restoration metadata is committed before the game DLLs are changed;
- a per-user operation lock prevents concurrent installers from racing;
- `SIGINT`, `SIGHUP` and `SIGTERM` trigger rollback and temporary-file cleanup;
- an interrupted second DLL installation remains fully restorable;
- an interrupted configuration update preserves the previous configuration;
- the next installation removes stale transaction files left by an
  untrappable interruption such as power loss or `SIGKILL`.
- a failed installation restores the original DLLs and configuration
  automatically before exiting.

## Automated validation

The installer was validated with an expanded development crash suite covering
installation, verification, uninstallation, interrupted
writes, rollback, repeated updates, corrupt metadata, Steam libraries, Flatpak,
Steam Deck microSD paths, Unicode paths, custom XDG directories and GPU launch
options. The development test programs are not included in the release archive.

The full Podman matrix passed on all four tested distribution families:

| Container | Package manager | Result |
|---|---:|---:|
| Fedora | `dnf` | Passed |
| Ubuntu | `apt` | Passed |
| Arch Linux | `pacman` | Passed |
| openSUSE Tumbleweed | `zypper` | Passed |

These containers validate distribution packaging and installer behavior. A
final test on physical Steam Deck hardware is still recommended because a
container cannot reproduce the Deck's GPU, Steam client or immutable operating
system exactly.

## Updating

Extract the new release over the existing package directory, then run:

```bash
./install.sh install
./install.sh verify
```

The original per-user backup is preserved across repeated installations and
updates.

## Restoring the original state

```bash
./install.sh restore
```

During the first installation, the installer records whether local DirectX
DLLs and an NMH vkBasalt configuration already existed:

- existing files are backed up and restored byte-for-byte;
- files created solely by the mod are removed during restoration;
- files changed by another program after installation are not deleted blindly.

Restoration data is created separately for every Linux user. No original game
DLL from the developer's computer is included or reused. After restoration,
the installer restores the previous No More Heroes Steam Launch Options
automatically. If the value was edited after installation, the uninstaller
removes only the variables managed by Dtagnan Mods and preserves the user's
newer commands.

## Installed locations

### Native Steam

| Component | Location |
|---|---|
| Custom DXVK DLLs | No More Heroes game directory |
| Shaders and LUT | `~/.local/share/Dtagnan-Mods/No-More-Heroes/` |
| vkBasalt profile | `~/.config/vkBasalt/nmh.conf` |
| Restore data | `~/.local/share/Dtagnan-Mods/No-More-Heroes/Vanilla-backup/` |

When `XDG_DATA_HOME` or `XDG_CONFIG_HOME` is defined, the installer respects
those locations.

### Steam Flatpak

Persistent files are stored beneath:

```text
~/.var/app/com.valvesoftware.Steam/
```

The generated vkBasalt configuration uses the corresponding paths visible from
inside the Flatpak sandbox.

## Troubleshooting

### The installer cannot find the game

```bash
./install.sh install "/full/path/to/No More Heroes"
```

The selected directory must contain `nmh.exe`.

### Steam Deck troubleshooting

- Run the installer from Desktop Mode as the normal `deck` user, never with
  `sudo`.
- Close Steam completely before confirming the installer prompt. A minimized
  Steam window or `steamwebhelper` process still counts as running.
- Run `./install.sh doctor` to inspect Steam, game, GPU, Vulkan and vkBasalt
  detection without changing the installation.
- For a microSD installation, verify that the card is mounted and registered
  in Steam's Storage settings. The installer reads `libraryfolders.vdf`; it
  does not scan arbitrary disks.
- If `localconfig.vdf` is missing, start Steam once, open the No More Heroes
  Properties window, close Steam completely and run the installer again.
- If several accounts exist, the account marked `MostRecent` in Steam's
  `loginusers.vdf` is preferred. The newest valid profile is the fallback.
- A 64-bit vkBasalt installation alone is insufficient because `nmh.exe` is
  32-bit. A 32-bit `libvkbasalt.so` must be visible to native Steam.
- Do not disable SteamOS read-only mode. Missing system components cause a safe
  stop before game files are changed.
- For Steam Flatpak on Deck, install a matching i386 vkBasalt runtime extension
  inside Flatpak. Native Steam remains the recommended Deck configuration.

Useful read-only checks:

```bash
./install.sh doctor
file ~/.local/lib32/libvkbasalt.so
grep -n '1420290' ~/.local/share/Steam/userdata/*/config/localconfig.vdf
```

These are diagnostic commands only. They are not Steam Launch Options.

### Existing custom Steam commands

No manual cleanup is normally required. During installation, the command
inspector combines unrelated options with the mod configuration and removes
duplicates of variables it manages. During restoration, it returns the
original value or strips only Dtagnan Mods variables from a newer user-edited
value.

### vkBasalt does not appear in the game

- Run `./install.sh install` again so the per-game Steam configuration can be refreshed. If Steam is running, the installer pauses and asks you to close it; type `y` once Steam is fully closed.
- Confirm that the 32-bit vkBasalt layer is installed.
- For Steam Flatpak, confirm that the layer exists inside the Flatpak runtime.
- Press **F10** and compare the image with the effects enabled and disabled.

### Steam verification replaced the DLLs

```bash
./install.sh install
```

### Terminal images are unavailable

Install `chafa`, or allow the installer to open both PNG files in the desktop
image viewer. The original files remain available in `Comparison/`.

### Libraries use nonstandard locations

Use the `VULKAN_LIBRARY` and `VKBASALT_LIBRARY` overrides shown above. Both
files must be genuine 32-bit ELF libraries.

## Package integrity

Expected custom DXVK hashes:

```text
4edc6a6abb56a056b37799edb510e9b52209fe3f47e25722c676346cddc16428  DXVK/d3d11.dll
bc82659d936412f8c1d911adbba859b09733ad0174190c683665058e4990106e  DXVK/dxgi.dll
```

## Credits and components

- [DXVK](https://github.com/doitsujin/dxvk)
- [vkBasalt](https://github.com/DadSchoorse/vkBasalt)
- [ReShade shader format](https://reshade.me/)

The custom game profile, color LUT, Bloom, Vignette, Dithering shader,
configuration and installer are part of this Dtagnan Mods release.

## License notice

This is an unofficial community project and is not affiliated with Grasshopper
Manufacture, Marvelous, XSEED Games, Valve, DXVK, vkBasalt or ReShade. Refer to
the licenses of the bundled open-source components and source patch before
redistribution. The exact DXVK source modification, upstream revision and
reproduction instructions are included in `Source-patch/`.
