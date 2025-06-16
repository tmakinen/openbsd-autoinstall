#!/bin/sh

set -eu
umask 022

if [ "$#" -ne 1 ]; then
    echo "Usage: $(basename "$0") <URL>" 1>&2
    exit 1
fi

URL="$1"
ARCH="$(basename "$1")"
VERSION="$(basename "$(dirname "$1")")"

WORKDIR="$(mktemp -d)"
trap '{
    mount | grep -Eq "^/dev/vnd0a on ${WORKDIR}/mount " && umount "${WORKDIR}/mount"
    vnconfig -l vnd0 | grep -Fq "not in use" || vnconfig -u vnd0
    rm -rf "${WORKDIR}"
}' EXIT
mkdir "${WORKDIR}/mount"
mkdir -p "${WORKDIR}/iso/${VERSION}/${ARCH}"

for f in cdboot cdbr; do
    echo "Downloading ${f}..."
    curl -sSf -o "${WORKDIR}/iso/${VERSION}/${ARCH}/${f}" "${URL}/${f}"
done
echo "Downloading bsd.rd..."
curl -sSf -o "${WORKDIR}/bsd.rd" "${URL}/bsd.rd"

echo "Creating custom bsd.rd..."
zcat "${WORKDIR}/bsd.rd" > "${WORKDIR}/bsd.urd"
rdsetroot -x "${WORKDIR}/bsd.urd" "${WORKDIR}/bsd.fs"
vnconfig vnd0 "${WORKDIR}/bsd.fs"
mount /dev/vnd0a "${WORKDIR}/mount"
install -m 0644 auto_install.conf "${WORKDIR}/mount/auto_install.conf"
install -m 0644 autopart.conf "${WORKDIR}/mount/autopart.conf"
umount "${WORKDIR}/mount"
rdsetroot "${WORKDIR}/bsd.urd" "${WORKDIR}/bsd.fs"
compress -9 < "${WORKDIR}/bsd.urd" > "${WORKDIR}/iso/${VERSION}/${ARCH}/bsd.rd"

echo "Create boot.conf..."
mkdir "${WORKDIR}/iso/etc"
{
    echo "set tty com0"
    echo "set image /${VERSION}/${ARCH}/kakka/bsd.rd"
    echo "boot"
} > "${WORKDIR}/iso/etc/boot.conf"

echo "Creating iso image..."
mkhybrid -R -T -l -L -d -D -N -o openbsd-autoinstall.iso \
  -A "OpenBSD/${ARCH}" \
  -P "OpenBSD Project" \
  -V "OpenBSD/${ARCH}" \
  -b "${VERSION}/${ARCH}/cdbr" \
  -c "${VERSION}/${ARCH}boot.catalog" \
  "${WORKDIR}/iso"
