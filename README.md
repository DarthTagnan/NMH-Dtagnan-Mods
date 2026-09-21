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

**Installer version 1.1.1**

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

| Original presentation | Dtagnan Mods post-processing |
|:---:|:---:|
| ![Original presentation](Comparison/Before.png) | ![Dtagnan Mods post-processing](Comparison/After.png) |

The installer can also display these images from its interactive menu. With
`chafa`, Kitty or WezTerm, they are rendered directly inside the terminal.

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
- Steam's primary library;
- additional libraries declared in `libraryfolders.vdf`;
- NVIDIA hybrid graphics, NVIDIA-only, AMD and Intel systems;
- custom XDG data and configuration directories;
- installation paths containing spaces;
- an explicitly supplied game directory.

NVIDIA PRIME variables are added only when a hybrid NVIDIA system is detected.
AMD, Intel and NVIDIA-only systems receive vendor-appropriate launch options
without unnecessary PRIME variables.

## Requirements

- A 64-bit Linux distribution
- Steam for Linux or Steam Flatpak
- No More Heroes on Steam — App ID `1420290`
- Proton or GE-Proton selected as the compatibility tool
- A Vulkan-capable GPU and working Vulkan driver
- 64-bit and 32-bit Vulkan userspace support
- vkBasalt with its 32-bit Vulkan layer
- Bash and standard GNU/Linux command-line tools
- Optional: `chafa` for terminal image previews

The executable `nmh.exe` is 32-bit. A system with only 64-bit Vulkan or
vkBasalt libraries is therefore incomplete. The installer verifies the 32-bit
Vulkan loader and vkBasalt layer before modifying the game.

### Fedora

```bash
sudo dnf install vkBasalt

# AMD or Intel with Mesa
sudo dnf install mesa-vulkan-drivers.x86_64 mesa-vulkan-drivers.i686

# NVIDIA with the RPM Fusion proprietary driver
sudo dnf install xorg-x11-drv-nvidia-libs.x86_64 xorg-x11-drv-nvidia-libs.i686

# Optional terminal image previews
sudo dnf install chafa
```

### Arch Linux

Install the Vulkan loader, its `lib32-` counterpart, vkBasalt and a compatible
32-bit vkBasalt build. Install the correct Vulkan driver and matching `lib32-`
driver for the GPU.

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

5. Select **Install or update the mod**.

6. Select **Show Steam launch options** and copy the complete generated line
   into:

   **Steam → Library → No More Heroes → Properties → General → Launch Options**

7. Start the game normally from Steam.

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
```

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
remove the mod launch options from Steam.

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

### vkBasalt does not appear in the game

- Confirm that the entire generated launch line was copied into Steam.
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
redistribution.
