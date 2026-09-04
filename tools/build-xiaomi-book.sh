#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--output DIR] [--jobs N] [--cross-prefix PREFIX] [--allow-dirty]"
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kernel_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
output_root="$kernel_root/../build/xiaomi-book-12.4"
cross_prefix=${CROSS_COMPILE:-aarch64-linux-gnu-}
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
allow_dirty=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output_root=$2; shift 2 ;;
        --jobs) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; jobs=$2; shift 2 ;;
        --cross-prefix) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; cross_prefix=$2; shift 2 ;;
        --allow-dirty) allow_dirty=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

mkdir -p -- "$output_root"
output_root=$(CDPATH= cd -- "$output_root" && pwd)

for tool in make sha256sum tar; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
depmod_bin=$(command -v depmod || { [ -x /sbin/depmod ] && echo /sbin/depmod; })
[ -n "$depmod_bin" ] || { echo "depmod (kmod) is required" >&2; exit 1; }
command -v "${cross_prefix}gcc" >/dev/null || {
    echo "${cross_prefix}gcc not found; set CROSS_COMPILE or --cross-prefix" >&2
    exit 1
}

cd -- "$kernel_root"
if [ "$allow_dirty" -eq 0 ] && { ! git diff --quiet || ! git diff --cached --quiet; }; then
    echo "kernel tree is dirty; commit changes before a release build" >&2
    echo "use --allow-dirty only for local testing" >&2
    exit 1
fi

commit=$(git rev-parse HEAD)
short_commit=$(git rev-parse --short=12 HEAD)
source_date_epoch=$(git show -s --format=%ct HEAD)
export SOURCE_DATE_EPOCH="$source_date_epoch"
export KBUILD_BUILD_USER=xiaomi-book
export KBUILD_BUILD_HOST=reproducible
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@${source_date_epoch}" '+%a %b %d %H:%M:%S UTC %Y')"
# An explicit empty LOCALVERSION prevents setlocalversion from appending '+'
# merely because this repository has no annotated release tag.
export LOCALVERSION=

build_dir="$output_root/build"
package_dir="$output_root/package"
rm -rf -- "$package_dir"

make -C "$kernel_root" O="$build_dir" ARCH=arm64 CROSS_COMPILE="$cross_prefix" defconfig
"$kernel_root/scripts/config" --file "$build_dir/.config" \
    --disable CONFIG_LOCALVERSION_AUTO \
    --module CONFIG_UHID \
    --module CONFIG_DRM_PANEL_HIMAX_HX83121A \
    --enable CONFIG_NF_TABLES \
    --enable CONFIG_IPV6 \
    --enable CONFIG_NF_TABLES_INET \
    --enable CONFIG_NF_TABLES_IPV4 \
    --enable CONFIG_NF_TABLES_IPV6 \
    --module CONFIG_NF_CONNTRACK \
    --module CONFIG_NF_NAT \
    --enable CONFIG_NF_NAT_MASQUERADE \
    --enable CONFIG_NF_TABLES_NETDEV \
    --module CONFIG_NFT_CT \
    --module CONFIG_NFT_NAT \
    --module CONFIG_NFT_MASQ \
    --module CONFIG_NFT_CHAIN_NAT \
    --module CONFIG_NFT_REDIR \
    --module CONFIG_NFT_FIB \
    --module CONFIG_NFT_FIB_INET \
    --module CONFIG_NFT_REJECT \
    --module CONFIG_NFT_COMPAT \
    --module CONFIG_IP_NF_FILTER \
    --module CONFIG_IP_NF_NAT \
    --module CONFIG_IP_NF_MANGLE \
    --module CONFIG_IP_NF_RAW \
    --module CONFIG_IP6_NF_FILTER \
    --module CONFIG_IP6_NF_NAT \
    --module CONFIG_IP6_NF_MANGLE \
    --module CONFIG_IP6_NF_RAW \
    --module CONFIG_NETFILTER_XT_TARGET_MASQUERADE \
    --module CONFIG_NETFILTER_XT_TARGET_NETMAP \
    --module CONFIG_NETFILTER_XT_TARGET_REDIRECT \
    --module CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
    --module CONFIG_NETFILTER_XT_MATCH_CONNTRACK \
    --module CONFIG_NETFILTER_XT_MATCH_IPVS \
    --set-str CONFIG_LOCALVERSION "-xiaomi-book-${short_commit}"
make -C "$kernel_root" O="$build_dir" ARCH=arm64 CROSS_COMPILE="$cross_prefix" olddefconfig
make -C "$kernel_root" O="$build_dir" ARCH=arm64 CROSS_COMPILE="$cross_prefix" -j"$jobs" \
    Image.gz modules qcom/sc8180x-xiaomi-book-12.4.dtb
make -C "$kernel_root" O="$build_dir" ARCH=arm64 CROSS_COMPILE="$cross_prefix" \
    INSTALL_MOD_PATH="$package_dir" INSTALL_MOD_STRIP=1 modules_install
mapfile -t releases < <(find "$package_dir/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[ "${#releases[@]}" -eq 1 ] || { echo "modules_install produced an unexpected release set" >&2; exit 1; }
release=${releases[0]}
case "$release" in *-dirty) echo "dirty release: $release" >&2; exit 1 ;; esac
"$depmod_bin" -b "$package_dir" "$release"

mkdir -p -- "$package_dir/boot"
cp -- "$build_dir/arch/arm64/boot/Image.gz" "$package_dir/boot/Image.gz"
cp -- "$build_dir/.config" "$package_dir/boot/kernel.config"
cp -- "$build_dir/arch/arm64/boot/dts/qcom/sc8180x-xiaomi-book-12.4.dtb" \
    "$package_dir/boot/sc8180x-xiaomi-book-12.4.dtb"
printf 'kernel_release=%s\ncommit=%s\nsource_date_epoch=%s\n' \
    "$release" "$commit" "$source_date_epoch" > "$package_dir/boot/BUILD-MANIFEST"
# Exclude the manifest itself: hashing an output file while creating it
# records the digest of the empty/truncated file and makes verification fail.
(cd "$package_dir" && find . -type f ! -path './SHA256SUMS' -print0 | sort -z | xargs -0 sha256sum) > "$package_dir/SHA256SUMS"

archive="$output_root/xiaomi-book-12.4-${release}.tar"
tar --sort=name --mtime="@${source_date_epoch}" --owner=0 --group=0 --numeric-owner \
    -cf "$archive" -C "$package_dir" .
gzip -n -f "$archive"
sha256sum "$archive.gz" > "$archive.gz.sha256"
echo "Built $release: $archive.gz"
