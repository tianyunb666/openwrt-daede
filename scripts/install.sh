#!/bin/sh

set -eu

FEED_BASE_URL="https://down.dllkids.xyz/openwrt-feed/daed"
GITHUB_PROXY_PREFIX="${GITHUB_PROXY_PREFIX:-https://ghfast.top/}"
# 将 GitHub API 也通过代理站进行加速，防止国内直连握手失败 [cite: 1]
GITHUB_API_URL="${GITHUB_PROXY_PREFIX}https://api.github.com/repos/kenzok8/openwrt-daede/releases/latest" [cite: 1]
VMLINUX_BTF_API="${VMLINUX_BTF_API:-${GITHUB_PROXY_PREFIX}https://api.github.com/repos/kenzok8/vmlinux-btf/releases/tags/latest}" [cite: 49]
TMP_DIR="/tmp/daede-install" [cite: 1]

# Which core backend to install alongside the LuCI app.
# daed ships the WebUI [cite: 1, 2]
# and is the default the LuCI app expects. Override with DAEDE_CORE=dae|daed|both. [cite: 2]
DAEDE_CORE="${DAEDE_CORE:-daed}" [cite: 3]

fetch_text() {
  url="$1"
  # 注入 --connect-timeout 和 --timeout，防止国内极端网络环境下无限期卡死
  if command -v curl >/dev/null 2>&1; then [cite: 3]
    curl -fsSL --connect-timeout 15 "$url" 2>/dev/null [cite: 4]
    return $? [cite: 4]
  fi [cite: 5]
  wget -qO- --timeout=15 "$url" 2>/dev/null [cite: 5]
}

download_file() {
  url="$1"
  out="$2" [cite: 5]
  if command -v curl >/dev/null 2>&1; then [cite: 5]
    curl -fL --connect-timeout 15 "$url" -o "$out" [cite: 6]
    return $? [cite: 6]
  fi [cite: 7]
  wget -qO "$out" --timeout=15 "$url" [cite: 7]
}

download_url() {
  url="$1" [cite: 7]
  case "$url" in [cite: 7]
    https://github.com/*) [cite: 7]
      printf '%s%s\n' "$GITHUB_PROXY_PREFIX" "$url" [cite: 7]
      ;; [cite: 7]
    *) [cite: 8]
      printf '%s\n' "$url" [cite: 8]
      ;; [cite: 8]
  esac [cite: 9]
}

# dae/daed hard-depend on the noarch v2ray-geoip/geosite packages, which live in [cite: 9]
# the aggregated feed (one level up from the daed feed). [cite: 9]
# Print their URLs so we [cite: 10]
# install them as local files and satisfy the dep without the device's own repos. [cite: 10]
resolve_geodata() {
  sdk="$1"; arch="$2" [cite: 11]
  [ -n "$sdk" ] || return 1 [cite: 11, 12]
  dir="${FEED_BASE_URL%/daed}/${sdk}/${arch}" [cite: 12]
  listing="$(fetch_text "${dir}/" || true)" [cite: 12]
  [ -n "$listing" ] || return 1 [cite: 12, 13]
  for pkg in v2ray-geoip v2ray-geosite; do [cite: 13]
    if [ "$PM" = "apk" ]; then [cite: 13, 14]
      file="$(printf '%s\n' "$listing" | grep -oE "${pkg}-[0-9][^\"/<]*\.apk" | head -n 1)" [cite: 14]
    else [cite: 14]
      file="$(printf '%s\n' "$listing" | grep -oE "${pkg}_[^\"/<]*_all\.ipk" | head -n 1)" [cite: 14]
    fi [cite: 15]
    [ -n "$file" ] || return 1 [cite: 15]
    printf '%s/%s\n' "$dir" "$file" [cite: 15]
  done [cite: 15]
}

detect_manager() {
  sdk="$(detect_sdk || true)" [cite: 15]
  case "$sdk" in [cite: 15]
    2[5-9].*|[3-9][0-9].*) [cite: 15]
      if command -v apk >/dev/null 2>&1; then echo apk; return; fi [cite: 15, 16]
      ;; [cite: 16]
  esac [cite: 16]
  if command -v opkg >/dev/null 2>&1; then echo opkg; return; fi [cite: 16, 17]
  if command -v apk >/dev/null 2>&1; then echo apk; return; fi [cite: 17, 18]
  echo "unsupported" [cite: 18]
}

