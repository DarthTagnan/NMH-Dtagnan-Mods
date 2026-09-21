#!/usr/bin/env bash
set -Eeuo pipefail

APP_ID="1420290"
GAME_NAME="No More Heroes"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ACTION="${1:-menu}"
EXPLICIT_GAME_DIR="${2:-}"
MOD_VERSION="1.1.3"
D3D11_SHA256="4edc6a6abb56a056b37799edb510e9b52209fe3f47e25722c676346cddc16428"
DXGI_SHA256="bc82659d936412f8c1d911adbba859b09733ad0174190c683665058e4990106e"
BEFORE_SHA256="25d1306a9a599bc70667654ac0f9d0230cd4f733415728ab3ed6ffffe7f1fbcc"
AFTER_SHA256="55526222429945823fede8780538ab7e58a2b0db4088b70a6833237fce31be5c"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
RUNTIME_DIR="$DATA_HOME/Dtagnan-Mods/No-More-Heroes"
SHADER_DIR="$RUNTIME_DIR/Shaders"
TEXTURE_DIR="$RUNTIME_DIR/Textures"
LUT_DIR="$RUNTIME_DIR/LUTs"
BACKUP_DIR="$RUNTIME_DIR/Vanilla-backup"
CONFIG_DIR="$CONFIG_HOME/vkBasalt"
CONFIG_FILE="$CONFIG_DIR/nmh.conf"
CONFIG_BACKUP="$CONFIG_DIR/nmh.conf.pre-dtagnan-mods"
BACKUP_STATE="$BACKUP_DIR/install-state"
VISIBLE_RUNTIME_DIR="$RUNTIME_DIR"
VISIBLE_CONFIG_FILE="$CONFIG_FILE"
COMPARISON_DIR="$ROOT/Comparison"
BEFORE_IMAGE="$COMPARISON_DIR/Before.png"
AFTER_IMAGE="$COMPARISON_DIR/After.png"
TEMP_FILES=()

cleanup_temp_files() {
  local temporary
  for temporary in "${TEMP_FILES[@]}"; do
    [[ -n "$temporary" ]] && rm -f -- "$temporary"
  done
}

trap cleanup_temp_files EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

if [[ -t 1 && "${TERM:-dumb}" != "dumb" && "${NO_COLOR:-}" == "" ]]; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  WHITE=$'\033[97m'
else
  RESET="" BOLD="" DIM="" RED="" GREEN="" YELLOW="" CYAN="" WHITE=""
fi

print_header() {
  printf '%s' "$GREEN"
  cat <<'EOF'
 DDDD  TTTTT  AAA   GGG  N   N  AAA  N   N    M   M  OOO  DDDD  SSSS
 D   D   T   A   A G     NN  N A   A NN  N    MM MM O   O D   D S
 D   D   T   AAAAA G  GG N N N AAAAA N N N    M M M O   O D   D SSS
 D   D   T   A   A G   G N  NN A   A N  NN    M   M O   O D   D    S
 DDDD    T   A   A  GGG  N   N A   A N   N    M   M  OOO  DDDD  SSSS
EOF
  printf '%s\n' "$RESET"
  printf '  %sNo More Heroes - Linux Enhancement Package%s\n' "$WHITE" "$RESET"
  printf '  %sCustom DXVK + vkBasalt post-processing%s\n\n' "$DIM" "$RESET"
}

print_rule() {
  printf '  %s%s%s\n' "$DIM" '--------------------------------------------------------' "$RESET"
}

die() {
  printf '\n  %s%s[ERROR]%s %s\n' "$BOLD" "$RED" "$RESET" "$*" >&2
  exit 1
}

note() {
  printf '\n  %s%s[INFO]%s %s\n' "$BOLD" "$CYAN" "$RESET" "$*"
}

success() {
  printf '  %s%s[ OK ]%s %s\n' "$BOLD" "$GREEN" "$RESET" "$*"
}

