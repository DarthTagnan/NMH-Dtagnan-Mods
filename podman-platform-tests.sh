#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
RESULTS="$ROOT/test-results/podman-$(date +%Y%m%d-%H%M%S)"
FULL_PACKAGES=0

usage() {
  cat <<'EOF'
Usage:
  ./podman-platform-tests.sh
  ./podman-platform-tests.sh --full-packages

Default mode runs the complete installer/crash matrix in disposable Fedora,
Ubuntu, Arch Linux and openSUSE containers.

--full-packages also performs real 32-bit Vulkan package installations inside
the disposable containers. It never installs packages on the host.
EOF
}

case "${1:-}" in
  "") ;;
  --full-packages) FULL_PACKAGES=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

command -v podman >/dev/null 2>&1 || {
  printf 'ERROR: Podman is not installed. On Fedora: sudo dnf install -y podman\n' >&2
  exit 1
}

[[ -f "$ROOT/install.sh" ]] || {
  printf 'ERROR: install.sh must be beside this script.\n' >&2
  exit 1
}
[[ -f "$ROOT/audit_crash_test.sh" ]] || {
  printf 'ERROR: audit_crash_test.sh must be beside this script.\n' >&2
  exit 1
}

# Prevent a new test suite from producing hundreds of misleading failures
# against an older installer copied into the repository.
if ! grep -q 'rollback_failed_install() {' "$ROOT/install.sh" ||
   ! grep -q 'For No More Heroes' "$ROOT/install.sh" ||
   ! grep -q '\\033\[39G\[ %-15\.15s %s \]' "$ROOT/install.sh"; then
  cat >&2 <<'EOF'
ERROR: install.sh is older than this test suite.
Replace install.sh, audit_crash_test.sh and podman-platform-tests.sh together,
then run the Podman test again.
EOF
  exit 1
fi

mkdir -p "$RESULTS"

declare -a NAMES=(fedora ubuntu arch opensuse)
declare -A IMAGES=(
  [fedora]="docker.io/library/fedora:latest"
  [ubuntu]="docker.io/library/ubuntu:24.04"
  [arch]="docker.io/library/archlinux:latest"
  [opensuse]="registry.opensuse.org/opensuse/tumbleweed:latest"
)

bootstrap_for() {
  case "$1" in
    fedora)
      cat <<'EOF'
dnf install -y bash coreutils diffutils file findutils gawk grep sed util-linux util-linux-script
EOF
      ;;
    ubuntu)
      cat <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y bash coreutils diffutils file findutils gawk grep sed util-linux
EOF
      ;;
    arch)
      cat <<'EOF'
pacman -Syu --noconfirm bash coreutils diffutils file findutils gawk grep sed util-linux
EOF
      ;;
    opensuse)
      cat <<'EOF'
zypper --non-interactive refresh
zypper --non-interactive install bash coreutils diffutils file findutils gawk grep sed util-linux
EOF
      ;;
  esac
}

package_test_for() {
  case "$1" in
    fedora)
      cat <<'EOF'
dnf install -y vulkan-loader.i686
if dnf install -y vkBasalt.i686; then
  echo 'REAL PACKAGE: vkBasalt.i686 available'
else
  echo 'EXPECTED LIMIT: vkBasalt.i686 unavailable in enabled repositories'
fi
EOF
      ;;
    ubuntu)
      cat <<'EOF'
dpkg --add-architecture i386
apt-get update
apt-get install -y libvulkan1:i386
if apt-get install -y vkbasalt:i386; then
  echo 'REAL PACKAGE: vkbasalt:i386 available'
else
  echo 'EXPECTED LIMIT: vkbasalt:i386 unavailable in enabled repositories'
fi
EOF
      ;;
    arch)
      cat <<'EOF'
sed -i '/^#\[multilib\]/{s/^#//;n;s/^#Include/Include/;}' /etc/pacman.conf
pacman -Syu --noconfirm
pacman -S --needed --noconfirm lib32-vulkan-icd-loader
if pacman -S --needed --noconfirm lib32-vkbasalt; then
  echo 'REAL PACKAGE: lib32-vkbasalt available'
else
  echo 'EXPECTED LIMIT: lib32-vkbasalt unavailable in enabled repositories'
fi
EOF
      ;;
    opensuse)
      cat <<'EOF'
zypper --non-interactive install libvulkan1-32bit
if zypper --non-interactive install vkBasalt-32bit; then
  echo 'REAL PACKAGE: vkBasalt-32bit available'
else
  echo 'EXPECTED LIMIT: vkBasalt-32bit unavailable in enabled repositories'
fi
EOF
      ;;
  esac
}

run_one() {
  local name="$1" image="${IMAGES[$1]}" log="$RESULTS/$1.log"
  local bootstrap package_test command
  bootstrap="$(bootstrap_for "$name")"
  package_test=""
  if (( FULL_PACKAGES )); then
    package_test="$(package_test_for "$name")"
  fi

  command="$bootstrap
$package_test
export INSTALLER=/src/install.sh
bash -n /src/install.sh
bash /src/audit_crash_test.sh"

  printf '\n===== %s — %s =====\n' "$name" "$image" | tee "$log"
  if podman run --rm \
      --security-opt label=disable \
      --volume "$ROOT:/src:ro" \
      "$image" bash -lc "$command" 2>&1 | tee -a "$log"; then
    printf 'RESULT: %s PASS\n' "$name" | tee -a "$log"
    return 0
  fi

  printf 'RESULT: %s FAIL\n' "$name" | tee -a "$log"
  return 1
}

failures=0
for name in "${NAMES[@]}"; do
  if ! run_one "$name"; then
    failures=$((failures + 1))
  fi
done

printf '\nReports: %s\n' "$RESULTS"
if (( failures )); then
  printf 'FINAL RESULT: %d platform(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'FINAL RESULT: all four platform containers passed.\n'