detect_arch() {
  pm="$1" [cite: 18]
  if [ "$pm" = "opkg" ]; then [cite: 18, 19]
    opkg print-architecture | awk '/^arch / {print $2}' | tail -n 1 [cite: 19, 20]
    return [cite: 20]
  fi [cite: 20]
  # apk --print-arch only returns the CPU family (e.g. aarch64), dropping the [cite: 20]
  # subtarget suffix; [cite: 21]
  # feed/release use the full target arch (aarch64_cortex-a53), [cite: 21]
  # so prefer DISTRIB_ARCH. [cite: 21]
  distrib_arch="$(sed -n "s/^DISTRIB_ARCH=['\"]\([^'\"]*\)['\"].*/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1)" [cite: 22]
  if [ -n "$distrib_arch" ]; then [cite: 22]
    printf '%s\n' "$distrib_arch" [cite: 22]
  else [cite: 22]
    apk --print-arch [cite: 22]
  fi [cite: 22]
}

detect_sdk() {
  if [ ! -r /etc/openwrt_release ]; then return 1; fi [cite: 22]
  release="$(sed -n "s/^DISTRIB_RELEASE=['\"]\\([^'\"]*\\)['\"]$/\\1/p" /etc/openwrt_release | head -n 1)" [cite: 22]
  [ -n "$release" ] || return 1 [cite: 22, 23]
  sdk="$(printf '%s\n' "$release" | grep -Eo '[0-9]+\.[0-9]+' | head -n 1)" [cite: 23]
  [ -n "$sdk" ] || return 1 [cite: 23, 24]
  printf '%s\n' "$sdk" [cite: 24]
}

# aarch64 subtargets without a feed (e.g. cortex-a76) fall back to aarch64_generic. [cite: 25]
fallback_arch() {
  case "$1" in [cite: 25]
    aarch64_generic) return 1 ;; [cite: 25]
    aarch64_*)       printf 'aarch64_generic\n' ;; [cite: 26]
    *)               return 1 ;; [cite: 27]
  esac [cite: 28]
}

# Feed base for package manifests and files.
feed_bases() {
  printf '%s\n' "$FEED_BASE_URL" [cite: 28]
}

feed_base_for() {
  printf '%s/%s/%s' "$1" "$2" "$3" [cite: 28]
}

package_sdks() {
  sdk="$1" [cite: 28]
  [ -n "$sdk" ] || return 0 [cite: 28, 29]

  if [ "$PM" = "opkg" ]; then [cite: 29]
    case "$sdk" in [cite: 29]
      2[5-9].*|[3-9][0-9].*) [cite: 29]
        # QWRT may report an OpenWrt 25.x SDK while still shipping opkg. [cite: 30]
        # Use the last IPK feed first instead of downloading APK packages. [cite: 30]
        printf '24.10\n' [cite: 31]
        [ "$sdk" = "24.10" ] || printf '%s\n' "$sdk" [cite: 31, 32]
        return [cite: 32]
        ;; [cite: 33]
    esac [cite: 33]
  fi [cite: 33]

  printf '%s\n' "$sdk" [cite: 33]
}

# Which packages to fetch, in install order (core before luci so opkg/apk can [cite: 33]
# resolve the luci-app-daede -> core dependency from local files). [cite: 34]
wanted_pkgs() {
  case "$DAEDE_CORE" in [cite: 34]
    dae)  printf 'dae\nluci-app-daede\n' ;; [cite: 34]
    both) printf 'dae\ndaed\nluci-app-daede\n' ;; [cite: 34]
    *)    printf 'daed\nluci-app-daede\n' ;; [cite: 35]
  esac [cite: 35]
}

# Globals filled by the resolver: space-separated list of "pkg|url|sha256".
PLAN="" [cite: 36]
MANIFEST_TEXT="" [cite: 36]

