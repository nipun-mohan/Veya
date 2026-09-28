"""Small, dependency-free internal dashboard for the Veya gateway."""
from __future__ import annotations

from collections import Counter, deque
from dataclasses import dataclass, field
import time


@dataclass
class GatewayMetrics:
    started_at: float = field(default_factory=time.time)
    routes: Counter = field(default_factory=Counter)
    statuses: Counter = field(default_factory=Counter)
    http_events: deque[tuple[float, bool]] = field(default_factory=lambda: deque(maxlen=5000))
    stream_events: deque[tuple[float, str]] = field(default_factory=lambda: deque(maxlen=2000))
    active_streams: int = 0

    def record_http(self, route: str, status: int) -> None:
        self.routes[route] += 1
        self.statuses[str(status)] += 1
        self.http_events.append((time.time(), status >= 400))

    def stream_opened(self) -> None:
        self.active_streams += 1
        self.stream_events.append((time.time(), 'opened'))

    def stream_finished(self, outcome: str) -> None:
        self.active_streams = max(0, self.active_streams - 1)
        self.stream_events.append((time.time(), outcome))

    @staticmethod
    def _count(events: deque, seconds: int, kind: str | None = None) -> int:
        since = time.time() - seconds
        if kind is None:
            return sum(1 for stamp, _ in events if stamp >= since)
        return sum(1 for stamp, value in events if stamp >= since and value == kind)

    def snapshot(self) -> dict[str, object]:
        now = time.time()
        five_minutes = [failed for stamp, failed in self.http_events if stamp >= now - 300]
        return {
            'started_at': int(self.started_at),
            'uptime_seconds': int(now - self.started_at),
            'traffic': {
                'requests_5m': len(five_minutes),
                'requests_1h': self._count(self.http_events, 3600),
                'errors_5m': sum(five_minutes),
                'active_streams': self.active_streams,
                'streams_1h': self._count(self.stream_events, 3600, 'opened'),
                'completed_streams_1h': self._count(self.stream_events, 3600, 'completed'),
                'failed_streams_1h': self._count(self.stream_events, 3600, 'failed'),
            },
            'routes': self.routes.most_common(12),
            'status_codes': dict(self.statuses),
        }


SUBSCRIPTIONS = [
    ('Google Cloud Run', 'Gateway hosting', 'Usage billed — cloud billing export not connected'),
    ('Google Cloud DNS', 'heyveya.app DNS zone', 'Usage billed — cloud billing export not connected'),
    ('Google Cloud Domains', 'heyveya.app registration', 'Annual registration — cloud billing export not connected'),
    ('Firebase Authentication', 'Phone OTP and app identity', 'Usage billed where applicable — Firebase usage feed not connected'),
    ('Sarvam AI', 'Saaras, Translate, and 105B', 'Usage billed — Sarvam usage feed not connected'),
    ('Google Workspace', 'heyveya.app verified', 'Gmail not activated'),
]