warning() {
  printf '  %s%s[WARN]%s %s\n' "$BOLD" "$YELLOW" "$RESET" "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

preflight() {
  [[ "$(uname -s)" == "Linux" ]] || die "This mod supports Linux only."
  if (( EUID == 0 )) && [[ "${DTAGNAN_ALLOW_ROOT:-0}" != "1" ]]; then
    die "Do not run this installer with sudo or as root. Run it as your normal Steam user."
  fi

  local command
  for command in realpath install cmp sed grep awk sha256sum file find head cp mv rm mkdir chmod uname; do
    require_command "$command"
  done
}

need_file() {
  [[ -s "$1" ]] || die "Required file is missing or empty: $1"
}

install_atomic() {
  local source="$1" destination="$2" mode="${3:-0644}"
  local temporary="${destination}.dtagnan-tmp.$$"
  TEMP_FILES+=("$temporary")

  if ! install -m "$mode" -- "$source" "$temporary"; then
    rm -f -- "$temporary"
    die "Failed to stage: $destination"
  fi
  if ! mv -f -- "$temporary" "$destination"; then
    rm -f -- "$temporary"
    die "Failed to install: $destination"
  fi
}

cleanup_stale_install_files() {
  local target stale

  for target in "$1" "$RUNTIME_DIR" "$CONFIG_DIR"; do
    [[ -d "$target" ]] || continue
    while IFS= read -r -d '' stale; do
      rm -f -- "$stale"
    done < <(find "$target" -type f \( \
      -name '*.dtagnan-tmp.*' -o \
      -name 'install-state.tmp.*' \
    \) -print0 2>/dev/null)
  done
}

find_game_dir() {
  local candidate manifest steamapps installdir steam_root library_file path
  local -a steam_roots=()
  local -a steamapps_dirs=()

  if [[ -n "$EXPLICIT_GAME_DIR" ]]; then
    [[ -f "$EXPLICIT_GAME_DIR/nmh.exe" ]] || \
      die "nmh.exe was not found in: $EXPLICIT_GAME_DIR"
    realpath -e -- "$EXPLICIT_GAME_DIR"
    return
  fi

  steam_roots+=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
  )

  for steam_root in "${steam_roots[@]}"; do
    [[ -d "$steam_root/steamapps" ]] || continue
    steamapps_dirs+=("$steam_root/steamapps")
    library_file="$steam_root/steamapps/libraryfolders.vdf"
    [[ -f "$library_file" ]] || continue

    while IFS= read -r path; do
      path="${path//\\\\/\\}"
      [[ -d "$path/steamapps" ]] && steamapps_dirs+=("$path/steamapps")
    done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$library_file")
  done

  for steamapps in "${steamapps_dirs[@]}"; do
    manifest="$steamapps/appmanifest_${APP_ID}.acf"
    [[ -f "$manifest" ]] || continue
    installdir="$(sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)"
    candidate="$steamapps/common/$installdir"
    if [[ -f "$candidate/nmh.exe" ]]; then
      realpath -e -- "$candidate"
      return
    fi
  done

  candidate=""
  if [[ -t 0 ]]; then
    printf '\n  %sGame not detected automatically.%s\n' "$YELLOW" "$RESET" >/dev/tty
    printf '  Enter the full No More Heroes directory (or leave blank to cancel): ' >/dev/tty
    IFS= read -r candidate </dev/tty
    if [[ -n "$candidate" && -f "$candidate/nmh.exe" ]]; then
      realpath -e -- "$candidate"
      return
    fi
  fi

  die "Steam installation not found. Use: ./install.sh install '/path/to/No More Heroes'"
}

