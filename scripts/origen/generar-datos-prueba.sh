#!/bin/bash
# ============================================================================
# Datos de prueba en el disco LVM de datos (/datos). Sustituyen a la base de
# datos y a los reportes SAP del acta: si después de la migración sus SHA-256
# coinciden con el manifiesto, el contenido del volumen llegó intacto.
#
#   /datos/prueba/binarios/   archivos aleatorios de varios tamaños ("datafiles")
#   /datos/prueba/tablas/     CSV con filas numeradas ("tablas") y sus conteos
#   /datos/prueba/SHA256SUMS  manifiesto de todo lo anterior
#
# Uso: generar-datos-prueba.sh [MB_TOTALES]   (por defecto 1024)
# Compatible con bash 3.2. No sobreescribe: falla si ya existe /datos/prueba.
# ============================================================================
set -e
export LANG=C LC_ALL=C
PATH=/sbin:/usr/sbin:/bin:/usr/bin

DEST=/datos/prueba
TOTAL_MB=${1:-1024}

if [ -e "$DEST" ]; then
  echo "Ya existe $DEST; no se regenera (cambiaría la línea base)" >&2
  exit 1
fi
mkdir -p "$DEST/binarios" "$DEST/tablas"

# Binarios: tamaños de 1 MB hasta ~TOTAL_MB/4, hasta completar el total.
restante=$TOTAL_MB
n=1
tam=1
while [ $restante -gt 0 ]; do
  [ $tam -gt $restante ] && tam=$restante
  dd if=/dev/urandom of="$DEST/binarios/datafile-$(printf '%03d' $n).dbf" bs=1M count=$tam 2>/dev/null
  restante=$((restante - tam))
  n=$((n + 1))
  tam=$((tam * 2))
  [ $tam -gt $((TOTAL_MB / 4)) ] && tam=$((TOTAL_MB / 4))
  [ $tam -lt 1 ] && tam=1
done

# Tablas: CSV deterministas con conteo conocido.
: > "$DEST/tablas/conteos.txt"
for t in MARA VBAK VBAP BKPF BSEG; do
  filas=$(( (RANDOM % 50000) + 10000 ))
  awk -v t=$t -v n=$filas 'BEGIN { for (i = 1; i <= n; i++) printf "%s,%08d,%d\n", t, i, (i * 7919) % 100003 }' > "$DEST/tablas/$t.csv"
  echo "$t $(wc -l < "$DEST/tablas/$t.csv")" >> "$DEST/tablas/conteos.txt"
done

sync
cd "$DEST"
find binarios tablas -type f | sort | xargs sha256sum > SHA256SUMS
sync

echo "Archivos: $(wc -l < SHA256SUMS)"
du -sh "$DEST"
cat tablas/conteos.txt
