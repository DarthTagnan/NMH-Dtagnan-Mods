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

detect_platform() {
  PLATFORM="linux"
  PLATFORM_NAME="Linux"

  OS_ID=""
  OS_ID_LIKE=""
  OS_NAME=""
  OS_VARIANT_ID=""

  if [[ -r /etc/os-release ]]; then
    OS_ID="$(sed -n 's/^ID=//p' /etc/os-release | head -n1 | tr -d '"')"
    OS_ID_LIKE="$(sed -n 's/^ID_LIKE=//p' /etc/os-release | head -n1 | tr -d '"')"
    OS_NAME="$(sed -n 's/^NAME=//p' /etc/os-release | head -n1 | tr -d '"')"
    OS_VARIANT_ID="$(sed -n 's/^VARIANT_ID=//p' /etc/os-release | head -n1 | tr -d '"')"

    [[ -n "$OS_NAME" ]] && PLATFORM_NAME="$OS_NAME"

    # SteamOS must be identified before any generic Arch-family logic.
    if [[ "$OS_ID" == "steamos" ]] ||
       [[ "$OS_VARIANT_ID" == "steamdeck" ]] ||
       [[ "$OS_NAME" == *"SteamOS"* ]]; then
      PLATFORM="steamdeck"
      PLATFORM_NAME="Steam Deck / SteamOS"
      return 0
    fi
  fi

  # Conservative fallback for Steam Deck installations where
  # /etc/os-release does not provide the expected SteamOS markers.
  if [[ "$HOME" == "/home/deck" &&
        -d "$HOME/.local/share/Steam" &&
        -x /usr/bin/steamos-readonly ]]; then
    PLATFORM="steamdeck"
    PLATFORM_NAME="Steam Deck / SteamOS"
  fi
}