DASHBOARD_HTML = r'''<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Veya internal</title>
<style>
:root{--bg:#101013;--surface:#1a1a20;--line:#32323b;--text:#f7f5f2;--muted:#aaa8b1;--orange:#ff8a20;--red:#ff7467}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,system-ui,sans-serif}.wrap{max-width:1100px;margin:auto;padding:36px 20px 64px}.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:28px}h1{margin:0;font-size:28px}.pill{color:var(--orange);font-size:12px;font-weight:800;letter-spacing:.12em;text-transform:uppercase}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}.card{background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:18px}.label{font-size:12px;color:var(--muted)}.value{font-size:28px;font-weight:750;margin-top:7px}.section{margin-top:28px;font-size:14px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted)}.wide{display:grid;grid-template-columns:1fr 1fr;gap:12px}.list{padding:0;margin:0;list-style:none}.list li{padding:13px 0;border-bottom:1px solid var(--line)}.list li:last-child{border:0}.name{font-weight:700}.detail{font-size:13px;color:var(--muted);margin-top:4px}.login{max-width:420px;margin:15vh auto;background:var(--surface);border:1px solid var(--line);border-radius:20px;padding:28px}input{width:100%;padding:14px;border-radius:12px;background:#111116;border:1px solid var(--line);color:white;font:inherit;margin:18px 0}button{border:0;border-radius:12px;background:var(--orange);color:#1a120a;padding:13px 17px;font-weight:800;font:inherit;cursor:pointer}.error{color:var(--red);min-height:20px;font-size:13px}.hidden{display:none}@media(max-width:720px){.grid{grid-template-columns:repeat(2,1fr)}.wide{grid-template-columns:1fr}}
</style></head><body><main id="login" class="login"><div class="pill">Veya · internal</div><h1 style="margin-top:8px">Gateway dashboard</h1><p class="detail">Enter the administrator token. It is kept only for this browser session.</p><input id="token" type="password" autocomplete="current-password" placeholder="Administrator token"><div id="error" class="error"></div><button onclick="login()">Open dashboard</button></main><main id="app" class="wrap hidden"><div class="top"><div><div class="pill">Veya · internal</div><h1>Gateway dashboard</h1></div><button onclick="refresh()">Refresh</button></div><div id="content"></div></main><script>
const $=id=>document.getElementById(id);let token=sessionStorage.getItem('veya_admin_token')||'';
async function load(){const res=await fetch('/internal/api/overview',{headers:{'X-Veya-Admin-Token':token}});if(!res.ok)throw new Error('Invalid administrator token');return res.json()}
function row(name,detail){return `<li><div class="name">${name}</div><div class="detail">${detail}</div></li>`}
function render(d){let t=d.traffic;$('content').innerHTML=`<div class="grid"><div class="card"><div class="label">Requests · 5 min</div><div class="value">${t.requests_5m}</div></div><div class="card"><div class="label">Errors · 5 min</div><div class="value">${t.errors_5m}</div></div><div class="card"><div class="label">Active streams</div><div class="value">${t.active_streams}</div></div><div class="card"><div class="label">Completed · 1 hr</div><div class="value">${t.completed_streams_1h}</div></div></div><div class="section">Service health</div><div class="wide"><div class="card"><ul class="list">${row('Gateway',d.health.ok?'Healthy':'Unavailable')}${row('Transcription',d.health.saaras_transcription_model)}${row('Translation',d.health.translation_model)}${row('Style generation',d.health.style_model)}${row('Last process',d.health.last_process_duration_ms?d.health.last_process_duration_ms+' ms':'No legacy request yet')}</ul></div><div class="card"><ul class="list">${row('Requests · 1 hour',t.requests_1h)}${row('Streams opened · 1 hour',t.streams_1h)}${row('Streams failed · 1 hour',t.failed_streams_1h)}${row('Instance uptime',Math.floor(d.uptime_seconds/60)+' min')}</ul></div></div><div class="section">Subscriptions and cost visibility</div><div class="card"><ul class="list">${d.subscriptions.map(x=>row(x.name,`${x.purpose} · ${x.cost_status}`)).join('')}</ul></div><div class="section">Top routes on this instance</div><div class="card"><ul class="list">${d.routes.length?d.routes.map(x=>row(x[0],x[1]+' requests')).join(''):row('No traffic recorded','This instance has not received a tracked HTTP request yet.')}</ul></div>`}
async function refresh(){try{render(await load())}catch(e){sessionStorage.removeItem('veya_admin_token');$('app').classList.add('hidden');$('login').classList.remove('hidden');$('error').textContent=e.message}}
async function login(){token=$('token').value;try{await load();sessionStorage.setItem('veya_admin_token',token);$('login').classList.add('hidden');$('app').classList.remove('hidden');refresh()}catch(e){$('error').textContent=e.message}}
if(token){$('login').classList.add('hidden');$('app').classList.remove('hidden');refresh()}
</script></main></body></html>'''
