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
    ('run', 'Google Cloud Run', 'Gateway hosting', 'Cloud Billing connected — awaiting first daily export'),
    ('database', 'Cloud SQL', 'veya-users-db · PostgreSQL', 'Cloud Billing connected — awaiting first daily export'),
    ('dns', 'Google Cloud DNS', 'heyveya.app DNS zone', 'Cloud Billing connected — awaiting first daily export'),
    ('domain', 'Google Cloud Domains', 'heyveya.app registration', 'Cloud Billing connected — awaiting first daily export'),
    ('auth', 'Firebase Authentication', 'Phone OTP and app identity', 'Usage billed where applicable — Firebase usage feed not connected'),
    ('sarvam', 'Sarvam AI', 'Saaras, Translate, and 105B', 'Usage billed — Sarvam usage feed not connected'),
    ('workspace', 'Google Workspace', 'heyveya.app verified', 'Gmail not activated'),
]


DASHBOARD_HTML = r'''<!doctype html>
<html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Veya internal</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,400,0,0');
:root{--bg:#0f0f12;--surface:#19191f;--surface2:#202027;--line:#35353e;--text:#f8f6f2;--muted:#aaa8b1;--orange:#ff8a20;--orange-soft:#432a17;--red:#ff7467}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 90% 0,#291b13 0,transparent 30rem),var(--bg);color:var(--text);font-family:Inter,ui-sans-serif,system-ui,sans-serif}.wrap{max-width:1100px;margin:auto;padding:42px 22px 76px}.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:34px}.brand{display:flex;gap:13px;align-items:center}.brand-mark{width:38px;height:38px;border-radius:13px;overflow:hidden;box-shadow:0 8px 26px #0007}.brand-mark svg{width:100%;height:100%;display:block}h1{margin:0;font-size:29px;letter-spacing:-.04em}.pill{color:var(--orange);font-size:11px;font-weight:800;letter-spacing:.15em;text-transform:uppercase}.material-symbols-rounded{font-family:'Material Symbols Rounded';font-weight:normal;font-style:normal;line-height:1;white-space:nowrap;letter-spacing:normal;text-transform:none;display:inline-block}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}.card{background:linear-gradient(145deg,var(--surface2),var(--surface));border:1px solid var(--line);border-radius:18px;padding:20px;box-shadow:0 10px 30px #0002}.label{font-size:12px;color:var(--muted)}.value{font-size:30px;font-weight:780;letter-spacing:-.04em;margin-top:8px}.section{margin:38px 0 14px;font-size:11px;font-weight:800;letter-spacing:.15em;text-transform:uppercase;color:var(--muted)}.wide{display:grid;grid-template-columns:1fr 1fr;gap:14px}.list{padding:0;margin:0;list-style:none}.list li{padding:14px 0;border-bottom:1px solid var(--line)}.list li:last-child{border:0}.health-row{display:flex;gap:12px;align-items:flex-start}.health-icon{color:var(--orange);font-size:20px;padding-top:2px}.name{font-weight:720}.detail{font-size:13px;line-height:1.45;color:var(--muted);margin-top:4px}.services{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}.service{background:linear-gradient(145deg,#202027,#18181e);border:1px solid var(--line);border-radius:18px;padding:18px;display:flex;gap:15px;align-items:flex-start;min-height:116px}.service-mark{width:44px;height:44px;flex:none;border-radius:14px;background:var(--orange-soft);border:1px solid #70451e;color:var(--orange);display:grid;place-items:center}.service-mark .material-symbols-rounded{font-size:23px}.service .name{padding-top:1px}.service .detail{font-size:12px}.login{max-width:420px;margin:15vh auto;background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:30px;box-shadow:0 20px 70px #0008}input{width:100%;padding:14px;border-radius:12px;background:#111116;border:1px solid var(--line);color:white;font:inherit;margin:18px 0}button{border:0;border-radius:12px;background:var(--orange);color:#1a120a;padding:12px 17px;font-weight:800;font:inherit;cursor:pointer;transition:transform .16s ease,filter .16s ease}button:active{transform:scale(.94);filter:brightness(.9)}button.loading{pointer-events:none}.refresh-symbol{font-size:17px;vertical-align:-3px;margin-right:5px}.loading .refresh-symbol{animation:spin .7s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}.error{color:var(--red);min-height:20px;font-size:13px}.hidden{display:none}@media(max-width:720px){.grid{grid-template-columns:repeat(2,1fr)}.wide,.services{grid-template-columns:1fr}.wrap{padding:28px 16px 56px}.service{min-height:0}}
</style></head><body><main id="login" class="login"><div class="pill">Veya · internal</div><h1 style="margin-top:8px">Gateway dashboard</h1><p class="detail">Enter the administrator token. It is kept only for this browser session.</p><input id="token" type="password" autocomplete="current-password" placeholder="Administrator token"><div id="error" class="error"></div><button onclick="login()">Open dashboard</button></main><main id="app" class="wrap hidden"><div class="top"><div class="brand"><div class="brand-mark"><svg viewBox="0 0 100 100" aria-label="Veya"><rect width="100" height="100" rx="28" fill="#ff8a20"/><g stroke="#230843" stroke-width="10" stroke-linecap="round"><path d="M21 31v31"/><path d="M35 44v31"/><path d="M50 57v31"/><path d="M65 44v31"/><path d="M79 31v31"/></g></svg></div><div><div class="pill">Veya · internal</div><h1>Gateway dashboard</h1></div></div><button id="refresh-button" onclick="refresh()"><span class="material-symbols-rounded refresh-symbol">refresh</span>Refresh</button></div><div id="content"></div></main><script>
const $=id=>document.getElementById(id);let token=sessionStorage.getItem('veya_admin_token')||'';
async function load(){const res=await fetch('/internal/api/overview',{headers:{'X-Veya-Admin-Token':token}});if(!res.ok)throw new Error('Invalid administrator token');return res.json()}
function symbol(name){return `<span class="material-symbols-rounded">${name}</span>`}
function row(icon,name,detail){return `<li class="health-row"><div class="health-icon">${symbol(icon)}</div><div><div class="name">${name}</div><div class="detail">${detail}</div></div></li>`}
function icon(k){return({run:'cloud',database:'database',dns:'dns',domain:'domain',auth:'local_fire_department',sarvam:'graphic_eq',workspace:'workspaces'})[k]||'info'}
function service(x){return `<article class="service"><div class="service-mark">${symbol(icon(x.icon))}</div><div><div class="name">${x.name}</div><div class="detail">${x.purpose}</div><div class="detail">${x.cost_status}</div></div></article>`}
function money(value,currency){return new Intl.NumberFormat('en-IN',{style:'currency',currency:currency||'INR',maximumFractionDigits:2}).format(value||0)}
function costPanel(cost){if(cost.status!=='available')return `<div class="card"><div class="label">Google Cloud cost</div><div class="name" style="margin-top:9px">${cost.status==='collecting'?'Collecting first export':'Not available'}</div><div class="detail">${cost.message}</div></div>`;return `<div class="card"><div class="label">Google Cloud cost · month to date</div><div class="value">${money(cost.month_to_date,cost.currency)}</div><div class="detail">${cost.message}</div></div><div class="card"><ul class="list">${cost.services.length?cost.services.slice(0,6).map(x=>row('payments',x.name,money(x.amount,x.currency))).join(''):row('payments','No billable usage yet','The export has no current-month line items.')}</ul></div>`}
function render(d){let t=d.traffic,c=d.cloud_costs;$('content').innerHTML=`<div class="grid"><div class="card"><div class="label">Requests · 5 min</div><div class="value">${t.requests_5m}</div></div><div class="card"><div class="label">Errors · 5 min</div><div class="value">${t.errors_5m}</div></div><div class="card"><div class="label">Active streams</div><div class="value">${t.active_streams}</div></div><div class="card"><div class="label">Completed · 1 hr</div><div class="value">${t.completed_streams_1h}</div></div></div><div class="section">Google Cloud cost</div><div class="wide">${costPanel(c)}</div><div class="section">Service health</div><div class="wide"><div class="card"><ul class="list">${row('monitor_heart','Gateway',d.health.ok?'Healthy':'Unavailable')}${row('mic','Transcription',d.health.saaras_transcription_model)}${row('translate','Translation',d.health.translation_model)}${row('edit_note','Style generation',d.health.style_model)}${row('timer','Last process',d.health.last_process_duration_ms?d.health.last_process_duration_ms+' ms':'No legacy request yet')}</ul></div><div class="card"><ul class="list">${row('query_stats','Requests · 1 hour',t.requests_1h)}${row('stream','Streams opened · 1 hour',t.streams_1h)}${row('error','Streams failed · 1 hour',t.failed_streams_1h)}${row('schedule','Instance uptime',Math.floor(d.uptime_seconds/60)+' min')}</ul></div></div><div class="section">Subscriptions and cost visibility</div><div class="services">${d.subscriptions.map(service).join('')}</div><div class="section">Top routes on this instance</div><div class="card"><ul class="list">${d.routes.length?d.routes.map(x=>row('route',x[0],x[1]+' requests')).join(''):row('route','No traffic recorded','This instance has not received a tracked HTTP request yet.')}</ul></div>`}
async function refresh(){const button=$('refresh-button');button?.classList.add('loading');try{render(await load())}catch(e){sessionStorage.removeItem('veya_admin_token');$('app').classList.add('hidden');$('login').classList.remove('hidden');$('error').textContent=e.message}finally{button?.classList.remove('loading')}}
async function login(){token=$('token').value;try{await load();sessionStorage.setItem('veya_admin_token',token);$('login').classList.add('hidden');$('app').classList.remove('hidden');refresh()}catch(e){$('error').textContent=e.message}}
if(token){$('login').classList.add('hidden');$('app').classList.remove('hidden');refresh()}
</script></main></body></html>'''
