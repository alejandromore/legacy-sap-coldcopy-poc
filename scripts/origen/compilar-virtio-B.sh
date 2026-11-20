#!/bin/bash
# ============================================================================
# Variante B, paso 1: compilar kmod-virtio para 2.6.18-53.el5 en un CLON
# AISLADO del servidor (nunca en el productivo: aquí se instalan gcc y fuentes).
#
# Insumos en /root/virtio-B:
#   kernel-2.6.18-128.el5.src.rpm   (fuentes de RHEL 5.3, donde Red Hat
#                                    incorporó VirtIO)
#   kcompat.h                        (scripts/origen/kmod-virtio/kcompat.h)
# Repositorio: el DVD de RHEL 5.1 conectado al clon (gcc, kernel-devel-53,
# rpm-build y dependencias).
#
# Resultado: /root/virtio-B/kmod/*.ko y SHA256SUMS, listos para copiar al
# servidor con preparar-virtio-B.sh.
# Compatible con bash 3.2.
# ============================================================================
set -e
export LANG=C LC_ALL=C
PATH=/sbin:/usr/sbin:/bin:/usr/bin

DIR=/root/virtio-B
KVER=2.6.18-53.el5

# 1. Herramientas desde el DVD, con rpm (el yum de 5.1 no lee el DVD como
#    repositorio: "unknown url type: media"). Firmas de Red Hat verificadas.
mkdir -p /media/dvd
mountpoint -q /media/dvd || mount -o ro /dev/hdd /media/dvd 2>/dev/null || mount -o ro /dev/hdc /media/dvd
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
D=/media/dvd/Server
files=""
for p in gcc cpp libgomp glibc-devel glibc-headers kernel-headers kernel-devel rpm-build \
         redhat-rpm-config elfutils elfutils-libs unifdef; do
  rpm -q $p >/dev/null 2>&1 && continue
  f=$(ls $D/$p-[0-9]*.x86_64.rpm $D/$p-[0-9]*.noarch.rpm 2>/dev/null | head -1)
  [ -n "$f" ] && files="$files $f"
done
[ -n "$files" ] && rpm -Uvh $files
rpm -q gcc kernel-devel-$KVER rpm-build

# 2. Fuentes de RHEL 5.3 con los parches de Red Hat aplicados
cd "$DIR"
rpm -ivh kernel-2.6.18-128.el5.src.rpm 2>/dev/null || true
rpmbuild -bp --nodeps --target=x86_64 /usr/src/redhat/SPECS/kernel-2.6.spec >rpmbuild-bp.log 2>&1
SRC=$(ls -d /usr/src/redhat/BUILD/kernel-2.6.18/linux-2.6.18*.x86_64 | head -1)
echo "Fuentes 5.3: $SRC"

# 3. Copia aislada de los drivers VirtIO
rm -rf kmod && mkdir -p kmod/include/linux
cp "$SRC"/drivers/virtio/virtio.c "$SRC"/drivers/virtio/virtio_ring.c \
   "$SRC"/drivers/virtio/virtio_pci.c "$SRC"/drivers/block/virtio_blk.c \
   "$SRC"/drivers/net/virtio_net.c kmod/
cp "$SRC"/include/linux/virtio*.h kmod/include/linux/
ls kmod kmod/include/linux

# kcompat.h (scripts/origen/kmod-virtio/kcompat.h) cubre lo que la API de
# 2.6.18-53 no tiene: bool/true/false y uninitialized_var. Las fuentes de
# Red Hat no se modifican. Debe copiarse antes a $DIR/kcompat.h.
cp "$DIR"/kcompat.h kmod/kcompat.h
cat > kmod/Makefile <<'EOF'
obj-m := virtio.o virtio_ring.o virtio_pci.o virtio_blk.o virtio_net.o
EXTRA_CFLAGS += -I$(M)/include -include $(M)/kcompat.h
EOF

# 4. Compilar contra el kernel 2.6.18-53.el5
make -C /lib/modules/$KVER/build M=$DIR/kmod modules 2>&1 | tee compilar.log
cd kmod && sha256sum *.ko | tee SHA256SUMS
for m in *.ko; do echo "== $m"; /sbin/modinfo "$m" | grep -E '^(vermagic|depends)'; done

# 5. Prueba de carga en el kernel destino: sin símbolos sin resolver
[ "$(uname -r)" = "$KVER" ] && {
  for m in virtio virtio_ring virtio_pci virtio_blk virtio_net; do /sbin/insmod ./$m.ko; done
  /sbin/lsmod | grep virtio
  for m in virtio_net virtio_blk virtio_pci virtio_ring virtio; do /sbin/rmmod $m; done
}
