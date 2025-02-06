#!/usr/bin/bash

# Usage:
# build.sh /path/to/metainfo.json

# Requirements:
# See https://openwrt.org/docs/guide-user/additional-software/imagebuilder for openwrt image builder dependencies
# curl jq bsdtar coreutils sed

# Notes:
# Use environment variable OPENWRT_DOWNLOAD to set an alternative site to https://downloads.openwrt.org

set -e
readonly METAINFO="$1"
if [[ ! -f "$METAINFO" ]]
then
    echo "$METAINFO is not a valid file."
    exit 1
fi

declare arch subarch packages profile files version
arch=$(jq -r .arch "$METAINFO")
subarch=$(jq -r .subarch "$METAINFO")
packages=$(jq -r '.packages | try join(" ")' "$METAINFO")
profile=$(jq -r .profile "$METAINFO")
files=$(jq -r .files "$METAINFO")
version=$(jq -r .version "$METAINFO")
if [[ "$arch" == "null" ]] || [[ "$subarch" == "null" ]] || [[ "$profile" == "null" ]] || [[ "$version" == "null" ]]
then
    echo "You have to set arch subarch profile version at least."
    exit 1
fi
if [[ -z "${packages// }" ]] || [[ "$packages" == "null" ]]
then
    packages=
fi
if [[ "$files" == "null" ]]
then
    files=
elif [[ ! -d "$files" ]]
then
    echo "custom files is not found."
    exit 1
fi
readonly arch subarch packages profile files version

declare host compress
host=$(uname -m)
compress="$(jq -r .builder.compress "$METAINFO")"
readonly imagebuilder="${OPENWRT_DOWNLOAD:-https://downloads.openwrt.org}/releases/$version/targets/$arch/$subarch/openwrt-imagebuilder-$version-$arch-$subarch.Linux-$host.tar.$compress"
unset host

readonly BUILDER="builders/$arch/$subarch/$version"
if [[ ! -d "$BUILDER" ]] || [[ ! -f "$BUILDER/Makefile" ]]
then
    echo "Builder not found or invalid, downloading from Internet."
    rm -rf "$BUILDER"
    mkdir -p "$BUILDER"
    echo "Using url $imagebuilder to download..."
    curl -L "$imagebuilder" -o - | bsdtar -x --strip-components=1 -C "$BUILDER" -p -f -
    if [[ -n "$OPENWRT_DOWNLOAD" ]]
    then
        sed -i "s|https://downloads.openwrt.org|$OPENWRT_DOWNLOAD|g" "$BUILDER/repositories.conf"
    fi
fi

echo "Building for metainfo $METAINFO..."
make -C "$BUILDER" \
    PROFILE="$profile" \
    PACKAGES="$packages" \
    FILES="$(readlink -f "$files")" \
    image
echo "You can get artifacts at $BUILDER/bin/targets/$arch/$subarch/"
