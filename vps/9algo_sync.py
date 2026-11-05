"""
9algo VPS <-> GitHub sync (tanpa koneksi masuk ke VPS; hanya keluar ke api.github.com)

Tiap siklus (default 90 detik):
  1. KIRIM status ke branch `status` (selalu 1 commit, ditimpa): state JSON EA, log Experts & Journal
     hari ini, versi source/ex5 terpasang, hasil compile terakhir.
  2. CEK permintaan di branch `main`: deploy/request.json  {"id": "...", "file": "src/9algo.mq5", "deploy": true}
     -> unduh source, compile dulu di folder uji (MQL5/Experts/9algo_ci). Kalau 0 error dan deploy=true:
        backup source lama, pasang ke MQL5/Experts/9algo.mq5, compile (EA di chart reload otomatis).
     Hasilnya masuk ke status.

Tidak bisa mengirim order / mengubah setelan akun. Satu-satunya aksi = compile + pasang file EA.
Konfigurasi: sync_config.json (dibuat setup_sync.bat): {"owner":..,"repo":..,"token":..,"interval":90,"allow_deploy":true}
Python 3.8+ standar, tanpa library tambahan.
"""
import base64, glob, json, os, shutil, subprocess, sys, tempfile, time, traceback, urllib.error, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CFG = json.loads((HERE / "sync_config.json").read_text(encoding="utf-8"))
OWNER, REPO, TOKEN = CFG["owner"], CFG["repo"], CFG["token"]
INTERVAL = int(CFG.get("interval", 90))
ALLOW_DEPLOY = bool(CFG.get("allow_deploy", True))
EA_FILE = CFG.get("ea_file", "9algo.mq5")
STATE = HERE / "sync_state.json"
API = f"https://api.github.com/repos/{OWNER}/{REPO}"
VERSION = "1.0"


def log(msg):
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
    print(line, flush=True)
    try:
        with open(HERE / "sync.log", "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except Exception:
        pass


def gh(method, path, body=None, headers=None, raw_url=None):
    url = raw_url or (API + path)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "9algo-sync")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            txt = r.read().decode("utf-8", errors="replace")
            return r.status, (json.loads(txt) if txt.strip() else {}), dict(r.headers)
    except urllib.error.HTTPError as e:
        txt = e.read().decode("utf-8", errors="replace")
        try:
            js = json.loads(txt)
        except Exception:
            js = {"raw": txt[:300]}
        return e.code, js, dict(e.headers or {})


