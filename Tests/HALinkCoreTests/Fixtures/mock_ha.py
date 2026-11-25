"""Loopback-only Home Assistant fixture. No credentials or real devices are used."""
import base64
import hashlib
import json
import socket
import struct
import time
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def entity(entity_id, state, **attributes):
    return dict(entity_id=entity_id, state=state, attributes=attributes, last_updated=timestamp())


states = {
    'light.desk': entity('light.desk', 'on', friendly_name='书桌台灯', brightness=102,
        supported_color_modes=['color_temp', 'hs'], color_mode='hs', hs_color=[30, 90], rgb_color=[255, 140, 25],
        color_temp_kelvin=3200, min_color_temp_kelvin=2200, max_color_temp_kelvin=6500),
    'light.ceiling': entity('light.ceiling', 'on', friendly_name='客厅主灯', brightness=153,
        supported_color_modes=['color_temp'], color_mode='color_temp', color_temp_kelvin=4000,
        min_color_temp_kelvin=2700, max_color_temp_kelvin=6500),
    'climate.living': entity('climate.living', 'heat', friendly_name='客厅空调', supported_features=953,
        temperature=25, current_temperature=28.5, min_temp=16, max_temp=30, target_temp_step=0.5,
        hvac_modes=['off', 'heat', 'cool', 'dry', 'fan_only', 'auto'], hvac_action='heating',
        fan_mode='auto', fan_modes=['auto', 'low', 'medium', 'high'], swing_mode='off', swing_modes=['off', 'on'],
        swing_horizontal_mode='off', swing_horizontal_modes=['off', 'on'],
        preset_mode='none', preset_modes=['none', 'eco', 'sleep']),
    'switch.plug': entity('switch.plug', 'off', friendly_name='桌面插座'),
    'scene.bright': entity('scene.bright', 'unknown', friendly_name='明亮'),
    'scene.cozy': entity('scene.cozy', 'unknown', friendly_name='温馨'),
    'scene.movie': entity('scene.movie', 'unknown', friendly_name='观影'),
    'scene.night': entity('scene.night', 'unknown', friendly_name='晚安'),
    'scene.away': entity('scene.away', 'unknown', friendly_name='离家'),
}
services = {'light': ['toggle', 'turn_on', 'turn_off'], 'switch': ['toggle', 'turn_on', 'turn_off'],
    'climate': ['turn_on', 'turn_off', 'set_temperature', 'set_hvac_mode', 'set_fan_mode', 'set_swing_mode',
                'set_swing_horizontal_mode', 'set_preset_mode'], 'scene': ['turn_on']}
lock = threading.RLock()
connections = []
commands = []
connection_count = 0
stale_snapshot = False