preflight() {
  [[ "$(uname -s)" == "Linux" ]] || die "This mod supports Linux only."

  detect_platform

  if (( EUID == 0 )) && [[ "${DTAGNAN_ALLOW_ROOT:-0}" != "1" ]]; then
    die "Do not run this installer with sudo or as root. Run it as your normal Steam user."
  fi

  local command
  for command in realpath install cmp sed grep awk sha256sum file head cp mv rm mkdir chmod uname; do
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
  local -a stale_files=()

  for target in "$1" "$RUNTIME_DIR" "$CONFIG_DIR"; do
    [[ -d "$target" ]] || continue

    stale_files=()

    shopt -s nullglob
    stale_files+=(
      "$target"/*.dtagnan-tmp.*
      "$target"/install-state.tmp.*
    )
    shopt -u nullglob

    for stale in "${stale_files[@]}"; do
      [[ -f "$stale" || -L "$stale" ]] || continue
      rm -f -- "$stale"
    done
  done
}

steam_backend_for_game() {
  local game_dir="$1"
  local backend steam_root library_file path
  local -a entries=(
    "native|$HOME/.local/share/Steam"
    "native|$HOME/.local/share/steam"
    "native|$HOME/.steam/steam"
    "native|$HOME/.steam/root"
    "native|$HOME/.steam/debian-installation"
    "native|${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
    "native|${XDG_DATA_HOME:-$HOME/.local/share}/steam"

    "flatpak|$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    "flatpak|$HOME/.var/app/com.valvesoftware.Steam/.local/share/steam"
    "flatpak|$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    "flatpak|$HOME/.var/app/com.valvesoftware.Steam/data/steam"

    "snap|$HOME/snap/steam/common/.local/share/Steam"
  )

  [[ -n "$game_dir" ]] || {
    printf 'unknown\n'
    return
  }

  game_dir="$(realpath -m -- "$game_dir")"

  for entry in "${entries[@]}"; do
    backend="${entry%%|*}"
    steam_root="${entry#*|}"

    [[ -d "$steam_root/steamapps" ]] || continue

    steam_root="$(realpath -m -- "$steam_root")"

    # Game stored directly in this Steam installation.
    if [[ "$game_dir" == "$steam_root/steamapps/common/"* ]]; then
      printf '%s\n' "$backend"
      return
    fi

    # Game stored in an additional library registered by this Steam
    # installation, including external disks and Steam Deck microSD.
    library_file="$steam_root/steamapps/libraryfolders.vdf"
    [[ -f "$library_file" ]] || continue

    while IFS= read -r path; do
      path="${path//\\\\/\\}"
      [[ -n "$path" ]] || continue

      path="$(realpath -m -- "$path")"

      if [[ "$game_dir" == "$path/steamapps/common/"* ]]; then
        printf '%s\n' "$backend"
        return
      fi
    done < <(
      sed -n 's/^[[:space:]]*"path"[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$library_file"
    )
  done

  printf 'unknown\n'
}

find_game_dir() {
  local candidate manifest steamapps installdir steam_root library_file path
  local manual_steam_root=""
  local steam_found=0
  local canonical=""
  local seen=""
  local interactive="${DTAGNAN_GAME_DETECTION_INTERACTIVE:-1}"
  local -a steam_roots=()
  local -a steamapps_dirs=()

  if [[ -n "$EXPLICIT_GAME_DIR" ]]; then
    [[ -f "$EXPLICIT_GAME_DIR/nmh.exe" ]] || \
      die "nmh.exe was not found in: $EXPLICIT_GAME_DIR"
    realpath -e -- "$EXPLICIT_GAME_DIR"
    return
  fi

  steam_roots=(
    # Native Steam
    "$HOME/.local/share/Steam"
    "$HOME/.local/share/steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "$HOME/.steam/debian-installation"
    "${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
    "${XDG_DATA_HOME:-$HOME/.local/share}/steam"

    # Flatpak Steam
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/steam"

    # Snap Steam
    "$HOME/snap/steam/common/.local/share/Steam"
  )

  # Register a Steam library only once.
  add_steamapps_dir() {
    local dir="$1" normalized

    [[ -d "$dir" ]] || return 0

    normalized="$(realpath -m -- "$dir")"

    case $'\n'"$seen"$'\n' in
      *$'\n'"$normalized"$'\n'*)
        return 0
        ;;
    esac

    seen+="${seen:+$'\n'}$normalized"
    steamapps_dirs+=("$normalized")
  }

  # Read one Steam installation and all libraries registered in its
  # libraryfolders.vdf. No filesystem scanning is performed.
  read_steam_root() {
    local root="$1" root_real library path

    [[ -d "$root/steamapps" ]] || return 1

    root_real="$(realpath -m -- "$root")"
    steam_found=1

    add_steamapps_dir "$root_real/steamapps"

    library="$root_real/steamapps/libraryfolders.vdf"
    [[ -f "$library" ]] || return 0

    while IFS= read -r path; do
      path="${path//\\\\/\\}"
      [[ -n "$path" ]] || continue
      add_steamapps_dir "$path/steamapps"
    done < <(
      sed -n 's/^[[:space:]]*"path"[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$library"
    )
  }

  # Check the standard Steam locations first. realpath normalization
  # prevents aliases such as ~/.steam/root and ~/.steam/steam from
  # causing the same installation to be processed repeatedly.
  seen=""

  for steam_root in "${steam_roots[@]}"; do
    [[ -d "$steam_root/steamapps" ]] || continue

    canonical="$(realpath -m -- "$steam_root")"

    case $'\n'"$seen"$'\n' in
      *$'\n'"ROOT:$canonical"$'\n'*)
        continue
        ;;
    esac

    seen+="${seen:+$'\n'}ROOT:$canonical"
    read_steam_root "$canonical" || true
  done

  # If Steam itself was not found, ask for its installation directory
  # before asking for the game directory.
  if (( ! steam_found )) && [[ "$interactive" == "1" ]] && [[ -t 0 ]]; then
    printf '\n  %sSteam could not be found in its usual locations.%s\n' \
      "$YELLOW" "$RESET" >/dev/tty
    printf '  Have you moved your Steam installation?\n' >/dev/tty
    printf '  Please enter the path to your Steam folder (or leave blank to cancel): ' \
      >/dev/tty

    IFS= read -r manual_steam_root </dev/tty

    [[ -n "$manual_steam_root" ]] || die "Installation cancelled."

    manual_steam_root="${manual_steam_root%/}"

    [[ -d "$manual_steam_root/steamapps" ]] || \
      die "This does not appear to be a Steam folder: $manual_steam_root"

    read_steam_root "$manual_steam_root" || \
      die "Unable to read the Steam installation: $manual_steam_root"
  fi

  # Locate NMH by AppID instead of relying on a fixed directory name.
  for steamapps in "${steamapps_dirs[@]}"; do
    manifest="$steamapps/appmanifest_${APP_ID}.acf"
    [[ -f "$manifest" ]] || continue

    installdir="$(
      sed -n 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$manifest" |
        head -n 1
    )"

    [[ -n "$installdir" ]] || continue

    candidate="$steamapps/common/$installdir"

    if [[ -f "$candidate/nmh.exe" ]]; then
      realpath -e -- "$candidate"
      return
    fi
  done

  # Steam exists, but NMH was not found in any registered library.
  if [[ "$interactive" == "1" ]] && [[ -t 0 ]]; then
    printf '\n  %sSteam was detected, but No More Heroes could not be found in any configured Steam library.%s\n' \
      "$YELLOW" "$RESET" >/dev/tty
    printf '  Have you moved the game or its Steam library?\n' >/dev/tty
    printf '  Please enter the path to your No More Heroes installation (or leave blank to cancel): ' \
      >/dev/tty

    IFS= read -r candidate </dev/tty

    [[ -n "$candidate" ]] || die "Installation cancelled."

    candidate="${candidate%/}"

    [[ -f "$candidate/nmh.exe" ]] || \
      die "nmh.exe was not found in: $candidate"

    realpath -e -- "$candidate"
    return
  fi

  if (( steam_found )); then
    die "No More Heroes was not found in the configured Steam libraries."
  fi

  die "Steam was not found in its usual locations."
}

configure_install_scope() {
  local game_dir="$1"
  local steam_backend

  steam_backend="$(steam_backend_for_game "$game_dir")"

  DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  RUNTIME_DIR="$DATA_HOME/Dtagnan-Mods/No-More-Heroes"
  CONFIG_DIR="$CONFIG_HOME/vkBasalt"
  CONFIG_FILE="$CONFIG_DIR/nmh.conf"
  CONFIG_BACKUP="$CONFIG_DIR/nmh.conf.pre-dtagnan-mods"

  if [[ "$steam_backend" == "flatpak" ]]; then
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


detect_package_manager() {
  # Development/testing override. Never used unless explicitly requested.
  if [[ -n "${DTAGNAN_TEST_PM:-}" ]]; then
    case "$DTAGNAN_TEST_PM" in
      steamos|dnf|apt|pacman|zypper|unknown)
        printf '%s\n' "$DTAGNAN_TEST_PM"
        return 0
        ;;
      *)
        printf 'unknown\n'
        return 0
        ;;
    esac
  fi

  # SteamOS is intentionally handled before pacman. SteamOS uses an
  # Arch-based system, but it must not inherit the generic Arch package
  # installation path.
  if [[ "${PLATFORM:-}" == "steamdeck" ]]; then
    printf 'steamos\n'
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    printf 'dnf\n'
  elif command -v apt-get >/dev/null 2>&1; then
    printf 'apt\n'
  elif command -v pacman >/dev/null 2>&1; then
    printf 'pacman\n'
  elif command -v zypper >/dev/null 2>&1; then
    printf 'zypper\n'
  else
    printf 'unknown\n'
  fi
}

confirm_dependency_install() {
  local description="$1"
  local answer=""

  # Non-interactive runs must never modify the system automatically.
  [[ -t 0 ]] || return 1

  printf '\n  %s%s[DEPENDENCY]%s %s is missing.%s\n' \
    "$BOLD" "$YELLOW" "$RESET" "$description" "$RESET" >/dev/tty

  printf '  Install it automatically now? [Y/n]: ' >/dev/tty
  IFS= read -r answer </dev/tty

  case "${answer,,}" in
    ""|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

run_privileged() {
  if [[ "${DTAGNAN_DEPENDENCY_DRY_RUN:-0}" == "1" ]]; then
    printf '  DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  # Already root: mainly useful for containers/testing.
  if (( EUID == 0 )); then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi

  if command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
    return
  fi

  die "Administrator privileges are required to install this dependency. Install it manually, then run Dtagnan Mods again."
}

install_native_dependency() {
  local dependency="$1"
  local pm

  pm="$(detect_package_manager)"

  case "$dependency:$pm" in
    vulkan32:steamos)
      warning "The SteamOS 32-bit Vulkan loader is missing."
      warning "Dtagnan Mods will not modify the SteamOS system image automatically."
      return 1
      ;;

    vkbasalt32:steamos)
      warning "The SteamOS 32-bit vkBasalt layer is missing."
      warning "Dtagnan Mods will not modify the SteamOS system image automatically."
      return 1
      ;;

    vulkan32:dnf)
      note "Installing the Fedora 32-bit Vulkan loader..."
      run_privileged dnf install -y vulkan-loader.i686
      ;;

    vulkan32:apt)
      note "Installing the Debian/Ubuntu 32-bit Vulkan loader..."
      run_privileged dpkg --add-architecture i386
      run_privileged apt-get update
      run_privileged apt-get install -y libvulkan1:i386
      ;;

    vulkan32:pacman)
      note "Installing the Arch Linux 32-bit Vulkan loader..."
      run_privileged pacman -S --needed lib32-vulkan-icd-loader
      ;;

    vulkan32:zypper)
      note "Installing the openSUSE 32-bit Vulkan loader..."
      run_privileged zypper --non-interactive install libvulkan1-32bit
      ;;

    vkbasalt32:dnf)
      note "Installing Fedora 32-bit vkBasalt..."
      run_privileged dnf install -y vkBasalt.i686
      ;;

    vkbasalt32:apt)
      warning "Automatic 32-bit vkBasalt installation is not configured for this Debian/Ubuntu system."
      return 1
      ;;

    vkbasalt32:pacman)
      warning "Automatic 32-bit vkBasalt installation is not configured for this Arch system."
      return 1
      ;;

    vkbasalt32:zypper)
      warning "Automatic 32-bit vkBasalt installation is not configured for this openSUSE system."
      return 1
      ;;

    *)
      warning "No automatic installation method is available for '$dependency' on this system."
      return 1
      ;;
  esac

  if [[ "${DTAGNAN_DEPENDENCY_DRY_RUN:-0}" == "1" ]]; then
    return 2
  fi
}

offer_dependency_install() {
  local dependency="$1"
  local description="$2"

  if ! confirm_dependency_install "$description"; then
    return 1
  fi

  install_native_dependency "$dependency"
  local rc=$?

  if (( rc == 2 )); then
    success "Dependency installation path tested successfully (dry run)."
    return 2
  fi

  return "$rc"
}

install_flatpak_vkbasalt_dependency() {
  local runtime=""

  command -v flatpak >/dev/null 2>&1 || return 1

  # Discover an available vkBasalt extension instead of hard-coding
  # a Steam runtime version.
  runtime="$(
    flatpak remote-ls --runtime --columns=ref 2>/dev/null |
      grep -Ei 'vkBasalt' |
      grep -Ei 'i386|x86_64' |
      head -n 1 || true
  )"

  [[ -n "$runtime" ]] || return 1

  if ! confirm_dependency_install "the Flatpak vkBasalt Vulkan layer"; then
    return 1
  fi

  note "Installing Flatpak vkBasalt runtime extension..."
  flatpak install -y flathub "$runtime"
}

find_vkbasalt32() {
  local c
  local -a candidates=()

  # Developer/testing override.
  [[ "${DTAGNAN_TEST_MISSING:-}" == "vkbasalt32" ]] && return 1

  candidates=(
    "${VKBASALT_LIBRARY:-}"
    /usr/lib/vkbasalt/libvkbasalt.so
    /usr/lib32/libvkbasalt.so
    /usr/lib32/vkbasalt/libvkbasalt.so
    /usr/lib/i386-linux-gnu/libvkbasalt.so
    /usr/lib/i386-linux-gnu/vkbasalt/libvkbasalt.so
    /lib/libvkbasalt.so
    /lib32/libvkbasalt.so
  )

  # Some distributions register vkBasalt with the dynamic linker.
  if command -v ldconfig >/dev/null 2>&1; then
    while IFS= read -r c; do
      candidates+=("$c")
    done < <(
      ldconfig -p 2>/dev/null |
        awk '/libvkbasalt\.so/ { print $NF }'
    )
  fi

  for c in "${candidates[@]}"; do
    [[ -n "$c" && -f "$c" ]] || continue

    if file -L "$c" | grep -qiE '32-bit|Intel 80386'; then
      printf '%s\n' "$c"
      return 0
    fi
  done

  return 1
}

find_vulkan32() {
  local c
  local -a candidates=()

  # Developer/testing override.
  [[ "${DTAGNAN_TEST_MISSING:-}" == "vulkan32" ]] && return 1

  candidates=(
    "${VULKAN_LIBRARY:-}"
    /lib/libvulkan.so.1
    /lib32/libvulkan.so.1
    /usr/lib/libvulkan.so.1
    /usr/lib32/libvulkan.so.1
    /usr/lib/i386-linux-gnu/libvulkan.so.1
  )

  if command -v ldconfig >/dev/null 2>&1; then
    while IFS= read -r c; do
      candidates+=("$c")
    done < <(
      ldconfig -p 2>/dev/null |
        awk '/libvulkan\.so\.1/ { print $NF }'
    )
  fi

  for c in "${candidates[@]}"; do
    [[ -n "$c" && -f "$c" ]] || continue

    if file -L "$c" | grep -qiE '32-bit|Intel 80386'; then
      printf '%s\n' "$c"
      return 0
    fi
  done

  return 1
}

check_vkbasalt() {
  local game_dir="${1:-}" lib="" candidate
  local -a candidates=()

  # Flatpak Steam has its own runtime and therefore needs a Flatpak
  # vkBasalt extension rather than a host-system 32-bit library.
  if [[ -n "$game_dir" ]] && [[ "$(steam_backend_for_game "$game_dir")" == "flatpak" ]]; then
    command -v flatpak >/dev/null 2>&1 || \
      die "Flatpak Steam was detected, but the flatpak command is unavailable."

    if flatpak list --runtime --columns=application,arch 2>/dev/null | \
         grep -i 'vkBasalt' | grep -qi 'i386'; then
      success "Flatpak 32-bit vkBasalt runtime detected."
      return
    fi

    warning "Flatpak Steam is missing its 32-bit vkBasalt runtime."

    if install_flatpak_vkbasalt_dependency; then
      if flatpak list --runtime --columns=application,arch 2>/dev/null | \
           grep -i 'vkBasalt' | grep -qi 'i386'; then
        success "Flatpak 32-bit vkBasalt runtime installed."
        return
      fi
    fi

    die "Flatpak Steam still does not have a usable 32-bit vkBasalt runtime."
  fi


  if [[ "${DTAGNAN_TEST_MISSING:-}" == "vkbasalt32" ]]; then
    lib=""
  else
    lib="$(find_vkbasalt32 || true)"
  fi

  if [[ -n "$lib" ]]; then
    success "32-bit vkBasalt detected: $lib"
    return
  fi

  warning "32-bit vkBasalt was not found."

  set +e
  offer_dependency_install \
    vkbasalt32 \
    "the 32-bit vkBasalt Vulkan layer"
  dep_rc=$?
  set -e

  if (( dep_rc == 2 )); then
    success "vkBasalt dependency test completed. No system changes were made."
    return 0
  elif (( dep_rc == 0 )); then

    lib="$(find_vkbasalt32 || true)"

    if [[ -n "$lib" ]]; then
      success "32-bit vkBasalt installed: $lib"
      return
    fi

    warning "Package installation completed, but no usable 32-bit vkBasalt library was detected."
  fi

  die "32-bit vkBasalt is required. Install the appropriate 32-bit vkBasalt package for your distribution, then run the installer again."
}

check_vulkan_loader() {
  local game_dir="${1:-}" loader="" candidate

  # Flatpak Steam supplies its own Vulkan loader.
  if [[ -n "$game_dir" ]] && [[ "$(steam_backend_for_game "$game_dir")" == "flatpak" ]]; then
    success "Flatpak Steam supplies the Vulkan loader."
    return
  fi


  if [[ "${DTAGNAN_TEST_MISSING:-}" == "vulkan32" ]]; then
    loader=""
  else
    loader="$(find_vulkan32 || true)"
  fi

  if [[ -n "$loader" ]]; then
    success "32-bit Vulkan loader detected: $loader"
    return
  fi

  warning "32-bit Vulkan loader was not found."

  set +e
  offer_dependency_install \
    vulkan32 \
    "the 32-bit Vulkan loader"
  dep_rc=$?
  set -e

  if (( dep_rc == 2 )); then
    success "Vulkan dependency test completed. No system changes were made."
    return 0
  elif (( dep_rc == 0 )); then

    loader="$(find_vulkan32 || true)"

    if [[ -n "$loader" ]]; then
      success "32-bit Vulkan loader installed: $loader"
      return
    fi

    warning "Package installation completed, but no usable 32-bit Vulkan loader was detected."
  fi

  die "A 32-bit Vulkan loader is required. Install your distribution's 32-bit Vulkan loader and GPU driver, then run the installer again."
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





test_dependencies() {
  local dependency="${DTAGNAN_TEST_MISSING:-}"

  print_rule
  printf '  %sDTAGNAN MODS — DEPENDENCY TEST%s\n\n' "$BOLD" "$RESET"

  case "$dependency" in
    vkbasalt32)
      note "Simulating missing 32-bit vkBasalt."
      ;;
    vulkan32)
      note "Simulating missing 32-bit Vulkan loader."
      ;;
    "")
      die "Choose a dependency with DTAGNAN_TEST_MISSING=vkbasalt32 or vulkan32."
      ;;
    *)
      die "Unknown dependency simulation: $dependency"
      ;;
  esac

  export DTAGNAN_DEPENDENCY_DRY_RUN=1

  printf '  Package manager: %s\n\n' "$(detect_package_manager)"

  case "$dependency" in
    vkbasalt32)
      if confirm_dependency_install "the 32-bit vkBasalt Vulkan layer"; then
        local rc=0

        set +e
        install_native_dependency vkbasalt32
        rc=$?
        set -e

        if (( rc == 2 )); then
          success "vkBasalt automatic-install path works. No system changes were made."
          return 0
        fi

        if (( rc == 1 )) && [[ "$(detect_package_manager)" == "steamos" ]]; then
          success "SteamOS safety guard works. No system changes were made."
          return 0
        fi

        die "Unexpected result from vkBasalt dependency test."
      else
        warning "Dependency installation declined. No changes were made."
      fi
      ;;

    vulkan32)
      if confirm_dependency_install "the 32-bit Vulkan loader"; then
        local rc=0

        set +e
        install_native_dependency vulkan32
        rc=$?
        set -e

        if (( rc == 2 )); then
          success "Vulkan automatic-install path works. No system changes were made."
          return 0
        fi

        if (( rc == 1 )) && [[ "$(detect_package_manager)" == "steamos" ]]; then
          success "SteamOS safety guard works. No system changes were made."
          return 0
        fi

        die "Unexpected result from Vulkan dependency test."
      else
        warning "Dependency installation declined. No changes were made."
      fi
      ;;
  esac
}

doctor() {
  local game_dir=""
  local pm gpu steam_type platform_name
  local vulkan32="" vkbasalt32=""
  local payload_status="OK"
  local game_status="NOT FOUND"
  local writable_status="N/A"
  local vulkan_status="MISSING"
  local vkbasalt_status="MISSING"
  local overall_ready=1

  print_rule
  printf '  %sDTAGNAN MODS — SYSTEM DOCTOR%s\n\n' "$BOLD" "$RESET"

  detect_platform
  platform_name="${PLATFORM_NAME:-Linux}"
  pm="$(detect_package_manager)"
  gpu="$(detect_gpu_vendor)"

  # Locate the game without terminating the doctor if it is absent.
  game_dir="$(find_game_dir 2>/dev/null || true)"

  if [[ -n "$game_dir" && -f "$game_dir/nmh.exe" ]]; then
    game_status="FOUND"
    if [[ -w "$game_dir" ]]; then
      writable_status="OK"
    else
      writable_status="NO"
      overall_ready=0
    fi

    case "$(steam_backend_for_game "$game_dir")" in
      flatpak)
        steam_type="Flatpak"

        # Flatpak supplies the Vulkan loader.
        vulkan_status="OK (Flatpak runtime)"

        if command -v flatpak >/dev/null 2>&1 &&
           flatpak list --runtime --columns=application,arch 2>/dev/null |
             grep -i 'vkBasalt' |
             grep -qi 'i386'; then
          vkbasalt_status="OK"
        else
          vkbasalt_status="MISSING"
          overall_ready=0
        fi
        ;;

      native)
        steam_type="Native"

        vulkan32="$(find_vulkan32 || true)"
        vkbasalt32="$(find_vkbasalt32 || true)"

        if [[ -n "$vulkan32" ]]; then
          vulkan_status="OK"
        else
          overall_ready=0
        fi

        if [[ -n "$vkbasalt32" ]]; then
          vkbasalt_status="OK"
        else
          overall_ready=0
        fi
        ;;

      snap)
        steam_type="Snap"

        # Snap dependency handling is not finalized yet.
        # Diagnose the host without claiming Snap runtime support.
        vulkan32="$(find_vulkan32 || true)"
        vkbasalt32="$(find_vkbasalt32 || true)"

        [[ -n "$vulkan32" ]] && vulkan_status="OK"
        [[ -n "$vkbasalt32" ]] && vkbasalt_status="OK"

        overall_ready=0
        ;;

      *)
        steam_type="Unknown"

        vulkan32="$(find_vulkan32 || true)"
        vkbasalt32="$(find_vkbasalt32 || true)"

        [[ -n "$vulkan32" ]] && vulkan_status="OK"
        [[ -n "$vkbasalt32" ]] && vkbasalt_status="OK"

        overall_ready=0
        ;;
    esac
  else
    steam_type="Unknown"
    overall_ready=0

    # We can still diagnose host dependencies even without the game.
    vulkan32="$(find_vulkan32 || true)"
    vkbasalt32="$(find_vkbasalt32 || true)"

    [[ -n "$vulkan32" ]] && vulkan_status="OK"
    [[ -n "$vkbasalt32" ]] && vkbasalt_status="OK"
  fi

  # Validate packaged mod files without calling die().
  local required
  for required in \
    "$ROOT/DXVK/d3d11.dll" \
    "$ROOT/DXVK/dxgi.dll" \
    "$ROOT/vkBasalt/Shaders/ReShade.fxh" \
    "$ROOT/vkBasalt/Shaders/NMH_Bloom.fx" \
    "$ROOT/vkBasalt/Shaders/NMH_Vignette.fx" \
    "$ROOT/vkBasalt/Shaders/NMH_Dither.fx" \
    "$ROOT/vkBasalt/LUTs/nmh-color.cube"
  do
    if [[ ! -f "$required" ]]; then
      payload_status="INCOMPLETE"
      overall_ready=0
      break
    fi
  done

  printf '  %-18s %s\n' "Platform"        "$platform_name"
  printf '  %-18s %s\n' "Package manager" "$pm"
  printf '  %-18s %s\n' "Steam"           "$steam_type"
  printf '  %-18s %s\n' "Game"            "$game_status"
  printf '  %-18s %s\n' "AppID"           "$APP_ID"
  printf '  %-18s %s\n' "GPU"             "$gpu"
  printf '  %-18s %s\n' "Vulkan 32-bit"   "$vulkan_status"
  printf '  %-18s %s\n' "vkBasalt 32-bit" "$vkbasalt_status"
  printf '  %-18s %s\n' "Game writable"   "$writable_status"
  printf '  %-18s %s\n' "Payload"         "$payload_status"

  if [[ -n "$game_dir" ]]; then
    printf '\n  %-18s %s\n' "Game directory" "$game_dir"
  fi

  [[ -n "$vulkan32" ]] &&
    printf '  %-18s %s\n' "Vulkan library" "$vulkan32"

  [[ -n "$vkbasalt32" ]] &&
    printf '  %-18s %s\n' "vkBasalt library" "$vkbasalt32"

  printf '\n'
  print_rule

  if (( overall_ready )); then
    success "System ready for Dtagnan Mods."
    return 0
  fi

  warning "System is not fully ready. See the missing requirements above."
  return 0
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

menu_system_check() {
  local game_dir="" steam_backend="unknown" gpu="unknown"
  local os_display="Linux"
  local steam_display="Not found"
  local game_display="Not found"
  local gpu_display="Unknown"
  local vulkan_display="Missing"
  local vkbasalt_display="Missing"
  local os_mark="✅" steam_mark="❌" game_mark="❌"
  local gpu_mark="⚠️" vulkan_mark="❌" vkbasalt_mark="❌"

  if [[ -r /etc/os-release ]]; then
    os_display="$(
      . /etc/os-release
      printf '%s %s' "${NAME:-Linux}" "${VERSION_ID:-}"
    )"
  fi

  game_dir="$(
    DTAGNAN_GAME_DETECTION_INTERACTIVE=0 find_game_dir 2>/dev/null || true
  )"

  if [[ -n "$game_dir" && -f "$game_dir/nmh.exe" ]]; then
    game_display="No More Heroes"
    game_mark="✅"
    steam_backend="$(steam_backend_for_game "$game_dir" 2>/dev/null || true)"
  fi

  case "$steam_backend" in
    native)
      steam_display="Native"
      steam_mark="✅"
      ;;
    flatpak)
      steam_display="Flatpak"
      steam_mark="✅"
      ;;
    snap)
      steam_display="Snap"
      steam_mark="✅"
      ;;
    *)
      if command -v steam >/dev/null 2>&1; then
        steam_display="Installed"
        steam_mark="✅"
      elif command -v flatpak >/dev/null 2>&1 &&
           flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
        steam_display="Flatpak"
        steam_mark="✅"
      fi
      ;;
  esac

  gpu="$(detect_gpu_vendor 2>/dev/null || true)"
  case "${gpu,,}" in
    *nvidia*)
      gpu_display="NVIDIA"
      gpu_mark="✅"
      ;;
    *amd*|*radeon*)
      gpu_display="AMD"
      gpu_mark="✅"
      ;;
    *intel*)
      gpu_display="Intel"
      gpu_mark="✅"
      ;;
  esac

  if find_vulkan32 >/dev/null 2>&1; then
    vulkan_display="Ready"
    vulkan_mark="✅"
  fi

  if find_vkbasalt32 >/dev/null 2>&1; then
    vkbasalt_display="Ready"
    vkbasalt_mark="✅"
  fi

  printf '     🐧 OS\033[42G[ %-15s %s ]\n' "$os_display" "$os_mark"
  printf '     ♨  Steam\033[42G[ %-15s %s ]\n' "$steam_display" "$steam_mark"
  printf '     👾 Game\033[42G[ %-15s %s ]\n' "$game_display" "$game_mark"
  printf '     🖥  GPU\033[42G[ %-15s %s ]\n' "$gpu_display" "$gpu_mark"
  printf '     📦 Vulkan 32-bit\033[42G[ %-15s %s ]\n' "$vulkan_display" "$vulkan_mark"
  printf '     📦 vkBasalt 32-bit\033[42G[ %-15s %s ]\n' "$vkbasalt_display" "$vkbasalt_mark"

  if [[ "$steam_mark$game_mark$gpu_mark$vulkan_mark$vkbasalt_mark" == \
        "✅✅✅✅✅" ]]; then
    printf '\n'
    printf '     🎯 Ready to be installed!\n'
  else
    printf '     ⚠ Some requirements are missing.\n'
    printf '     🔧 Run the system doctor for details.\n'
  fi
}

main_menu() {
  local choice

  while true; do
    clear 2>/dev/null || true

    printf '\n'
    printf '╭──────────────────────────────────────────────────────────╮\n'
    printf '│                                                          │\n'
    printf '│                 ✦  DTAGNAN MODS  ✦                       │\n'
    printf '│                   No More Heroes                         │\n'
    printf '│                                                          │\n'
    printf '│     Created by Suda51 at Grasshopper Manufacture 🇯🇵      │\n'
    printf '│                                                          │\n'
    printf '│              Linux Installation Wizard                   │\n'
    printf '│                Made with ❤ for you.                      │\n'
    printf '│                                                          │\n'
    printf '╰──────────────────────────────────────────────────────────╯\n'
    printf '\n'

    printf '  ❤ Checking your system...\n'
    printf '\n'

    menu_system_check
    printf '  ──────────────────────────────────────────────────────────\n'
    printf '\n'

    printf '  ✨ Dtagnan Mods — No More Heroes\n'
    printf '\n'
    printf '       %s[1]%s ❤ Install / Update\n' "$CYAN" "$RESET"
    printf '       %s[2]%s ✓ Verify installation\n' "$CYAN" "$RESET"
    printf '       %s[3]%s 🎮 Show Steam launch options\n' "$CYAN" "$RESET"
    printf '       %s[4]%s 🗑️ Uninstall the mod\n' "$CYAN" "$RESET"
    printf '       %s[5]%s ✦ About this mod\n' "$CYAN" "$RESET"
    printf '       %s[6]%s 🚪 Exit\n' "$CYAN" "$RESET"
    printf '\n'
    printf '  %sChoose an option%s %s[1-6]%s: ' \
      "$BOLD" "$RESET" "$DIM" "$RESET"

    read -r choice

    case "$choice" in
      1) install_mod; pause_menu ;;
      2) verify_mod; pause_menu ;;
      3) show_launch_options; pause_menu ;;
      4) confirm_restore; pause_menu ;;
      5) show_about; pause_menu ;;
      6)
        printf '\n  ❤ %sSee you next time.%s\n' "$GREEN" "$RESET"
        return
        ;;
      *)
        warning "Invalid option. Choose a number from 1 to 6."
        sleep 1
        ;;
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
  ./install.sh doctor                      Run a read-only system diagnostic
  ./install.sh test-deps                   Test dependency installation safely
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
  doctor)  doctor ;;
  test-deps) test_dependencies ;;
  -h|--help|help) usage ;;
  *) usage; die "Unknown action: $ACTION" ;;
esac
