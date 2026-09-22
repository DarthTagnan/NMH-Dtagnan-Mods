#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALLER="${INSTALLER:-$SCRIPT_DIR/install.sh}"
PASS=0
FAIL=0

pass() { printf 'PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

make_fixture() {
  FIXTURE="$(mktemp -d)"
  cp "$INSTALLER" "$FIXTURE/install.sh"
  chmod +x "$FIXTURE/install.sh"
  mkdir -p "$FIXTURE/DXVK" "$FIXTURE/vkBasalt/Shaders" \
    "$FIXTURE/vkBasalt/LUTs" "$FIXTURE/home" "$FIXTURE/fakebin"
  printf d3d11 >"$FIXTURE/DXVK/d3d11.dll"
  printf dxgi >"$FIXTURE/DXVK/dxgi.dll"
  local shader
  for shader in ReShade.fxh NMH_Bloom.fx NMH_Vignette.fx NMH_Dither.fx; do
    printf '%s' "$shader" >"$FIXTURE/vkBasalt/Shaders/$shader"
  done
  printf lut >"$FIXTURE/vkBasalt/LUTs/nmh-color.cube"
  printf elf >"$FIXTURE/lib32.so"
  cat >"$FIXTURE/fakebin/file" <<'EOF'
#!/bin/sh
printf '%s: ELF 32-bit LSB shared object, Intel 80386\n' "${2:-$1}"
EOF
  chmod +x "$FIXTURE/fakebin/file"
}

run_env() {
  env HOME="$FIXTURE/home" PATH="$FIXTURE/fakebin:/usr/bin:/bin" \
    DTAGNAN_ALLOW_ROOT=1 DTAGNAN_SKIP_PAYLOAD_HASH_CHECK=1 \
    VULKAN_LIBRARY="$FIXTURE/lib32.so" VKBASALT_LIBRARY="$FIXTURE/lib32.so" \
    "$@"
}

expect_ok() {
  local name="$1"; shift
  if "$@" >"$FIXTURE/test.log" 2>&1; then pass "$name"; else fail "$name"; cat "$FIXTURE/test.log"; fi
}

expect_fail() {
  local name="$1"; shift
  if "$@" >"$FIXTURE/test.log" 2>&1; then fail "$name"; else pass "$name"; fi
}

bash -n "$INSTALLER" && pass "bash syntax" || fail "bash syntax"
[[ "$(grep -c '\\033\[39G\[ %-15\.15s %s \]' "$INSTALLER")" == 6 ]] \
  && pass "menu status columns stay inside width" || fail "menu status columns stay inside width"
[[ "$(grep -c "printf '     %s\[[1-6]\]" "$INSTALLER")" == 6 ]] \
  && pass "menu numbers align with diagnostic icons" || fail "menu numbers align with diagnostic icons"

# First launch without Steam or the game must show the menu rather than exit.
make_fixture
if printf '6\n' | env HOME="$FIXTURE/home" PATH="$FIXTURE/fakebin:/usr/bin:/bin" \
  TERM=dumb DTAGNAN_ALLOW_ROOT=1 DTAGNAN_GAME_DETECTION_INTERACTIVE=0 \
  "$FIXTURE/install.sh" >"$FIXTURE/test.log" 2>&1; then
  pass "first launch without game"
else
  fail "first launch without game"; cat "$FIXTURE/test.log"
fi
grep -q 'Some requirements are missing' "$FIXTURE/test.log" \
  && pass "missing-game menu diagnostic" || fail "missing-game menu diagnostic"

# SteamOS first launch without Steam/game must also remain usable.
make_fixture
if printf '6\n' | env HOME="$FIXTURE/home" PATH="$FIXTURE/fakebin:/usr/bin:/bin" \
  TERM=dumb DTAGNAN_ALLOW_ROOT=1 DTAGNAN_TEST_PLATFORM=steamdeck \
  DTAGNAN_GAME_DETECTION_INTERACTIVE=0 "$FIXTURE/install.sh" \
  >"$FIXTURE/test.log" 2>&1; then
  pass "SteamOS first launch without game"
else
  fail "SteamOS first launch without game"; cat "$FIXTURE/test.log"
fi

# Dependency-routing matrix in a pseudo-terminal.
for pm in dnf apt pacman zypper steamos unknown; do
  for dep in vkbasalt32 vulkan32; do
    make_fixture
    if printf 'y\n' | script -qec \
      "env HOME='$FIXTURE/home' PATH='$FIXTURE/fakebin:/usr/bin:/bin' DTAGNAN_ALLOW_ROOT=1 DTAGNAN_TEST_PM='$pm' DTAGNAN_TEST_MISSING='$dep' '$FIXTURE/install.sh' test-deps" \
      /dev/null >"$FIXTURE/test.log" 2>&1; then
      pass "dependency $pm/$dep"
    else
      fail "dependency $pm/$dep"
    fi
  done
done

# Native install/verify/restore with no original DLLs.
make_fixture
mkdir -p "$FIXTURE/game with spaces"
printf exe >"$FIXTURE/game with spaces/nmh.exe"
expect_ok "native install" run_env "$FIXTURE/install.sh" install "$FIXTURE/game with spaces"
expect_ok "native verify" run_env "$FIXTURE/install.sh" verify "$FIXTURE/game with spaces"
expect_ok "native restore" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game with spaces"
[[ ! -e "$FIXTURE/game with spaces/d3d11.dll" && ! -e "$FIXTURE/game with spaces/dxgi.dll" ]] \
  && pass "restore removes originally absent DLLs" || fail "restore removes originally absent DLLs"
[[ ! -e "$FIXTURE/home/.local/share/Dtagnan-Mods/No-More-Heroes" ]] \
  && pass "uninstall removes owned mod assets" || fail "uninstall removes owned mod assets"

# Preserve and restore pre-existing DLLs byte-for-byte.
make_fixture
mkdir -p "$FIXTURE/game"
printf exe >"$FIXTURE/game/nmh.exe"
printf original-d3d11 >"$FIXTURE/game/d3d11.dll"
printf original-dxgi >"$FIXTURE/game/dxgi.dll"
expect_ok "backup existing DLLs" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
expect_ok "restore existing DLLs" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game"
[[ "$(<"$FIXTURE/game/d3d11.dll")" == original-d3d11 && \
   "$(<"$FIXTURE/game/dxgi.dll")" == original-dxgi ]] \
  && pass "original DLL contents preserved" || fail "original DLL contents preserved"

# Repeated install is idempotent and retains the original backup.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
printf vanilla-d3d11 >"$FIXTURE/game/d3d11.dll"
printf vanilla-dxgi >"$FIXTURE/game/dxgi.dll"
expect_ok "idempotent install first pass" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
expect_ok "idempotent install second pass" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
expect_ok "idempotent install restore" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game"
[[ "$(<"$FIXTURE/game/d3d11.dll")" == vanilla-d3d11 && \
   "$(<"$FIXTURE/game/dxgi.dll")" == vanilla-dxgi ]] \
  && pass "idempotent install backup preserved" || fail "idempotent install backup preserved"

# Unicode, apostrophes and spaces in the game path.
make_fixture
GAME="$FIXTURE/Carte SD de l'amié/No More Heroes"
mkdir -p "$GAME"; printf exe >"$GAME/nmh.exe"
expect_ok "unicode game path install" run_env "$FIXTURE/install.sh" install "$GAME"
expect_ok "unicode game path verify" run_env "$FIXTURE/install.sh" verify "$GAME"
expect_ok "unicode game path restore" run_env "$FIXTURE/install.sh" restore "$GAME"

# A Steam repair/update between installs must refresh the vanilla backup.
make_fixture
mkdir -p "$FIXTURE/game"
printf exe >"$FIXTURE/game/nmh.exe"
printf original-v1-d3d11 >"$FIXTURE/game/d3d11.dll"
printf original-v1-dxgi >"$FIXTURE/game/dxgi.dll"
expect_ok "first install before game update" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
printf original-v2-d3d11 >"$FIXTURE/game/d3d11.dll"
printf original-v2-dxgi >"$FIXTURE/game/dxgi.dll"
expect_ok "reinstall after game update" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
expect_ok "restore after game update" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game"
[[ "$(<"$FIXTURE/game/d3d11.dll")" == original-v2-d3d11 && \
   "$(<"$FIXTURE/game/dxgi.dll")" == original-v2-dxgi ]] \
  && pass "latest game DLLs preserved" || fail "latest game DLLs preserved"

# Native Steam discovery by AppID manifest.
make_fixture
STEAM="$FIXTURE/home/.local/share/Steam"
mkdir -p "$STEAM/steamapps/common/No More Heroes"
printf exe >"$STEAM/steamapps/common/No More Heroes/nmh.exe"
printf '"AppState"\n{\n "appid" "1420290"\n "installdir" "No More Heroes"\n}\n' \
  >"$STEAM/steamapps/appmanifest_1420290.acf"
expect_ok "native Steam discovery" run_env "$FIXTURE/install.sh" doctor
grep -q 'Steam[[:space:]]*Native' "$FIXTURE/test.log" \
  && pass "native backend classification" || fail "native backend classification"

# Additional Steam library discovery, including spaces in its path.
make_fixture
STEAM="$FIXTURE/home/.local/share/Steam"
LIB="$FIXTURE/External Library"
mkdir -p "$STEAM/steamapps" "$LIB/steamapps/common/No More Heroes"
printf exe >"$LIB/steamapps/common/No More Heroes/nmh.exe"
printf '"libraryfolders"\n{\n "0"\n {\n  "path" "%s"\n }\n}\n' "$LIB" >"$STEAM/steamapps/libraryfolders.vdf"
printf '"AppState"\n{\n "appid" "1420290"\n "installdir" "No More Heroes"\n}\n' \
  >"$LIB/steamapps/appmanifest_1420290.acf"
expect_ok "external Steam library discovery" run_env "$FIXTURE/install.sh" doctor
grep -Fq "$LIB/steamapps/common/No More Heroes" "$FIXTURE/test.log" \
  && pass "external path returned" || fail "external path returned"

# Legacy Steam libraryfolders.vdf format remains supported.
make_fixture
STEAM="$FIXTURE/home/.local/share/Steam"
LIB="$FIXTURE/Legacy Library"
mkdir -p "$STEAM/steamapps" "$LIB/steamapps/common/No More Heroes"
printf exe >"$LIB/steamapps/common/No More Heroes/nmh.exe"
printf '"LibraryFolders"\n{\n "1" "%s"\n}\n' "$LIB" \
  >"$STEAM/steamapps/libraryfolders.vdf"
printf '"AppState"\n{\n "appid" "1420290"\n "installdir" "No More Heroes"\n}\n' \
  >"$LIB/steamapps/appmanifest_1420290.acf"
expect_ok "legacy Steam library discovery" run_env "$FIXTURE/install.sh" doctor
grep -Fq "$LIB/steamapps/common/No More Heroes" "$FIXTURE/test.log" \
  && pass "legacy external path returned" || fail "legacy external path returned"

# Flatpak Steam: runtime detection and paths must stay inside app storage.
make_fixture
STEAM="$FIXTURE/home/.var/app/com.valvesoftware.Steam/.local/share/Steam"
mkdir -p "$STEAM/steamapps/common/No More Heroes"
printf exe >"$STEAM/steamapps/common/No More Heroes/nmh.exe"
printf '"AppState"\n{\n "appid" "1420290"\n "installdir" "No More Heroes"\n}\n' \
  >"$STEAM/steamapps/appmanifest_1420290.acf"
cat >"$FIXTURE/fakebin/flatpak" <<'EOF'
#!/bin/sh
case "$1" in
  list) printf 'org.freedesktop.Platform.VulkanLayer.vkBasalt\ti386\n' ;;
  info) exit 0 ;;
  remote-ls) printf 'org.freedesktop.Platform.VulkanLayer.vkBasalt/i386/23.08\n' ;;
  install) exit 0 ;;