is_flatpak_game() {
  local game_dir="$1" library_file path

  [[ "${DTAGNAN_STEAM_FLATPAK:-0}" == "1" ]] && return 0
  [[ "$game_dir" == "$HOME/.var/app/com.valvesoftware.Steam/"* ]] && return 0

  library_file="$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/libraryfolders.vdf"
  [[ -f "$library_file" ]] || return 1

  while IFS= read -r path; do
    path="${path//\\\\/\\}"
    [[ "$game_dir" == "$path/steamapps/common/"* ]] && return 0
  done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\([^"]*\)".*/\1/p' "$library_file")

  return 1
}

configure_install_scope() {
  local game_dir="$1"

  DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  RUNTIME_DIR="$DATA_HOME/Dtagnan-Mods/No-More-Heroes"
  CONFIG_DIR="$CONFIG_HOME/vkBasalt"
  CONFIG_FILE="$CONFIG_DIR/nmh.conf"
  CONFIG_BACKUP="$CONFIG_DIR/nmh.conf.pre-dtagnan-mods"

  if is_flatpak_game "$game_dir"; then
    DATA_HOME="$HOME/.var/app/com.valvesoftware.Steam/data"
    CONFIG_HOME="$HOME/.var/app/com.valvesoftware.Steam/config"
    RUNTIME_DIR="$DATA_HOME/Dtagnan-Mods/No-More-Heroes"
    CONFIG_DIR="$CONFIG_HOME/vkBasalt"
    CONFIG_FILE="$CONFIG_DIR/nmh.conf"
    CONFIG_BACKUP="$CONFIG_DIR/nmh.conf.pre-dtagnan-mods"
    VISIBLE_RUNTIME_DIR="$HOME/.local/share/Dtagnan-Mods/No-More-Heroes"
    VISIBLE_CONFIG_FILE="$HOME/.config/vkBasalt/nmh.conf"
  else
    VISIBLE_RUNTIME_DIR="$RUNTIME_DIR"
    VISIBLE_CONFIG_FILE="$CONFIG_FILE"
  fi

  SHADER_DIR="$RUNTIME_DIR/Shaders"
  TEXTURE_DIR="$RUNTIME_DIR/Textures"
  LUT_DIR="$RUNTIME_DIR/LUTs"
  BACKUP_DIR="$RUNTIME_DIR/Vanilla-backup"
  BACKUP_STATE="$BACKUP_DIR/install-state"
}

check_package() {
  need_file "$ROOT/DXVK/d3d11.dll"
  need_file "$ROOT/DXVK/dxgi.dll"
  need_file "$ROOT/vkBasalt/Shaders/ReShade.fxh"
  need_file "$ROOT/vkBasalt/Shaders/NMH_Bloom.fx"
  need_file "$ROOT/vkBasalt/Shaders/NMH_Vignette.fx"
  need_file "$ROOT/vkBasalt/Shaders/NMH_Dither.fx"
  need_file "$ROOT/vkBasalt/LUTs/nmh-color.cube"

  if [[ "${DTAGNAN_SKIP_PAYLOAD_HASH_CHECK:-0}" != "1" ]]; then
    [[ "$(sha256sum "$ROOT/DXVK/d3d11.dll" | awk '{print $1}')" == "$D3D11_SHA256" ]] || \
      die "Package integrity check failed for DXVK/d3d11.dll"
    [[ "$(sha256sum "$ROOT/DXVK/dxgi.dll" | awk '{print $1}')" == "$DXGI_SHA256" ]] || \
      die "Package integrity check failed for DXVK/dxgi.dll"
  fi
}

check_vkbasalt() {
  local game_dir="${1:-}" lib="" candidate
  local -a candidates=()

  if [[ -n "$game_dir" ]] && is_flatpak_game "$game_dir"; then
    command -v flatpak >/dev/null 2>&1 || \
      die "Flatpak Steam was detected, but the flatpak command is unavailable."

    if ! flatpak list --runtime --columns=application,arch 2>/dev/null | \
         grep -i 'vkBasalt' | grep -qi 'i386'; then
      die "Flatpak Steam needs a 32-bit vkBasalt Vulkan-layer extension inside its Flatpak runtime. Install it, then run this installer again."
    fi

    success "Flatpak Steam and a vkBasalt runtime extension were detected."
    return
  fi

  candidates=(
    "${VKBASALT_LIBRARY:-}" \
    /usr/lib/vkbasalt/libvkbasalt.so \
    /usr/lib32/libvkbasalt.so \
    /usr/lib32/vkbasalt/libvkbasalt.so \
    /usr/lib/i386-linux-gnu/libvkbasalt.so \
    /usr/lib/i386-linux-gnu/vkbasalt/libvkbasalt.so
  )

  while IFS= read -r candidate; do
    candidates+=("$candidate")
  done < <(find /usr/lib /usr/lib32 /lib /lib32 \
    -maxdepth 4 -type f -o -type l 2>/dev/null | grep -E '/libvkbasalt\.so([.0-9]*)?$' || true)

  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    if file -L "$candidate" | grep -qiE '32-bit|Intel 80386'; then
      lib="$candidate"
      break
    fi
  done

  [[ -n "$lib" ]] || die "32-bit vkBasalt was not found. Install the i686/32-bit vkBasalt package."
}

check_vulkan_loader() {
  local game_dir="${1:-}" candidate loader=""
  local -a candidates=()

  # Flatpak Steam supplies its own Vulkan loader through the runtime.
  if [[ -n "$game_dir" ]] && is_flatpak_game "$game_dir"; then
    return
  fi

  candidates=(
    "${VULKAN_LIBRARY:-}" \
    /lib/libvulkan.so.1 \
    /lib32/libvulkan.so.1 \
    /usr/lib/libvulkan.so.1 \
    /usr/lib32/libvulkan.so.1 \
    /usr/lib/i386-linux-gnu/libvulkan.so.1
  )

  if command -v ldconfig >/dev/null 2>&1; then
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(ldconfig -p 2>/dev/null | awk '/libvulkan\.so\.1/ { print $NF }')
  fi

  while IFS= read -r candidate; do
    candidates+=("$candidate")
  done < <(find /usr/lib /usr/lib32 /lib /lib32 \
    -maxdepth 4 \( -type f -o -type l \) -name 'libvulkan.so*' 2>/dev/null || true)

  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    if file -L "$candidate" | grep -qiE '32-bit|Intel 80386'; then
      loader="$candidate"
      break
    fi
  done

  [[ -n "$loader" ]] || die "The 32-bit Vulkan loader was not found. Install your distribution's i686/i386 Vulkan loader and GPU driver."
}

detect_gpu_vendor() {
  local devices=""

  if [[ -n "${DTAGNAN_GPU_PROFILE:-}" ]]; then
    case "$DTAGNAN_GPU_PROFILE" in
      nvidia-hybrid|nvidia|amd|intel|unknown) printf '%s\n' "$DTAGNAN_GPU_PROFILE"; return ;;
    esac
  fi

  if command -v lspci >/dev/null 2>&1; then
    devices="$(lspci 2>/dev/null | grep -Ei 'VGA|3D controller|Display controller' || true)"
  elif command -v vulkaninfo >/dev/null 2>&1; then
    devices="$(vulkaninfo --summary 2>/dev/null || true)"
  fi

  if [[ -z "$devices" ]]; then
    local vendor
    for vendor in /sys/class/drm/card*/device/vendor; do
      [[ -r "$vendor" ]] || continue
      case "$(<"$vendor")" in
        0x10de) devices+=" NVIDIA" ;;
        0x8086) devices+=" Intel" ;;
        0x1002) devices+=" AMD" ;;
      esac
    done
  fi

  if grep -qiE 'NVIDIA' <<<"$devices" && grep -qiE 'Intel|AMD|ATI|Radeon' <<<"$devices"; then
    printf 'nvidia-hybrid\n'
  elif grep -qiE 'NVIDIA' <<<"$devices"; then
    printf 'nvidia\n'
  elif grep -qiE 'AMD|ATI|Radeon' <<<"$devices"; then
    printf 'amd\n'
  elif grep -qiE 'Intel' <<<"$devices"; then
    printf 'intel\n'
  else
    printf 'unknown\n'
  fi
}