manifest_value() {
  printf '%s\n' "$MANIFEST_TEXT" | sed -n "s/^$1=//p" | head -n 1 [cite: 36, 37]
}

# Resolve every wanted package from the R2 feed manifest. [cite: 37]
#   Manifest lines look like: [cite: 38]
#   dae=dae_..._<arch>.ipk [cite: 38]
#   dae_sha256=<hex>           (optional) [cite: 38]
#   daed=... [cite: 38]
#   luci-app-daede=... [cite: 38]
resolve_from_manifest() {
  sdk="$1" [cite: 38]
  arch="$2" [cite: 38]
  for fb in $(feed_bases); do [cite: 38, 39]
    base="$(feed_base_for "$fb" "$sdk" "$arch")" [cite: 39]
    MANIFEST_TEXT="$(fetch_text "${base}/manifest-daede.txt" || true)" [cite: 39]
    [ -n "$MANIFEST_TEXT" ] || continue [cite: 39, 40]

    plan="" [cite: 40]
    ok=1 [cite: 40]
    for pkg in $(wanted_pkgs); do [cite: 40, 41]
      file="$(manifest_value "$pkg")" [cite: 41]
      if [ -z "$file" ]; then [cite: 41, 42]
        echo "Manifest has no entry for '$pkg' on ${sdk}/${arch}" [cite: 42]
        ok=0 [cite: 42]
        break [cite: 42]
      fi [cite: 42]
      file_ext="${file##*.}" [cite: 42]
      if [ "$file_ext" != "$EXT" ]; then [cite: 42, 43]
        echo "Manifest entry for '$pkg' on ${sdk}/${arch} is .${file_ext}, but ${PM} needs .${EXT}; skipping" [cite: 43]
        ok=0 [cite: 43]
        break [cite: 43]
      fi [cite: 43]
      sha="$(manifest_value "${pkg}_sha256")" [cite: 43]
      plan="${plan}${pkg}|${base}/${file}|${sha}
" [cite: 43]
    done [cite: 44]
    [ "$ok" = 1 ] || continue [cite: 44]
    PLAN="$plan" [cite: 44]
    return 0 [cite: 44]
  done [cite: 44]
  return 1 [cite: 44]
}

# GitHub release fallback (best effort, no sha256 available there).
resolve_from_github() { [cite: 45]
  arch="$1" [cite: 45]
  ext="$2" [cite: 45]
  payload="$(fetch_text "$GITHUB_API_URL" || true)" [cite: 45]
  [ -n "$payload" ] || return 1 [cite: 45, 46]
  urls="$(printf '%s\n' "$payload" | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p')" [cite: 46]
  [ -n "$urls" ] || return 1 [cite: 46]

  plan="" [cite: 46]
  for pkg in $(wanted_pkgs); do [cite: 46]
    if [ "$pkg" = "luci-app-daede" ]; then [cite: 46]
      if [ "$ext" = "apk" ]; then [cite: 46]
        url="$(printf '%s\n' "$urls" | grep -E "/luci-app-daede-[^/]*-${arch}\.apk$" | head -n 1)" [cite: 46]
      else [cite: 46]
        url="$(printf '%s\n' "$urls" | grep -E '/luci-app-daede_.*_all\.ipk$' | head -n 1)" [cite: 46]
      fi [cite: 46]
    else [cite: 46]
      if [ "$ext" = "apk" ]; then [cite: 47]
        url="$(printf '%s\n' "$urls" | grep -E "/${pkg}-[^/]*-${arch}\.apk$" | head -n 1)" [cite: 47]
      else [cite: 47]
        url="$(printf '%s\n' "$urls" | grep -E "/${pkg}_[^/]*_${arch}\.ipk$" | head -n 1)" [cite: 47]
      fi [cite: 47]
    fi [cite: 47]
    if [ -z "$url" ]; then [cite: 47]
      echo "GitHub release has no '$pkg' for arch: $arch" [cite: 47]
      return 1 [cite: 47]
    fi [cite: 47]
    plan="${plan}${pkg}|${url}|
" [cite: 48]
  done [cite: 48]
  PLAN="$plan" [cite: 48]
  return 0 [cite: 48]
}

