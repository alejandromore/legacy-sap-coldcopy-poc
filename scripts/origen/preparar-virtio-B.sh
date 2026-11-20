#!/bin/bash
# ============================================================================
# Variante B, paso 2: aplicar kmod-virtio en el servidor (2.6.18-53.el5).
#
# Requisitos (en /root/virtio-B/kmod): los .ko y SHA256SUMS producidos por
# compilar-virtio-B.sh en el clon aislado. En el servidor NO se instala gcc
# ni fuentes: solo se copian los módulos.
#
# Qué hace (la entrada original sigue siendo la predeterminada):
#   1. Respalda los archivos que toca en /root/virtio-B/respaldo/.
#   2. Verifica los SHA-256 de los .ko y los copia a
#      /lib/modules/2.6.18-53.el5/extra/virtio/ (depmod).
#   3. Preparación común: lvm.conf con virtblk, ifcfg-eth0 sin HWADDR,
#      kudzu desactivado.
#   4. Arma un initrd PARALELO (initrd-2.6.18-53.el5-virtio.img) con
#      virtio_pci y virtio_blk, más el driver SCSI de VMware. El initrd
#      original no se toca.
#   5. Agrega una entrada de GRUB con el mismo kernel y el initrd VirtIO,
#      con consola serie.
#
# Compatible con bash 3.2. Se puede volver a correr: no duplica cambios.
# ============================================================================
set -e
export LANG=C LC_ALL=C
PATH=/sbin:/usr/sbin:/bin:/usr/bin

DIR=/root/virtio-B
KVER=2.6.18-53.el5
DEST=/lib/modules/$KVER/extra/virtio
INITRD=/boot/initrd-$KVER-virtio.img
TITULO="RHEL 5.1 - kernel $KVER + kmod-virtio (Huawei Cloud)"
EXTRA="console=ttyS0,115200 console=tty0 clocksource=acpi_pm"

cd "$DIR"

# 1. Respaldo (solo la primera vez)
if [ ! -d respaldo ]; then
  mkdir respaldo
  cp -p /boot/grub/grub.conf /etc/lvm/lvm.conf /etc/sysconfig/network-scripts/ifcfg-eth0 respaldo/
  chkconfig --list kudzu > respaldo/kudzu.chkconfig
fi

# 2. Módulos verificados
(cd kmod && sha256sum -c SHA256SUMS)
mkdir -p "$DEST"
cp kmod/virtio.ko kmod/virtio_ring.ko kmod/virtio_pci.ko kmod/virtio_blk.ko kmod/virtio_net.ko "$DEST"/
depmod -a $KVER
modinfo -F vermagic "$DEST"/virtio_blk.ko

# 3. Preparación común
grep -q 'virtblk' /etc/lvm/lvm.conf || \
  sed -i '/^devices {/a\    types = [ "virtblk", 16 ]' /etc/lvm/lvm.conf
sed -i '/^HWADDR=/d' /etc/sysconfig/network-scripts/ifcfg-eth0
chkconfig kudzu off

# 4. initrd paralelo con VirtIO
mkinitrd -f --with=virtio_pci --with=virtio_blk "$INITRD" $KVER
zcat "$INITRD" | cpio -t 2>/dev/null | grep -E 'virtio|mpt'

# 5. Entrada de GRUB (al principio de la lista; el default se ajusta abajo)
if ! grep -q "kmod-virtio" /boot/grub/grub.conf; then
  awk -v t="$TITULO" -v k="$KVER" -v x="$EXTRA" -v i="$(basename $INITRD)" '
    !hecho && /^title / {
      print "title " t
      print "\troot (hd0,0)"
      print "\tkernel /vmlinuz-" k " ro root=/dev/VolGroup00/LogVol00 " x
      print "\tinitrd /" i
      hecho = 1
    }
    { print }
  ' /boot/grub/grub.conf > /tmp/grub.conf.$$
  # La entrada nueva desplaza a las demás una posición: el default original
  # se corre en 1 para que siga apuntando al mismo kernel.
  awk '/^default=/ { split($0, a, "="); print "default=" a[2] + 1; next } { print }' /tmp/grub.conf.$$ > /boot/grub/grub.conf
  rm -f /tmp/grub.conf.$$
fi

echo "--- grub.conf"
grep -v '^#' /boot/grub/grub.conf
