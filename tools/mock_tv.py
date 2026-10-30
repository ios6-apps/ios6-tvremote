#!/usr/bin/env python3
"""A stand-in for an Android TV, for testing the app without one. Speaks the same two protocols (pairing on PORT+1, remote on PORT),
using the message definitions from the androidtvremote2 library, and checks the pairing code exactly like a TV does.

    python3 tools/mock_tv.py [--host 0.0.0.0] [--port 6466] [--name "Living Room TV"]

Needs the androidtvremote2 package (pip install androidtvremote2) and pyOpenSSL for the protobuf definitions and TLS.
Prints every key it receives and writes the pairing code it "shows" to $MOCK_CODE_FILE (default /tmp/mock_tv_code).
Set MOCK_ALLOW_UNPAIRED=1 to accept the remote connection without pairing first."""
import argparse, hashlib, os, random, socket, ssl, struct, subprocess, sys, tempfile, threading
from androidtvremote2 import polo_pb2 as polo, remotemessage_pb2 as rm

def varint(n):
    out = bytearray()
    while n >= 0x80:
        out.append((n & 0x7f) | 0x80); n >>= 7
    out.append(n); return bytes(out)

def read_msg(conn):
    n, shift = 0, 0
    while True:
        b = conn.recv(1)
        if not b: return None
        n |= (b[0] & 0x7f) << shift
        if not b[0] & 0x80: break
        shift += 7
    data = b""
    while len(data) < n:
        chunk = conn.recv(n - len(data))
        if not chunk: return None
        data += chunk
    return data

def send_msg(conn, msg):
    raw = msg.SerializeToString()
    conn.sendall(varint(len(raw)) + raw)

def rsa_parts(der):
    from cryptography import x509
    nums = x509.load_der_x509_certificate(der).public_key().public_numbers()
    return nums.n, nums.e

def make_server_cert(d):
    key, crt = os.path.join(d, "k.pem"), os.path.join(d, "c.pem")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", crt, "-days", "30", "-subj", "/CN=MockTV"], check=True, capture_output=True)
    return crt, key

class TLSSock:
    """Adapts a pyOpenSSL connection to the few socket calls above. pyOpenSSL lets the verify callback accept any client
    certificate, which is what a TV does and what Python's own ssl module cannot do."""
    def __init__(self, conn): self.c = conn
    def recv(self, n):
        from OpenSSL import SSL
        try: return self.c.recv(n)
        except SSL.ZeroReturnError: return b""
        except SSL.SysCallError: return b""
    def sendall(self, b): self.c.sendall(b)
    def getpeercert(self, binary=True):
        from OpenSSL import crypto
        cert = self.c.get_peer_certificate()
        return crypto.dump_certificate(crypto.FILETYPE_ASN1, cert) if cert else None

def context(crt, key):
    from OpenSSL import SSL
    ctx = SSL.Context(SSL.TLS_SERVER_METHOD)
    ctx.use_certificate_file(crt); ctx.use_privatekey_file(key)
    ctx.set_verify(SSL.VERIFY_PEER, lambda conn, cert, errno, depth, ok: True)
    return ctx

def wrap(ctx, sock):
    from OpenSSL import SSL
    c = SSL.Connection(ctx, sock); c.set_accept_state(); c.do_handshake()
    return TLSSock(c)

paired_fingerprints = set()

def client_fp(conn):
    der = conn.getpeercert(True)
    return der

def pairing(conn, crt_der):
    client_der = client_fp(conn)
    if not client_der:
        print("pairing: client sent no certificate"); return
    O = polo.OuterMessage
    def out(**kw):
        m = O(); m.protocol_version = 2; m.status = O.STATUS_OK
        for k, v in kw.items(): getattr(m, k).CopyFrom(v)
        return m
    nonce = bytes(random.randrange(256) for _ in range(2))
    cm, ce = rsa_parts(client_der); sm, se = rsa_parts(crt_der)
    h = hashlib.sha256()
    h.update(bytes.fromhex(f"{cm:X}")); h.update(bytes.fromhex(f"0{ce:X}"))
    h.update(bytes.fromhex(f"{sm:X}")); h.update(bytes.fromhex(f"0{se:X}"))
    h.update(nonce)
    digest = h.digest()
    code = f"{digest[0]:02X}{nonce.hex().upper()}"
    while True:
        raw = read_msg(conn)
        if raw is None: print("pairing: closed"); return
        msg = O(); msg.ParseFromString(raw)
        if msg.HasField("pairing_request"):
            print(f"pairing: request from {msg.pairing_request.client_name!r} service {msg.pairing_request.service_name!r}")
            ack = polo.PairingRequestAck(); ack.server_name = "MockTV"
            send_msg(conn, out(pairing_request_ack=ack))
        elif msg.HasField("options"):
            opt = polo.Options(); e = opt.input_encodings.add(); e.type = 3; e.symbol_length = 6; opt.preferred_role = 2
            send_msg(conn, out(options=opt))
        elif msg.HasField("configuration"):
            send_msg(conn, out(configuration_ack=polo.ConfigurationAck()))
            print(f"pairing: CODE ON SCREEN: {code}", flush=True)
            open(os.environ.get("MOCK_CODE_FILE", "/tmp/mock_tv_code"), "w").write(code)
        elif msg.HasField("secret"):
            if msg.secret.secret == digest:
                ack = polo.SecretAck(); ack.secret = digest
                send_msg(conn, out(secret_ack=ack))
                paired_fingerprints.add(hashlib.sha256(client_der).hexdigest())
                print("pairing: OK, client remembered")
            else:
                m = O(); m.protocol_version = 2; m.status = O.STATUS_BAD_SECRET
                send_msg(conn, m); print("pairing: wrong secret")
                return