build_launch_options() {
  local gpu config_quoted
  gpu="$(detect_gpu_vendor)"
  printf -v config_quoted '%q' "$VISIBLE_CONFIG_FILE"

  printf 'ENABLE_VKBASALT=1 VK_INSTANCE_LAYERS=VK_LAYER_VKBASALT_post_processing VKBASALT_CONFIG_FILE=%s WINEDLLOVERRIDES="d3d11,dxgi=n,b"' "$config_quoted"

  if [[ "$gpu" == "nvidia-hybrid" ]]; then
    printf ' __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only'
  fi

  printf ' %%command%%\n'
}

write_config() {
  local visible_shader_dir="$VISIBLE_RUNTIME_DIR/Shaders"
  local visible_texture_dir="$VISIBLE_RUNTIME_DIR/Textures"
  local visible_lut_dir="$VISIBLE_RUNTIME_DIR/LUTs"
  local temporary="$CONFIG_FILE.dtagnan-tmp.$$"
  TEMP_FILES+=("$temporary")
  mkdir -p -- "$CONFIG_DIR"

  cat > "$temporary" <<EOF
# No More Heroes - Dtagnan Mods vkBasalt profile
effects = smaa:lut:nmhBloom:nmhVignette:cas:nmhDither

toggleKey = F10
enableOnLaunch = True
depthCapture = off

casSharpness = 0.20

smaaEdgeDetection = luma
smaaThreshold = 0.08
smaaMaxSearchSteps = 16
smaaMaxSearchStepsDiag = 8
smaaCornerRounding = 25

lutFile = "$visible_lut_dir/nmh-color.cube"

nmhBloom = "$visible_shader_dir/NMH_Bloom.fx"
nmhVignette = "$visible_shader_dir/NMH_Vignette.fx"
nmhDither = "$visible_shader_dir/NMH_Dither.fx"

reshadeIncludePath = "$visible_shader_dir"
reshadeTexturePath = "$visible_texture_dir"
EOF
  chmod 0644 "$temporary"
  mv -f -- "$temporary" "$CONFIG_FILE"
}

