#!/usr/bin/bash

# Usage:
# build.sh /path/to/metainfo.json

# Requirements:
# See https://openwrt.org/docs/guide-user/additional-software/imagebuilder for openwrt image builder dependencies
# curl jq bsdtar coreutils sed grep

# Notes:
# Use environment variable OPENWRT_DOWNLOAD to set an alternative site to https://downloads.openwrt.org

set -e

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
readonly SECRETS_JSON="secrets.json"

declare arch subarch packages profile files version
arch="$(__ensure_not_null .arch "$METAINFO")"
subarch="$(__ensure_not_null .subarch "$METAINFO")"
packages="$(__handle_possible_null '.packages | try join(" ")' "$METAINFO")"
profile="$(__ensure_not_null .profile "$METAINFO")"
files="$(__handle_possible_null ".files | keys[]" "$METAINFO")"
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
if [[ -n "$files" ]]
then
    declare file_path target_file file file_mode
    file_path="$(mktemp -dt "openwrt-builder-$profile-XXXXXX")"
    while read -r file
    do
        declare -a source_files
        read -r -a source_files <<< "$(jq -r ".files.\"$file\".source[]" "$METAINFO")"
        if [[ "${#source_files[@]}" -gt 0 ]]
        then
            target_file="$file_path/$file"
            file_mode="$(jq -r ".files.\"$file\".mode" "$METAINFO")"
            if [[ -z "$file_mode" ]] || [[ "$file_mode" == "null" ]]
            then
                file_mode=644
            fi
            echo "Generating $file with ${source_files[*]}..."
            cat "${source_files[@]}" | install -D /dev/stdin "$target_file"
            if [[ -f "$SECRETS_JSON" ]]
            then
                declare secret_placeholder
                while read -r secret_placeholder
                do
                    echo "Applying secret $secret_placeholder into configuration..."
                    declare secret_jq_expression secret_value
                    secret_jq_expression="$(echo "$secret_placeholder" | sed 's/^@//;s/@$//')"
                    secret_value="$(jq -r "$secret_jq_expression" "$SECRETS_JSON")"
                    sed -i "s/$secret_placeholder/$secret_value/g" "$target_file"
                done < <(grep -o -E '@\..+@' "$target_file")
            fi
            chmod "$file_mode" "$target_file"
        fi
    done <<< "$files"
    make_args+=(FILES="$file_path")
    unset file_path target_file source_files file
fi
make "${make_args[@]}" image
echo "You can get artifacts at $BUILDER/bin/targets/$arch/$subarch/"
