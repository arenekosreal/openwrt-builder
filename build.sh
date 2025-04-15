#!/usr/bin/bash -e

# Usage:
# build.sh /path/to/metainfo.json

# Requirements:
# See https://openwrt.org/docs/guide-user/additional-software/imagebuilder for openwrt image builder dependencies
# curl jq bsdtar coreutils sed

# Notes:
# Use environment variable OPENWRT_DOWNLOAD to set an alternative site to https://downloads.openwrt.org

# __ensure_not_null $jq_expression $json
function __ensure_not_null() {
    local value
    value="$(jq -r "$1" "$2")"
    if [[ "$value" == "null" ]]
    then
        echo "You have to set $1 in $2." > /dev/stderr
        exit 1
    fi
    echo "$value"
}

# __handle_possible_null $jq_expression $json
function __handle_possible_null() {
    local value
    value="$(jq -r "$1" "$2")"
    if [[ -z "${value// }" ]] || [[ "$value" == "null" ]]
    then
        value=
    fi
    echo "$value"
}

readonly METAINFO="$1"
if [[ ! -f "$METAINFO" ]]
then
    echo "$METAINFO is not a valid file." > /dev/stderr
    exit 1
fi

declare arch subarch packages profile files version
arch="$(__ensure_not_null .arch "$METAINFO")"
subarch="$(__ensure_not_null .subarch "$METAINFO")"
packages="$(__handle_possible_null '.packages | try join(" ")' "$METAINFO")"
profile="$(__ensure_not_null .profile "$METAINFO")"
files="$(__handle_possible_null .files "$METAINFO")"
version="$(__ensure_not_null .version "$METAINFO")"
readonly arch subarch packages profile files version

declare host compress
host="$(uname -m)"
compress="$(__ensure_not_null .builder.compress "$METAINFO" )"
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
declare -a make_args=(-C "$BUILDER" PROFILE="$profile" PACKAGES="$packages")
if [[ -n "$files" ]] && [[ -d "$files" ]]
then
    make_args+=(FILES="$(readlink -f "$files")")
fi
make "${make_args[@]}" image
echo "You can get artifacts at $BUILDER/bin/targets/$arch/$subarch/"