state_has() {
  [[ -f "$BACKUP_STATE" ]] && grep -Fqx -- "$1" "$BACKUP_STATE"
}

prepare_backups() {
  local game_dir="$1" current tmp_state
  [[ -f "$BACKUP_STATE" ]] && return

  mkdir -p -- "$BACKUP_DIR" "$CONFIG_DIR"
  tmp_state="$BACKUP_STATE.tmp.$$"
  TEMP_FILES+=("$tmp_state")
  : > "$tmp_state"

  for current in d3d11.dll dxgi.dll; do
    if [[ -f "$game_dir/$current" ]]; then
      if cmp -s -- "$game_dir/$current" "$ROOT/DXVK/$current"; then
        if [[ -f "$BACKUP_DIR/$current" ]]; then
          printf '%s=present\n' "$current" >> "$tmp_state"
          continue
        fi
        rm -f -- "$tmp_state"
        die "Cannot create an original backup: $current is already the modded DLL and no previous backup exists. Verify the game files in Steam, then install again."
      fi
      install_atomic "$game_dir/$current" "$BACKUP_DIR/$current"
      printf '%s=present\n' "$current" >> "$tmp_state"
    else
      printf '%s=absent\n' "$current" >> "$tmp_state"
    fi
  done

  if [[ -f "$CONFIG_FILE" ]] && ! grep -q '^# No More Heroes - Dtagnan Mods' "$CONFIG_FILE"; then
    cp -a -- "$CONFIG_FILE" "$CONFIG_BACKUP"
    printf 'config=present\n' >> "$tmp_state"
  elif [[ -f "$CONFIG_BACKUP" ]]; then
    printf 'config=present\n' >> "$tmp_state"
  else
    printf 'config=absent\n' >> "$tmp_state"
  fi

  mv -f -- "$tmp_state" "$BACKUP_STATE"
}

install_mod() {
  local game_dir
  check_package
  game_dir="$(find_game_dir)"
  configure_install_scope "$game_dir"
  check_vulkan_loader "$game_dir"
  check_vkbasalt "$game_dir"

  note "Game detected: $game_dir"
  mkdir -p -- "$SHADER_DIR" "$TEXTURE_DIR" "$LUT_DIR" "$BACKUP_DIR"
  cleanup_stale_install_files "$game_dir"
  [[ -w "$game_dir" ]] || die "The game directory is not writable: $game_dir"
  prepare_backups "$game_dir"

  install_atomic "$ROOT/vkBasalt/Shaders/ReShade.fxh" "$SHADER_DIR/ReShade.fxh"
  install_atomic "$ROOT/vkBasalt/Shaders/NMH_Bloom.fx" "$SHADER_DIR/NMH_Bloom.fx"
  install_atomic "$ROOT/vkBasalt/Shaders/NMH_Vignette.fx" "$SHADER_DIR/NMH_Vignette.fx"
  install_atomic "$ROOT/vkBasalt/Shaders/NMH_Dither.fx" "$SHADER_DIR/NMH_Dither.fx"
  install_atomic "$ROOT/vkBasalt/LUTs/nmh-color.cube" "$LUT_DIR/nmh-color.cube"

  install_atomic "$ROOT/DXVK/d3d11.dll" "$game_dir/d3d11.dll"
  install_atomic "$ROOT/DXVK/dxgi.dll" "$game_dir/dxgi.dll"
  write_config

  success "Installation completed"
  printf '\n  %-15s %s\n' 'Configuration:' "$CONFIG_FILE"
  printf '  %-15s %s\n' 'Assets:' "$RUNTIME_DIR"
  printf '  %-15s %s\n' 'Toggle key:' 'F10'
  show_launch_options "$game_dir"

  verify_mod "$game_dir"
}