def remote(conn):
    fp = hashlib.sha256(client_fp(conn) or b"").hexdigest()
    if fp not in paired_fingerprints and not os.environ.get("MOCK_ALLOW_UNPAIRED"):
        print("remote: client not paired, dropping"); return
    R = rm.RemoteMessage
    m = R(); m.remote_configure.code1 = 622; m.remote_configure.device_info.model = ARGS.name; m.remote_configure.device_info.vendor = ""
    m.remote_configure.device_info.unknown1 = 1; m.remote_configure.device_info.unknown2 = "1"; m.remote_configure.device_info.package_name = "mock"; m.remote_configure.device_info.app_version = "1"
    send_msg(conn, m)
    stop = threading.Event()
    def pinger():
        n = 0
        while not stop.wait(5):
            p = R(); p.remote_ping_request.val1 = n; n += 1
            try: send_msg(conn, p)
            except Exception: return
    threading.Thread(target=pinger, daemon=True).start()
    names = {v.number: v.name for v in rm.RemoteKeyCode.DESCRIPTOR.values}
    dirs = {1: "START_LONG", 2: "END_LONG", 3: "SHORT"}
    try:
        while True:
            raw = read_msg(conn)
            if raw is None: break
            msg = R(); msg.ParseFromString(raw)
            if msg.HasField("remote_configure"):
                print(f"remote: configure features={msg.remote_configure.code1} app={msg.remote_configure.device_info.package_name}")
                a = R(); a.remote_set_active.active = 0; send_msg(conn, a)
            elif msg.HasField("remote_set_active"):
                s = R(); s.remote_start.started = True; send_msg(conn, s)
                v = R(); v.remote_set_volume_level.volume_max = 100; v.remote_set_volume_level.volume_level = 23; v.remote_set_volume_level.volume_muted = False; send_msg(conn, v)
                i = R(); i.remote_ime_key_inject.app_info.app_package = "com.google.android.youtube.tv"; send_msg(conn, i)
            elif msg.HasField("remote_ping_response"): pass
            elif msg.HasField("remote_key_inject"):
                k = msg.remote_key_inject
                print(f"key: {names.get(k.key_code, k.key_code)} {dirs.get(k.direction, k.direction)}", flush=True)
            elif msg.HasField("remote_app_link_launch_request"):
                print(f"launch: {msg.remote_app_link_launch_request.app_link}", flush=True)
            else:
                print("remote: other", msg)
    finally:
        stop.set()

def serve(port, ctx, handler):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind((ARGS.host, port)); s.listen(5)
    while True:
        c, addr = s.accept()
        def run(c=c):
            try:
                tls = wrap(ctx, c)
                handler(tls)
            except Exception as e:
                print("connection ended:", type(e).__name__, e)
            finally:
                try: c.close()
                except Exception: pass
        threading.Thread(target=run, daemon=True).start()

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--host", default="0.0.0.0"); ap.add_argument("--port", type=int, default=6466)
    ap.add_argument("--name", default="Mock TV", help="device name the TV reports")
    ARGS = ap.parse_args()
    d = tempfile.mkdtemp(); crt, key = make_server_cert(d)
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
    crt_der = x509.load_pem_x509_certificate(open(crt, "rb").read()).public_bytes(serialization.Encoding.DER)
    ctx = context(crt, key)
    threading.Thread(target=serve, args=(ARGS.port + 1, ctx, lambda c: pairing(c, crt_der)), daemon=True).start()
    print(f"mock TV on {ARGS.host}: remote {ARGS.port}, pairing {ARGS.port + 1}", flush=True)
    serve(ARGS.port, ctx, remote)