def broadcast(entity_id, new_state):
    message = dict(type='event', id=1, event=dict(event_type='state_changed', time_fired=timestamp(),
        data=dict(entity_id=entity_id, new_state=new_state)))
    for connection in list(connections):
        try:
            connection.send_ws(message)
        except OSError:
            pass


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def respond(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        global stale_snapshot
        if self.path == '/api/websocket':
            self.websocket()
        elif self.path == '/api/states':
            with lock:
                snapshot = json.loads(json.dumps(list(states.values())))
                if stale_snapshot:
                    stale_snapshot = False
                    states['light.desk']['state'] = 'off'
                    states['light.desk']['last_updated'] = timestamp()
                    broadcast('light.desk', states['light.desk'])
                    time.sleep(0.15)
                self.respond(snapshot)
        elif self.path.startswith('/api/states/'):
            with lock:
                state = states.get(self.path.split('/')[-1])
                self.respond(state or {}, 200 if state else 404)
        elif self.path == '/api/services':
            self.respond([dict(domain=d, services={name: {} for name in names}) for d, names in services.items()])
        elif self.path == '/test/counters':
            with lock:
                self.respond(dict(connections=connection_count, commands=commands))
        else:
            self.respond({}, 404)

    def do_POST(self):
        global stale_snapshot
        value = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        with lock:
            if self.path == '/test/stale-snapshot':
                stale_snapshot = True
                self.respond({})
                return
            if self.path == '/test/drop':
                for connection in list(connections):
                    try:
                        connection.connection.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                self.respond({})
                return
            if self.path == '/test/change':
                entity_id = value['entity_id']
                if value.get('remove'):
                    states.pop(entity_id, None)
                    broadcast(entity_id, None)
                else:
                    current = states[entity_id]
                    current['state'] = value.get('state', current['state'])
                    current['attributes'].update(value.get('attributes', {}))
                    current['last_updated'] = timestamp()
                    broadcast(entity_id, current)
                self.respond({})
                return
            if not self.path.startswith('/api/services/'):
                self.respond({}, 404)
                return
            if self.headers.get('Authorization') != 'Bearer fixture-token':
                self.respond({}, 401)
                return
            domain, service = self.path.split('/')[-2:]
            commands.append(dict(domain=domain, service=service, data=value))
            current = states[value['entity_id']]
            a = current['attributes']
            if service in ('turn_on', 'turn_off', 'toggle'):
                current['state'] = ('on' if current['state'] == 'off' else 'off') if service == 'toggle' else ('off' if service == 'turn_off' else 'heat' if domain == 'climate' else 'on')
            if 'brightness_pct' in value:
                a['brightness'] = round(value['brightness_pct'] / 100 * 255)
            for key in ('color_temp_kelvin', 'hs_color'):
                if key in value:
                    a[key] = value[key]
                    a['color_mode'] = 'hs' if key == 'hs_color' else 'color_temp'
            for key in ('temperature', 'target_temp_low', 'target_temp_high', 'fan_mode', 'swing_mode', 'swing_horizontal_mode', 'preset_mode'):
                if key in value:
                    a[key] = value[key]
            if 'hvac_mode' in value:
                current['state'] = value['hvac_mode']
            current['last_updated'] = timestamp()
            broadcast(current['entity_id'], current)
            self.respond([])

    def send_ws(self, value):
        data = json.dumps(value).encode()
        header = bytes([0x81, len(data)]) if len(data) < 126 else bytes([0x81, 126]) + struct.pack('!H', len(data))
        with self.ws_lock:
            self.connection.sendall(header + data)

    def receive_ws(self):
        head = self.rfile.read(2)
        if len(head) != 2 or head[0] & 0x0f == 8:
            raise EOFError()
        length = head[1] & 0x7f
        if length == 126:
            length = struct.unpack('!H', self.rfile.read(2))[0]
        elif length == 127:
            length = struct.unpack('!Q', self.rfile.read(8))[0]
        mask = self.rfile.read(4) if head[1] & 0x80 else None
        data = self.rfile.read(length)
        if mask:
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        return json.loads(data)

    def websocket(self):
        global connection_count
        key = self.headers['Sec-WebSocket-Key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
        self.send_response(101)
        self.send_header('Upgrade', 'websocket')
        self.send_header('Connection', 'Upgrade')
        self.send_header('Sec-WebSocket-Accept', base64.b64encode(hashlib.sha1(key.encode()).digest()).decode())
        self.end_headers()
        self.ws_lock = threading.Lock()
        self.close_connection = True
        with lock:
            connection_count += 1
        try:
            self.send_ws(dict(type='auth_required', ha_version='fixture'))
            auth = self.receive_ws()
            if auth.get('type') != 'auth' or auth.get('access_token') != 'fixture-token':
                self.send_ws(dict(type='auth_invalid', message='Invalid token'))
                return
            self.send_ws(dict(type='auth_ok', ha_version='fixture'))
            while True:
                request = self.receive_ws()
                kind = request['type']
                if kind == 'ping':
                    self.send_ws(dict(type='pong', id=request['id']))
                    continue
                with lock:
                    if kind == 'subscribe_events':
                        result = None
                        if request.get('event_type') == 'state_changed' and self not in connections:
                            connections.append(self)
                    elif kind == 'get_states':
                        result = list(states.values())
                    elif kind == 'get_config':
                        result = dict(unit_system=dict(temperature='°C'))
                    elif kind == 'config/area_registry/list':
                        result = [dict(area_id='living', name='客厅'), dict(area_id='study', name='书房')]
                    elif kind == 'config/device_registry/list':
                        result = [dict(id='desk-device', area_id='study')]
                    elif kind == 'config/entity_registry/list':
                        result = [dict(entity_id=k, area_id='living' if k in ('light.ceiling', 'climate.living') else None,
                            device_id='desk-device' if k == 'light.desk' else None) for k in states]
                    else:
                        self.send_ws(dict(type='result', id=request['id'], success=False, error=dict(code='unknown_command')))
                        continue
                    self.send_ws(dict(type='result', id=request['id'], success=True, result=result))
        except (EOFError, OSError, ValueError):
            pass
        finally:
            with lock:
                if self in connections:
                    connections.remove(self)


class Server(ThreadingHTTPServer):
    daemon_threads = True


if __name__ == '__main__':
    server = Server(('127.0.0.1', 0), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()