esac
EOF
chmod +x "$FIXTURE/fakebin/flatpak"
expect_ok "Flatpak install" run_env "$FIXTURE/install.sh" install "$STEAM/steamapps/common/No More Heroes"
FLAT_CONFIG="$FIXTURE/home/.var/app/com.valvesoftware.Steam/config/vkBasalt/nmh.conf"
grep -Fq "$FIXTURE/home/.var/app/com.valvesoftware.Steam/data/Dtagnan-Mods" "$FLAT_CONFIG" \
  && pass "Flatpak config paths" || fail "Flatpak config paths"

# Missing Flatpak runtime: discover the i386 extension, install it, recheck it.
make_fixture
STEAM="$FIXTURE/home/.var/app/com.valvesoftware.Steam/.local/share/Steam"
mkdir -p "$STEAM/steamapps/common/No More Heroes"
printf exe >"$STEAM/steamapps/common/No More Heroes/nmh.exe"
cat >"$FIXTURE/fakebin/flatpak" <<'EOF'
#!/bin/sh
case "$1" in
  list)
    [ -f "$DTAGNAN_FLATPAK_STATE" ] && \
      printf 'org.freedesktop.Platform.VulkanLayer.vkBasalt\ti386\n'
    ;;
  info) exit 0 ;;
  remote-ls)
    printf 'org.freedesktop.Platform.VulkanLayer.vkBasalt/x86_64/23.08\n'
    printf 'org.freedesktop.Platform.VulkanLayer.vkBasalt/i386/23.08\n'
    ;;
  install)
    : >"$DTAGNAN_FLATPAK_STATE"
    ;;
