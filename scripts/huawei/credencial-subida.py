#!/usr/bin/env python3
# ============================================================================
# Credencial temporal de subida para "GesNet" (Fase 4).
#
# Emite un AK/SK temporal + security token con una política reducida a
# subir objetos en <bucket>/incoming/ (PutObject y multipart). No puede
# listar, leer ni escribir fuera de incoming/ (probado: 403).
#
# Escribe un archivo de configuración de obsutil listo para usar:
#   obsutil cp <archivo> obs://<bucket>/incoming/<variante>/ -config=<archivo>
#
# Uso:  credencial-subida.py <bucket> <archivo-config-obsutil> [segundos]
# Credenciales del emisor: HW_ACCESS_KEY / HW_SECRET_KEY (administrador del
# laboratorio; en producción, el equipo de Huawei que entrega la credencial).
#
# Hallazgo del laboratorio: aunque expires_at indique la duración pedida, la
# credencial dejó de ser válida a los ~60 minutos. Emitirla justo antes de
# subir y, en subidas largas, volver a emitirla y reanudar (obsutil -r).
# ============================================================================
import os
import sys

from huaweicloudsdkcore.auth.credentials import GlobalCredentials
from huaweicloudsdkiam.v3 import (CreateTemporaryAccessKeyByTokenRequest, CreateTemporaryAccessKeyByTokenRequestBody,
                                  IamClient, IdentityToken, ServicePolicy, ServiceStatement, TokenAuth,
                                  TokenAuthIdentity)
from huaweicloudsdkiam.v3.region.iam_region import IamRegion

REGION = os.environ.get("HW_REGION", "la-south-2")


def main():
    bucket, salida = sys.argv[1], sys.argv[2]
    segundos = int(sys.argv[3]) if len(sys.argv) > 3 else 3600
    iam = IamClient.new_builder().with_credentials(
        GlobalCredentials(os.environ["HW_ACCESS_KEY"], os.environ["HW_SECRET_KEY"])
    ).with_region(IamRegion.value_of(REGION)).build()

    politica = ServicePolicy(version="1.1", statement=[ServiceStatement(
        effect="Allow",
        action=["obs:object:PutObject", "obs:object:AbortMultipartUpload", "obs:object:ListMultipartUploadParts",
                "obs:bucket:HeadBucket", "obs:bucket:GetBucketLocation", "obs:bucket:ListBucketMultipartUploads"],
        resource=["obs:*:*:object:%s/incoming/*" % bucket, "obs:*:*:bucket:%s" % bucket])])
    body = CreateTemporaryAccessKeyByTokenRequestBody(auth=TokenAuth(identity=TokenAuthIdentity(
        methods=["token"], token=IdentityToken(duration_seconds=segundos), policy=politica)))
    c = iam.create_temporary_access_key_by_token(CreateTemporaryAccessKeyByTokenRequest(body=body)).credential

    fd = os.open(salida, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("endpoint=https://obs.%s.myhuaweicloud.com\nak=%s\nsk=%s\ntoken=%s\n"
                % (REGION, c.access, c.secret, c.securitytoken))
    print("Credencial de subida en %s (expires_at %s; en la práctica ~60 min)" % (salida, c.expires_at))


if __name__ == "__main__":
    main()