verify_mod() {
  local game_dir="${1:-}"
  [[ -n "$game_dir" ]] || game_dir="$(find_game_dir)"
  configure_install_scope "$game_dir"
  check_package
  check_vulkan_loader "$game_dir"
  check_vkbasalt "$game_dir"

  note "Verifying installation"
  cmp -s -- "$ROOT/DXVK/d3d11.dll" "$game_dir/d3d11.dll" || \
    die "Installed d3d11.dll does not match the package"
  cmp -s -- "$ROOT/DXVK/dxgi.dll" "$game_dir/dxgi.dll" || \
    die "Installed dxgi.dll does not match the package"

  need_file "$CONFIG_FILE"
  need_file "$SHADER_DIR/ReShade.fxh"
  need_file "$SHADER_DIR/NMH_Bloom.fx"
  need_file "$SHADER_DIR/NMH_Vignette.fx"
  need_file "$SHADER_DIR/NMH_Dither.fx"
  need_file "$LUT_DIR/nmh-color.cube"
  need_file "$BACKUP_STATE"

  cmp -s -- "$ROOT/vkBasalt/Shaders/ReShade.fxh" "$SHADER_DIR/ReShade.fxh" || die "Installed ReShade.fxh does not match the package"
  cmp -s -- "$ROOT/vkBasalt/Shaders/NMH_Bloom.fx" "$SHADER_DIR/NMH_Bloom.fx" || die "Installed NMH_Bloom.fx does not match the package"
  cmp -s -- "$ROOT/vkBasalt/Shaders/NMH_Vignette.fx" "$SHADER_DIR/NMH_Vignette.fx" || die "Installed NMH_Vignette.fx does not match the package"
  cmp -s -- "$ROOT/vkBasalt/Shaders/NMH_Dither.fx" "$SHADER_DIR/NMH_Dither.fx" || die "Installed NMH_Dither.fx does not match the package"
  cmp -s -- "$ROOT/vkBasalt/LUTs/nmh-color.cube" "$LUT_DIR/nmh-color.cube" || die "Installed LUT does not match the package"

  grep -q '^effects = smaa:lut:nmhBloom:nmhVignette:cas:nmhDither$' "$CONFIG_FILE" || \
    die "The effect chain in nmh.conf is incorrect"
  grep -Fqx "lutFile = \"$VISIBLE_RUNTIME_DIR/LUTs/nmh-color.cube\"" "$CONFIG_FILE" || \
    die "The LUT path in nmh.conf is incorrect"
  grep -Fqx "nmhBloom = \"$VISIBLE_RUNTIME_DIR/Shaders/NMH_Bloom.fx\"" "$CONFIG_FILE" || \
    die "The Bloom shader path in nmh.conf is incorrect"
  grep -Fqx "nmhVignette = \"$VISIBLE_RUNTIME_DIR/Shaders/NMH_Vignette.fx\"" "$CONFIG_FILE" || \
    die "The Vignette shader path in nmh.conf is incorrect"
  grep -Fqx "nmhDither = \"$VISIBLE_RUNTIME_DIR/Shaders/NMH_Dither.fx\"" "$CONFIG_FILE" || \
    die "The Dither shader path in nmh.conf is incorrect"

  success "DXVK DLLs, configuration, LUT and shaders are installed correctly."
  sha256sum "$game_dir/d3d11.dll" "$game_dir/dxgi.dll"
}

