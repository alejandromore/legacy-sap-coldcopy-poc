#!/usr/bin/env python3
# ============================================================================
# Agente del ECS receptor (sin EIP, sin Internet, solo biblioteca estándar).
#
# Lo ejecuta un timer de systemd cada minuto:
#   1. Publica su estado en resultados/receptor/estado.json (latido).
#   2. Busca incoming/<variante>/manifiesto.json sin procesar.
#   3. Por cada disco del manifiesto: descarga el VMDK desde OBS por la red
#      interna (SHA-256 del archivo), lo escribe en su EVS (qemu-img si está;
#      si no, conversor streamOptimized propio) y calcula el SHA-256 del EVS
#      sobre exactamente el tamaño virtual del disco.
#   4. Sube resultados/<variante>/resultado.json con hashes y tiempos.
#
# Credenciales: las temporales de la agencia del ECS, desde el metadata
# service. Ninguna AK/SK vive en el disco.
# ============================================================================
import base64
import email.utils
import hashlib
import hmac
import json
import os
import shutil
import struct
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zlib

ENV = dict(l.strip().split("=", 1) for l in open(os.environ.get("COLDCOPY_ENV", "/etc/coldcopy.env")) if "=" in l)
BUCKET, REGION = ENV["BUCKET"], ENV["REGION"]
HOST = "%s.obs.%s.myhuaweicloud.com" % (BUCKET, REGION)
STATE = "/var/lib/coldcopy"
WORK = "/var/tmp/coldcopy"
LOG = "/var/log/coldcopy-receptor.log"
CHUNK = 8 * 1024 * 1024


def log(msg):
    line = "%s %s" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), msg)
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def creds():
    url = "http://169.254.169.254/openstack/latest/securitykey"
    with urllib.request.urlopen(url, timeout=10) as r:
        c = json.load(r)["credential"]
    return c["access"], c["secret"], c["securitytoken"]


def obs(method, key="", query="", body=None, ctype=""):
    """Petición OBS firmada (firma V2) con security token."""
    ak, sk, tok = creds()
    date = email.utils.formatdate(usegmt=True)
    resource = "/%s/%s" % (BUCKET, key)
    sts = "%s\n\n%s\n%s\nx-obs-security-token:%s\n%s" % (method, ctype, date, tok, resource)
    sig = base64.b64encode(hmac.new(sk.encode(), sts.encode(), hashlib.sha1).digest()).decode()
    url = "https://%s/%s" % (HOST, urllib.parse.quote(key))
    if query:
        url += "?" + query
    headers = {"Date": date, "Authorization": "OBS %s:%s" % (ak, sig), "x-obs-security-token": tok}
    if ctype:
        headers["Content-Type"] = ctype
    try:
        return urllib.request.urlopen(urllib.request.Request(url, data=body, method=method, headers=headers), timeout=120)
    except urllib.error.HTTPError as e:
        raise RuntimeError("OBS %s %s -> HTTP %s: %s" % (method, key or "/", e.code, e.read()[:600].decode(errors="replace")))


def put_json(key, data):
    obs("PUT", key, body=json.dumps(data, indent=2).encode(), ctype="application/json").read()


def listar(prefix):
    keys, marker = [], ""
    while True:
        q = "prefix=" + urllib.parse.quote(prefix) + ("&marker=" + urllib.parse.quote(marker) if marker else "")
        root = ET.fromstring(obs("GET", "", q).read())
        ns = root.tag.split("}")[0] + "}" if root.tag.startswith("{") else ""
        page = [c.find(ns + "Key").text for c in root.findall(ns + "Contents")]
        keys += page
        if root.findtext(ns + "IsTruncated") != "true" or not page:
            return keys
        marker = page[-1]


def lsblk():
    out = subprocess.run(["lsblk", "-bdno", "NAME,SIZE,SERIAL,TYPE"], capture_output=True, text=True).stdout
    return [l.split() for l in out.splitlines() if l.strip()]


def dispositivo(evs_id):
    link = "/dev/disk/by-id/virtio-" + evs_id[:20]
    if os.path.exists(link):
        return os.path.realpath(link)
    for f in lsblk():
        if len(f) >= 3 and evs_id.startswith(f[2]):
            return "/dev/" + f[0]
    raise RuntimeError("No encuentro el EVS %s (%s)" % (evs_id, lsblk()))


def descargar(key, destino):
    h, n, t0 = hashlib.sha256(), 0, time.time()
    with obs("GET", key) as r, open(destino, "wb") as f:
        while True:
            b = r.read(CHUNK)
            if not b:
                break
            h.update(b)
            f.write(b)
            n += len(b)
    return h.hexdigest(), n, time.time() - t0


