# Acta de validación — variante A (kernel 2.6.18-419.el5 con VirtIO)

Fecha: 2026-11-19 (UTC). Laboratorio `legacy-sap-coldcopy-poc`, Huawei Cloud `la-south-2`, Enterprise Project `default`.

## 1. SHA-256 origen = SHA-256 destino

| Disco | Tamaño virtual | SHA-256 origen (contenido crudo) | SHA-256 destino (EVS) | Resultado |
|---|---|---|---|---|
| sistema | 12 GiB | `a1e6e6f00278e89cdcbd75744cb00b6b8b2d635e8fd3e4ab0fd56f86cf0dc94b` | `a1e6e6f00278e89cdcbd75744cb00b6b8b2d635e8fd3e4ab0fd56f86cf0dc94b` | **Idéntico** |
| datos | 4 GiB | `806971cad5b31f4bda511b702e5ed75ba742a191ba2b06e729fdac550ed8dc93` | `806971cad5b31f4bda511b702e5ed75ba742a191ba2b06e729fdac550ed8dc93` | **Idéntico** |

Cómo se obtuvo cada hash:

- **Origen:** `vmware-vdiskmanager -t 4` convierte cada VMDK exportado a una imagen cruda y se le calcula `sha256sum`. El mismo cálculo sobre los discos de la VM, antes de exportar, da el mismo valor: la exportación OVF no cambió ningún byte.
- **Destino:** el agente del receptor calcula el SHA-256 de cada EVS sobre exactamente el tamaño virtual del disco de origen. El EVS puede ser mayor. Resultados: [`virtio-A/resultado-receptor.json`](virtio-A/resultado-receptor.json) y [`virtio-A/resultado-receptor-ecs.json`](virtio-A/resultado-receptor-ecs.json).

### Integridad de la transferencia (archivo VMDK)

| Archivo | SHA-256 en el notebook | SHA-256 descargado en el receptor |
|---|---|---|
| `rhel51-origen-disk1.vmdk` (467 MB) | `aa44053423840351b758c3a0f3f8a55f0ecc015cccba9bcc5bd716160e51afb8` | igual |
| `rhel51-origen-disk2.vmdk` (1.08 GB) | `427c89a239a511108ca67a492cba8ddb668bd3c0ef91d4f33057780ca2d4694c` | igual |

## 2. Recorrido del disco

1. `rhel51-origen` (RHEL 5.1 oficial) con la variante A aplicada. Se puso la entrada VirtIO como predeterminada y se apagó (snapshot `virtio-A-export`).
2. Exportación OVF con `ovftool` 9.1.1: un VMDK por disco, en 2 min.
3. Subida a `obs-legacy-coldcopy-vmdk/incoming/virtio-A/` con `obsutil` 5.8.9. Se usó una credencial temporal reducida a `PutObject` en `incoming/`: 1.55 GB en 78 s (≈ 20 MB/s, ≈ 71 GB/h). La misma credencial recibió **403** al listar, al leer y al escribir fuera de `incoming/`.
4. ECS receptor sin EIP: descarga por la red interna, a ≈ 80–90 MB/s.
   - Escribe con el conversor propio, porque `qemu-img` no se pudo instalar sin Internet.
   - Calcula el SHA-256 de cada EVS.
5. ECS SAP final: disco de sistema en `/dev/vda` y disco de datos en `/dev/vdb`, con la IP privada de origen `192.168.63.50`.
   - Arranca `2.6.18-419.el5` con `virtio_blk`.
   - Ve `vda: vda1 vda2` y `vdb: vdb1`, y monta la raíz ext3 sobre LVM (consola serie).

## 3. Hallazgos que cambian el procedimiento

