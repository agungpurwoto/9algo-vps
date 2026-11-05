"""Isi/lengkapi sync_config.json lewat pertanyaan di layar (dipanggil setup_sync.bat)."""
import getpass, json
from pathlib import Path

p = Path(__file__).with_name("sync_config.json")
cfg = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}

def ask(label, default=""):
    v = input(f"  {label}{' [' + default + ']' if default else ''}: ").strip()
    return v or default

if not cfg.get("token"):
    print("\n== GitHub ==")
    cfg["owner"] = ask("Username GitHub", cfg.get("owner", "agungpurwoto"))
    cfg["repo"] = ask("Nama repo", cfg.get("repo", "9algo-vps"))
    cfg["token"] = getpass.getpass("  Token GitHub (github_pat_..., tidak tampil saat diketik/ditempel): ").strip()
    cfg.setdefault("interval", 90)
    cfg.setdefault("allow_deploy", True)

if not (cfg.get("tester") or {}).get("password"):
    print("\n== Login untuk BACKTEST (terminal MT5 terpisah, tidak mengganggu yang live) ==")
    print("  Pakai password INVESTOR (read-only) dari email/dashboard The5ers. Disimpan hanya di VPS ini.")
    t = cfg.get("tester") or {}
    t["login"] = ask("Nomor akun MT5", str(t.get("login", "26804145")))
    t["server"] = ask("Server", t.get("server", "FivePercentOnline-Real"))
    t["password"] = getpass.getpass("  Password investor (tidak tampil): ").strip()
    cfg["tester"] = t

p.write_text(json.dumps(cfg, indent=1), encoding="utf-8")
print("\nKonfigurasi tersimpan di sync_config.json\n")