esac
EOF
chmod +x "$FIXTURE/fakebin/flatpak"
if printf 'y\n' | script -qec \
  "env HOME='$FIXTURE/home' PATH='$FIXTURE/fakebin:/usr/bin:/bin' DTAGNAN_ALLOW_ROOT=1 DTAGNAN_SKIP_PAYLOAD_HASH_CHECK=1 DTAGNAN_FLATPAK_STATE='$FIXTURE/flatpak-installed' '$FIXTURE/install.sh' install '$STEAM/steamapps/common/No More Heroes'" \
  /dev/null >"$FIXTURE/test.log" 2>&1; then
  pass "Flatpak missing-runtime installation"
else
  fail "Flatpak missing-runtime installation"; cat "$FIXTURE/test.log"
fi
[[ -f "$FIXTURE/flatpak-installed" ]] \
  && pass "Flatpak i386 runtime selected" || fail "Flatpak i386 runtime selected"

# A failed Flatpak extension installation must not touch game DLLs.
make_fixture
STEAM="$FIXTURE/home/.var/app/com.valvesoftware.Steam/.local/share/Steam"
GAME="$STEAM/steamapps/common/No More Heroes"
mkdir -p "$GAME"; printf exe >"$GAME/nmh.exe"
cat >"$FIXTURE/fakebin/flatpak" <<'EOF'
#!/bin/sh
case "$1" in
  info) exit 0 ;;
  list) exit 0 ;;
  remote-ls) printf 'org.freedesktop.Platform.VulkanLayer.vkBasalt/i386/23.08\n' ;;
  install) exit 9 ;;
