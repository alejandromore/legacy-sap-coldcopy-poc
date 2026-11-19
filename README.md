# legacy-sap-coldcopy-poc

Prueba de concepto para migrar servidores SAP R/3 sobre **RHEL 5.1** desde VMware a **Huawei Cloud** (`la-south-2`) en frío: exportación OVF, subida a un bucket **OBS** privado, escritura en discos EVS con `qemu-img` desde un ECS receptor sin IP pública, y verificación SHA-256 origen = destino. Sin usar el servicio SMS.

- Guía de implementación (producción: GesNet, Huawei, Integratel): [IMPLEMENTATION-GUIDE.md](IMPLEMENTATION-GUIDE.md)
- Plan y estado de la PoC: [PLAN.md](PLAN.md)
- Acta de la variante A: [evidencia/acta-A.md](evidencia/acta-A.md)
- Diagrama: [doc/diagrama-migracion-rhel51.jpg](doc/diagrama-migracion-rhel51.jpg)
- Prompt del diagrama: [doc/prompt-diagrama-migracion-rhel51.txt](doc/prompt-diagrama-migracion-rhel51.txt)
