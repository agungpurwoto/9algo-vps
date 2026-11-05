"""
9algo VPS <-> GitHub sync (tanpa koneksi masuk ke VPS; hanya keluar ke api.github.com)

Tiap siklus (default 90 detik):
  1. KIRIM status ke branch `status` (selalu 1 commit, ditimpa): state JSON EA, log Experts & Journal
     hari ini, versi source/ex5 terpasang, hasil compile terakhir.
  2. CEK permintaan di branch `main`: deploy/request.json  {"id": "...", "file": "src/9algo.mq5", "deploy": true}
     -> unduh source, compile dulu di folder uji (MQL5/Experts/9algo_ci). Kalau 0 error dan deploy=true:
        backup source lama, pasang ke MQL5/Experts/9algo.mq5, compile (EA di chart reload otomatis).
     Hasilnya masuk ke status.

  3. CEK deploy/tester.json {"id": "...", "jobs": [...]} -> jalankan backtest di terminal MT5 TERPISAH (portable,
     C:/9algo_tester/mt5, prioritas rendah, login investor) lalu kirim ringkasan hasil ke status.
  4. Update diri sendiri kalau vps/9algo_sync.py di repo berubah.

Tidak bisa mengirim order / mengubah setelan akun. Aksi hanya: compile + pasang file EA, dan backtest di terminal terpisah.
Konfigurasi: sync_config.json (dibuat setup_sync.bat): {"owner":..,"repo":..,"token":..,"interval":90,"allow_deploy":true}
Python 3.8+ standar, tanpa library tambahan.
"""
import base64, glob, hashlib, json, os, re, shutil, subprocess, sys, tempfile, threading, time, traceback, urllib.error, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CFG = json.loads((HERE / "sync_config.json").read_text(encoding="utf-8"))
OWNER, REPO, TOKEN = CFG["owner"], CFG["repo"], CFG["token"]
INTERVAL = int(CFG.get("interval", 90))
ALLOW_DEPLOY = bool(CFG.get("allow_deploy", True))
EA_FILE = CFG.get("ea_file", "9algo.mq5")
STATE = HERE / "sync_state.json"
API = f"https://api.github.com/repos/{OWNER}/{REPO}"
VERSION = "1.2"


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
          "data_dir": str(d) if d else None, "allow_deploy": ALLOW_DEPLOY, "last_compile": last_compile,
          "tester": tester_status()}
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
    files = [{"path": "status.json", "mode": "100644", "type": "blob", "content": content},
             {"path": "README.md", "mode": "100644", "type": "blob", "content": readme}]
    if TESTER["results"]:
        files.append({"path": "tester_results.json", "mode": "100644", "type": "blob",
                      "content": json.dumps(TESTER["results"], ensure_ascii=False)})
    c, tree, _ = gh("POST", "/git/trees", {"tree": files})
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


def fetch_json_if_changed(state, path, etag_key):
    hdr = {"If-None-Match": state[etag_key]} if state.get(etag_key) else {}
    c, js, h = gh("GET", f"/contents/{path}?ref=main", headers=hdr)
    if c == 304 or c == 404:
        return None
    if c != 200:
        log(f"{path}: HTTP {c} {str(js)[:200]}")
        return None
    state[etag_key] = h.get("ETag") or h.get("etag")
    try:
        return json.loads(base64.b64decode(js["content"]).decode("utf-8"))
    except Exception as e:
        log(f"{path} rusak: {e}")
        return None


def check_request(state):
    req = fetch_json_if_changed(state, "deploy/request.json", "etag")
    if not req or not req.get("id") or req.get("id") == state.get("done_id"):
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
    if lc["ok"]:
        # compile lewat command line tidak membuat MT5 memuat ulang EA -> beri tanda; EA (v2.88+) memuat ulang dirinya
        try:
            (d / "MQL5" / "Files").mkdir(parents=True, exist_ok=True)
            (d / "MQL5" / "Files" / "9algo_reload.txt").write_text(f"{req['id']} {time.strftime('%Y-%m-%d %H:%M:%S')}", encoding="ascii")
        except Exception as e:
            out["reload_flag_error"] = str(e)
    out["result"] = "DIPASANG - EA di chart reload otomatis" if lc["ok"] else "compile live gagal (cek live_compile)"
    return out