esac
EOF
chmod +x "$FIXTURE/fakebin/flatpak"
if printf 'y\n' | script -qec \
  "env HOME='$FIXTURE/home' PATH='$FIXTURE/fakebin:/usr/bin:/bin' DTAGNAN_ALLOW_ROOT=1 DTAGNAN_SKIP_PAYLOAD_HASH_CHECK=1 '$FIXTURE/install.sh' install '$GAME'" \
  /dev/null >"$FIXTURE/test.log" 2>&1; then
  fail "Flatpak runtime failure is reported"
else
  pass "Flatpak runtime failure is reported"
fi
[[ ! -e "$GAME/d3d11.dll" && ! -e "$GAME/dxgi.dll" ]] \
  && pass "Flatpak runtime failure leaves game untouched" \
  || fail "Flatpak runtime failure leaves game untouched"

# Snap is detected but must fail safely before installation.
make_fixture
SNAP="$FIXTURE/home/snap/steam/common/.local/share/Steam"
mkdir -p "$SNAP/steamapps/common/No More Heroes"
printf exe >"$SNAP/steamapps/common/No More Heroes/nmh.exe"
printf '"AppState"\n{\n "appid" "1420290"\n "installdir" "No More Heroes"\n}\n' \
  >"$SNAP/steamapps/appmanifest_1420290.acf"