verify_sha256() {
  file="$1" [cite: 48]
  want="$2" [cite: 48]
  [ -n "$want" ] || return 0 [cite: 48]
  if command -v sha256sum >/dev/null 2>&1; then [cite: 48]
    got="$(sha256sum "$file" | awk '{print $1}')" [cite: 48]
  elif command -v openssl >/dev/null 2>&1; then [cite: 48]
    got="$(openssl dgst -sha256 "$file" | awk '{print $NF}')" [cite: 48]
  else [cite: 48]
    echo "[WARN] no sha256 tool, skipping checksum for $(basename "$file")" [cite: 48]
    return 0 [cite: 48]
  fi [cite: 48]
  if [ "$got" != "$want" ]; then [cite: 48]
    echo "Checksum mismatch for $(basename "$file"): expected $want, got $got" [cite: 48, 49]
    return 1 [cite: 49]
  fi [cite: 49]
  echo "  sha256 ok: $(basename "$file")" [cite: 49]
}

# dae/daed load CO-RE eBPF that needs kernel BTF: /sys/kernel/btf/vmlinux when the [cite: 49]
# kernel was built with CONFIG_DEBUG_INFO_BTF, else a packaged detached BTF. [cite: 49]
btf_available() {
  [ -e /sys/kernel/btf/vmlinux ] && return 0 [cite: 49]
  [ -e "/usr/lib/debug/boot/vmlinux-$(uname -r)" ] && return 0 [cite: 49]
  return 1 [cite: 49]
}