restore_vanilla() {
  local game_dir current
  game_dir="$(find_game_dir)"
  configure_install_scope "$game_dir"

  need_file "$BACKUP_STATE"

  note "Restoring original DLLs"
  for current in d3d11.dll dxgi.dll; do
    if state_has "$current=present"; then
      need_file "$BACKUP_DIR/$current"
      install_atomic "$BACKUP_DIR/$current" "$game_dir/$current"
    elif state_has "$current=absent"; then
      if [[ ! -e "$game_dir/$current" ]] || cmp -s -- "$game_dir/$current" "$ROOT/DXVK/$current"; then
        rm -f -- "$game_dir/$current"
      else
        warning "$current was changed by another program and was left untouched."
      fi
    else
      die "Invalid backup state for $current"
    fi
  done

  if state_has 'config=present'; then
    need_file "$CONFIG_BACKUP"
    cp -a -- "$CONFIG_BACKUP" "$CONFIG_FILE"
    success "Previous vkBasalt configuration restored."
  elif state_has 'config=absent'; then
    if [[ -f "$CONFIG_FILE" ]] && grep -q '^# No More Heroes - Dtagnan Mods' "$CONFIG_FILE"; then
      rm -f -- "$CONFIG_FILE"
    fi
    success "The mod-created vkBasalt configuration was removed."
  else
    die "Invalid backup state for the vkBasalt configuration"
  fi

  success "Original DLLs restored to: $game_dir"
  warning "Remember to remove the mod launch options from Steam."
}

show_launch_options() {
  local game_dir="${1:-}" gpu
  if [[ -z "$game_dir" ]]; then
    game_dir="$(find_game_dir)"
    configure_install_scope "$game_dir"
  fi
  gpu="$(detect_gpu_vendor)"
  print_rule
  cat <<EOF
  STEAM LAUNCH OPTIONS

ENABLE_VKBASALT=1 enables the vkBasalt Vulkan post-processing layer.
VKBASALT_CONFIG_FILE tells vkBasalt to load the NMH-specific profile.
WINEDLLOVERRIDES forces Proton to use the custom DXVK DLLs in the game folder.

Detected GPU profile: $gpu
NVIDIA PRIME variables are added only on hybrid NVIDIA systems.
AMD and Intel systems receive clean vendor-neutral options.

Copy this entire line into the game's Steam Launch Options:

EOF
  build_launch_options
  printf '\n'
}

display_terminal_image() {
  local image="$1"

  if [[ "${TERM:-}" == xterm-kitty* ]] && command -v kitty >/dev/null 2>&1; then
    if kitty +kitten icat --align left -- "$image"; then
      return 0
    fi
  fi

  if [[ -n "${WEZTERM_PANE:-}" ]] && command -v wezterm >/dev/null 2>&1; then
    if wezterm imgcat --width 90 --height 32 -- "$image"; then
      return 0
    fi
  fi

  if command -v chafa >/dev/null 2>&1; then
    if chafa --format symbols --colors full --dither diffusion \
        --size "${COLUMNS:-120}x${DTAGNAN_PREVIEW_HEIGHT:-40}" -- "$image"; then
      return 0
    fi
  fi

  return 1
}

show_comparison() {
  need_file "$BEFORE_IMAGE"
  need_file "$AFTER_IMAGE"
  [[ "$(sha256sum "$BEFORE_IMAGE" | awk '{print $1}')" == "$BEFORE_SHA256" ]] || die "Before.png is corrupted"
  [[ "$(sha256sum "$AFTER_IMAGE" | awk '{print $1}')" == "$AFTER_SHA256" ]] || die "After.png is corrupted"
  print_rule
  printf '  %sBEFORE / AFTER COMPARISON%s\n\n' "$BOLD" "$RESET"

  printf '  %sBEFORE%s — original presentation\n\n' "$BOLD" "$RESET"
  if display_terminal_image "$BEFORE_IMAGE"; then
    printf '\n  %sAFTER%s — Dtagnan Mods post-processing\n\n' "$BOLD" "$RESET"
    display_terminal_image "$AFTER_IMAGE"
    printf '\n'
  else
    warning "This terminal cannot render images directly. Install 'chafa' for an in-terminal preview."
    if command -v xdg-open >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
      xdg-open "$BEFORE_IMAGE" >/dev/null 2>&1 &
      xdg-open "$AFTER_IMAGE" >/dev/null 2>&1 &
      success "The before and after images were opened in your image viewer."
    else
      printf '  Before: %s\n  After:  %s\n' "$BEFORE_IMAGE" "$AFTER_IMAGE"
    fi
  fi
}