expect_fail "Snap safety refusal" run_env "$FIXTURE/install.sh" install "$SNAP/steamapps/common/No More Heroes"
grep -q 'Snap Steam is detected' "$FIXTURE/test.log" \
  && pass "Snap refusal message" || fail "Snap refusal message"

# Steam Deck/SteamOS complete lifecycle using persistent /home/deck-style data.
make_fixture
DECK="$FIXTURE/home/.local/share/Steam"
mkdir -p "$DECK/steamapps/common/No More Heroes"
printf exe >"$DECK/steamapps/common/No More Heroes/nmh.exe"
printf '"AppState"\n{\n "appid" "1420290"\n "installdir" "No More Heroes"\n}\n' \
  >"$DECK/steamapps/appmanifest_1420290.acf"
expect_ok "SteamOS doctor" run_env DTAGNAN_TEST_PLATFORM=steamdeck "$FIXTURE/install.sh" doctor
grep -q 'Steam Deck / SteamOS' "$FIXTURE/test.log" \
  && pass "SteamOS platform classification" || fail "SteamOS platform classification"
expect_ok "SteamOS install with dependencies present" run_env DTAGNAN_TEST_PLATFORM=steamdeck "$FIXTURE/install.sh" install "$DECK/steamapps/common/No More Heroes"
expect_ok "SteamOS verify" run_env DTAGNAN_TEST_PLATFORM=steamdeck "$FIXTURE/install.sh" verify "$DECK/steamapps/common/No More Heroes"
expect_ok "SteamOS restore" run_env DTAGNAN_TEST_PLATFORM=steamdeck "$FIXTURE/install.sh" restore "$DECK/steamapps/common/No More Heroes"

# SteamOS missing dependencies must refuse installation without touching the game.
for dep in vkbasalt32 vulkan32; do
  make_fixture
  DECK="$FIXTURE/home/.local/share/Steam"
  GAME="$DECK/steamapps/common/No More Heroes"
  mkdir -p "$GAME"; printf exe >"$GAME/nmh.exe"
  if printf 'y\n' | script -qec \
    "env HOME='$FIXTURE/home' PATH='$FIXTURE/fakebin:/usr/bin:/bin' DTAGNAN_ALLOW_ROOT=1 DTAGNAN_SKIP_PAYLOAD_HASH_CHECK=1 DTAGNAN_TEST_PLATFORM=steamdeck DTAGNAN_TEST_MISSING='$dep' VULKAN_LIBRARY='$FIXTURE/lib32.so' VKBASALT_LIBRARY='$FIXTURE/lib32.so' '$FIXTURE/install.sh' install '$GAME'" \
    /dev/null >"$FIXTURE/test.log" 2>&1; then
    fail "SteamOS safely refuses missing $dep"
  else
    pass "SteamOS safely refuses missing $dep"
  fi
  [[ ! -e "$GAME/d3d11.dll" && ! -e "$GAME/dxgi.dll" ]] \
    && pass "SteamOS $dep failure leaves game untouched" \
    || fail "SteamOS $dep failure leaves game untouched"
done

