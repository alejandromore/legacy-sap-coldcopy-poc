# Acta de validación — variante B (kernel original 2.6.18-53.el5 + kmod-virtio)

Fecha: 2026-11-20 (UTC). Laboratorio `legacy-sap-coldcopy-poc`, Huawei Cloud `la-south-2`, Enterprise Project `default`.

## 1. SHA-256 origen = SHA-256 destino

| Disco | Tamaño virtual | SHA-256 origen (contenido crudo) | SHA-256 destino (EVS) | Resultado |
|---|---|---|---|---|
| sistema | 12 GiB | `a5c7d64e825b0621cfd82687468497985500a5135c7444dff3d9ebbd99c498f1` | `a5c7d64e825b0621cfd82687468497985500a5135c7444dff3d9ebbd99c498f1` | **Idéntico** |
| datos | 4 GiB | `2817d20c80921457cf5dbd861fa59dde5920693982918e1a62b0f5830b27b057` | `2817d20c80921457cf5dbd861fa59dde5920693982918e1a62b0f5830b27b057` | **Idéntico** |

Fuente: [`virtio-B/resultado-receptor.json`](virtio-B/resultado-receptor.json).

- El disco de sistema se escribió sobre un EVS **creado desde imagen**, que el receptor puso en cero antes de escribir (`limpiar`, 49 s para 12 GiB). Este es el procedimiento corregido después de la variante A, y aquí se usó por primera vez de punta a punta.
- El hash del disco de datos difiere del de la variante A. Es esperable: cada arranque de la VM actualiza los metadatos ext3 de `/datos` (contador y fecha de montaje). Lo que se compara es origen contra destino de la misma exportación.

### Integridad de la transferencia (archivo VMDK)

| Archivo | SHA-256 en el notebook | SHA-256 descargado en el receptor |
|---|---|---|
| `rhel51-origen-disk1.vmdk` (415 MB) | `0c0f35d824be50ce46573f186a2a7c8fdcc81e78524209d7e81c5ad86f869a9f` | igual |
| `rhel51-origen-disk2.vmdk` (1.08 GB) | `0845d9cd4c805315100d54640a7de7eb28a6f909208b1d9a773b69c33eb183de` | igual |

## 2. Cómo se construyó la variante B

1. **Compilación en un clon aislado** (`rhel51-build`, clon enlazado de `linea-base`). Así el servidor nunca tuvo `gcc` ni fuentes.
   - Herramientas del DVD de RHEL 5.1, con firma de Red Hat verificada.
   - Fuentes `kernel-2.6.18-128.el5.src.rpm` (RHEL 5.3) preparadas con `rpmbuild -bp`, es decir, con los parches de Red Hat.
   - Script: [`scripts/origen/compilar-virtio-B.sh`](../scripts/origen/compilar-virtio-B.sh).
2. **Backport mínimo.** Los cinco drivers (`virtio`, `virtio_ring`, `virtio_pci`, `virtio_blk`, `virtio_net`) compilan contra `kernel-devel-2.6.18-53.el5` **sin modificar las fuentes de Red Hat**. Basta un header de compatibilidad, [`kcompat.h`](../scripts/origen/kmod-virtio/kcompat.h), con dos definiciones que la API de `-53` no tiene: `bool`/`true`/`false` y `uninitialized_var`.
3. **Prueba de carga en `2.6.18-53.el5`.** Los cinco `insmod` funcionaron sin símbolos sin resolver y los `rmmod` fueron limpios. `vermagic`: `2.6.18-53.el5 SMP mod_unload gcc-4.1` ([`virtio-B/kmod-modinfo.txt`](virtio-B/kmod-modinfo.txt), [`virtio-B/kmod-SHA256SUMS`](virtio-B/kmod-SHA256SUMS)).
4. **Aplicación en el servidor** desde `linea-base`, con [`scripts/origen/preparar-virtio-B.sh`](../scripts/origen/preparar-virtio-B.sh) ([`virtio-B/preparar-virtio-B.txt`](virtio-B/preparar-virtio-B.txt)):
   - copia de los `.ko` verificados a `/lib/modules/2.6.18-53.el5/extra/virtio/` y `depmod`;
   - un initrd **paralelo** (`initrd-2.6.18-53.el5-virtio.img`) con `virtio_pci`, `virtio_blk` y `mptspi`;
   - una entrada de GRUB con el mismo kernel;
   - la preparación común.

   El kernel, su initrd original y los paquetes no se tocan.
5. **Prueba en VMware:** los dos arranques dan IP, 3 montajes, 0 errores y 18 archivos OK. Con la entrada nueva se cargan los módulos VirtIO junto a `mptspi`.
6. **Exportación:** con la entrada VirtIO como predeterminada (snapshot `virtio-B-export`), `ovftool` tardó 3 min 49 s.
7. **Subida:** a OBS con la credencial reducida, 1.5 GB en 26 s (≈ 58 MB/s, el doble que en la variante A por la conexión del día).
8. **Recepción:** en EVS por el receptor sin EIP; ver el §1.
9. **Armado del ECS final** con el workflow `ambiente` → `armar-final` (primera ejecución desde GitHub, con OIDC):
   - desconectó el disco provisorio;
   - conectó el EVS de sistema como `/dev/vda` y el de datos como `/dev/vdb`;
   - borró el provisorio y encendió el ECS.
10. **Arranque en el ECS** (consola serie): `Linux version 2.6.18-53.el5 (brewbuilder@...) 2007`, `vda: vda1 vda2`, `vdb: vdb1` y `EXT3-fs: mounted`. Es el kernel original de RHEL 5.1.

