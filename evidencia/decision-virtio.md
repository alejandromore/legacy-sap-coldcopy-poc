# Decisión: variante VirtIO para la migración de RHEL 5.1

Fecha: 2026-11-20. Base: [`acta-A.md`](acta-A.md) y [`acta-B.md`](acta-B.md). Criterios y pesos: [`doc/PLAN.md` §5](../doc/PLAN.md).

Las dos variantes migraron el mismo RHEL 5.1 oficial por el mismo camino (OVF → OBS → receptor → EVS → ECS final) y **pasaron todos los criterios del acta**:

- SHA-256 igual;
- arranque;
- misma IP;
- 18 archivos de prueba OK;
- 5 reinicios;
- escritura sostenida;
- vuelta atrás.

La elección se decide por los criterios cualitativos:

- **Variante A:** kernel adicional `2.6.18-419.el5`.
- **Variante B:** kernel original `2.6.18-53.el5` + `kmod-virtio`.

## Evaluación por criterio

| Criterio | Peso | A | B | Mejor |
|---|---|---|---|---|
| Arranca en el ECS y ve discos y red | Excluyente | Sí | Sí | Empate |
| Estabilidad (5 reinicios, `dd`, `dmesg`) | Alto | 5/5 en ~50 s; escritura 264/261 MB/s, lectura 255/226 MB/s; 0 errores | 5/5 en ~50 s; escritura 255/254 MB/s, lectura 222/214 MB/s; 0 errores | Empate (diferencias dentro del ruido de una medición) |
| Defendible ante cumplimiento | Alto | Binario **firmado por el fabricante** (en producción, paquete de Red Hat con la suscripción del cliente). Kernel de una versión menor posterior de la misma versión mayor | Módulos **compilados por el integrador** a partir de fuentes de Red Hat sin modificar, más un header de compatibilidad de 2 definiciones. El kernel que corre es **exactamente el certificado** del servidor | **A**, si el cumplimiento exige binarios del fabricante. **B**, si exige no cambiar el kernel |
| Cambios en el sistema | Medio | Paquete nuevo (408 → 410 paquetes), 1 292 archivos de módulos, kernel e initrd nuevos en `/boot` y 4 archivos de configuración | 5 `.ko`, índices `depmod`, 1 initrd paralelo y 4 archivos de configuración. **Paquetes idénticos** a la línea base (408, mismo hash) | **B** |
| Reversibilidad | Medio | Entrada original intacta; vuelta atrás probada | Entrada original intacta; vuelta atrás probada | Empate |
| Esfuerzo para 4 servidores | Medio | Instalar 1 RPM + script por servidor. Requiere obtener el paquete de Red Hat | Compilar **una vez** (si los 4 servidores tienen exactamente `2.6.18-53.el5`) y copiar 5 archivos + script por servidor. Requiere un clon de compilación una vez | Empate |

## Recomendación

**Variante A como opción principal, variante B como alternativa validada.**

- Con los pesos del plan, el único criterio de peso alto que diferencia a las variantes es **"defendible ante cumplimiento"**. Ahí gana A: el binario lo firma Red Hat, y en una auditoría alcanza con mostrar el paquete y su firma. B requiere explicar y conservar la cadena de compilación (fuentes, header de compatibilidad, `SHA256SUMS` de los `.ko`).
- **B es preferible** en cualquiera de estos casos:
  - el cliente no puede obtener `kernel-2.6.18-419.el5` de Red Hat (suscripción sin acceso a RHEL 5.11);
  - SAP u Oracle exigen mantener **el mismo kernel** certificado del servidor;
  - el auditor prioriza "**no se instaló ningún paquete**" por sobre el origen del binario.
- Las dos se aplican igual en la ventana (un script, entrada de GRUB paralela, vuelta atrás con la entrada original) y producen la misma evidencia.

**Decisión final:** la toma **Integratel** con su área de cumplimiento, a la luz de este cuadro. Se registra aquí:

- [ ] Variante A — aprobada por: ____________ fecha: ________
- [ ] Variante B — aprobada por: ____________ fecha: ________

## Requisitos previos según la variante elegida

| Variante | Requisito para producción |
|---|---|
| A | Descargar `kernel-2.6.18-419.el5.x86_64.rpm` del portal de Red Hat con la suscripción del cliente y verificar la firma con `RPM-GPG-KEY-redhat-release`. En laboratorio se usó el rebuild de CentOS 5.11, con firma de CentOS verificada |
| B | Confirmar que cada servidor corre exactamente `2.6.18-53.el5` (`uname -r`); si alguno difiere, compilar para ese kernel. Conservar `kcompat.h`, el script de compilación y `SHA256SUMS` de los `.ko` como evidencia de auditoría |