def svmdk_a_dispositivo(src, dev):
    """Conversor mínimo de VMDK streamOptimized (el formato de OVF) a crudo.
    Los grains ausentes son ceros: el EVS recién creado ya está en cero."""
    with open(src, "rb") as f, open(dev, "r+b") as out:
        hdr = f.read(512)
        if hdr[:4] != b"KDMV":
            raise RuntimeError("No es un VMDK sparse")
        overhead = struct.unpack_from("<Q", hdr, 64)[0]
        f.seek(overhead * 512)
        while True:
            m = f.read(512)
            if len(m) < 16:
                break
            val, size = struct.unpack_from("<QI", m, 0)
            if size > 0:
                if 12 + size <= 512:
                    data = m[12:12 + size]
                else:
                    data = m[12:] + f.read(size - 500)
                    f.read((-(12 + size)) % 512)
                out.seek(val * 512)
                out.write(zlib.decompress(data))
            else:
                tipo = struct.unpack_from("<I", m, 12)[0]
                if tipo == 0:
                    break
                f.seek(val * 512, 1)
        out.flush()
        os.fsync(out.fileno())


def escribir(src, dev):
    t0 = time.time()
    if shutil.which("qemu-img"):
        subprocess.run(["qemu-img", "convert", "-O", "raw", src, dev], check=True)
        metodo = "qemu-img"
    else:
        svmdk_a_dispositivo(src, dev)
        metodo = "conversor-python"
    subprocess.run(["sync"], check=True)
    return metodo, time.time() - t0


def hash_dispositivo(dev, nbytes):
    h, restante, t0 = hashlib.sha256(), nbytes, time.time()
    with open(dev, "rb") as f:
        while restante > 0:
            b = f.read(min(CHUNK, restante))
            if not b:
                raise RuntimeError("%s más chico que %d bytes" % (dev, nbytes))
            h.update(b)
            restante -= len(b)
    return h.hexdigest(), time.time() - t0


def procesar(key):
    man = json.load(obs("GET", key))
    var = man["variante"]
    log("Procesando %s" % var)
    res = {"variante": var, "inicio": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "discos": []}
    os.makedirs(WORK, exist_ok=True)
    for d in man["discos"]:
        r = {"nombre": d["nombre"], "objeto": d["objeto"], "evs_id": d["evs_id"]}
        local = os.path.join(WORK, os.path.basename(d["objeto"]))
        r["sha256_archivo"], r["bytes_archivo"], r["seg_descarga"] = descargar(d["objeto"], local)
        r["archivo_ok"] = r["sha256_archivo"] == d["sha256_archivo"]
        r["dispositivo"] = dev = dispositivo(d["evs_id"])
        r["metodo"], r["seg_escritura"] = escribir(local, dev)
        r["sha256_destino"], r["seg_hash"] = hash_dispositivo(dev, d["bytes_virtuales"])
        r["sha256_origen"] = d["sha256_crudo"]
        r["contenido_ok"] = r["sha256_destino"] == d["sha256_crudo"]
        os.remove(local)
        log("%s: archivo_ok=%s contenido_ok=%s" % (d["nombre"], r["archivo_ok"], r["contenido_ok"]))
        res["discos"].append(r)
    res["fin"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    res["todo_ok"] = all(x["archivo_ok"] and x["contenido_ok"] for x in res["discos"])
    put_json("resultados/%s/resultado.json" % var, res)
    open(os.path.join(STATE, var + ".hecho"), "w").write(res["fin"])


def main():
    os.makedirs(STATE, exist_ok=True)
    estado = {
        "hora": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "qemu_img": shutil.which("qemu-img"),
        "discos": lsblk(),
        "hechos": sorted(os.listdir(STATE)),
    }
    try:
        for key in listar("incoming/"):
            if key.endswith("/manifiesto.json"):
                var = key.split("/")[1]
                if not os.path.exists(os.path.join(STATE, var + ".hecho")):
                    try:
                        procesar(key)
                    except Exception:
                        err = traceback.format_exc()
                        log(err)
                        put_json("resultados/%s/error.json" % var, {"error": err})
                        open(os.path.join(STATE, var + ".hecho"), "w").write("error")
        estado["hechos"] = sorted(os.listdir(STATE))
    except Exception:
        estado["error"] = traceback.format_exc()
        log(estado["error"])
    try:
        estado["log"] = open(LOG).read()[-4000:] if os.path.exists(LOG) else ""
        put_json("resultados/receptor/estado.json", estado)
    except Exception:
        log("No pude publicar el estado: " + traceback.format_exc())
        sys.exit(1)


if __name__ == "__main__":
    main()
