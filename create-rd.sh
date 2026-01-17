#!/bin/sh

set -eu
umask 022

if [ "$#" -ne 1 ]; then
    echo "Usage: $(basename "$0") <URL>" 1>&2
    exit 1
fi

URL="$1"
MACHINE="$(basename "$1")"

WORKDIR="$(mktemp -d)"
trap '{
    if [ -n "$_vnd" ]; then
        mount | grep -Eq "^/dev/${_vnd}a on ${WORKDIR}/mount " && \
            umount "${WORKDIR}/mount"
        vnconfig -l "$_vnd" | grep -Fq "not in use" || \
            vnconfig -u "$_vnd"
    fi
    rm -rf "${WORKDIR}"
}' EXIT
mkdir "${WORKDIR}/mount"

echo "Downloading bsd.rd..."
curl -sSf -o "${WORKDIR}/bsd.rd" "${URL}/bsd.rd"

_vnd="$(vnconfig -l | sed -n "s/^\(vnd[0-9]\): not in use/\1/p" | head -n 1)"
if [ -z "$_vnd" ]; then
    echo "ERROR: Cannot find free vnd device. Exiting..." 1>&2
    exit 1
fi

echo "Creating custom bsd.rd..."

if file -b "${WORKDIR}/bsd.rd" | grep -qE "^gzip compressed data, " ; then
    compress=true
    zcat "${WORKDIR}/bsd.rd" > "${WORKDIR}/bsd.urd"
else
    compress=false
    mv "${WORKDIR}/bsd.rd" "${WORKDIR}/bsd.urd"
fi
rdsetroot -x "${WORKDIR}/bsd.urd" "${WORKDIR}/bsd.fs"
vnconfig "$_vnd" "${WORKDIR}/bsd.fs"
mount "/dev/${_vnd}a" "${WORKDIR}/mount"
install -m 0644 auto_install.conf "${WORKDIR}/mount/auto_install.conf"
install -m 0644 autopart.conf "${WORKDIR}/mount/autopart.conf"
umount "${WORKDIR}/mount"
rdsetroot "${WORKDIR}/bsd.urd" "${WORKDIR}/bsd.fs"

mkdir "${MACHINE}"
if [ "$compress" ]; then
    compress -9 < "${WORKDIR}/bsd.urd" > "${MACHINE}/bsd.rd"
else
    cat "${WORKDIR}/bsd.urd" > "${MACHINE}/bsd.rd"
fi