Cambios en el servidor respecto de `linea-base` ([`virtio-B/cambios.txt`](virtio-B/cambios.txt)):

- los 5 `.ko` y los índices de `depmod`;
- `lvm.conf`;
- `ifcfg-eth0`;
- `grub.conf`;
- el initrd paralelo.

El resto son archivos que el sistema actualiza solo al arrancar.

## 3. Verificación del ECS final

El receptor entró por SSH desde la VPC y corrió el inventario de la línea base ([`virtio-B/inventario-despues.txt`](virtio-B/inventario-despues.txt), [`virtio-B/diff-antes-despues.txt`](virtio-B/diff-antes-despues.txt)):

| Verificación | Antes (VMware) | Después (ECS) | Resultado |
|---|---|---|---|
| Kernel | `2.6.18-53.el5` | `2.6.18-53.el5` (**el mismo**), entrada kmod-virtio | OK |
| Paquetes | 408, hash `968f11a4…577b` | **408, mismo hash** | **Idénticos** |
| Discos | `sda` 12 GB, `sdb` 4 GB | `vda` 40 GB, `vdb` 10 GB, mismas particiones | OK |
| LVM | `VolGroup00` en `sda2`, `VolGroupDatos` en `sdb1` | en `vda2` y `vdb1`, mismos LV | OK |
| Montajes | `/`, `/boot`, `/datos` | `/`, `/boot`, `/datos` | OK |
| Red | `eth0` 192.168.63.50, gateway .2 | `eth0` 192.168.63.50 (`virtio_net`), gateway .2, SSH desde la VPC | OK, **misma IP** |
| Módulos | `mptspi` | `virtio`, `virtio_ring`, `virtio_pci`, `virtio_blk`, `virtio_net` (compilados) | OK |
| Datos de prueba | 18 archivos | **18 archivos OK** | OK |

## 4. Estabilidad en el ECS

El receptor ejecutó la prueba desde la VPC ([`virtio-B/estabilidad.txt`](virtio-B/estabilidad.txt)):

| Prueba | Resultado |
|---|---|
| 5 reinicios seguidos | Los 5 volvieron por SSH en ≈ 50 s. Cada vez: kernel `2.6.18-53.el5`, IP 192.168.63.50, 3 montajes, 0 errores en dmesg |
| Escritura sostenida `/` (`vda`, LVM) | 4 GiB a 255 MB/s (`conv=fsync`) |
| Lectura sostenida `/` | 4 GiB a 222 MB/s (caché vaciada) |
| Escritura sostenida `/datos` (`vdb`, LVM) | 2 GiB a 254 MB/s |
| Lectura sostenida `/datos` | 2 GiB a 214 MB/s |
| Datos de prueba después de todo | 18 OK |
| dmesg (I/O error, EXT3-fs error, Call Trace, BUG, soft lockup, virtio) | ninguno |

## 5. Vuelta atrás (Fase 8)

| Arranque en VMware | Kernel | Entrada | IP | Montajes | Errores en dmesg | Módulos VirtIO | Datos de prueba |
|---|---|---|---|---|---|---|---|
| Tal como quedó tras exportar | `2.6.18-53.el5` | kmod-virtio | 192.168.63.50 | 3 | 0 | 4 cargados | — |
| Entrada original | `2.6.18-53.el5` | original | 192.168.63.50 | 3 | 0 | 0 | **18 OK** |

Las diferencias con la línea base ([`virtio-B/diff-antes-vuelta-atras.txt`](virtio-B/diff-antes-vuelta-atras.txt)) son solo los cambios de la variante:

- la entrada de GRUB y el initrd paralelo;
- `virtblk` en `lvm.conf`;
- `ifcfg-eth0` sin `HWADDR`;
- `kudzu` desactivado.

El kernel y los paquetes no cambiaron.

## 6. Criterios de éxito (variante B)

- [x] RHEL 5.1 arranca en el ECS final, con su kernel original.
- [x] SHA-256 origen = SHA-256 destino en el 100 % de los discos.
- [x] La credencial de subida solo puede subir; el bucket es privado y cifrado.
- [x] Ningún ECS tuvo IP pública; el receptor leyó OBS por la red interna con la política del bucket (sin `OBS OperateAccess`).
- [x] LVM, montajes y red operativos en el ECS final, con la misma IP que en VMware.
- [x] Los SHA-256 de los archivos de prueba coinciden con la línea base.
- [x] Vuelta atrás en VMware: arranca con las dos entradas, 18 archivos OK.
- [x] Estabilidad: 5 reinicios sin errores y escritura y lectura sostenida de 6 GiB a más de 210 MB/s, sin errores en dmesg.

## 7. Cierre

`destroy` del ambiente ([run 44675992813](https://github.com/alejandromore/legacy-sap-coldcopy-poc/actions/runs/44675992813)): 14 recursos destruidos. Verificado en la API de Huawei: 0 ECS, 0 EVS y el bucket ya no existe. La llave de laboratorio estuvo en OBS solo durante la verificación y la estabilidad, y se borró al terminar.

## 8. Hallazgos nuevos

| Hallazgo | Ajuste |
|---|---|
| `obsutil -vmd5` falla siempre con el bucket cifrado (`VerifyMd5Error`): con SSE el ETag no es el MD5 | Se sube sin `-vmd5`; la verificación es el SHA-256 en el receptor. Corregido en la guía |
| El clon de compilación recibió otra MAC y `kudzu` reconfiguró `eth0` con DHCP | Solo afecta al clon; en el servidor `kudzu` queda desactivado por la preparación común |