# Steam Deck microSD/additional-library path, including spaces.
make_fixture
DECK="$FIXTURE/home/.local/share/Steam"
SD="$FIXTURE/run media deck SD Card"
GAME="$SD/steamapps/common/No More Heroes"
mkdir -p "$DECK/steamapps" "$GAME"
printf exe >"$GAME/nmh.exe"
printf '"libraryfolders"\n{\n "0"\n {\n  "path" "%s"\n }\n}\n' "$SD" \
  >"$DECK/steamapps/libraryfolders.vdf"
printf '"AppState"\n{\n "appid" "1420290"\n "installdir" "No More Heroes"\n}\n' \
  >"$SD/steamapps/appmanifest_1420290.acf"
expect_ok "SteamOS microSD discovery and install" run_env \
  DTAGNAN_TEST_PLATFORM=steamdeck "$FIXTURE/install.sh" install
expect_ok "SteamOS microSD verify" run_env \
  DTAGNAN_TEST_PLATFORM=steamdeck "$FIXTURE/install.sh" verify
expect_ok "SteamOS microSD restore" run_env \
  DTAGNAN_TEST_PLATFORM=steamdeck "$FIXTURE/install.sh" restore

# Steam Deck user-local vkBasalt installs must work without changing SteamOS.
make_fixture
DECK="$FIXTURE/home/.local/share/Steam"
mkdir -p "$DECK/steamapps/common/No More Heroes" "$FIXTURE/home/.local/lib32"
printf exe >"$DECK/steamapps/common/No More Heroes/nmh.exe"
printf elf >"$FIXTURE/home/.local/lib32/libvkbasalt.so"
expect_ok "SteamOS user-local vkBasalt" env \
  HOME="$FIXTURE/home" PATH="$FIXTURE/fakebin:/usr/bin:/bin" \
  DTAGNAN_ALLOW_ROOT=1 DTAGNAN_SKIP_PAYLOAD_HASH_CHECK=1 \
  DTAGNAN_TEST_PLATFORM=steamdeck VULKAN_LIBRARY="$FIXTURE/lib32.so" \
  "$FIXTURE/install.sh" install "$DECK/steamapps/common/No More Heroes"

# Custom XDG roots must be honored on a native Steam/SteamOS install.
make_fixture
GAME="$FIXTURE/game"; mkdir -p "$GAME"; printf exe >"$GAME/nmh.exe"
expect_ok "custom XDG install" run_env DTAGNAN_TEST_PLATFORM=steamdeck \
  XDG_DATA_HOME="$FIXTURE/custom data" XDG_CONFIG_HOME="$FIXTURE/custom config" \
  "$FIXTURE/install.sh" install "$GAME"
[[ -f "$FIXTURE/custom config/vkBasalt/nmh.conf" &&
   -f "$FIXTURE/custom data/Dtagnan-Mods/No-More-Heroes/Shaders/NMH_Bloom.fx" ]] \
  && pass "custom XDG paths honored" || fail "custom XDG paths honored"
expect_ok "custom XDG restore" run_env DTAGNAN_TEST_PLATFORM=steamdeck \
  XDG_DATA_HOME="$FIXTURE/custom data" XDG_CONFIG_HOME="$FIXTURE/custom config" \
  "$FIXTURE/install.sh" restore "$GAME"

# Existing user vkBasalt configuration is restored byte-for-byte.
make_fixture
mkdir -p "$FIXTURE/game" "$FIXTURE/home/.config/vkBasalt"
printf exe >"$FIXTURE/game/nmh.exe"
printf 'user configuration\n' >"$FIXTURE/home/.config/vkBasalt/nmh.conf"
expect_ok "install over user config" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
expect_ok "restore user config" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game"
[[ "$(<"$FIXTURE/home/.config/vkBasalt/nmh.conf")" == "user configuration" &&
   ! -e "$FIXTURE/home/.config/vkBasalt/nmh.conf.pre-dtagnan-mods" ]] \
  && pass "user config preserved" || fail "user config preserved"