# ---------------- MT5 lokasi ----------------
def data_dirs():
    roots = [Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal"]
    roots += [Path(p) for p in CFG.get("portable_dirs", [])]
    out = []
    for root in roots:
        for d in glob.glob(str(root / "*")):
            if (Path(d) / "MQL5" / "Experts").is_dir():
                out.append(Path(d))
        if (root / "MQL5" / "Experts").is_dir():
            out.append(root)
    return out


def main_dir():
    """Data folder terminal yang berisi EA (kalau ada beberapa terminal: yang punya 9algo.mq5)."""
    ds = data_dirs()
    for d in ds:
        if (d / "MQL5" / "Experts" / EA_FILE).exists():
            return d
    return ds[0] if ds else None


def common_files():
    return Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal" / "Common" / "Files" / "9algo"


def read_any(f: Path) -> str:
    raw = f.read_bytes()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16", errors="replace")
    try:
        return raw.decode("utf-8")
    except Exception:
        return raw.decode("utf-16", errors="replace") if raw.count(b"\x00") > len(raw) // 4 else raw.decode("latin-1", errors="replace")


def metaeditor(d: Path):
    if CFG.get("mt5_dir"):
        p = Path(CFG["mt5_dir"]) / "metaeditor64.exe"
        if p.exists():
            return p
    o = d / "origin.txt"
    if o.exists():
        p = Path(read_any(o).strip().strip("\ufeff")) / "metaeditor64.exe"
        if p.exists():
            return p
    for p in glob.glob(r"C:\Program Files*\*\metaeditor64.exe"):
        return Path(p)
    return None


def compile_file(d: Path, src: Path):
    me = metaeditor(d)
    if not me:
        return {"ok": False, "result": "metaeditor64.exe tidak ditemukan (isi mt5_dir di sync_config.json)", "errors": [], "warnings": []}
    logf = Path(tempfile.gettempdir()) / "9algo_sync_compile.log"
    try:
        logf.unlink()
    except Exception:
        pass
    subprocess.run([str(me), f"/compile:{src}", f"/log:{logf}"], timeout=240, capture_output=True)
    if not logf.exists():
        return {"ok": False, "result": "compile tidak menghasilkan log", "errors": [], "warnings": []}
    lines = [l.strip() for l in read_any(logf).splitlines() if l.strip()]
    import re
    errs = [l for l in lines if re.search(r":\s*error\b", l, re.I) and not l.lower().startswith("result")]
    warns = [l for l in lines if re.search(r":\s*warning\b", l, re.I)]
    result = next((l for l in reversed(lines) if l.lower().startswith("result")), lines[-1] if lines else "")
    m = re.search(r"(\d+)\s+error", result, re.I)
    ok = (int(m.group(1)) == 0) if m else (not errs and src.with_suffix(".ex5").exists())
    return {"ok": ok, "result": result, "errors": errs[:60], "warnings": warns[:60], "log": lines[-80:]}


def tail(f: Path, n: int):
    if not f.exists():
        return []
    return read_any(f).splitlines()[-n:]


def collect(last_compile):
    d = main_dir()
    st = {"sync_version": VERSION, "vps_time": time.strftime("%Y-%m-%d %H:%M:%S"), "utc": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
          "data_dir": str(d) if d else None, "allow_deploy": ALLOW_DEPLOY, "last_compile": last_compile}
    if d:
        src = d / "MQL5" / "Experts" / EA_FILE
        if src.exists():
            ver = next((l.strip() for l in read_any(src).splitlines() if l.startswith("#property version")), "")
            ex5 = src.with_suffix(".ex5")
            st["ea"] = {"version": ver, "source_mtime": time.ctime(src.stat().st_mtime),
                        "ex5_mtime": time.ctime(ex5.stat().st_mtime) if ex5.exists() else None}
        day = time.strftime("%Y%m%d")
        st["experts_log"] = tail(d / "MQL5" / "Logs" / f"{day}.log", 400)
        st["journal"] = tail(d / "logs" / f"{day}.log", 150)
    states = {}
    for f in glob.glob(str(common_files() / "state_*.json")):
        try:
            states[Path(f).name] = {"age_sec": int(time.time() - os.path.getmtime(f)), "data": json.loads(read_any(Path(f)))}
        except Exception as e:
            states[Path(f).name] = {"error": str(e)}
    st["ea_state"] = states
    return st


# ---------------- GitHub ----------------
def push_status(st: dict):
    """Branch `status` = satu commit tanpa parent, ditimpa tiap kali (riwayat tidak menumpuk)."""
    content = json.dumps(st, ensure_ascii=False, indent=1)
    readme = "Status VPS 9algo, ditimpa otomatis oleh 9algo_sync.py. Jangan diedit.\n"
    c, tree, _ = gh("POST", "/git/trees", {"tree": [
        {"path": "status.json", "mode": "100644", "type": "blob", "content": content},
        {"path": "README.md", "mode": "100644", "type": "blob", "content": readme}]})
    if c != 201:
        raise RuntimeError(f"tree {c} {tree}")
    c, com, _ = gh("POST", "/git/commits", {"message": "status " + st["utc"], "tree": tree["sha"], "parents": []})
    if c != 201:
        raise RuntimeError(f"commit {c} {com}")
    c, r, _ = gh("PATCH", "/git/refs/heads/status", {"sha": com["sha"], "force": True})
    if c == 422 or c == 404:
        c, r, _ = gh("POST", "/git/refs", {"ref": "refs/heads/status", "sha": com["sha"]})
    if c not in (200, 201):
        raise RuntimeError(f"ref {c} {r}")


def load_state():
    try:
        return json.loads(STATE.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_state(s):
    STATE.write_text(json.dumps(s, indent=1), encoding="utf-8")


def check_request(state):
    hdr = {"If-None-Match": state["etag"]} if state.get("etag") else {}
    c, js, h = gh("GET", "/contents/deploy/request.json?ref=main", headers=hdr)
    if c == 304 or c == 404:
        return None
    if c != 200:
        log(f"request.json: HTTP {c} {str(js)[:200]}")
        return None
    state["etag"] = h.get("ETag") or h.get("etag")
    try:
        req = json.loads(base64.b64decode(js["content"]).decode("utf-8"))
    except Exception as e:
        log(f"request.json rusak: {e}")
        return None
    if not req.get("id") or req.get("id") == state.get("done_id"):
        return None
    return req


def fetch_file(path):
    c, js, _ = gh("GET", f"/contents/{path}?ref=main")
    if c != 200:
        raise RuntimeError(f"unduh {path}: HTTP {c}")
    if js.get("content"):
        return base64.b64decode(js["content"])
    # file > 1 MB: pakai blob API
    c, blob, _ = gh("GET", f"/git/blobs/{js['sha']}")
    return base64.b64decode(blob["content"])


def handle_request(req):
    d = main_dir()
    if not d:
        return {"id": req["id"], "ok": False, "result": "folder data MT5 tidak ditemukan"}
    src_bytes = fetch_file(req.get("file", f"src/{EA_FILE}"))
    ci_dir = d / "MQL5" / "Experts" / "9algo_ci"
    ci_dir.mkdir(parents=True, exist_ok=True)
    ci_src = ci_dir / EA_FILE
    ci_src.write_bytes(src_bytes)
    log(f"compile uji {req['id']} ...")
    test = compile_file(d, ci_src)
    out = {"id": req["id"], "time": time.strftime("%Y-%m-%d %H:%M:%S"), "test_compile": test, "deployed": False}
    if not test["ok"]:
        out["result"] = "compile uji GAGAL - tidak dipasang"
        return out
    if not (req.get("deploy") and ALLOW_DEPLOY):
        out["result"] = "compile uji OK (deploy tidak diminta / dimatikan)"
        return out
    live = d / "MQL5" / "Experts" / EA_FILE
    if live.exists():
        bk = ci_dir / f"backup_{time.strftime('%Y%m%d_%H%M%S')}_{EA_FILE}"
        shutil.copy2(live, bk)
        out["backup"] = str(bk)
    live.write_bytes(src_bytes)
    log("compile live ...")
    lc = compile_file(d, live)
    out["live_compile"] = lc
    out["deployed"] = lc["ok"]
    out["result"] = "DIPASANG - EA di chart reload otomatis" if lc["ok"] else "compile live gagal (cek live_compile)"
    return out


def main():
    log(f"9algo_sync {VERSION} mulai: repo {OWNER}/{REPO}, interval {INTERVAL}s, deploy {'ON' if ALLOW_DEPLOY else 'OFF'}")
    c, js, _ = gh("GET", "")
    if c != 200:
        log(f"[!] Tidak bisa akses repo ({c}): {js.get('message', js)} -> cek owner/repo/token di sync_config.json")
        return
    state = load_state()
    while True:
        try:
            req = check_request(state)
            if req:
                res = handle_request(req)
                state["done_id"] = req["id"]
                state["last_compile"] = res
                log(f"permintaan {req['id']}: {res.get('result')}")
            save_state(state)
            push_status(collect(state.get("last_compile")))
            log("status terkirim")
        except Exception as e:
            log("[!] " + str(e))
            traceback.print_exc()
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
