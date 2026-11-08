#!/usr/bin/env python3
"""cdp.py <ws-url|page-id> [js] — DIAGNÓSTICO: conecta no DevTools (porta 9222), despeja mensagens
de console/log/exceções guardadas e, se dado, avalia <js> na página. Só stdlib."""
import base64, json, os, socket, struct, sys, time, urllib.request
tgt = sys.argv[1]
if not tgt.startswith('ws://'):
    pages = json.load(urllib.request.urlopen('http://127.0.0.1:9222/json'))
    tgt = next(p['webSocketDebuggerUrl'] for p in pages if p['id'].startswith(tgt) or tgt in p['url'])
host, path = tgt[5:].split('/', 1); h, port = host.split(':')
s = socket.create_connection((h, int(port)))
key = base64.b64encode(os.urandom(16)).decode()
s.send(f'GET /{path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'.encode())
buf = b''
while b'\r\n\r\n' not in buf: buf += s.recv(4096)
buf = buf.split(b'\r\n\r\n', 1)[1]
def send(obj):
    d = json.dumps(obj).encode(); m = os.urandom(4)
    hdr = bytes([0x81]) + (bytes([0x80 | len(d)]) if len(d) < 126 else bytes([0x80 | 126]) + struct.pack('>H', len(d)) if len(d) < 65536 else bytes([0x80 | 127]) + struct.pack('>Q', len(d)))
    s.send(hdr + m + bytes(b ^ m[i % 4] for i, b in enumerate(d)))
def recv(timeout):
    global buf
    s.settimeout(timeout); msg = b''
    while True:
        while len(buf) < 2: buf += s.recv(65536)
        b1, b2 = buf[0], buf[1]; n = b2 & 127; off = 2
        if n == 126:
            while len(buf) < 4: buf += s.recv(65536)
            n = struct.unpack('>H', buf[2:4])[0]; off = 4
        elif n == 127:
            while len(buf) < 10: buf += s.recv(65536)
            n = struct.unpack('>Q', buf[2:10])[0]; off = 10
        while len(buf) < off + n: buf += s.recv(65536)
        msg += buf[off:off + n]; buf = buf[off + n:]
        if b1 & 0x80: return json.loads(msg)
send({'id': 1, 'method': 'Runtime.enable'}); send({'id': 2, 'method': 'Log.enable'})
if len(sys.argv) > 2:
    send({'id': 3, 'method': 'Runtime.evaluate', 'params': {'expression': sys.argv[2], 'returnByValue': True, 'awaitPromise': True}})
end = time.time() + 4
while time.time() < end:
    try: m = recv(max(0.1, end - time.time()))
    except socket.timeout: break
    meth = m.get('method')
    if meth == 'Runtime.consoleAPICalled':
        p = m['params']; print('console.%s:' % p['type'], ' '.join(str(a.get('value', a.get('description', '')))[:300] for a in p['args']))
    elif meth == 'Runtime.exceptionThrown':
        e = m['params']['exceptionDetails']; print('EXCEPTION:', e.get('text'), (e.get('exception') or {}).get('description', '')[:600])
    elif meth == 'Log.entryAdded':
        e = m['params']['entry']; print('log.%s [%s]:' % (e['level'], e['source']), e['text'][:300], e.get('url', '')[:100])
    elif m.get('id') == 3:
        print('RESULT:', json.dumps(m.get('result', m), ensure_ascii=False)[:3000])