| Hallazgo | Efecto | Ajuste |
|---|---|---|
| Huawei no acepta como disco de sistema un EVS creado vacío (`device is illegal`), ni siquiera marcándolo `bootable` | El EVS `sistema` no sirve como disco de sistema | El disco de sistema debe ser un EVS **creado desde una imagen**. El receptor lo pone en cero en el tramo del disco de origen y escribe encima. Aquí se reutilizó el disco de sistema original del ECS final. Hash verificado igual |
| En flavors KVM el disco de sistema se conecta como `/dev/vda` | `/dev/sda` es rechazado | `armar-final.py` usa `/dev/vda`, `/dev/vdb`… |
| La agencia del ECS no obtuvo acceso a OBS con un rol personalizado acotado al bucket | `AccessDenied` desde el receptor | Se usó `OBS OperateAccess`, que es más amplio. Pendiente acotarlo con una política de bucket |
| El receptor sin Internet no puede instalar `qemu-img` | — | El agente trae su propio conversor de VMDK streamOptimized, validado contra los hashes crudos |

## 4. Verificación del ECS final

El receptor entró por SSH al ECS final dentro de la VPC (simula el acceso de Integratel) y corrió el mismo [`inventario.sh`](../scripts/origen/inventario.sh) de la línea base: [`virtio-A/inventario-despues.txt`](virtio-A/inventario-despues.txt), diferencias en [`virtio-A/diff-antes-despues.txt`](virtio-A/diff-antes-despues.txt).

| Verificación | Antes (VMware) | Después (ECS) | Resultado |
|---|---|---|---|
| Kernel | `2.6.18-53.el5` | `2.6.18-419.el5` (entrada VirtIO) | Esperado |
| Discos | `sda` 12 GB, `sdb` 4 GB | `vda` 40 GB, `vdb` 10 GB, mismas particiones | OK |
| LVM | `VolGroup00` en `sda2`, `VolGroupDatos` en `sdb1` | `VolGroup00` en `vda2`, `VolGroupDatos` en `vdb1`, mismos LV y tamaños | OK |
| Montajes | `/`, `/boot`, `/datos` | `/`, `/boot`, `/datos` | OK |
| `fstab` | — | idéntico | OK |
| Red | `eth0` 192.168.63.50, gateway .2 | `eth0` 192.168.63.50 (`virtio_net`), gateway .2, SSH desde la VPC | OK, **misma IP** |
| Paquetes | 408 | 410 (`kernel-2.6.18-419.el5` y la clave GPG importada) | Esperado |
| Datos de prueba (`/datos/prueba`, 1.1 GB) | 18 archivos | **18 archivos OK** contra `SHA256SUMS` | OK |
| Conteos de "tablas" | MARA 28145, VBAK 31539, VBAP 22663, BKPF 27564, BSEG 30261 | incluidos en los 18 archivos verificados | OK |

## 5. Criterios de éxito (variante A)

- [x] RHEL 5.1 arranca en el ECS final.
- [x] SHA-256 origen = SHA-256 destino en el 100 % de los discos.
- [x] La credencial de subida solo puede subir; el bucket es privado y cifrado.
- [x] Ningún ECS tuvo IP pública; el receptor leyó OBS por la red interna.
- [x] LVM, montajes y red operativos en el ECS final, con la misma IP que en VMware.
- [x] Los SHA-256 de los archivos de prueba coinciden con la línea base.
- [ ] Vuelta atrás en VMware (Fase 8).
- [ ] Estabilidad: 5 reinicios y escritura sostenida (criterio de elección, §5).

## 6. Tiempos medidos

| Tramo | Volumen | Tiempo | Velocidad |
|---|---|---|---|
| Exportación OVF (notebook) | 16 GiB virtuales → 1.55 GB | 2 min 5 s | — |
| Subida a OBS (Internet del notebook) | 1.55 GB | 78 s | ≈ 20 MB/s (≈ 71 GB/h) |
| Descarga OBS → receptor (red interna) | 1.55 GB | 17.7 s | ≈ 88 MB/s |
| Escritura en EVS (conversor) | 16 GiB virtuales | 10.7 s | — (solo grains con datos) |
| SHA-256 de los EVS | 16 GiB | 72 s | ≈ 240 MB/s |

Nota: un receptor recreado intentó reprocesar `virtio-A` antes de que el agente revisara `resultados/` y dejó `resultados/virtio-A/error.json` sin escribir nada: el EVS ya no estaba conectado. Desde entonces el agente se salta toda variante con `resultado.json` publicado.
