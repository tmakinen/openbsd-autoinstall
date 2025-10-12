#!/bin/sh

set -eu
umask 022

if [ "$#" -ne 1 ]; then
    echo "Usage: $(basename "$0") <URL>" 1>&2
    exit 1
fi

URL="$1"
MACHINE="$(basename "$1")"
OSREV="$(basename "$(dirname "$1")")"

WORKDIR="$(mktemp -d)"
trap '{
    mount | grep -Eq "^/dev/vnd0a on ${WORKDIR}/mount " && umount "${WORKDIR}/mount"
    vnconfig -l vnd0 | grep -Fq "not in use" || vnconfig -u vnd0
    rm -rf "${WORKDIR}"
}' EXIT
mkdir "${WORKDIR}/mount"
mkdir -p "${WORKDIR}/iso/${OSREV}/${MACHINE}"

for f in cdboot cdbr; do
    echo "Downloading ${f}..."
    curl -sSf -o "${WORKDIR}/iso/${OSREV}/${MACHINE}/${f}" "${URL}/${f}"
done
for f in BOOTIA32.EFI BOOTX64.EFI bsd.rd ; do
    echo "Downloading ${f}..."
    curl -sSf -o "${WORKDIR}/${f}" "${URL}/${f}"
done

echo "Creating custom bsd.rd..."
zcat "${WORKDIR}/bsd.rd" > "${WORKDIR}/bsd.urd"
rdsetroot -x "${WORKDIR}/bsd.urd" "${WORKDIR}/bsd.fs"
vnconfig vnd0 "${WORKDIR}/bsd.fs"
mount /dev/vnd0a "${WORKDIR}/mount"
install -m 0644 auto_install.conf "${WORKDIR}/mount/auto_install.conf"
install -m 0644 autopart.conf "${WORKDIR}/mount/autopart.conf"
umount "${WORKDIR}/mount"
rdsetroot "${WORKDIR}/bsd.urd" "${WORKDIR}/bsd.fs"
compress -9 < "${WORKDIR}/bsd.urd" > "${WORKDIR}/iso/${OSREV}/${MACHINE}/bsd.rd"

echo "Create boot.conf..."
mkdir "${WORKDIR}/iso/etc"
{
    echo "set tty com0"
    echo "set image /${OSREV}/${MACHINE}/bsd.rd"
    echo "boot"
} > "${WORKDIR}/iso/etc/boot.conf"

echo "Creating eficdboot..."
mkdir -p "${WORKDIR}/eficdboot-dir/efi/boot"
cp "${WORKDIR}/BOOTIA32.EFI" "${WORKDIR}/BOOTX64.EFI" \
    "${WORKDIR}/eficdboot-dir/efi/boot/"
makefs -t msdos -o create_size=350K \
    "${WORKDIR}/iso/${OSREV}/${MACHINE}/eficdboot" "${WORKDIR}/eficdboot-dir"

echo "Creating iso image..."
mkhybrid -a -R -T -L -l -d -D -N -o openbsd-autoinstall.iso \
    -A "OpenBSD ${OSREV} ${MACHINE} Autoinstall CD" \
    -P "Copyright (c) `date +%Y` The OpenBSD project" \
    -p "Timo Maekinen <tmakinen@foo.sh>" \
    -V "OpenBSD/${MACHINE}   ${OSREV} Install CD" \
    -b "${OSREV}/${MACHINE}/cdbr" -c "${OSREV}/${MACHINE}boot.catalog" \
    -e "${OSREV}/${MACHINE}/eficdboot" \
    "${WORKDIR}/iso"
