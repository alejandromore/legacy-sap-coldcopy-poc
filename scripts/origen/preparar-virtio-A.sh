#!/bin/bash
# ============================================================================
# Variante A: kernel adicional 2.6.18-419.el5 (serie 5.11) con VirtIO.
#
# Requisitos (en /root/virtio-A):
#   kernel-2.6.18-419.el5.x86_64.rpm  (laboratorio: rebuild CentOS 5.11;
#                                      producción: paquete de Red Hat)
#   RPM-GPG-KEY-CentOS-5              (clave con la que se verifica el RPM)
#
# Qué hace (la entrada original 2.6.18-53.el5 sigue siendo la predeterminada):
#   1. Respalda los archivos que toca en /root/virtio-A/respaldo/.
#   2. Verifica la firma e instala el kernel sin cambiar el predeterminado.
#   3. Preparación común: lvm.conf con virtblk, ifcfg-eth0 sin HWADDR,
#      kudzu desactivado.
#   4. Rehace el initrd del kernel nuevo con virtio_pci y virtio_blk (más el
#      driver SCSI de VMware, que mkinitrd agrega solo), para que arranque
#      tanto en VMware como en el ECS.
#   5. Renombra la entrada de GRUB del kernel nuevo y le agrega consola serie.
#
# Compatible con bash 3.2. Se puede volver a correr: no duplica cambios.
# ============================================================================
set -e
export LANG=C LC_ALL=C
PATH=/sbin:/usr/sbin:/bin:/usr/bin

DIR=/root/virtio-A
KVER=2.6.18-419.el5
RPM=$DIR/kernel-$KVER.x86_64.rpm
TITULO="RHEL 5.1 - kernel $KVER VirtIO (Huawei Cloud)"
EXTRA="console=ttyS0,115200 console=tty0 clocksource=acpi_pm"

cd "$DIR"

# 1. Respaldo (solo la primera vez)
if [ ! -d respaldo ]; then
  mkdir respaldo
  cp -p /boot/grub/grub.conf /etc/lvm/lvm.conf /etc/sysconfig/kernel \
        /etc/sysconfig/network-scripts/ifcfg-eth0 respaldo/
  chkconfig --list kudzu > respaldo/kudzu.chkconfig
fi

# 2. Kernel adicional, sin volverlo predeterminado
sed -i 's/^UPDATEDEFAULT=yes/UPDATEDEFAULT=no/' /etc/sysconfig/kernel
if ! rpm -q kernel-$KVER >/dev/null 2>&1; then
  rpm --import RPM-GPG-KEY-CentOS-5
  rpm -K "$RPM" | grep -q 'gpg OK' || { echo "Firma del RPM no válida" >&2; exit 1; }
  rpm -ivh "$RPM"
fi

# 3. Preparación común
grep -q 'virtblk' /etc/lvm/lvm.conf || \
  sed -i '/^devices {/a\    types = [ "virtblk", 16 ]' /etc/lvm/lvm.conf
sed -i '/^HWADDR=/d' /etc/sysconfig/network-scripts/ifcfg-eth0
chkconfig kudzu off

# 4. initrd con VirtIO
mkinitrd -f --with=virtio_pci --with=virtio_blk /boot/initrd-$KVER.img $KVER
zcat /boot/initrd-$KVER.img | cpio -t 2>/dev/null | grep -E 'virtio|mpt'

# 5. Entrada de GRUB del kernel nuevo
awk -v k="$KVER" -v t="$TITULO" -v x="$EXTRA" '
  /^title / { entrada = 0 }
  /^title / && index($0, k) { print "title " t; entrada = 1; next }
  entrada && /^[ \t]*kernel / && index($0, "console=") == 0 { print $0 " " x; next }
  { print }
' /boot/grub/grub.conf > /tmp/grub.conf.$$
cat /tmp/grub.conf.$$ > /boot/grub/grub.conf
rm -f /tmp/grub.conf.$$

echo "--- grub.conf"
grep -v '^#' /boot/grub/grub.conf