show_about() {
  print_rule
  printf '  ABOUT THIS DTAGNAN MODS RELEASE — VERSION %s\n\n' "$MOD_VERSION"
  cat <<'EOF'
This package improves No More Heroes on Linux in two separate stages:

1. Custom DXVK build
   Converts the game's Direct3D 11 rendering to Vulkan. This build contains
   an NMH-specific profile with a one-frame latency cap, four shader compiler
   threads, present timing and implicit resolves.

2. vkBasalt post-processing
   vkBasalt is a Vulkan post-processing layer. It receives the final image
   produced by DXVK and applies this effect chain:

     SMAA -> Color LUT -> Bloom -> Vignette -> CAS -> Dithering

   SMAA       Smooths jagged edges.
   Color LUT  Adjusts color, contrast and midtones for NMH.
   Bloom      Adds a subtle glow around bright areas.
   Vignette   Slightly darkens the outer corners.
   CAS        Restores fine detail and sharpness.
   Dithering  Reduces visible color banding in skies and gradients.

The F10 key toggles all post-processing effects on or off while playing.

Native Steam locations
----------------------
Custom DXVK DLLs:  the No More Heroes game directory
Shaders and LUT:   ~/.local/share/Dtagnan-Mods/No-More-Heroes
vkBasalt profile:  ~/.config/vkBasalt/nmh.conf
Restore data:      ~/.local/share/Dtagnan-Mods/No-More-Heroes/Vanilla-backup

Flatpak Steam stores the same data inside its persistent per-application
directories under ~/.var/app/com.valvesoftware.Steam.

Requirements
------------
Steam, Proton, Vulkan, and the 32-bit vkBasalt library are required.
The installer checks the 32-bit Vulkan loader and vkBasalt before installing.

ENABLE_VKBASALT=1 does not install vkBasalt. It tells Vulkan to enable the
already-installed vkBasalt layer when No More Heroes starts.
EOF
}

pause_menu() {
  printf '\n  %sPress Enter to return to the main menu...%s' "$DIM" "$RESET"
  read -r _
}

confirm_restore() {
  local answer
  printf '\n  %sRestore the original DLLs?%s %s[y/N]%s: ' \
    "$BOLD" "$RESET" "$YELLOW" "$RESET"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) restore_vanilla ;;
    *) warning "Restore cancelled." ;;
  esac
}

main_menu() {
  local choice

  while true; do
    clear 2>/dev/null || true
    print_header
    print_rule
    printf '\n'
    printf '    %s%s1%s  Install or update the mod\n' "$BOLD" "$CYAN" "$RESET"
    printf '    %s%s2%s  Verify the current installation\n' "$BOLD" "$CYAN" "$RESET"
    printf '    %s%s3%s  Restore the original game DLLs\n' "$BOLD" "$CYAN" "$RESET"
    printf '    %s%s4%s  Show Steam launch options\n' "$BOLD" "$CYAN" "$RESET"
    printf '    %s%s5%s  About this mod\n' "$BOLD" "$CYAN" "$RESET"
    printf '    %s%s6%s  Show before / after comparison\n' "$BOLD" "$CYAN" "$RESET"
    printf '    %s%s7%s  Exit\n\n' "$BOLD" "$CYAN" "$RESET"
    print_rule
    printf '\n  %sChoose an option%s %s[1-7]%s: ' \
      "$BOLD" "$RESET" "$DIM" "$RESET"
    read -r choice

    case "$choice" in
      1) install_mod; pause_menu ;;
      2) verify_mod; pause_menu ;;
      3) confirm_restore; pause_menu ;;
      4) show_launch_options; pause_menu ;;
      5) show_about; pause_menu ;;
      6) show_comparison; pause_menu ;;
      7) printf '\n  %sGoodbye.%s\n' "$GREEN" "$RESET"; return ;;
      *) warning "Invalid option. Choose a number from 1 to 7."; sleep 1 ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage:
  ./install.sh                             Open the interactive menu
  ./install.sh install [game-directory]    Install or update the mod
  ./install.sh verify  [game-directory]    Verify the installation
  ./install.sh restore [game-directory]    Restore the original DLLs
  ./install.sh options                     Show Steam launch options
  ./install.sh about                       Explain what the mod installs
  ./install.sh compare                     Show the before / after comparison
EOF
}

preflight

case "$ACTION" in
  menu)    main_menu ;;
  install) install_mod ;;
  verify)  verify_mod ;;
  restore) restore_vanilla ;;
  options) show_launch_options ;;
  about)   show_about ;;
  compare) show_comparison ;;
  -h|--help|help) usage ;;
  *) usage; die "Unknown action: $ACTION" ;;
esac