# ---------------- self-update ----------------
def self_update(state):
    c, js, h = gh("GET", "/contents/vps/9algo_sync.py?ref=main",
                  headers={"If-None-Match": state["etag_self"]} if state.get("etag_self") else {})
    if c != 200:
        return
    state["etag_self"] = h.get("ETag") or h.get("etag")
    new = base64.b64decode(js["content"])
    me = Path(__file__).resolve()
    if hashlib.sha1(new).hexdigest() == hashlib.sha1(me.read_bytes()).hexdigest():
        return
    tmp = me.with_suffix(".new")
    tmp.write_bytes(new)
    try:
        compile(new.decode("utf-8"), str(tmp), "exec")
    except Exception as e:
        log(f"[!] update sync ditolak (syntax error): {e}")
        return
    shutil.copy2(me, me.with_suffix(".bak"))
    os.replace(tmp, me)
    save_state(state)
    log("sync diperbarui dari repo -> restart")
    os.execv(sys.executable, [sys.executable, str(me)])


# ---------------- backtest (terminal portable terpisah) ----------------
TESTER = {"running": None, "results": []}


def tester_dir():
    return Path(CFG.get("tester_dir", "C:/9algo_tester/mt5"))


def ensure_tester():
    td = tester_dir()
    if (td / "terminal64.exe").exists():
        return td
    d = main_dir()
    inst = None
    if d and (d / "origin.txt").exists():
        inst = Path(read_any(d / "origin.txt").strip().strip("\ufeff"))
    if CFG.get("mt5_dir"):
        inst = Path(CFG["mt5_dir"])
    if not inst or not (inst / "terminal64.exe").exists():
        raise RuntimeError("folder instalasi MT5 tidak ditemukan untuk membuat terminal tester")
    log(f"menyalin MT5 {inst} -> {td} (sekali saja)")
    shutil.copytree(inst, td, dirs_exist_ok=True)
    return td


def write_utf16(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\xff\xfe" + text.replace("\n", "\r\n").encode("utf-16-le"))


def parse_report(html: str):
    txt = re.sub(r"<[^>]+>", "|", html)
    txt = re.sub(r"\|+", "|", txt.replace("&nbsp;", " "))
    out = {}
    keys = {"net": "Total Net Profit", "pf": "Profit Factor", "trades": "Total Trades", "payoff": "Expected Payoff",
            "dd_bal": "Balance Drawdown Maximal", "dd_eq": "Equity Drawdown Maximal", "rel_dd_eq": "Equity Drawdown Relative",
            "win": "Profit Trades (% of total)", "loss": "Loss Trades (% of total)", "recovery": "Recovery Factor",
            "sharpe": "Sharpe Ratio", "gross_profit": "Gross Profit", "gross_loss": "Gross Loss",
            "max_consec_loss": "Maximal consecutive loss (count)", "bars": "Bars", "ticks": "Ticks", "quality": "History Quality"}
    for k, lab in keys.items():
        m = re.search(re.escape(lab) + r":?\|\s*([^|]+)", txt)
        if m:
            out[k] = m.group(1).strip()
    # tabel deals: waktu, simbol, arah, profit, komentar (untuk statistik per strategi)
    deals = []
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.S | re.I):
        cells = [re.sub(r"<[^>]+>", "", c).replace("&nbsp;", " ").strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S | re.I)]
        if len(cells) >= 13 and re.match(r"\d{4}\.\d{2}\.\d{2}", cells[0]) and cells[4] in ("in", "out", "in/out", "out by"):
            deals.append({"t": cells[0], "sym": cells[2], "type": cells[3], "dir": cells[4], "vol": cells[5], "price": cells[6],
                          "order": cells[7], "profit": cells[10], "comment": cells[12]})
    return out, deals