# External modification after install must never be deleted by restore.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
expect_ok "install before external DLL change" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
printf third-party >"$FIXTURE/game/d3d11.dll"
expect_ok "restore preserves external DLL change" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game"
[[ "$(<"$FIXTURE/game/d3d11.dll")" == third-party ]] \
  && pass "external DLL left untouched" || fail "external DLL left untouched"

# User-modified shader assets must survive uninstall.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
expect_ok "install before shader modification" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
SHADER="$FIXTURE/home/.local/share/Dtagnan-Mods/No-More-Heroes/Shaders/NMH_Bloom.fx"
printf user-edited-shader >"$SHADER"
expect_ok "uninstall with modified shader" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game"
[[ "$(<"$SHADER")" == user-edited-shader ]] \
  && pass "modified shader left untouched" || fail "modified shader left untouched"

# Corrupt backup metadata must stop restoration rather than guessing.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
expect_ok "install before corrupt-state test" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
printf 'invalid-state\n' >"$FIXTURE/home/.local/share/Dtagnan-Mods/No-More-Heroes/Vanilla-backup/install-state"
expect_fail "corrupt backup state refusal" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game"

# Verification detects tampering, and restoration refuses a missing backup.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
printf original >"$FIXTURE/game/d3d11.dll"
expect_ok "install before tamper test" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
printf tampered >"$FIXTURE/game/dxgi.dll"
expect_fail "tampered DLL verification" run_env "$FIXTURE/install.sh" verify "$FIXTURE/game"
rm -f "$FIXTURE/home/.local/share/Dtagnan-Mods/No-More-Heroes/Vanilla-backup/d3d11.dll"
expect_fail "missing original backup refusal" run_env "$FIXTURE/install.sh" restore "$FIXTURE/game"

# Stale atomic-install files are removed on the next safe install.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
mkdir -p "$FIXTURE/home/.local/share/Dtagnan-Mods/No-More-Heroes"
: >"$FIXTURE/game/dxgi.dll.dtagnan-tmp.111"
: >"$FIXTURE/home/.local/share/Dtagnan-Mods/No-More-Heroes/orphan.dtagnan-tmp.222"
expect_ok "stale temporary cleanup install" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
[[ ! -e "$FIXTURE/game/dxgi.dll.dtagnan-tmp.111" &&
   ! -e "$FIXTURE/home/.local/share/Dtagnan-Mods/No-More-Heroes/orphan.dtagnan-tmp.222" ]] \
  && pass "stale temporary files removed" || fail "stale temporary files removed"

# Failure while committing the second DLL must roll back the first DLL too.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
printf rollback-original-d3d11 >"$FIXTURE/game/d3d11.dll"
printf rollback-original-dxgi >"$FIXTURE/game/dxgi.dll"
cat >"$FIXTURE/fakebin/mv" <<'EOF'
#!/bin/sh
for arg in "$@"; do
  case "$arg" in
    */game/dxgi.dll) exit 70 ;;
  esac
done
exec /usr/bin/mv "$@"
EOF
chmod +x "$FIXTURE/fakebin/mv"
expect_fail "mid-install failure is reported" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"
[[ "$(<"$FIXTURE/game/d3d11.dll")" == rollback-original-d3d11 &&
   "$(<"$FIXTURE/game/dxgi.dll")" == rollback-original-dxgi ]] \
  && pass "mid-install failure rolls back both DLLs" \
  || fail "mid-install failure rolls back both DLLs"
grep -q '\[ROLLBACK\]' "$FIXTURE/test.log" \
  && pass "rollback is reported to user" || fail "rollback is reported to user"

# SIGTERM during the second DLL commit must restore originals and remove temps.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
printf interrupt-original-d3d11 >"$FIXTURE/game/d3d11.dll"
printf interrupt-original-dxgi >"$FIXTURE/game/dxgi.dll"
cat >"$FIXTURE/fakebin/mv" <<'EOF'
#!/bin/sh
for arg in "$@"; do
  case "$arg" in
    */game/dxgi.dll) sleep 30 ;;
  esac