# Fetch a vmlinux-btf matching this kernel + arch when the firmware ships no BTF.
ensure_btf() {
  pm="$1"; arch="$2" [cite: 50]
  if btf_available; then [cite: 50]
    echo "Kernel BTF present; dae/daed eBPF is ready." [cite: 50]
    return 0 [cite: 51]
  fi [cite: 51]

  krel="$(uname -r)" [cite: 51]
  kmm="$(printf '%s' "$krel" | grep -Eo '^[0-9]+\.[0-9]+')" [cite: 51]
  kver="$(printf '%s' "$krel" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+')" [cite: 51]
  ext="ipk"; [cite: 51]
  [ "$pm" = "apk" ] && ext="apk" [cite: 52]

  echo "Kernel BTF missing — dae/daed need it for eBPF. Looking for vmlinux-btf (${arch}, kernel ${kver:-$krel})...." [cite: 52]

  urls="$(fetch_text "$VMLINUX_BTF_API" \
    | grep -Eo '"browser_download_url"[^,]*' \
    | sed -E 's/.*"(https[^"]+)".*/\1/' \
    | grep -E "/vmlinux-btf[^/]*\.${ext}$" \
    | grep -F "$arch")" [cite: 52]

  url="" [cite: 52]
  [ -n "$urls" ] && [ -n "$kver" ] && url="$(printf '%s\n' "$urls" | grep -F "$kver" | head -n 1)" [cite: 52]
  [ -z "$url" ] && [ -n "$urls" ] && [ -n "$kmm" ] && url="$(printf '%s\n' "$urls" | grep -E "[_-]${kmm}\.[0-9]+" | head -n 1)" [cite: 52, 53]
  [ -z "$url" ] && url="$(printf '%s\n' "$urls" | head -n 1)" [cite: 53]

  if [ -z "$url" ]; then [cite: 53]
    echo "[WARN] No vmlinux-btf for arch '${arch}', kernel '${krel}'." [cite: 53]
    echo "       dae/daed will not start without kernel BTF." [cite: 53, 54]
    echo "       Reflash firmware with CONFIG_DEBUG_INFO_BTF, or build a" [cite: 55]
    echo "       matching package: https://github.com/kenzok8/vmlinux-btf" [cite: 55]
    return 1 [cite: 55]
  fi [cite: 55]

  out="$TMP_DIR/vmlinux-btf.${ext}" [cite: 55]
  echo "Downloading $(basename "$url")..." [cite: 55]
  download_file "$(download_url "$url")" "$out" || { echo "[WARN] vmlinux-btf download failed."; return 1; } [cite: 55]

  echo "Installing vmlinux-btf..." [cite: 55]
  if [ "$pm" = "opkg" ]; then [cite: 55]
    opkg install "$out" || { echo "[WARN] vmlinux-btf install failed."; return 1; } [cite: 55]
  else [cite: 55]
    apk add --allow-untrusted "$out" || { echo "[WARN] vmlinux-btf install failed."; return 1; } [cite: 55]
  fi [cite: 55]

  if btf_available; then [cite: 56]
    echo "vmlinux-btf installed; kernel BTF now available." [cite: 56]
  else [cite: 56]
    echo "[WARN] vmlinux-btf installed but BTF still missing for kernel ${krel} (series mismatch?)." [cite: 56]
  fi [cite: 56]
}

PM="$(detect_manager)" [cite: 56]
if [ "$PM" = "unsupported" ]; then [cite: 56]
  echo "No supported package manager (opkg/apk)." [cite: 56]
  exit 1 [cite: 56]
fi [cite: 56]

# 优化体验：在国内环境下自动刷新包管理器索引，防止本地依赖解析因为过期而卡住
echo "Updating package index via $PM..."
if [ "$PM" = "opkg" ]; then
  opkg update || echo "[WARN] opkg update failed, proceeding anyway..."
else
  apk update || echo "[WARN] apk update failed, proceeding anyway..."
fi

ARCH="$(detect_arch "$PM")" [cite: 56]
[ -n "$ARCH" ] || { echo "Cannot detect architecture"; exit 1; } [cite: 56]

EXT="ipk" [cite: 56]
[ "$PM" = "apk" ] && EXT="apk" [cite: 56]

SDK="$(detect_sdk || true)" [cite: 56]

# Try the exact arch first, then the generic fallback (e.g. cortex-a76 -> generic). [cite: 56]
RESOLVED_ARCH="" [cite: 56]
RESOLVED_SDK="" [cite: 56]
for sdk_try in $(package_sdks "$SDK"); do [cite: 56]
  for a in "$ARCH" $(fallback_arch "$ARCH" || true); do [cite: 56]
    if resolve_from_manifest "$sdk_try" "$a"; then [cite: 57]
      [ "$sdk_try" = "$SDK" ] || echo "Device reports SDK ${SDK:-?}; using ${sdk_try} ${EXT} feed for ${PM}." [cite: 57, 58]
      echo "Using R2 feed manifest: ${sdk_try}/${a}" [cite: 58]
      RESOLVED_ARCH="$a" [cite: 58]
      RESOLVED_SDK="$sdk_try" [cite: 58]
      break 2 [cite: 58]
    fi [cite: 58]
  done [cite: 58]
done [cite: 58]
if [ -z "$RESOLVED_ARCH" ]; then [cite: 58]
  for a in "$ARCH" $(fallback_arch "$ARCH" || true); do [cite: 58]
    if resolve_from_github "$a" "$EXT"; then [cite: 58]
      echo "Using GitHub latest release: ${a}" [cite: 58]
      RESOLVED_ARCH="$a"; break [cite: 58]
    fi [cite: 58]
  done [cite: 58]
fi [cite: 58]
[ -n "$RESOLVED_ARCH" ] || { echo "Cannot resolve daede packages for arch: $ARCH"; exit 1; } [cite: 58, 59]
[ "$RESOLVED_ARCH" = "$ARCH" ] || echo "No ${ARCH} feed; using ${RESOLVED_ARCH} (ABI-compatible)." [cite: 59, 60]
# apk rejects packages whose arch is not listed in /etc/apk/arch; register fallback arch [cite: 60]
if [ "$PM" = "apk" ] && [ "$RESOLVED_ARCH" != "$ARCH" ]; then [cite: 60]
  if ! grep -qxF "$RESOLVED_ARCH" /etc/apk/arch 2>/dev/null; then [cite: 60]
    echo "$RESOLVED_ARCH" >> /etc/apk/arch [cite: 60]
  fi [cite: 60]
fi [cite: 60]

rm -rf "$TMP_DIR" [cite: 60]
mkdir -p "$TMP_DIR" [cite: 60]

FILES="" [cite: 60]
echo "$PLAN" | while IFS='|' read -r pkg url sha; do [cite: 60, 61]
  [ -n "$pkg" ] || continue [cite: 61]
  out="$TMP_DIR/${pkg}.${EXT}" [cite: 61]
  echo "Downloading ${pkg}..." [cite: 61]
  download_file "$(download_url "$url")" "$out" [cite: 61]
  verify_sha256 "$out" "$sha" [cite: 61]
done [cite: 61]

# The while loop above runs in a subshell (pipe), so rebuild the file list here. [cite: 61]
for pkg in $(wanted_pkgs); do [cite: 61]
  FILES="$FILES $TMP_DIR/${pkg}.${EXT}" [cite: 61]
done [cite: 61]

GEO_SDK="${RESOLVED_SDK:-$SDK}" [cite: 61]
GEO_URLS="$(resolve_geodata "$GEO_SDK" "$RESOLVED_ARCH" || true)" [cite: 61]
if [ -n "$GEO_URLS" ]; then [cite: 61]
  for gurl in $GEO_URLS; do [cite: 61]
    gout="$TMP_DIR/${gurl##*/}" [cite: 61]
    echo "Downloading ${gurl##*/}..." [cite: 61]
    if download_file "$(download_url "$gurl")" "$gout"; then [cite: 61]
      FILES="$FILES $gout" [cite: 61]
    else [cite: 61]
      echo "[WARN] geodata download failed; install may fail on v2ray-geoip/geosite." [cite: 62]
    fi [cite: 62]
  done [cite: 62]
else [cite: 62]
  echo "[WARN] v2ray-geoip/geosite not found in feed for ${GEO_SDK:-?}/${RESOLVED_ARCH}; relying on device repos." [cite: 62, 63]
fi [cite: 63]

echo "Installing (core first, then LuCI)..." [cite: 63]
_install_rc=0 [cite: 63]
if [ "$PM" = "opkg" ]; then [cite: 63]
  # shellcheck disable=SC2086
  opkg install $FILES || _install_rc=$? [cite: 63]
else [cite: 63]
  echo "[WARN] no stable signing key yet, using --allow-untrusted; sha256 is verified above when the manifest provides it." [cite: 63, 64]
  # shellcheck disable=SC2086
  apk add --allow-untrusted $FILES || _install_rc=$? [cite: 64]
fi [cite: 64]

if [ "$_install_rc" -ne 0 ]; then [cite: 64]
  echo "[ERROR] Package install failed (exit $_install_rc). daed/dae was NOT installed." [cite: 64, 65]
  echo "        Most common cause: unmet dependencies (v2ray-geoip / v2ray-geosite / kmod-*)." [cite: 65]
  # 动态适配报错语意：根据实际使用的包管理器提供对应的命令指引
  echo "        Run '$PM update' first, ensure those deps are reachable, then retry."
  exit "$_install_rc" [cite: 65]
fi [cite: 65]

# opkg/apk can exit 0 yet skip the core package on a dependency hiccup, leaving [cite: 65]
# no /usr/bin/daed while still printing success (issue #30). Verify it landed. [cite: 65]
case "$DAEDE_CORE" in [cite: 65]
  daed|both) [cite: 65]
    # 动态适配报错语意：将硬编码的 opkg 变更为动态变量 $PM
    [ -x /usr/bin/daed ] || { echo "[ERROR] Install finished but /usr/bin/daed is missing — a dependency was likely skipped; check the '$PM install' output above."; exit 1; }
    ;; [cite: 66]
esac [cite: 66]
case "$DAEDE_CORE" in [cite: 66]
  dae|both) [cite: 66]
    # 动态适配报错语意：将硬编码的 opkg 变更为动态变量 $PM
    [ -x /usr/bin/dae ] || { echo "[ERROR] Install finished but /usr/bin/dae is missing — a dependency was likely skipped; check the '$PM install' output above."; exit 1; }
    ;; [cite: 67]
esac [cite: 67]

echo "Install complete." [cite: 67]

# Supply kernel BTF if the firmware ships none, else dae/daed eBPF won't load. [cite: 67]
ensure_btf "$PM" "$RESOLVED_ARCH" || true [cite: 67]