def run_tester_job(td: Path, job: dict, creds: dict):
    name = re.sub(r"[^A-Za-z0-9_-]", "_", job["name"])
    src = fetch_file(job.get("file", f"src/{EA_FILE}"))
    exp_dir = td / "MQL5" / "Experts" / "9algo_test"
    exp_dir.mkdir(parents=True, exist_ok=True)
    srcf = exp_dir / f"{name}.mq5"
    srcf.write_bytes(src)
    me = td / "metaeditor64.exe"
    logf = Path(tempfile.gettempdir()) / f"9algo_tc_{name}.log"
    subprocess.run([str(me), "/portable", f"/compile:{srcf}", f"/log:{logf}"], timeout=300, capture_output=True)
    comp = read_any(logf).splitlines()[-3:] if logf.exists() else ["(log compile tidak ada)"]
    if not srcf.with_suffix(".ex5").exists():
        return {"name": job["name"], "ok": False, "error": "compile gagal", "compile": comp}
    params = job.get("inputs", {})
    write_utf16(td / "MQL5" / "Profiles" / "Tester" / f"{name}.set", "\n".join(f"{k}={v}" for k, v in params.items()) + "\n")
    rep_rel = f"reports\\{name}"
    for ext in (".htm", ".html"):
        try:
            (td / (rep_rel + ext)).unlink()
        except Exception:
            pass
    ini = "\n".join([
        "[Common]", f"Login={creds['login']}", f"Password={creds['password']}", f"Server={creds['server']}", "",
        "[Tester]", f"Expert=9algo_test\\{name}.ex5", f"ExpertParameters={name}.set",
        f"Symbol={job['symbol']}", f"Period={job.get('period', 'H1')}", f"Model={job.get('model', 1)}",
        f"FromDate={job['from']}", f"ToDate={job['to']}", f"Deposit={job.get('deposit', 2500)}", "Currency=USD",
        f"Leverage={job.get('leverage', 100)}", "Optimization=0", "Visual=0", f"Report={rep_rel}", "ReplaceReport=1",
        "ShutdownTerminal=1", ""])
    inif = td / f"9algo_{name}.ini"
    inif.write_text(ini, encoding="ascii", errors="replace")
    t0 = time.time()
    flags = 0x00000040 if os.name == "nt" else 0          # IDLE_PRIORITY_CLASS: jangan ganggu terminal live
    p = subprocess.Popen([str(td / "terminal64.exe"), "/portable", f"/config:{inif}"], creationflags=flags)
    try:
        p.wait(timeout=int(job.get("timeout_min", 180)) * 60)
    except subprocess.TimeoutExpired:
        p.kill()
        return {"name": job["name"], "ok": False, "error": "timeout", "minutes": round((time.time() - t0) / 60, 1)}
    finally:
        try:
            inif.unlink()                                   # file berisi password: hapus
        except Exception:
            pass
    rep = next((td / (rep_rel + e) for e in (".htm", ".html") if (td / (rep_rel + e)).exists()), None)
    if not rep:
        return {"name": job["name"], "ok": False, "error": "report tidak dibuat (cek login tester / simbol / tanggal)",
                "minutes": round((time.time() - t0) / 60, 1)}
    stats, deals = parse_report(read_any(rep))
    return {"name": job["name"], "ok": True, "symbol": job["symbol"], "from": job["from"], "to": job["to"],
            "minutes": round((time.time() - t0) / 60, 1), "stats": stats, "deals": deals[-3000:]}


def tester_worker(req, state):
    try:
        creds = CFG.get("tester")
        if not creds or not creds.get("password"):
            TESTER["results"] = [{"id": req["id"], "ok": False, "error": "login tester belum diisi (jalankan setup_sync.bat versi baru)"}]
            return
        td = ensure_tester()
        res = []
        for job in req.get("jobs", []):
            TESTER["running"] = {"id": req["id"], "job": job.get("name"), "since": time.strftime("%H:%M:%S"), "done": len(res)}
            log(f"backtest {req['id']} / {job.get('name')} ...")
            try:
                r = run_tester_job(td, job, creds)
            except Exception as e:
                r = {"name": job.get("name"), "ok": False, "error": str(e)}
            r["id"] = req["id"]
            res.append(r)
            TESTER["results"] = res
            log(f"backtest {job.get('name')}: {'OK' if r.get('ok') else r.get('error')}")
    finally:
        TESTER["running"] = None
        state["tester_done_id"] = req["id"]
        save_state(state)


def check_tester(state):
    if TESTER["running"]:
        return
    req = fetch_json_if_changed(state, "deploy/tester.json", "etag_tester")
    if not req or not req.get("id") or req.get("id") == state.get("tester_done_id"):
        return
    TESTER["running"] = {"id": req["id"], "job": "mulai", "since": time.strftime("%H:%M:%S"), "done": 0}
    threading.Thread(target=tester_worker, args=(req, state), daemon=True).start()


def tester_status():
    return {"running": TESTER["running"], "results": [{k: v for k, v in r.items() if k != "deals"} for r in TESTER["results"]],
            "configured": bool((CFG.get("tester") or {}).get("password")), "dir": str(tester_dir())}


def main():
    log(f"9algo_sync {VERSION} mulai: repo {OWNER}/{REPO}, interval {INTERVAL}s, deploy {'ON' if ALLOW_DEPLOY else 'OFF'}")
    c, js, _ = gh("GET", "")
    if c != 200:
        log(f"[!] Tidak bisa akses repo ({c}): {js.get('message', js)} -> cek owner/repo/token di sync_config.json")
        return
    state = load_state()
    TESTER["results"] = state.get("tester_results", [])
    while True:
        try:
            self_update(state)
            check_tester(state)
            req = check_request(state)
            if req:
                res = handle_request(req)
                state["done_id"] = req["id"]
                state["last_compile"] = res
                log(f"permintaan {req['id']}: {res.get('result')}")
            state["tester_results"] = TESTER["results"]
            save_state(state)
            push_status(collect(state.get("last_compile")))
            log("status terkirim")
        except Exception as e:
            log("[!] " + str(e))
            traceback.print_exc()
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
