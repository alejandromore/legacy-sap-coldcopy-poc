#!/usr/bin/env python3
# ============================================================================
# Fase 6: arma el ECS SAP final con los EVS copiados.
#
#   1. Verifica que el ECS final esté apagado.
#   2. Desconecta su disco de sistema provisorio (el que creó Terraform).
#   3. Conecta el EVS "sistema" como disco de sistema (/dev/vda) y los demás
#      EVS como discos de datos, en el orden del origen.
#   4. Borra el disco provisorio (vacío, ya no lo referencia nada).
#   5. Enciende el ECS.
#
# Uso: armar-final.py <nombre-ecs-final> <evs-sistema-id> [<evs-datos-id> ...]
# Credenciales: HW_ACCESS_KEY / HW_SECRET_KEY (y HW_SECURITY_TOKEN si son
# temporales, como en GitHub Actions con OIDC).
# ============================================================================
import os
import sys
import time

from huaweicloudsdkcore.auth.credentials import BasicCredentials
import huaweicloudsdkecs.v2 as ecs
from huaweicloudsdkecs.v2.region.ecs_region import EcsRegion
import huaweicloudsdkevs.v2 as evs
from huaweicloudsdkevs.v2.region.evs_region import EvsRegion

REGION = os.environ.get("HW_REGION", "la-south-2")


def cred():
    c = BasicCredentials(os.environ["HW_ACCESS_KEY"], os.environ["HW_SECRET_KEY"])
    if os.environ.get("HW_SECURITY_TOKEN"):
        c = c.with_security_token(os.environ["HW_SECURITY_TOKEN"])
    return c


E = ecs.EcsClient.new_builder().with_credentials(cred()).with_region(EcsRegion.value_of(REGION)).build()
V = evs.EvsClient.new_builder().with_credentials(cred()).with_region(EvsRegion.value_of(REGION)).build()


def esperar_job(job_id, que):
    while True:
        j = E.show_job(ecs.ShowJobRequest(job_id=job_id))
        if j.status == "SUCCESS":
            print("  %s: listo" % que)
            return
        if j.status == "FAIL":
            raise RuntimeError("%s falló: %s" % (que, j.fail_reason))
        time.sleep(5)


def esperar_estado(server_id, estado):
    while True:
        s = E.show_server(ecs.ShowServerRequest(server_id=server_id)).server
        if s.status == estado:
            return s
        time.sleep(5)


def main():
    nombre, sistema, datos = sys.argv[1], sys.argv[2], sys.argv[3:]
    srv = [s for s in E.list_servers_details(ecs.ListServersDetailsRequest(name=nombre)).servers if s.name == nombre]
    if len(srv) != 1:
        sys.exit("No encuentro un único ECS llamado %s" % nombre)
    srv = srv[0]
    print("ECS final %s (%s)" % (srv.id, srv.status))
    if srv.status != "SHUTOFF":
        sys.exit("El ECS final debe estar apagado")

    # En flavors KVM el disco de sistema es /dev/vda y los de datos /dev/vdb...
    # (/dev/sda responde "device is illegal").
    discos = E.list_server_block_devices(ecs.ListServerBlockDevicesRequest(server_id=srv.id)).volume_attachments
    sistema_ok = any(d.volume_id == sistema and d.boot_index == 0 for d in discos)
    provisorio = None
    if not sistema_ok:
        # Se desconecta todo lo que no sea el EVS de sistema (el disco
        # provisorio y discos de datos conectados antes de tiempo) para que el
        # de sistema entre primero.
        for d in discos:
            if d.boot_index == 0 and d.volume_id not in datos:
                provisorio = d.volume_id
            print("1. Desconectar %s (%s)" % (d.volume_id, d.device))
            r = E.detach_server_volume(ecs.DetachServerVolumeRequest(server_id=srv.id, volume_id=d.volume_id))
            esperar_job(r.job_id, "desconexión")
        print("2. Conectar el EVS de sistema %s como /dev/vda" % sistema)
        body = ecs.AttachServerVolumeRequestBody(volume_attachment=ecs.AttachServerVolumeOption(volume_id=sistema, device="/dev/vda"))
        esperar_job(E.attach_server_volume(ecs.AttachServerVolumeRequest(server_id=srv.id, body=body)).job_id, "disco de sistema")

    conectados = {d.volume_id for d in E.list_server_block_devices(ecs.ListServerBlockDevicesRequest(server_id=srv.id)).volume_attachments}
    for i, vid in enumerate(datos):
        if vid in conectados:
            continue
        dev = "/dev/vd" + "bcdefghij"[i]
        print("3. Conectar el EVS de datos %s como %s" % (vid, dev))
        body = ecs.AttachServerVolumeRequestBody(volume_attachment=ecs.AttachServerVolumeOption(volume_id=vid, device=dev))
        esperar_job(E.attach_server_volume(ecs.AttachServerVolumeRequest(server_id=srv.id, body=body)).job_id, "disco de datos")

    if provisorio:
        print("4. Borrar el disco provisorio %s" % provisorio)
        V.delete_volume(evs.DeleteVolumeRequest(volume_id=provisorio))

    print("5. Encender el ECS final")
    body = ecs.BatchStartServersRequestBody(os_start=ecs.BatchStartServersOption(servers=[ecs.ServerId(id=srv.id)]))
    esperar_job(E.batch_start_servers(ecs.BatchStartServersRequest(body=body)).job_id, "encendido")
    esperar_estado(srv.id, "ACTIVE")
    for d in E.list_server_block_devices(ecs.ListServerBlockDevicesRequest(server_id=srv.id)).volume_attachments:
        print("  %s boot_index=%s %s" % (d.device, d.boot_index, d.volume_id))


if __name__ == "__main__":
    main()
