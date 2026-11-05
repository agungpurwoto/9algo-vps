# 9algo-vps

Jembatan antara VPS MT5 dan Claude (tanpa koneksi masuk ke VPS).

| Lokasi | Isi |
|---|---|
| `src/9algo.mq5` | Source EA terbaru (yang ingin dipasang) |
| `deploy/request.json` | Permintaan compile/pasang: `{"id": "...", "file": "src/9algo.mq5", "deploy": true}` |
| branch `status` → `status.json` | Dikirim VPS tiap 90 detik: state EA, log Experts/Journal, versi terpasang, hasil compile |
| `vps/` | `9algo_sync.py` + `setup_sync.bat` (dijalankan sekali di VPS) |

Alur deploy: VPS melihat `id` baru → unduh source → compile uji di `MQL5/Experts/9algo_ci` →
hanya jika 0 error: backup source lama, pasang ke `MQL5/Experts/9algo.mq5`, compile (EA reload otomatis).
Sync tidak bisa mengirim order atau mengubah setelan akun.
