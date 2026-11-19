#!/bin/bash
# ============================================================================
# Inventario del sistema origen (RHEL 5.1). Compatible con bash 3.2.
#
# Uso: inventario.sh > inventario-<momento>.txt
#
# Se corre antes de la migración (evidencia/antes/), en el ECS final
# (evidencia/despues/) y en la vuelta atrás. Las salidas se comparan con diff:
# todo lo que no sea fecha, tiempo de actividad o nombres de dispositivo
# (sdX -> vdX) debe coincidir.
# ============================================================================
export LANG=C LC_ALL=C
PATH=/sbin:/usr/sbin:/bin:/usr/bin

seccion() {
  echo
  echo "=== $1 ==="
}

ejecutar() {
  seccion "$*"
  "$@" 2>&1
}

seccion "fecha"
date -u '+%Y-%m-%dT%H:%M:%SZ'

ejecutar hostname
ejecutar uname -a
ejecutar cat /etc/redhat-release
ejecutar rpm -q kernel redhat-release glibc lvm2 mkinitrd grub
seccion "paquetes (cantidad y SHA-256 de la lista ordenada)"
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /tmp/rpm-qa.$$
wc -l < /tmp/rpm-qa.$$
sha256sum < /tmp/rpm-qa.$$ | cut -d' ' -f1
rm -f /tmp/rpm-qa.$$

ejecutar fdisk -l
ejecutar pvs
ejecutar vgs
ejecutar lvs
ejecutar df -hP -x tmpfs
ejecutar cat /etc/fstab
ejecutar cat /boot/grub/grub.conf
ejecutar ls -l /boot
ejecutar lsmod
ejecutar cat /etc/modprobe.conf

seccion "red"
for f in /etc/sysconfig/network /etc/sysconfig/network-scripts/ifcfg-eth*; do
  echo "--- $f"
  cat "$f"
done
ejecutar ifconfig -a
ejecutar route -n
ejecutar cat /etc/resolv.conf

ejecutar chkconfig --list
ejecutar cat /etc/lvm/lvm.conf

seccion "datos de prueba (verificación contra el manifiesto)"
if [ -f /datos/prueba/SHA256SUMS ]; then
  (cd /datos/prueba && sha256sum -c SHA256SUMS 2>&1 | grep -c ': OK$' | sed 's/$/ archivos OK/'
   sha256sum -c SHA256SUMS 2>&1 | grep -v ': OK$' || true)
else
  echo "sin /datos/prueba/SHA256SUMS"
fi