done
exec /usr/bin/mv "$@"
EOF
chmod +x "$FIXTURE/fakebin/mv"
set +e
timeout -s TERM -k 3 1 env HOME="$FIXTURE/home" \
  PATH="$FIXTURE/fakebin:/usr/bin:/bin" DTAGNAN_ALLOW_ROOT=1 \
  DTAGNAN_SKIP_PAYLOAD_HASH_CHECK=1 VULKAN_LIBRARY="$FIXTURE/lib32.so" \
  VKBASALT_LIBRARY="$FIXTURE/lib32.so" "$FIXTURE/install.sh" install \
  "$FIXTURE/game" >"$FIXTURE/test.log" 2>&1
interrupt_rc=$?
set -e
[[ "$interrupt_rc" == 124 || "$interrupt_rc" == 143 ]] \
  && pass "forced interruption observed" || fail "forced interruption observed"
[[ "$(<"$FIXTURE/game/d3d11.dll")" == interrupt-original-d3d11 &&
   "$(<"$FIXTURE/game/dxgi.dll")" == interrupt-original-dxgi ]] \
  && pass "interrupted install restores both DLLs" \
  || fail "interrupted install restores both DLLs"
if find "$FIXTURE" -name '*.dtagnan-tmp.*' -print -quit | grep -q .; then
  fail "interrupted install removes temporary files"
else
  pass "interrupted install removes temporary files"
fi

# Explicit symlink path and C locale must not break path normalization.
make_fixture
mkdir -p "$FIXTURE/real game"; printf exe >"$FIXTURE/real game/nmh.exe"
ln -s "$FIXTURE/real game" "$FIXTURE/game-link"
expect_ok "symlink game path install in C locale" run_env LC_ALL=C \
  "$FIXTURE/install.sh" install "$FIXTURE/game-link"
expect_ok "symlink game path verify in C locale" run_env LC_ALL=C \
  "$FIXTURE/install.sh" verify "$FIXTURE/game-link"
expect_ok "symlink game path restore in C locale" run_env LC_ALL=C \
  "$FIXTURE/install.sh" restore "$FIXTURE/game-link"

# GPU-specific launch options: PRIME only belongs on hybrid NVIDIA systems.
for gpu in nvidia-hybrid nvidia amd intel unknown; do
  make_fixture
  mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
  expect_ok "launch options $gpu" run_env DTAGNAN_GPU_PROFILE="$gpu" \
    "$FIXTURE/install.sh" options "$FIXTURE/game"
  if [[ "$gpu" == nvidia-hybrid ]]; then
    grep -q '__NV_PRIME_RENDER_OFFLOAD=1' "$FIXTURE/test.log" \
      && pass "hybrid PRIME options present" || fail "hybrid PRIME options present"
  elif grep -q '__NV_PRIME_RENDER_OFFLOAD=1' "$FIXTURE/test.log"; then
    fail "$gpu has no unwanted PRIME options"
  else
    pass "$gpu has no unwanted PRIME options"
  fi
done

# Failure paths.
make_fixture
mkdir -p "$FIXTURE/game"; printf exe >"$FIXTURE/game/nmh.exe"
printf '' >"$FIXTURE/DXVK/d3d11.dll"
expect_fail "empty payload refusal" run_env "$FIXTURE/install.sh" install "$FIXTURE/game"

make_fixture
expect_fail "invalid explicit game path" run_env "$FIXTURE/install.sh" install "$FIXTURE/missing"

make_fixture
expect_fail "unknown platform override" run_env DTAGNAN_TEST_PLATFORM=plan9 "$FIXTURE/install.sh" doctor

make_fixture
expect_fail "unknown command refusal" run_env "$FIXTURE/install.sh" explode

make_fixture
expect_fail "root execution guard" env HOME="$FIXTURE/home" \
  PATH="$FIXTURE/fakebin:/usr/bin:/bin" "$FIXTURE/install.sh" doctor

printf '\nTOTAL: %s passed, %s failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
