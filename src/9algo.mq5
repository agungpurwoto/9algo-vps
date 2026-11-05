//+------------------------------------------------------------------+
//|                                                        9algo.mq5 |
//|                                             9algo by Singularity |
//|                                                                  |
//|  9 algoritma, 1 EA. Pasang di chart mana saja, strategi dipilih  |
//|  otomatis sesuai simbol:                                         |
//|    XAUUSD   -> Noise, Narrow, Week, Round, BigDay                |
//|    XAGUSD   -> BigDay                                            |
//|    USDJPY   -> Tokyo (butuh GBPUSD), Narrow                      |
//|    NQ/US100 -> Noise (2 engine)                                  |
//|                                                                  |
//|  Prop-firm guard (account-wide, dibagi lewat Global Variables):  |
//|    - Max Daily Loss & Max Loss (statis / trailing HWM)           |
//|    - Cap total open risk (posisi + pending, semua simbol)        |
//|    - Panel target: profit goal, profitable days, inactivity,     |
//|      statistik akun                                              |
//|  Cukup ganti InitialBalance: semua limit, target, dan lot size   |
//|  dihitung dari persen saldo awal (preset risk = rekomendasi,     |
//|  max DD historis gabungan ~6%, non-compounding).                 |
//|  Flag "total halt" persisten -> hapus via Tools > Global Vars    |
//|  (F3), tombol RESET HALT di panel, atau ResetGuardState=true.    |
//|                                                                  |
//|  Copyright (c) 2026 Singularity. All rights reserved.            |
//|  Lisensi: proprietary. Dilarang menyalin, mendistribusikan, atau |
//|  memodifikasi tanpa izin tertulis dari Singularity.              |
//+------------------------------------------------------------------+
#property copyright   "9algo by Singularity"
#property link        "https://singularity.id"
#property version     "2.86"
#property description "9algo by Singularity - 9 algoritma dalam 1 EA untuk XAUUSD, XAGUSD, USDJPY, NQ"
#property description "Prop-firm guard: Max Daily Loss, Max Loss (trailing HWM), cap total risk, panel target & statistik"
#include <Trade\Trade.mqh>

enum ENUM_RISK_MODE
  {
   NonCompounding_PercentOfInitialBalance = 0,
   Compounding_PercentOfCurrentEquity = 1
  };

enum ENUM_DAILY_BASE
  {
   DailyBase_StartOfDay = 0,   // % dari balance/equity awal hari (umum di prop firm)
   DailyBase_InitialBalance = 1 // % dari saldo awal akun
  };

enum ENUM_ROLE
  {
   Role_Auto    = -1, // otomatis
   Role_Sprint  = 0,  // Sprint  : gold breakout, 14 hari, cap x3
   Role_Counter = 1,  // Counter : pullback metals + JPY + NQ, 30 hari, cap x2.5
   Role_Index   = 2,  // Index   : NQ + week/round gold, 30 hari, cap x2.5
   Role_Steady  = 3   // Steady  : semua strategi, 45 hari, cap x1.5
  };

enum ENUM_CSTYLE
  {
   Style_Fast         = 0, // Fast: risk tetap ~1%/trade saat challenge (lebih banyak & lebih cepat lolos, lebih banyak gagal)
   Style_Conservative = 1  // Conservative: Challenge Mode adaptif (lambat, hampir tidak pernah gagal)
  };

enum ENUM_PHASE
  {
   Phase_Auto         = -1, // OTOMATIS: deteksi dari akun (komentar deposit, nama server, trade mode)
   Phase_Challenge    = 0,  // Challenge / Phase 1 (kejar target)
   Phase_Funded       = 1,  // Funded (jaga akun, risk turun)
   Phase_Verification = 2   // Verification / Phase 2 (target lebih kecil)
  };

enum ENUM_NEWS_IMP
  {
   News_HighOnly   = 0, // High impact saja
   News_MediumHigh = 1  // Medium + High
  };

enum ENUM_MAXLOSS
  {
   MaxLoss_StaticFromInitial = 0, // statis: saldo awal - X%
   MaxLoss_TrailingFromHWM   = 1  // trailing: all-time high-water-mark equity - X%
  };

input group "=== Preset ==="
input bool            UsePresetTerbaru      = true;   // true = selalu pakai setelan rekomendasi versi EA ini (update EA = setelan ikut terbaru, tanpa load .set). false = pakai nilai input di bawah

input group "=== Akun & Aturan Prop Firm ==="
input double          InitialBalance        = 0;      // 0 = OTOMATIS (deposit history / snap ke ukuran akun prop standar)
input ENUM_RISK_MODE  I_RiskMode              = NonCompounding_PercentOfInitialBalance;
ENUM_RISK_MODE RiskMode = NonCompounding_PercentOfInitialBalance;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_PropMaxDailyLossMoney = 0;      // Max Daily Loss dalam uang (0 = pakai %, ikut InitialBalance)
double PropMaxDailyLossMoney = 0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_PropMaxDailyLossPct   = 5.0;    // Max Daily Loss (%) - dipakai jika uang = 0
double PropMaxDailyLossPct = 5.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input ENUM_DAILY_BASE I_DailyLossBase         = DailyBase_StartOfDay;
ENUM_DAILY_BASE DailyLossBase = DailyBase_StartOfDay;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_DailyResetHourUTC     = -1;     // Reset harian: -1 = tengah malam server broker (umum di prop firm), 0..23 = jam UTC
int DailyResetHourUTC = -1;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_PropMaxLossMoney      = 0;      // Max Loss dalam uang (0 = pakai %, ikut InitialBalance)
double PropMaxLossMoney = 0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_PropMaxLossPct        = 10.0;   // Max Loss (%) - dipakai jika uang = 0
double PropMaxLossPct = 10.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input ENUM_MAXLOSS    I_MaxLossMode           = MaxLoss_StaticFromInitial; // Max Loss dihitung dari... (The5ers High Stakes: statis dari saldo awal)
ENUM_MAXLOSS MaxLossMode = MaxLoss_StaticFromInitial;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_TrailingFloorCapAtInitial = true; // Floor trailing berhenti naik di saldo awal
bool TrailingFloorCapAtInitial = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_GuardFraction         = 0.80;   // EA berhenti di 80% dari limit prop firm
double GuardFraction = 0.80;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_CloseAllOnGuard       = true;   // Tutup semua posisi saat guard kena
bool CloseAllOnGuard = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_MaxTotalOpenRiskPct   = 2.5;    // Cap total risk terbuka (semua simbol, %)
double MaxTotalOpenRiskPct = 2.5;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_RiskScale             = 1.0;    // Pengali semua risk strategi (1.0 = preset rekomendasi)
double RiskScale = 1.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_MinLotFallback        = true;   // Akun kecil: pakai lot minimum jika risk < 0.01 lot
bool MinLotFallback = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_MinLotMaxRiskPct      = 0.75;   // ...tapi hanya jika risk lot minimum <= X% saldo (akun FUNDED)
double MinLotMaxRiskPct = 0.75;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_MinLotMaxRiskFastPct  = 2.0;    // ...batas yang sama saat challenge / verifikasi (akun kecil, SL lebar)
double MinLotMaxRiskFastPct = 2.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_StopEntriesAtProfitPct= 0;      // Stop entry baru setelah profit total X% (0 = off)
double StopEntriesAtProfitPct = 0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_DailyProfitLockPct    = 0;      // Stop entry baru hari ini setelah profit harian X% (0 = off)
double DailyProfitLockPct = 0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_CloseBeforeWeekend    = false;  // Tutup semua posisi Jumat sebelum sesi NY tutup
bool CloseBeforeWeekend = false;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_WeekendCloseNYMin     = 16 * 60 + 45; // ...menit NY (16:45 = 1005)
int WeekendCloseNYMin = 16 * 60 + 45;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            PushAlerts            = true;   // Push notification: guard halt, entry/exit (butuh MetaQuotes ID)

input group "=== Filter News (kalender ekonomi MT5) ==="
input bool            I_NewsFilter            = true;   // Blok entry baru di sekitar news
bool NewsFilter = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_NewsBeforeMin         = 60;     // Menit sebelum news
int NewsBeforeMin = 60;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_NewsAfterMin          = 60;     // Menit sesudah news
int NewsAfterMin = 60;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input ENUM_NEWS_IMP   I_NewsImportance        = News_HighOnly;
ENUM_NEWS_IMP NewsImportance = News_HighOnly;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input string          NewsExtraCurrencies   = "";     // Tambahan mata uang, mis. "EUR,GBP" (USD/JPY otomatis sesuai simbol)
input bool            I_NewsClosePositions    = false;  // Tutup posisi terbuka saat masuk window news
bool NewsClosePositions = false;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_NewsHardMin           = 3;      // Aturan firm (High Stakes: tidak boleh eksekusi order +-2 menit news): blok + tarik order di broker +-X menit, selalu aktif
int NewsHardMin = 3;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            ResetGuardState       = false;  // true = hapus semua state tersimpan (halt, HWM, tanggal mulai, pause) saat init

input group "=== Consistency Rule (prop firm) ==="
input bool            I_ConsistencyGuard      = true;   // Jaga best day <= X% dari total profit
bool ConsistencyGuard = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_ConsistencyMaxPct     = 40.0;   // Batas best-day (% dari total profit), isi sesuai firm
double ConsistencyMaxPct = 40.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_ConsistencySafety     = 0.85;   // EA stop entry hari ini di 85% dari batas
double ConsistencySafety = 0.85;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_LotConsistency        = false;  // Jaga lot tiap trade dalam rentang +-X% dari median 20 trade terakhir
bool LotConsistency = false;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_LotConsistencyPct     = 50.0;   // Rentang lot (+-%)
double LotConsistencyPct = 50.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_NetOfCommission       = true;   // Hitung risk termasuk komisi broker
bool NetOfCommission = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)

input group "=== Regime Filter ONNX (opsional, model di Common/Files/9algo/regime.onnx) ==="
input bool            I_RegimeFilter          = false;  // Aktifkan filter regime (butuh file model)
bool RegimeFilter = false;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_RegimeTrendMin        = 0.55;   // Prob trending minimal untuk strategi breakout
double RegimeTrendMin = 0.55;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_RegimeChopMin         = 0.55;   // Prob choppy minimal untuk strategi pullback
double RegimeChopMin = 0.55;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)

input group "=== Integrasi (MCP / Claude Code) ==="
input bool            ExportState           = true;   // Tulis state JSON ke Common/Files/9algo/ tiap 30 detik

input group "=== Challenge Mode ==="
input ENUM_PHASE      AccountPhase          = Phase_Auto;
input int             I_ChallengeSteps        = 2;      // 1 = 1-step (lolos -> funded), 2 = 2-step (lolos -> verification -> funded)
int ChallengeSteps = 2;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_VerificationGoalPct   = 5.0;    // Target fase verification (%)
double VerificationGoalPct = 5.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_ChallengeMode         = true;   // Risk otomatis saat challenge (lihat ChallengeStyle)
bool ChallengeMode = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input ENUM_CSTYLE     I_ChallengeStyle        = Style_Fast; // Hasil simulasi 10 akun: Fast ~7 funded vs Conservative ~5 dalam 6 bulan
ENUM_CSTYLE ChallengeStyle = Style_Fast;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_FastRiskPct           = 1.0;    // Fast: rata-rata risk per trade (%), turun separuh setelah 90% goal
double FastRiskPct = 1.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_FastOpenRiskPct       = 3.5;    // Fast: cap total open risk (%)
double FastOpenRiskPct = 3.5;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_FastDirCapPct         = 2.0;    // Fast: cap risk searah (%)
double FastDirCapPct = 2.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_TargetDays            = 14;     // Target lolos dalam X hari (0 = tidak mengejar waktu)
int TargetDays = 14;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_MaxRiskScaleAuto      = 3.0;    // Batas atas pengali risk otomatis
double MaxRiskScaleAuto = 3.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_PhaseRiskA            = 1.5;    // Pengali saat progres 0-50% goal
double PhaseRiskA = 1.5;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_PhaseRiskB            = 1.0;    // Pengali saat progres 50-90% goal
double PhaseRiskB = 1.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_PhaseRiskC            = 0.5;    // Pengali saat progres >90% goal
double PhaseRiskC = 0.5;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_CushionK              = 8.0;    // Tambahan pengali per 1% cushion profit (house money)
double CushionK = 8.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_ProgressLock          = true;   // Kunci progres: floor = setengah profit yang sudah dicapai
bool ProgressLock = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_ProgressLockStepPct   = 2.5;    // Floor naik tiap profit +X% saldo awal
double ProgressLockStepPct = 2.5;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_DirectionalCapPct     = 1.2;    // Cap risk posisi searah (semua simbol 9algo), % saldo
double DirectionalCapPct = 1.2;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_SpreadFilter          = true;   // Skip entry saat spread > X x rata-rata
bool SpreadFilter = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_SpreadMaxMult         = 2.0;
double SpreadMaxMult = 2.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input bool            I_AutoPauseNegative     = true;   // Pause otomatis strategi ber-expectancy negatif
bool AutoPauseNegative = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_AutoPauseMinTrades    = 15;     // ...setelah minimal N trade
int AutoPauseMinTrades = 15;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_FundedRiskScale       = 0.6;    // Pengali risk saat fase Funded
double FundedRiskScale = 0.6;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)

input group "=== Multi-akun: ZERO CONFIG (beberapa terminal di 1 VPS) ==="
input bool            I_AutoRole              = true;   // Peran akun (Sprint/Counter/Index/Steady) dibagi otomatis antar akun 1 firm
bool AutoRole = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input ENUM_ROLE       RoleOverride          = Role_Auto; // Paksa peran tertentu (Auto = ikut pembagian)
input string          FirmTag               = "";     // Kosong = otomatis dari nama broker. Akun dengan tag sama dilarang saling hedging
input bool            I_GroupHedgeGuard       = true;   // Tolak entry yang berlawanan arah dengan akun lain (tag sama)
bool GroupHedgeGuard = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)

input group "=== Antrean order (pending siaga) ==="
input bool            I_VirtualPending        = true;   // Semua setup dipasang SIAGA di EA; order asli ke broker baru dikirim saat harga mendekat & rule lolos
bool VirtualPending = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_ArmDistADR            = 0.25;   // Order asli dipasang saat jarak harga ke entry <= x ADR (yang paling dekat duluan)
double ArmDistADR = 0.25;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_DisarmDistADR         = 0.60;   // Order asli ditarik lagi saat harga menjauh > x ADR (budget risk dilepas untuk setup lain)
double DisarmDistADR = 0.60;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_LateFillADR           = 0.10;   // Harga sudah melewati entry (gap/lonjakan): tetap masuk market kalau lewatnya <= x ADR
double LateFillADR = 0.10;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)

input group "=== Garis bantu di chart ==="
input bool            ShowLevels            = true;   // Gambar level entry / SL / TP / batas waktu tiap strategi di chart
input bool            ShowNoiseBands        = true;   // Gambar band Noise (banyak segmen)
input bool            ChartStyle            = true;   // Rapikan chart: tema gelap, tanpa grid/volume, ruang kosong di kanan untuk label
input int             ChartShiftPct         = 30;     // Lebar ruang kosong di kanan chart (%) tempat kartu setup

input group "=== Auto Setup (pasang di 1 chart, sisanya otomatis) ==="
input bool            AutoDeployOtherCharts = true;   // Buka chart XAUUSD/XAGUSD/USDJPY/NQ lain & pasang 9algo otomatis
input ENUM_TIMEFRAMES AutoChartPeriod       = PERIOD_H1; // Timeframe chart yang dibuka otomatis

input group "=== Target Prop Firm (panel) ==="
input double          I_ProfitGoalMoney       = 0;      // Profit Goal dalam uang (0 = pakai %, ikut InitialBalance)
double ProfitGoalMoney = 0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_ProfitGoalPct         = 10.0;   // Profit Goal (%) - dipakai jika uang = 0
double ProfitGoalPct = 10.0;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_MinProfitableDays     = 3;      // Profitable Days minimal
int MinProfitableDays = 3;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double          I_ProfitableDayMinPct   = 0.5;    // Hari dihitung profit jika >= X% saldo awal (The5ers: 0.5%)
double ProfitableDayMinPct = 0.5;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input int             I_InactivityDays        = 30;     // Batas hari tanpa trade
int InactivityDays = 30;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input datetime        ChallengeStartDate    = 0;      // Mulai hitung statistik (0 = saat EA pertama dipasang)

input group "=== XAUUSD : Noise-AU  (NoiseMomentum - breakout band noise setelah NY open) ==="
input bool   I_NMG_On    = true;
bool NMG_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_NMG_Risk  = 0.18;   // preset rekomendasi
double NMG_Risk = 0.18;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   NMG_Magic = 12201;

input group "=== XAUUSD : Narrow-AU  (S009 - breakout high/low hari sempit) ==="
input bool   I_S009_On    = true;
bool S009_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_S009_Risk  = 0.32;  // preset rekomendasi
double S009_Risk = 0.32;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   S009_Magic = 9101;

input group "=== XAUUSD : Week-AU  (S015 - breakout high/low minggu lalu) ==="
input bool   I_S015_On    = true;
bool S015_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_S015_Risk  = 0.20;  // preset rekomendasi
double S015_Risk = 0.20;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   S015_Magic = 15101;

input group "=== XAUUSD : Round-AU  (S017 - breakout level bulat $50) ==="
input bool   I_S017_On    = true;
bool S017_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_S017_Risk  = 0.27;  // preset rekomendasi
double S017_Risk = 0.27;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   S017_Magic = 17101;

input group "=== XAUUSD : BigDay-AU  (S018 - pullback setelah hari range besar) ==="
input bool   I_S018G_On    = true;
bool S018G_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_S018G_Risk  = 0.18; // preset rekomendasi
double S018G_Risk = 0.18;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   S018G_Magic = 18101;

input group "=== XAGUSD : BigDay-AG  (S018 - pullback setelah hari range besar) ==="
input bool   I_S018S_On    = true;
bool S018S_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_S018S_Risk  = 0.32; // preset rekomendasi
double S018S_Risk = 0.32;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   S018S_Magic = 18201;

input group "=== USDJPY : Tokyo-JPY  (B8 - momentum sesi Tokyo, filter GBPUSD, butuh simbol GBPUSD) ==="
input bool   I_B8_On    = true;
bool B8_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_B8_Risk  = 0.23;    // preset rekomendasi
double B8_Risk = 0.23;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   B8_Magic = 8101;

input group "=== USDJPY : Narrow-JPY  (S009U - breakout high/low hari sempit) ==="
input bool   I_S009U_On    = true;
bool S009U_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_S009U_Risk  = 0.26; // preset rekomendasi
double S009U_Risk = 0.26;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   S009U_Magic = 9201;

input group "=== NASDAQ : Noise-NQ  (NoiseMomentum 2 engine = 2 magic) ==="
input bool   I_NMN_On    = true;
bool NMN_On = true;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input double I_NMN_Risk  = 0.15;   // preset rekomendasi
double NMN_Risk = 0.15;   // nilai efektif (preset terbaru, atau input di atas jika UsePresetTerbaru=false)
input long   NMN_Magic = 12101;

//+------------------------------------------------------------------+
//| Deteksi market                                                   |
//+------------------------------------------------------------------+
enum ENUM_MARKET { MKT_UNKNOWN = 0, MKT_GOLD, MKT_SILVER, MKT_USDJPY, MKT_NQ };

string GVP();
ENUM_MARKET g_market = MKT_UNKNOWN;
string      g_marketName = "";
bool        g_marketMatch = false;

//+------------------------------------------------------------------+
//| Timezone core (identik dengan versi lama)                        |
//+------------------------------------------------------------------+
int      g_tzModel = 2;
int      g_tzBase = 7 * 3600;
int      g_tzRecords = 0;
int      g_tzVotes[3];
datetime g_tzLastDetect = 0;
bool     g_tzOk = false;
datetime g_ofsCacheDay = -1;
int      g_ofsCacheVal = 0;

datetime DayStart(datetime t) { return t - (t % 86400); }
int DayOfWeekOf(datetime t) { return (int)(((t / 86400) + 4) % 7); }

datetime MakeDate(int y, int m, int d)
  {
   MqlDateTime s;
   s.year = y; s.mon = m; s.day = d; s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
  }

int YearOf(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year; }

datetime NthSunday(int y, int m, int n)
  {
   datetime first = MakeDate(y, m, 1);
   int dw = DayOfWeekOf(first);
   int add = (7 - dw) % 7;
   return first + (add + 7 * (n - 1)) * 86400;
  }

datetime LastSunday(int y, int m)
  {
   int ny = (m == 12) ? y + 1 : y;
   int nm = (m == 12) ? 1 : m + 1;
   datetime last = MakeDate(ny, nm, 1) - 86400;
   return last - DayOfWeekOf(last) * 86400;
  }

bool USDst(datetime utc)
  {
   int y = YearOf(utc);
   datetime a, b;
   if(y >= 2007) { a = NthSunday(y, 3, 2) + 7 * 3600; b = NthSunday(y, 11, 1) + 6 * 3600; }
   else          { a = NthSunday(y, 4, 1) + 7 * 3600; b = LastSunday(y, 10) + 6 * 3600; }
   return utc >= a && utc < b;
  }

bool UKDst(datetime utc)
  {
   int y = YearOf(utc);
   datetime a = LastSunday(y, 3) + 3600;
   datetime b = LastSunday(y, 10) + 3600;
   return utc >= a && utc < b;
  }

datetime UTCToLondon(datetime u) { return u + (UKDst(u) ? 3600 : 0); }
datetime UTCToNY(datetime u) { return u - (USDst(u) ? 4 * 3600 : 5 * 3600); }
datetime LondonToUTC(datetime l) { datetime u = l - 3600; if(UKDst(u)) return u; return l; }
datetime NYToUTC(datetime n) { datetime u = n + 4 * 3600; if(USDst(u)) return u; return n + 5 * 3600; }

int ServerOffsetAt(datetime s)
  {
   datetime d = DayStart(s);
   if(d == g_ofsCacheDay)
      return g_ofsCacheVal;
   datetime probe = d + 12 * 3600;
   int ofs = g_tzBase;
   if(g_tzModel == 1)
      ofs = g_tzBase;
   else if(g_tzModel == 2)
     {
      datetime u = NYToUTC(probe - g_tzBase);
      ofs = (int)(probe - u);
     }
   else
     {
      datetime u = LondonToUTC(probe - g_tzBase);
      ofs = (int)(probe - u);
     }
   g_ofsCacheDay = d;
   g_ofsCacheVal = ofs;
   return ofs;
  }

datetime ServerToUTC(datetime s) { return s - ServerOffsetAt(s); }
datetime UTCToServer(datetime u) { datetime s = u + ServerOffsetAt(u + g_tzBase); int o2 = ServerOffsetAt(s); return u + o2; }
datetime ServerToLondon(datetime s) { return UTCToLondon(ServerToUTC(s)); }
datetime ServerToNY(datetime s) { return UTCToNY(ServerToUTC(s)); }
datetime LondonToServer(datetime l) { return UTCToServer(LondonToUTC(l)); }
datetime NYToServer(datetime n) { return UTCToServer(NYToUTC(n)); }

int ModeOf(int &v[], int n, int &cnt)
  {
   int best = 0;
   cnt = 0;
   for(int i = 0; i < n; i++)
     {
      int c = 0;
      for(int j = 0; j < n; j++)
         if(v[j] == v[i])
            c++;
      if(c > cnt) { cnt = c; best = v[i]; }
     }
   return best;
  }

void LiveTZCorrection()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   long live = (long)(TimeTradeServer() - TimeGMT());
   int liveR = (int)(MathRound(live / 900.0) * 900);
   g_ofsCacheDay = -1;
   int modelNow = ServerOffsetAt(TimeTradeServer());
   if(liveR != modelNow)
     {
      g_tzBase += (liveR - modelNow);
      g_ofsCacheDay = -1;
     }
  }

bool DetectTimeZone(string sym)
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   datetime now = TimeCurrent();
   int n = CopyRates(sym, PERIOD_H1, now - 800 * 86400, now, r);
   if(n < 100) { LiveTZCorrection(); return false; }
   int a[], b[], c[];
   int k = 0;
   for(int i = 1; i < n; i++)
     {
      long gap = (long)(r[i].time - r[i - 1].time);
      if(gap < 30 * 3600)
         continue;
      datetime close = r[i - 1].time + 3600;
      int tau = (int)(close % 86400);
      int delta = tau - 17 * 3600;
      delta = ((delta % 86400) + 86400) % 86400;
      if(delta >= 18 * 3600)
         delta -= 86400;
      int us = USDst(close) ? 1 : 0;
      int uk = UKDst(close) ? 1 : 0;
      int u = delta - (us ? 4 * 3600 : 5 * 3600);
      ArrayResize(a, k + 1); ArrayResize(b, k + 1); ArrayResize(c, k + 1);
      a[k] = u; b[k] = delta; c[k] = u - uk * 3600;
      k++;
     }
   if(k < 3) { LiveTZCorrection(); return false; }
   int c1, c2, c3;
   int m1 = ModeOf(a, k, c1);
   int m2 = ModeOf(b, k, c2);
   int m3 = ModeOf(c, k, c3);
   g_tzVotes[0] = c1; g_tzVotes[1] = c2; g_tzVotes[2] = c3;
   g_tzRecords = k;
   int model = 2, base = m2, best = c2;
   if(c3 > best) { model = 3; base = m3; best = c3; }
   if(c1 > best) { model = 1; base = m1; best = c1; }
   g_tzModel = model;
   g_tzBase = base;
   g_ofsCacheDay = -1;
   LiveTZCorrection();
   g_tzLastDetect = now;
   g_tzOk = k >= 8;
   return true;
  }

//+------------------------------------------------------------------+
//| Day table (identik dengan versi lama)                            |
//+------------------------------------------------------------------+
struct DayRec
  {
   datetime d;
   double   o, h, l, c;
   int      n, hrs;
   bool     valid;
  };

class CDayTable
  {
public:
   string   sym;
   int      fold, rule;
   double   frac;
   DayRec   days[];
   int      n;

   CDayTable() { sym = ""; fold = 0; rule = 0; frac = 0.5; n = 0; }

   void Init(string s, int f, int r, double fr)
     {
      sym = s; fold = f; rule = r; frac = fr; n = 0;
      ArrayResize(days, 512);
      Rebuild(TimeCurrent() - 120 * 86400);
      for(int j = 0; j < n; j++)
         days[j].valid = ValidCalc(j);
     }

   datetime KeyOf(datetime srv)
     {
      datetime d = DayStart(ServerToLondon(srv));
      if(fold == 1 && DayOfWeekOf(d) == 0)
         d += 86400;
      return d;
     }

   void Rebuild(datetime fromSrv)
     {
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int k = CopyRates(sym, PERIOD_M1, fromSrv, TimeCurrent(), r);
      if(k <= 0)
         return;
      datetime firstKey = -1;
      for(int i = 0; i < k && firstKey < 0; i++)
        {
         datetime key = KeyOf(r[i].time);
         int dw = DayOfWeekOf(key);
         if(dw >= 1 && dw <= 5)
            firstKey = key;
        }
      if(firstKey < 0)
         return;
      int keep = n;
      while(keep > 0 && days[keep - 1].d >= firstKey)
         keep--;
      n = keep;
      int lastHour = -1;
      for(int i = 0; i < k; i++)
        {
         datetime l = ServerToLondon(r[i].time);
         datetime key = DayStart(l);
         if(fold == 1 && DayOfWeekOf(key) == 0)
            key += 86400;
         int dw = DayOfWeekOf(key);
         if(dw < 1 || dw > 5 || key < firstKey)
            continue;
         int hr = (int)(l / 3600);
         if(n == 0 || days[n - 1].d != key)
           {
            if(n >= ArraySize(days))
               ArrayResize(days, n + 256);
            days[n].d = key; days[n].o = r[i].open; days[n].h = r[i].high;
            days[n].l = r[i].low; days[n].c = r[i].close;
            days[n].n = 1; days[n].hrs = 1; days[n].valid = false;
            n++;
            lastHour = hr;
           }
         else
           {
            int j = n - 1;
            if(r[i].high > days[j].h) days[j].h = r[i].high;
            if(r[i].low < days[j].l)  days[j].l = r[i].low;
            days[j].c = r[i].close;
            days[j].n++;
            if(hr != lastHour) { days[j].hrs++; lastHour = hr; }
           }
        }
      for(int j = MathMax(0, n - 15); j < n; j++)
         days[j].valid = ValidCalc(j);
     }

   bool ValidCalc(int j)
     {
      if(rule == 0) return days[j].n > 0;
      if(rule == 2) return days[j].hrs >= 10;
      int m = MathMin(j, 60);
      if(m < 20) return days[j].n > 0;
      int tmp[];
      ArrayResize(tmp, m);
      for(int q = 0; q < m; q++)
         tmp[q] = days[j - m + q].n;
      ArraySort(tmp);
      double med = (m % 2 == 1) ? tmp[m / 2] : 0.5 * (tmp[m / 2 - 1] + tmp[m / 2]);
      return days[j].n >= frac * med;
     }

   void Update()
     {
      if(n < 30)
        {
         n = 0;
         Rebuild(TimeCurrent() - 120 * 86400);
         for(int j = 0; j < n; j++)
            days[j].valid = ValidCalc(j);
         return;
        }
      datetime d = DayStart(ServerToLondon(TimeCurrent())) - 12 * 86400;
      while(DayOfWeekOf(d) != 6)
         d -= 86400;
      Rebuild(LondonToServer(d));
     }

   int IndexBefore(datetime key)
     {
      int j = n - 1;
      while(j >= 0 && days[j].d >= key)
         j--;
      return j;
     }

   int IndexOf(datetime key)
     {
      for(int j = n - 1; j >= 0; j--)
        {
         if(days[j].d == key) return j;
         if(days[j].d < key)  return -1;
        }
      return -1;
     }

   int PrevValid(int j)
     {
      int q = j;
      while(q >= 0 && !days[q].valid)
         q--;
      return q;
     }

   double ADRBeforeKey(datetime key, bool validOnly)
     {
      int j = IndexBefore(key);
      double s = 0;
      int c = 0;
      while(j >= 0 && c < 10)
        {
         if(!validOnly || days[j].valid) { s += days[j].h - days[j].l; c++; }
         j--;
        }
      if(c < 10) return 0;
      return s / 10.0;
     }

   double MedianBefore(datetime key)
     {
      int j = IndexBefore(key) + 1;
      int m = MathMin(j, 60);
      if(m < 20) return 0;
      int tmp[];
      ArrayResize(tmp, m);
      for(int q = 0; q < m; q++)
         tmp[q] = days[j - m + q].n;
      ArraySort(tmp);
      return (m % 2 == 1) ? tmp[m / 2] : 0.5 * (tmp[m / 2 - 1] + tmp[m / 2]);
     }

   bool ValidSoFar(datetime key)
     {
      if(rule != 1) return true;
      double med = MedianBefore(key);
      if(med <= 0) return true;
      datetime st = key;
      if(fold == 1 && DayOfWeekOf(key) == 1)
         st -= 86400;
      int cnt = Bars(sym, PERIOD_M1, LondonToServer(st), TimeCurrent());
      return cnt >= frac * med;
     }

   datetime NextDayAfter(datetime e, bool needValid)
     {
      datetime today = DayStart(ServerToLondon(TimeCurrent()));
      datetime x = e + 86400;
      for(int guard = 0; guard < 30; guard++)
        {
         int dw = DayOfWeekOf(x);
         if(dw == 0 || dw == 6) { x += 86400; continue; }
         if(x > today) return x;
         if(x == today)
           {
            if(needValid && !ValidSoFar(x)) { x += 86400; continue; }
            return x;
           }
         int j = IndexOf(x);
         if(j >= 0 && (!needValid || days[j].valid))
            return x;
         x += 86400;
        }
      return x;
     }
  };

//+------------------------------------------------------------------+
//| Trade core                                                       |
//+------------------------------------------------------------------+
CTrade   g_trade;
double   g_initBal = 0;
int      g_digits = 2;
double   g_tick = 0.01;
double   g_point = 0.01;
int      g_closeMin[7];
datetime g_closeLearnDay = -1;
const bool g_sameDay = false;

// daftar magic milik 9algo (semua strategi, semua simbol) -> untuk hitung risk account-wide
long g_mgBase[];
int  g_mgCount[];

void RegisterMagic(long base, int count)
  {
   int n = ArraySize(g_mgBase);
   ArrayResize(g_mgBase, n + 1);
   ArrayResize(g_mgCount, n + 1);
   g_mgBase[n] = base;
   g_mgCount[n] = count;
  }

bool IsOurMagic(long m)
  {
   for(int i = 0; i < ArraySize(g_mgBase); i++)
      if(m >= g_mgBase[i] && m < g_mgBase[i] + g_mgCount[i])
         return true;
   return false;
  }

double NormPrice(double p)
  {
   if(g_tick <= 0)
      return NormalizeDouble(p, g_digits);
   return NormalizeDouble(MathRound(p / g_tick) * g_tick, g_digits);
  }

double RiskBase()
  {
   if(RiskMode == Compounding_PercentOfCurrentEquity)
      return AccountInfoDouble(ACCOUNT_EQUITY);
   return g_initBal;
  }

double LossPerLot(double riskDist)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pr = 0;
   if(bid > 0 && OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, bid, bid - riskDist, pr) && pr < 0)
      return -pr;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0)
      tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0)
      return 0;
   return riskDist / ts * tv;
  }

//--- komisi per 1 lot round-trip: rata-rata komisi/lot dari 30 deal terakhir simbol ini (0 kalau belum ada)
double CommissionPerLot()
  {
   if(!HistorySelect(TimeCurrent() - 60 * 86400, TimeCurrent() + 60)) return 0;
   double sumC = 0, sumV = 0; int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0 && n < 30; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      double v = HistoryDealGetDouble(d, DEAL_VOLUME);
      if(v <= 0) continue;
      sumC += MathAbs(HistoryDealGetDouble(d, DEAL_COMMISSION)); sumV += v; n++;
     }
   if(sumV <= 0) return 0;
   return 2.0 * sumC / sumV;
  }

//--- median lot N deal entry terakhir milik 9algo (semua simbol) untuk lot-consistency
double MedianLotRecent(int N)
  {
   if(!HistorySelect(TimeCurrent() - 90 * 86400, TimeCurrent() + 60)) return 0;
   double v[]; int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0 && n < N; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || !IsOurMagic(HistoryDealGetInteger(d, DEAL_MAGIC))) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      ArrayResize(v, n + 1); v[n] = HistoryDealGetDouble(d, DEAL_VOLUME); n++;
     }
   if(n < 5) return 0;
   ArraySort(v);
   return (n % 2 == 1) ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
  }

//--- risk uang dari 1 tiket (posisi/pending) berdasar jarak ke SL
double TicketRiskMoney(string sym, bool isBuy, double vol, double price, double sl)
  {
   if(sl <= 0 || vol <= 0 || price <= 0)
      return 0;
   double pr = 0;
   if(OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, vol, price, sl, pr) && pr < 0)
      return -pr;
   return 0;
  }

//--- total risk terbuka milik 9algo, semua simbol (posisi + pending)
//    Pending OCO (buy stop + sell stop dari strategi yang sama) hanya bisa terisi salah satu,
//    jadi per (simbol, magic) yang dihitung hanya pending dengan risk terbesar, bukan dijumlah.
long g_capMagic = 0;   // magic yang sedang dipasang: pending lain dengan magic ini (OCO) tidak dihitung, karena hanya 1 sisi bisa terisi
double OpenRiskTotal()
  {
   double s = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         continue;
      bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      s += TicketRiskMoney(PositionGetString(POSITION_SYMBOL), isBuy, PositionGetDouble(POSITION_VOLUME),
                           PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL));
     }
   string keys[];
   double maxr[];
   int nk = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !IsOurMagic(OrderGetInteger(ORDER_MAGIC)))
         continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool isBuy = (ot == ORDER_TYPE_BUY || ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP_LIMIT);
      double r = TicketRiskMoney(OrderGetString(ORDER_SYMBOL), isBuy, OrderGetDouble(ORDER_VOLUME_CURRENT),
                                 OrderGetDouble(ORDER_PRICE_OPEN), OrderGetDouble(ORDER_SL));
      if(g_capMagic != 0 && OrderGetInteger(ORDER_MAGIC) == g_capMagic && OrderGetString(ORDER_SYMBOL) == _Symbol) continue;
      string key = OrderGetString(ORDER_SYMBOL) + "|" + IntegerToString(OrderGetInteger(ORDER_MAGIC));
      int f = -1;
      for(int k = 0; k < nk; k++) if(keys[k] == key) { f = k; break; }
      if(f < 0) { ArrayResize(keys, nk + 1); ArrayResize(maxr, nk + 1); keys[nk] = key; maxr[nk] = r; nk++; }
      else if(r > maxr[f]) maxr[f] = r;
     }
   for(int k = 0; k < nk; k++) s += maxr[k];
   return s;
  }

//--- risk terbuka searah (dir=1 buy / -1 sell), semua simbol 9algo
double DirectionalRiskOpen(int dir)
  {
   double s = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsOurMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      if((dir > 0) != isBuy) continue;
      s += TicketRiskMoney(PositionGetString(POSITION_SYMBOL), isBuy, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL));
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !IsOurMagic(OrderGetInteger(ORDER_MAGIC))) continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool isBuy = (ot == ORDER_TYPE_BUY || ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP_LIMIT);
      if((dir > 0) != isBuy) continue;
      s += TicketRiskMoney(OrderGetString(ORDER_SYMBOL), isBuy, OrderGetDouble(ORDER_VOLUME_CURRENT), OrderGetDouble(ORDER_PRICE_OPEN), OrderGetDouble(ORDER_SL));
     }
   return s;
  }

bool EntriesBlocked();   // forward (guard)
// kunci hari (untuk daily loss, profitable days, consistency) - satu definisi untuk semua
datetime DayKeyOf(datetime srv)
  {
   if(DailyResetHourUTC < 0) return DayStart(srv);
   return DayStart(ServerToUTC(srv) - DailyResetHourUTC * 3600);
  }
datetime DayKeyStartServer(datetime srv)   // waktu server saat hari (kunci) dimulai
  {
   if(DailyResetHourUTC < 0) return DayStart(srv);
   datetime k = DayKeyOf(srv);
   return srv - (ServerToUTC(srv) - DailyResetHourUTC * 3600 - k);
  }
bool g_curPaused = false; // strategi yang sedang Tick di-pause dari panel
bool g_curVirt = false;    // strategi yang sedang Tick memakai pending siaga (cap risk dicek saat order asli dipasang)
bool g_armCtx = false;     // sedang memasang order asli dari antrean siaga
double g_lastRiskDist = 0, g_lastRiskPct = 0, g_lastMlCap = 0;   // argumen LotsFor terakhir (disimpan bersama setup siaga)
string g_lotWhy = "";      // alasan LotsFor mengembalikan 0
bool   g_curAuto = false;  // strategi yang sedang Tick di-auto-pause
int    g_targetDays = 14;  // efektif (bisa di-override peran otomatis)
double g_openCapPct = 2.5, g_dirCapPct = 1.2;
bool   g_fast = false;      // challenge mode Fast sedang aktif
int    g_phase = 0;        // fase efektif (Phase_Challenge / Phase_Verification / Phase_Funded)
string g_phaseSrc = "";
bool IsEval() { return g_phase == Phase_Challenge || g_phase == Phase_Verification; }
string PhaseName(int ph) { return ph == Phase_Funded ? "FUNDED" : ph == Phase_Verification ? "VERIFICATION" : "CHALLENGE"; }
double g_capScale = 3.0;
string g_firm = "";        // FirmTag efektif
int    g_role = -1;        // peran efektif
string g_roleTxt = "";
int    g_firmAccounts = 0;
int    g_curTrades = 0; double g_curNet = 0;
string g_dirWhy = "";      // alasan cap arah (disalin ke why strategi setelah Tick)
double g_effMult = 1.0;    // pengali risk efektif (Challenge Mode)
datetime g_deployUntil = 0; // batas waktu cek ulang auto-deploy
datetime g_closeRetryAt = 0;  // throttle LearnSessionClose saat history belum lengkap
int    g_phaseEpoch = -1;  // epoch fase yang sudah diterapkan chart ini
int    g_manualSeen = -99; // nilai PHASE_MANUAL terakhir yang dilihat chart ini
double g_spreadAvg = 0;    // rata-rata spread (EMA)
bool   g_progLockHit = false;
datetime g_progLockDay = 0;
double g_progFloor = 0;
double g_pPass = -1, g_pBust = -1, g_autoScale = 1.0, g_dailyRet = 0, g_dailySd = 0;
int    g_challengeDay = 0;
double DirectionalRiskOpen(int dir);
bool MarketOpenNow();
string g_regimeTxt = "";
bool RegimeAllows(int kind);
string BlockReason();
// true kalau entry gagal karena hambatan SEMENTARA (news, spread, cap risk, pause, group-hedge) -> setup jangan dibuang, coba lagi nanti
bool TempBlocked()
  {
   if(g_dirWhy != "") return true;
   return StringFind(g_lotWhy, "news") >= 0 || StringFind(g_lotWhy, "spread") >= 0 ||
          StringFind(g_lotWhy, "cap total") >= 0 || StringFind(g_lotWhy, "di-pause") >= 0;
  }

//--- satu-satunya pintu masuk ukuran lot: guard + cap total risk ada di sini
double LotsFor(double riskDist, double riskPct)
  {
   g_lotWhy = "";
   g_lastRiskDist = riskDist; g_lastRiskPct = riskPct; g_lastMlCap = 0;
   bool capOn = !(VirtualPending && g_curVirt && !g_armCtx);   // setup siaga belum memakai budget; dicek lagi saat dipasang
   if(riskDist <= 0 || riskPct <= 0)
     { g_lotWhy = "risk 0"; return 0; }
   if(g_curPaused)
     { g_lotWhy = "di-pause dari panel"; return 0; }
   if(g_curAuto)
     { g_lotWhy = "auto-pause: expectancy negatif (" + IntegerToString(g_curTrades) + " trade, net " + DoubleToString(g_curNet, 0) + ")"; return 0; }
   if(g_progLockHit)
     { g_lotWhy = "progress lock kena hari ini"; return 0; }
   if(SpreadFilter && g_spreadAvg > 0)
     {
      double sp = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(sp > SpreadMaxMult * g_spreadAvg)
        { g_lotWhy = "spread " + DoubleToString(sp, 0) + " > " + DoubleToString(SpreadMaxMult, 1) + "x rata-rata " + DoubleToString(g_spreadAvg, 0); return 0; }
     }
   if(EntriesBlocked())
     { g_lotWhy = BlockReason(); return 0; }
   double lpl = LossPerLot(riskDist);
   if(lpl <= 0)
     { g_lotWhy = "tick value tidak tersedia"; return 0; }
   if(NetOfCommission)
     {
      double cpl = CommissionPerLot();
      if(cpl > 0) lpl += cpl;
     }
   double money = RiskBase() * riskPct * RiskScale * g_effMult / 100.0;
   if(g_openCapPct > 0 && capOn)
     {
      double room = RiskBase() * g_openCapPct / 100.0 - OpenRiskTotal();
      if(room <= 0)
        { g_lotWhy = "cap total open risk " + DoubleToString(g_openCapPct, 1) + "% penuh"; return 0; }
      if(money > room)
         money = room;
     }
   double lots = money / lpl;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0)
      step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots > vmax)
      lots = vmax;
   if(lots < vmin)
     {
      if(!MinLotFallback)
        { g_lotWhy = "lot hitung " + DoubleToString(lots, 3) + " < min " + DoubleToString(vmin, 2); return 0; }
      double minRisk = lpl * vmin;
      double mlCap = g_fast ? MinLotMaxRiskFastPct : MinLotMaxRiskPct;   // Fast challenge: akun kecil + SL lebar tetap boleh 0.01 lot
      if(g_dirCapPct > 0) mlCap = MathMin(mlCap, g_dirCapPct);            // jangan lolos di sini lalu pasti ditolak cap arah
      g_lastMlCap = mlCap;
      if(minRisk > RiskBase() * mlCap / 100.0)
        { g_lotWhy = "lot min = risk " + DoubleToString(100 * minRisk / RiskBase(), 2) + "% > batas " + DoubleToString(mlCap, 2) + "%" +
                     (!g_fast && IsEval() && ChallengeStyle == Style_Fast ? " (klik CHALLENGE di panel -> batas " + DoubleToString(MathMin(MinLotMaxRiskFastPct, FastDirCapPct), 1) + "%)" : ""); return 0; }
      if(g_openCapPct > 0 && capOn && minRisk > RiskBase() * g_openCapPct / 100.0 - OpenRiskTotal())
        { g_lotWhy = "lot min melebihi sisa cap total risk"; return 0; }
      lots = vmin;
     }
   if(LotConsistency)
     {
      double med = MedianLotRecent(20);
      if(med > 0)
        {
         double lo = med * (1 - LotConsistencyPct / 100.0), hi = med * (1 + LotConsistencyPct / 100.0);
         if(lots > hi) lots = MathFloor(hi / step) * step;
         if(lots < lo)
           { g_lotWhy = "lot " + DoubleToString(lots, 2) + " di bawah rentang konsistensi (median " + DoubleToString(med, 2) + ")"; return 0; }
        }
     }
   double margin = 0;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double freeM = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   while(lots >= vmin && OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, price, margin) && margin > freeM * 0.95)
      lots = MathFloor(lots * 0.9 / step) * step;
   if(lots < vmin)
     { g_lotWhy = "margin tidak cukup"; return 0; }
   int vd = (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(lots, vd);
  }

bool HasToken(string u, string list)
  {
   string k[];
   int n = StringSplit(list, ',', k);
   for(int i = 0; i < n; i++)
      if(StringLen(k[i]) > 0 && StringFind(u, k[i]) >= 0)
         return true;
   return false;
  }

void DetectMarket()
  {
   string u = _Symbol;
   StringToUpper(u);
   string exMetal = "EUR,AUD,GBP,CHF,JPY,CAD,NZD,CNH,SGD,HKD,TRY,ZAR,MXN,INR";
   g_market = MKT_UNKNOWN;
   if(HasToken(u, "XAU,GOLD") && !HasToken(u, exMetal + ",XAG,SILVER"))
     { g_market = MKT_GOLD; g_marketName = "XAUUSD (gold)"; }
   else if(HasToken(u, "XAG,SILVER") && !HasToken(u, exMetal + ",XAU,GOLD"))
     { g_market = MKT_SILVER; g_marketName = "XAGUSD (silver)"; }
   else if(HasToken(u, "USDJPY,USD/JPY,USD_JPY,USD.JPY,USD-JPY"))
     { g_market = MKT_USDJPY; g_marketName = "USDJPY"; }
   else if(HasToken(u, "NDX,NAS,NQ,US100,US 100,USTEC,UST100,USTECH,US TECH,USATECH,TECH100,NSDQ,NDAQ"))
     { g_market = MKT_NQ; g_marketName = "Nasdaq-100"; }
   g_marketMatch = g_market != MKT_UNKNOWN;
   if(!g_marketMatch)
      Print("Symbol ", _Symbol, " tidak dikenali (XAUUSD / XAGUSD / USDJPY / NQ). Tidak ada strategi yang dijalankan.");
  }

int CountPositions(long magic)
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magic) continue;
      c++;
     }
   return c;
  }

//--- antrean pending siaga (per chart). tk = 0: masih siaga di EA; tk > 0: sudah jadi order asli di broker
struct VOrd
  {
   long     magic;
   int      type;
   double   lots, price, sl, tp, rdist, rpct;
   datetime expAt, lastTry, armedAt, created;
   ulong    tk;
   string   cmt, why;
  };
VOrd g_vo[];
bool g_voDirty = false;

int VoFind(long magic, int type)
  {
   for(int i = 0; i < ArraySize(g_vo); i++) if(g_vo[i].magic == magic && g_vo[i].type == type) return i;
   return -1;
  }
void VoRemove(int i)
  {
   int n = ArraySize(g_vo);
   if(i < 0 || i >= n) return;
   for(int k = i; k < n - 1; k++) g_vo[k] = g_vo[k + 1];
   ArrayResize(g_vo, n - 1);
   g_voDirty = true;
  }
int VoIdleCount(long magic)
  {
   int c = 0;
   for(int i = 0; i < ArraySize(g_vo); i++) if(g_vo[i].magic == magic && g_vo[i].tk == 0) c++;
   return c;
  }
// -1 tidak ada, 0 siaga (belum di broker), 1 sudah order asli
int VoState(long magic, ENUM_ORDER_TYPE t)
  {
   int i = VoFind(magic, (int)t);
   return i < 0 ? -1 : (g_vo[i].tk > 0 ? 1 : 0);
  }
bool EntrySince(long magic, datetime t);   // forward (didefinisikan di bagian antrean)
string VoWhy(long magic, ENUM_ORDER_TYPE t) { int i = VoFind(magic, (int)t); return i < 0 ? "" : g_vo[i].why; }

int CountOrders(long magic)
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != magic) continue;
      c++;
     }
   return c + VoIdleCount(magic);
  }

void DeleteOrders(long magic)
  {
   for(int i = ArraySize(g_vo) - 1; i >= 0; i--)
      if(g_vo[i].magic == magic) VoRemove(i);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != magic) continue;
      g_trade.OrderDelete(tk);
     }
  }

bool HasOrderOfType(long magic, ENUM_ORDER_TYPE t)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != magic) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == t) return true;
     }
   return VoState(magic, t) == 0;
  }

void ClosePositionTicket(ulong tk)
  {
   for(int k = 0; k < 3; k++)
     {
      if(g_trade.PositionClose(tk))
         break;
      Sleep(100);
     }
  }

void CloseAll(long magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magic) continue;
      ClosePositionTicket(tk);
     }
  }

int OurTicketsAll()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) { ulong t = PositionGetTicket(i); if(t > 0 && IsOurMagic(PositionGetInteger(POSITION_MAGIC))) c++; }
   for(int i = OrdersTotal() - 1; i >= 0; i--) { ulong t = OrderGetTicket(i); if(t > 0 && IsOurMagic(OrderGetInteger(ORDER_MAGIC))) c++; }
   return c;
  }

bool GroupHedgeConflict(int dir, string &who);

bool DirectionalCapOk(bool buy, double &lots, double price, double sl)
  {
   string who = "";
   if(GroupHedgeConflict(buy ? 1 : -1, who))
     {
      g_dirWhy = "group-hedge: akun lain (" + who + ") punya posisi berlawanan di market ini";
      Print("9algo: entry ditolak, ", g_dirWhy);
      return false;
     }
   if(g_dirCapPct <= 0) return true;
   double add = TicketRiskMoney(_Symbol, buy, lots, price, sl);
   double have = DirectionalRiskOpen(buy ? 1 : -1);
   double cap = RiskBase() * g_dirCapPct / 100.0;
   if(have + add > cap && add > 0)
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(step <= 0) step = 0.01;
      double room = cap - have;
      double nl = room > 0 ? MathFloor(lots * room / add / step + 1e-9) * step : 0;
      if(nl >= vmin)
        {
         lots = NormalizeDouble(nl, (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9)));
         return true;
        }
     }
   if(have + add > cap)
     {
      add = TicketRiskMoney(_Symbol, buy, lots, price, sl);
      string w = "cap arah " + (buy ? "BUY" : "SELL") + " " + DoubleToString(g_dirCapPct, 1) + "% penuh (" + DoubleToString(have, 0) + "+" + DoubleToString(add, 0) + ")";
      g_dirWhy = w;
      Print("9algo: entry ditolak, ", w);
      return false;
     }
   return true;
  }

// slippage maksimal: 5x spread saat ini, minimal 30 point (dulu 1000 point = $10 di gold)
int DeviationPts()
  {
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (int)MathMax(30, 5 * sp);
  }

//--- kunci singkat antar chart: cek budget + kirim order tidak boleh balapan (emas & perak bisa entry di detik yang sama)
bool g_capLockHeld = false;
bool CapLock()
  {
   if(MQLInfoInteger(MQL_TESTER)) return true;
   string nm = "ALGO9_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_CAPLOCK";
   if(!GlobalVariableCheck(nm)) GlobalVariableSet(nm, 0);
   for(int k = 0; k < 120; k++)
     {
      double v = GlobalVariableGet(nm);
      double now = (double)TimeLocal();
      if(v == 0 || now - v > 10)                     // kosong, atau kunci basi (chart crash)
         if(GlobalVariableSetOnCondition(nm, now, v)) { g_capLockHeld = true; return true; }
      Sleep(50);
     }
   return false;
  }
void CapUnlock(bool sent)
  {
   if(!g_capLockHeld) return;
   if(sent) Sleep(150);                               // beri waktu posisi/order baru muncul di terminal
   GlobalVariableSet("ALGO9_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_CAPLOCK", 0);
   g_capLockHeld = false;
  }
// kecilkan lot supaya risk tiket ini muat di sisa budget (cap total). false = tidak muat sama sekali
bool FitCap(bool buy, double &lots, double px, double sl)
  {
   if(g_openCapPct <= 0 || sl <= 0) return true;
   double rk = TicketRiskMoney(_Symbol, buy, lots, px, sl);
   double room = RiskBase() * g_openCapPct / 100.0 - OpenRiskTotal();
   if(rk <= room + 0.01) return true;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0) step = 0.01;
   double nl = room > 0 && rk > 0 ? MathFloor(lots * room / rk / step + 1e-9) * step : 0;
   if(nl < vmin) { g_dirWhy = "cap total open risk " + DoubleToString(g_openCapPct, 1) + "% penuh"; return false; }
   lots = NormalizeDouble(nl, (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9)));
   return true;
  }

bool SendMarket(long magic, int dir, double lots, double sl, double tp, string cmt)
  {
   g_trade.SetDeviationInPoints(DeviationPts());
   double px = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // harga sudah lebih jauh dari SL dibanding rencana -> kecilkan lot supaya risk uang tetap sama
   // (toleransi 5% + 2x spread: stop dihitung dari bid tapi entry di ask)
   double ad = MathAbs(px - sl);
   double spr = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(sl > 0 && g_lastRiskDist > 0 && ad > g_lastRiskDist * 1.05 + 2.0 * MathMax(0, spr))
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(step <= 0) step = 0.01;
      double nl = MathFloor(lots * g_lastRiskDist / ad / step + 1e-9) * step;
      if(nl < vmin)
        {
         // sudah di lot minimum: tetap boleh kalau risk lot minimum di jarak aktual masih di bawah batas lot-minimum
         bool okMin = lots <= vmin + 1e-9 && g_lastMlCap > 0 && TicketRiskMoney(_Symbol, dir > 0, vmin, px, sl) <= RiskBase() * g_lastMlCap / 100.0;
         if(!okMin) { g_lotWhy = "harga sudah terlalu jauh dari SL"; return false; }
         nl = vmin;
        }
      lots = NormalizeDouble(nl, (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9)));
     }
   if(!CapLock()) { g_dirWhy = "antrian kirim order sibuk"; return false; }
   if(!FitCap(dir > 0, lots, px, sl) || !DirectionalCapOk(dir > 0, lots, px, sl)) { CapUnlock(false); return false; }
   g_trade.SetExpertMagicNumber(magic);
   bool ok;
   if(dir > 0)
      ok = g_trade.Buy(lots, _Symbol, 0, sl > 0 ? NormPrice(sl) : 0, tp > 0 ? NormPrice(tp) : 0, "9algo " + cmt);
   else
      ok = g_trade.Sell(lots, _Symbol, 0, sl > 0 ? NormPrice(sl) : 0, tp > 0 ? NormPrice(tp) : 0, "9algo " + cmt);
   uint rc = g_trade.ResultRetcode();
   bool done = ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL);
   CapUnlock(done);
   return done;
  }

bool ExpirySupported()
  {
   int m = (int)SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
   return (m & SYMBOL_EXPIRATION_SPECIFIED) != 0;
  }

bool SendPendingReal(long magic, ENUM_ORDER_TYPE type, double lots, double price, double sl, double tp, datetime expSrv, string cmt);
bool SendPending(long magic, ENUM_ORDER_TYPE type, double lots, double price, double sl, double tp, datetime expSrv, string cmt)
  {
   if(!VirtualPending || g_armCtx) return SendPendingReal(magic, type, lots, price, sl, tp, expSrv, cmt);
   int i = VoFind(magic, (int)type);
   if(i < 0) { i = ArraySize(g_vo); ArrayResize(g_vo, i + 1); g_vo[i].tk = 0; g_vo[i].lastTry = 0; g_vo[i].armedAt = 0; g_vo[i].why = ""; g_vo[i].created = TimeCurrent(); }
   g_vo[i].magic = magic; g_vo[i].type = (int)type; g_vo[i].lots = lots; g_vo[i].price = price; g_vo[i].sl = sl; g_vo[i].tp = tp;
   g_vo[i].rdist = g_lastRiskDist > 0 ? g_lastRiskDist : MathAbs(price - sl); g_vo[i].rpct = g_lastRiskPct;
   g_vo[i].expAt = expSrv > 0 ? expSrv : TimeCurrent() + 86400; g_vo[i].cmt = cmt;
   g_voDirty = true;
   return true;
  }

bool SendPendingReal(long magic, ENUM_ORDER_TYPE type, double lots, double price, double sl, double tp, datetime expSrv, string cmt)
  {
   bool buy = (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT);
   if(!CapLock()) { g_dirWhy = "antrian kirim order sibuk"; return false; }
   long cm = g_capMagic; g_capMagic = magic;            // sisi OCO lain tidak ikut dihitung
   bool fit = FitCap(buy, lots, price, sl);
   g_capMagic = cm;
   if(!fit || !DirectionalCapOk(buy, lots, price, sl)) { CapUnlock(false); return false; }
   g_trade.SetExpertMagicNumber(magic);
   ENUM_ORDER_TYPE_TIME tt = ORDER_TIME_GTC;
   datetime ex = 0;
   if(expSrv > 0 && ExpirySupported() && expSrv > TimeCurrent() + 60)
     {
      tt = ORDER_TIME_SPECIFIED;
      ex = expSrv;
     }
   bool ok = g_trade.OrderOpen(_Symbol, type, lots, 0, NormPrice(price), sl > 0 ? NormPrice(sl) : 0, tp > 0 ? NormPrice(tp) : 0, tt, ex, "9algo " + cmt);
   uint rc = g_trade.ResultRetcode();
   bool done = ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED);
   CapUnlock(done);
   return done;
  }

void LearnSessionClose()
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   datetime now = TimeCurrent();
   int n = CopyRates(_Symbol, PERIOD_M1, now - 70 * 86400, now, r);
   if(n < 1000)
      return;
   int vals[7][12];
   int cnt[7];
   ArrayInitialize(cnt, 0);
   for(int i = 1; i < n; i++)
     {
      long gap = (long)(r[i].time - r[i - 1].time);
      if(gap < 30 * 60)
         continue;
      datetime ny = ServerToNY(r[i - 1].time);
      int mod = (int)((ny % 86400) / 60);
      if(mod < 12 * 60 || mod > 18 * 60)
         continue;
      int dw = DayOfWeekOf(ny);
      if(cnt[dw] < 12) { vals[dw][cnt[dw]] = mod; cnt[dw]++; }
      else
        {
         for(int k = 0; k < 11; k++)
            vals[dw][k] = vals[dw][k + 1];
         vals[dw][11] = mod;
        }
     }
   for(int dw = 0; dw < 7; dw++)
     {
      if(cnt[dw] < 3) { g_closeMin[dw] = 24 * 60; continue; }
      int m = MathMin(cnt[dw], 6);
      int tmp[];
      ArrayResize(tmp, m);
      for(int k = 0; k < m; k++)
         tmp[k] = vals[dw][cnt[dw] - m + k];
      ArraySort(tmp);
      g_closeMin[dw] = tmp[m / 2];
     }
   g_closeLearnDay = DayStart(now);
  }

datetime CapToSessionClose(datetime nyTarget)
  {
   int dw = DayOfWeekOf(nyTarget);
   int mod = (int)((nyTarget % 86400) / 60);
   if(g_closeMin[dw] < mod)
      return DayStart(nyTarget) + g_closeMin[dw] * 60;
   return nyTarget;
  }

double CloseBefore(string sym, datetime srvTime)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(sym, PERIOD_M1, srvTime - 1, 1, r) != 1) return 0;
   if(r[0].time >= srvTime) return 0;
   return r[0].close;
  }

int TradeEndSec(int dw)
  {
   datetime f, t;
   int best = -1;
   for(int k = 0; k < 10; k++)
     {
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dw, k, f, t))
         break;
      int te = (int)t;
      if(te <= 0 || te > 86400)
         te = 86400;
      if(te > best)
         best = te;
     }
   return best < 0 ? 86400 : best;
  }

datetime CapToTradeEnd(datetime srvT)
  {
   int te = TradeEndSec(DayOfWeekOf(srvT));
   if((int)(srvT % 86400) > te - 60)
      return DayStart(srvT) + te - 60;
   return srvT;
  }

datetime ExitServerTime(datetime xLondonDate, int nyMin)
  {
   datetime nyT = CapToSessionClose(xLondonDate + nyMin * 60);
   return CapToTradeEnd(NYToServer(nyT));
  }

void HighLowBetween(datetime s0, datetime s1, double &hi, double &lo, int &n, datetime &firstT)
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   hi = -DBL_MAX; lo = DBL_MAX; n = 0; firstT = 0;
   int k = CopyRates(_Symbol, PERIOD_M1, s0, s1 - 1, r);
   for(int i = 0; i < k; i++)
     {
      if(r[i].time < s0 || r[i].time >= s1) continue;
      if(n == 0) firstT = r[i].time;
      if(r[i].high > hi) hi = r[i].high;
      if(r[i].low < lo)  lo = r[i].low;
      n++;
     }
  }

//+------------------------------------------------------------------+
//| Kalender libur (US / futures / Jepang)                           |
//+------------------------------------------------------------------+
int NthWeekday(int y, int m, int dw, int n)
  {
   datetime first = MakeDate(y, m, 1);
   int f = DayOfWeekOf(first);
   return 1 + ((dw - f + 7) % 7) + 7 * (n - 1);
  }

int LastWeekday(int y, int m, int dw)
  {
   int ny = (m == 12) ? y + 1 : y;
   int nm = (m == 12) ? 1 : m + 1;
   datetime last = MakeDate(ny, nm, 1) - 86400;
   MqlDateTime s;
   TimeToStruct(last, s);
   return s.day - ((DayOfWeekOf(last) - dw + 7) % 7);
  }

bool Observed(int y, int m, int d, int hm, int hd)
  {
   datetime t = MakeDate(y, hm, hd);
   int w = DayOfWeekOf(t);
   if(w == 6) t -= 86400;
   else if(w == 0) t += 86400;
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.year == y && s.mon == m && s.day == d;
  }

bool IsGoodFriday(int y, int m, int d)
  {
   int a = y % 19, b = y / 100, c = y % 100, dd = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3;
   int h = (19 * a + b - dd - g + 15) % 30, i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7;
   int mm = (a + 11 * h + 22 * l) / 451;
   int em = (h + l - 7 * mm + 114) / 31, ed = ((h + l - 7 * mm + 114) % 31) + 1;
   MqlDateTime gs;
   TimeToStruct(MakeDate(y, em, ed) - 2 * 86400, gs);
   return m == gs.mon && d == gs.day;
  }

bool USHolidayOrHalf(datetime day)
  {
   MqlDateTime x;
   TimeToStruct(day, x);
   int y = x.year, m = x.mon, d = x.day, w = DayOfWeekOf(day);
   if(w == 0 || w == 6) return true;
   if(Observed(y, m, d, 1, 1)) return true;
   if(m == 12 && d == 31 && w == 5) return true;
   if(m == 1 && d == NthWeekday(y, 1, 1, 3)) return true;
   if(m == 2 && d == NthWeekday(y, 2, 1, 3)) return true;
   if(IsGoodFriday(y, m, d)) return true;
   if(m == 5 && d == LastWeekday(y, 5, 1)) return true;
   if(y >= 2022 && Observed(y, m, d, 6, 19)) return true;
   if(Observed(y, m, d, 7, 4)) return true;
   if(m == 7 && d == 3) return true;
   if(m == 9 && d == NthWeekday(y, 9, 1, 1)) return true;
   int thx = NthWeekday(y, 11, 4, 4);
   if(m == 11 && (d == thx || d == thx + 1)) return true;
   if(m == 12 && d == 24) return true;
   if(Observed(y, m, d, 12, 25)) return true;
   return false;
  }

int FutSession(datetime day)
  {
   MqlDateTime x;
   TimeToStruct(day, x);
   int y = x.year, m = x.mon, d = x.day, w = DayOfWeekOf(day);
   if(w == 0 || w == 6) return 2;
   if((m == 1 && Observed(y, m, d, 1, 1)) || IsGoodFriday(y, m, d) || Observed(y, m, d, 12, 25)) return 2;
   int thx = NthWeekday(y, 11, 4, 4);
   if((m == 1 && d == NthWeekday(y, 1, 1, 3)) || (m == 2 && d == NthWeekday(y, 2, 1, 3)) || (m == 5 && d == LastWeekday(y, 5, 1)) ||
      (y >= 2022 && Observed(y, m, d, 6, 19)) || Observed(y, m, d, 7, 4) || (m == 7 && d == 3) ||
      (m == 9 && d == NthWeekday(y, 9, 1, 1)) || (m == 11 && (d == thx || d == thx + 1)) || (m == 12 && d == 24))
      return 1;
   return 0;
  }

datetime CutServer(datetime day)
  {
   int s = FutSession(day);
   if(s == 2) return 0;
   return ExitServerTime(day, s == 1 ? 12 * 60 + 50 : 16 * 60);
  }

datetime CapToCut(datetime x, datetime day)
  {
   datetime c = CutServer(day);
   if(c > 0 && c < x) return c;
   return x;
  }

int NthMondayDay(int y, int m, int n)
  {
   datetime first = MakeDate(y, m, 1);
   int dw = DayOfWeekOf(first);
   int off = (8 - dw) % 7;
   return 1 + off + 7 * (n - 1);
  }

int VernalDay(int y)   { return (int)MathFloor(20.8431 + 0.242194 * (y - 1980) - (int)((y - 1980) / 4)); }
int AutumnalDay(int y) { return (int)MathFloor(23.2488 + 0.242194 * (y - 1980) - (int)((y - 1980) / 4)); }

bool JPBase(int y, int m, int d)
  {
   if(m == 1 && d == 1) return true;
   if(m == 1 && ((y >= 2000 && d == NthMondayDay(y, 1, 2)) || (y < 2000 && d == 15))) return true;
   if(m == 2 && d == 11) return true;
   if(m == 2 && d == 23 && y >= 2020) return true;
   if(m == 12 && d == 23 && y >= 1989 && y <= 2018) return true;
   if(m == 3 && d == VernalDay(y)) return true;
   if(m == 4 && d == 29) return true;
   if(m == 5 && (d == 3 || d == 5)) return true;
   if(m == 5 && d == 4 && y >= 2007) return true;
   if(y == 2020)
     {
      if((m == 7 && (d == 23 || d == 24)) || (m == 8 && d == 10)) return true;
     }
   else if(y == 2021)
     {
      if((m == 7 && (d == 22 || d == 23)) || (m == 8 && d == 8)) return true;
     }
   else
     {
      if(m == 7 && ((y >= 2003 && d == NthMondayDay(y, 7, 3)) || (y >= 1996 && y < 2003 && d == 20))) return true;
      if(m == 8 && d == 11 && y >= 2016) return true;
      if(m == 10 && ((y >= 2000 && d == NthMondayDay(y, 10, 2)) || (y < 2000 && d == 10))) return true;
     }
   if(m == 9 && ((y >= 2003 && d == NthMondayDay(y, 9, 3)) || (y < 2003 && d == 15))) return true;
   if(m == 9 && d == AutumnalDay(y)) return true;
   if(m == 11 && (d == 3 || d == 23)) return true;
   if(y == 2019 && ((m == 4 && d == 30) || (m == 5 && (d == 1 || d == 2)) || (m == 10 && d == 22))) return true;
   return false;
  }

bool JPBaseT(datetime t) { MqlDateTime s; TimeToStruct(t, s); return JPBase(s.year, s.mon, s.day); }

bool IsJPHoliday(datetime day)
  {
   MqlDateTime s;
   TimeToStruct(day, s);
   if(JPBase(s.year, s.mon, s.day)) return true;
   if(s.year >= 2007)
     {
      for(int k = 1; k < 10; k++)
        {
         datetime p = day - k * 86400;
         if(!JPBaseT(p)) break;
         if(DayOfWeekOf(p) == 0) return true;
        }
     }
   else if(DayOfWeekOf(day) == 1 && JPBaseT(day - 86400))
      return true;
   if(s.year >= 1988 && DayOfWeekOf(day) != 0 && JPBaseT(day - 86400) && JPBaseT(day + 86400))
      return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Garis bantu level strategi (prefix 9AL_, terpisah dari panel)    |
//+------------------------------------------------------------------+
color LvC(string tag)
  {
   if(StringFind(tag, "Narrow") == 0) return C'88,166,255';
   if(StringFind(tag, "Week") == 0)   return C'255,159,67';
   if(StringFind(tag, "Round") == 0)  return C'227,179,65';
   if(StringFind(tag, "BigDay") == 0) return C'188,140,255';
   if(StringFind(tag, "Tokyo") == 0)  return C'57,208,216';
   if(StringFind(tag, "Noise") == 0)  return C'63,185,80';
   return clrSilver;
  }

// garis horizontal dari t1 ke t2 + label kecil di ujung kanan (label kosong = tanpa teks)
void LvLine(string id, double price, datetime t1, datetime t2, color c, ENUM_LINE_STYLE st, int w, string label)
  {
   if(price <= 0 || t2 <= t1) return;
   string nm = "9AL_" + id;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, st);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, label + " " + DoubleToString(price, g_digits));
   if(label == "") return;
   string tn = nm + "_t";
   if(ObjectFind(0, tn) < 0) ObjectCreate(0, tn, OBJ_TEXT, 0, t2, price);
   ObjectSetString(0, tn, OBJPROP_TEXT, label + "  " + DoubleToString(price, g_digits));
   ObjectSetString(0, tn, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, tn, OBJPROP_COLOR, c);
   ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, tn, OBJPROP_BACK, false);
   ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
  }

// garis vertikal penanda waktu (cek / batas)
void LvTime(string id, datetime t, color c, string label)
  {
   if(t <= 0) return;
   string nm = "9AL_" + id;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TEXT, label);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, label);
  }

void LvVSeg(string id, datetime t, double p1, double p2, color c)
  {
   if(p1 <= 0 || p2 <= 0 || p1 == p2) return;
   string nm = "9AL_" + id;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_TREND, 0, t, p1, t, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }

#define CLR_RWD  C'22,73,58'     // zona TP (hijau gelap, di belakang candle)
#define CLR_RSK  C'88,32,42'     // zona SL (merah gelap)
#define CLR_WIN  C'26,34,54'     // jendela waktu / koridor Noise / kotak ukur Tokyo
#define CLR_CARD C'24,30,42'     // latar kartu
#define CLR_EDGE C'44,52,70'     // bingkai kartu
#define CLR_TXT2 C'174,180,192'  // teks sekunder
#define CLR_LDIM C'107,114,128'  // teks redup
#define CLR_GRY  C'139,145,156'  // abu (ditolak)

void LvRect(string id, datetime t1, double p1, datetime t2, double p2, color c)
  {
   if(t2 <= t1 || p1 <= 0 || p2 <= 0) return;
   string nm = "9AL_" + id;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_FILL, true);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }

// teks kecil yang menempel di waktu/harga (hanya untuk nama kotak, pendek)
void LvLabel(string id, datetime t, double price, string text, color c, ENUM_ANCHOR_POINT anc)
  {
   if(price <= 0 || t <= 0) return;
   string nm = "9AL_" + id;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
   ObjectSetString(0, nm, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }

string NYhm(datetime srv) { return TimeToString(ServerToNY(srv), TIME_MINUTES) + " NY"; }
string NYdhm(datetime srv)
  {
   string d[] = {"Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"};
   datetime ny = ServerToNY(srv);
   return d[DayOfWeekOf(ny)] + " " + TimeToString(ny, TIME_MINUTES) + " NY";
  }
string U(ushort ch) { return ShortToString(ch); }
string SName(string tag) { int p = StringFind(tag, "-"); return p > 0 ? StringSubstr(tag, 0, p) : tag; }
string UpS(string v) { string u = v; StringToUpper(u); return u; }
string Px(double v) { return DoubleToString(v, g_digits); }

double g_adrC = 0; datetime g_adrDay = 0;
double ChartADR()
  {
   datetime d = DayStart(TimeCurrent());
   if(d == g_adrDay && g_adrC > 0) return g_adrC;
   double h[], l[];
   int n = MathMin(CopyHigh(_Symbol, PERIOD_D1, 1, 14, h), CopyLow(_Symbol, PERIOD_D1, 1, 14, l));
   if(n < 5) return g_adrC;
   double s = 0;
   for(int i = 0; i < n; i++) s += h[i] - l[i];
   g_adrC = s / n; g_adrDay = d;
   return g_adrC;
  }

string g_pendNote = "";   // catatan antrean dari PendState() terakhir

//--- data kartu & status. Diisi oleh Levels() tiap strategi, digambar oleh LayoutLabels()
// kartu kind: 0 AKTIF, 1 MENUNGGU, 2 DITOLAK, 3 POSISI
double   g_cdP[];  datetime g_cdT[];  color g_cdC[];  int g_cdK[];  string g_cdA[], g_cdB[];
// baris status kind: 0 terpasang/posisi, 1 menunggu, 2 ditolak, 3 libur/selesai/nonaktif
string   g_rwTag[], g_rwTx[];  int g_rwK[];

void LbReset()
  {
   ArrayResize(g_cdP, 0); ArrayResize(g_cdT, 0); ArrayResize(g_cdC, 0); ArrayResize(g_cdK, 0); ArrayResize(g_cdA, 0); ArrayResize(g_cdB, 0);
   ArrayResize(g_rwTag, 0); ArrayResize(g_rwTx, 0); ArrayResize(g_rwK, 0);
  }

void CardAdd(double price, datetime tEnd, color c, int kind, string a, string b)
  {
   if(price <= 0) return;
   int n = ArraySize(g_cdP);
   ArrayResize(g_cdP, n + 1); ArrayResize(g_cdT, n + 1); ArrayResize(g_cdC, n + 1); ArrayResize(g_cdK, n + 1); ArrayResize(g_cdA, n + 1); ArrayResize(g_cdB, n + 1);
   g_cdP[n] = price; g_cdT[n] = tEnd; g_cdC[n] = c; g_cdK[n] = kind; g_cdA[n] = a; g_cdB[n] = b;
  }

bool LvHasRow(string tag)
  {
   for(int i = 0; i < ArraySize(g_rwTag); i++) if(g_rwTag[i] == tag) return true;
   return false;
  }

// satu baris per strategi; status terbaik menang, status sama digabung (mis. BUY STOP & SELL STOP)
void LvRow(string tag, int kind, string text)
  {
   for(int i = 0; i < ArraySize(g_rwTag); i++)
     {
      if(g_rwTag[i] != tag) continue;
      if(kind < g_rwK[i]) { g_rwK[i] = kind; g_rwTx[i] = text; }
      else if(kind == g_rwK[i] && kind <= 1 && StringFind(g_rwTx[i], text) < 0) g_rwTx[i] += "  &  " + text;
      return;
     }
   int n = ArraySize(g_rwTag);
   ArrayResize(g_rwTag, n + 1); ArrayResize(g_rwTx, n + 1); ArrayResize(g_rwK, n + 1);
   g_rwTag[n] = tag; g_rwTx[n] = text; g_rwK[n] = kind;
  }

// satu setup/posisi: zona SL (merah) + zona TP (hijau) + garis entry dari awal berlaku s/d batas waktu,
// ditambah kartu di kanan chart dan baris di "Rencana hari ini".
// state: 0 order asli terpasang di broker, 1 DITOLAK, 2 posisi terbuka, 3 menunggu (belum dipasang), 4 SIAGA (antrean EA)
void LvTrade(string id, string tag, bool buy, double entry, double sl, double tp, datetime t1, datetime t2,
             int state, string head, string note)
  {
   if(entry <= 0 || t2 <= t1) return;
   color c = LvC(tag);
   string nm = UpS(SName(tag)), px = Px(entry);
   double rr = (sl > 0 && tp > 0 && MathAbs(entry - sl) > 0) ? MathAbs(tp - entry) / MathAbs(entry - sl) : 0;
   string slt = "SL " + (sl > 0 ? Px(sl) : "-") + "   TP " + (tp > 0 ? Px(tp) : "exit waktu");
   if(StringFind(note, "lot 0: ") == 0) note = StringSubstr(note, 7);
   StringReplace(note, " (SL terlalu lebar utk saldo ini)", "");
   if(state == 1)
     {
      LvLine(id + "_e", entry, t1, t2, C'92,99,112', STYLE_DOT, 1, "");
      CardAdd(entry, t2, c, 2, nm + "  " + U(0x00B7) + "  " + head + "  " + px, note);
      LvRow(tag, 2, "ditolak: " + note);
      return;
     }
   if(sl > 0) LvRect(id + "_rk", t1, entry, t2, sl, CLR_RSK);
   if(tp > 0) LvRect(id + "_rw", t1, entry, t2, tp, CLR_RWD);
   LvLine(id + "_e", entry, t1, t2, c, (state == 3 || state == 4) ? STYLE_DASH : STYLE_SOLID, (state == 3 || state == 4) ? 1 : 2, "");
   if(state == 4)
     {
      string an = g_pendNote;
      bool lim = StringFind(head, "LIMIT") >= 0;
      double ad = ChartADR() * ArmDistADR;
      double ap = (buy != lim) ? entry - ad : entry + ad;           // buy stop / sell limit: dari bawah, sebaliknya dari atas
      string cmp = ((buy != lim) ? U(0x2265) : U(0x2264)) + " " + Px(ap);
      CardAdd(entry, t2, c, 4, nm + "  " + U(0x00B7) + "  " + head + "  " + px,
              an != "" ? an : slt + (rr > 0 ? "   RR 1:" + DoubleToString(rr, 1) : "") + "   ke broker saat harga " + cmp);
      LvRow(tag, 1, head + " " + px + (an != "" ? " (" + an + ")" : " siaga, ke broker saat harga " + cmp));
      return;
     }
   if(state == 2)
     {
      CardAdd(entry, t2, c, 3, nm + "  " + U(0x00B7) + "  " + head + " @ " + px, note + "   " + slt + "   tutup maks " + NYdhm(t2));
      LvRow(tag, 0, "posisi " + head + " @ " + px + "   " + note);
      return;
     }
   CardAdd(entry, t2, c, state == 0 ? 0 : 1, nm + "  " + U(0x00B7) + "  " + head + "  " + px,
           slt + (rr > 0 ? "   RR 1:" + DoubleToString(rr, 1) : "") + "   s/d " + NYdhm(t2));
   LvRow(tag, state == 0 ? 0 : 1, head + " " + px);
  }

//+------------------------------------------------------------------+
//| Base class strategi                                              |
//+------------------------------------------------------------------+
class CStrat
  {
public:
   string    tag;
   bool      on;
   long      magic;
   int       magicCount;
   double    risk;
   bool      paused;
   string    why;        // alasan terakhir tidak entry (untuk panel & MCP)
   bool      autoPaused; // di-pause otomatis karena expectancy negatif
   int       stTrades;   // statistik per strategi (dari history)
   double    stNet;
   int       kind;       // 0 = breakout/momentum, 1 = pullback/mean-reversion
   bool      dtOn;
   bool      pend;       // strategi pending order (ikut antrean siaga)
   CDayTable dt;

   CStrat() { tag = ""; on = false; magic = 0; magicCount = 1; risk = 0; paused = false; why = ""; kind = 0; autoPaused = false; stTrades = 0; stNet = 0; dtOn = false; pend = false; }
   virtual ~CStrat() {}

   void Setup(string t, bool o, long m, int mc, double r)
     {
      tag = t; on = o; magic = m; magicCount = mc; risk = r;
      paused = GlobalVariableCheck(GVP() + "PAUSE_" + IntegerToString(m));
      RegisterMagic(m, mc);
     }
   bool Mine(long m) { return m >= magic && m < magic + magicCount; }
   void InitDays(int fold, int rule, double frac) { dt.Init(_Symbol, fold, rule, frac); dtOn = true; }

   int Positions()
     {
      int c = 0;
      for(int k = 0; k < magicCount; k++)
         c += CountPositions(magic + k);
      return c;
     }
   int Orders()
     {
      int c = 0;
      for(int k = 0; k < magicCount; k++)
         c += CountOrders(magic + k);
      return c;
     }
   void DeleteAllOrders() { for(int k = 0; k < magicCount; k++) DeleteOrders(magic + k); }
   void CloseAllPositions() { for(int k = 0; k < magicCount; k++) CloseAll(magic + k); }

   virtual void   Init() {}
   virtual void   Tick(datetime now) {}
   virtual void   OnDeal(ulong deal) {}
   virtual void   Missed(int type) {}   // setup siaga terlewat (harga lompat) -> jangan dikejar lagi hari ini
   virtual void   DayChange() { if(dtOn) dt.Update(); }
   virtual string Extra() { return ""; }
   virtual void   Levels(datetime now) {}
   virtual datetime ExitAt(datetime openSrv) { return openSrv + 86400; }   // batas waktu posisi ditutup
   int    PendState(ENUM_ORDER_TYPE t)
     {
      int v = VoState(magic, t);
      if(v == 0) { g_pendNote = VoWhy(magic, t); return 4; }   // siaga di EA
      return HasOrderOfType(magic, t) ? 0 : (Rejected() ? 1 : 3);
     }
   bool   Placed() { return Orders() > 0 || Positions() > 0; }
   bool   Rejected() { return !Placed() && (StringFind(why, "lot 0") == 0 || StringFind(why, "tertunda") == 0 || StringFind(why, "terlewat") == 0); }
   color  LvCol(color c) { return Rejected() ? clrDimGray : c; }
   string LvNote() { return Rejected() ? "  [TIDAK DIPASANG: " + why + "]" : (Placed() ? "  [aktif]" : ""); }
   string Why() { return why; }

   string Line()
     {
      string s = tag + "  risk " + DoubleToString(risk * RiskScale, 2) + "%  pos " + IntegerToString(Positions());
      int o = Orders();
      if(o > 0) s += "  ord " + IntegerToString(o);
      string x = Extra();
      if(x != "") s += "  " + x;
      return s;
     }
  };

//+------------------------------------------------------------------+
//| NoiseMomentum (Gold = 1 engine, NQ = 2 engine)                   |
//+------------------------------------------------------------------+
struct NMEngine
  {
   bool     on;
   int      lookback;
   double   mult;
   int      chk;
   double   hardK, trailK, trailAct;
   int      maxTrades;
   long     magic;
   double   sig[];
   bool     sigOk;
   double   sigE;
   int      tradesToday;
   double   entry, unit, best;
   int      dir;
  };

class CNoiseMomentum : public CStrat
  {
public:
   bool     gold;
   NMEngine e[2];
   int      anchor, L;
   datetime lastBar, dayKey;
   bool     dayValid;
   double   O, PC;
   int      retry;

   CNoiseMomentum(bool g) { gold = g; anchor = 570; L = 390; lastBar = 0; dayKey = 0; dayValid = false; O = 0; PC = 0; retry = 0; }

   void SetEngine(int k, bool o, int lb, double mult, int chk, double hk, double tk, double ta, long mg)
     {
      e[k].on = o; e[k].lookback = lb; e[k].mult = mult; e[k].chk = chk;
      e[k].hardK = hk; e[k].trailK = tk; e[k].trailAct = ta; e[k].maxTrades = 3;
      e[k].magic = mg; e[k].sigOk = false; e[k].tradesToday = 0; e[k].dir = 0;
      e[k].entry = 0; e[k].unit = 0; e[k].best = 0; e[k].sigE = 0;
     }

   virtual void Init()
     {
      if(gold)
        {
         anchor = 180; L = 780;
         SetEngine(0, true, 20, 3.0, 30, 0.75, 0.0, 0.0, magic);
         SetEngine(1, false, 20, 1.5, 30, 1.0, 0.0, 0.0, magic + 1);
        }
      else
        {
         anchor = 570; L = 390;
         SetEngine(0, true, 10, 1.2, 15, 0.5, 0.25, 0.5, magic);
         SetEngine(1, true, 20, 1.5, 30, 1.0, 0.0, 0.0, magic + 1);
        }
     }

   int CountPos(long mg, ulong &ticket, int &dir, double &op, double &sl, datetime &ot)
     {
      int cnt = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != mg) continue;
         cnt++;
         ticket = tk;
         dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         op = PositionGetDouble(POSITION_PRICE_OPEN);
         sl = PositionGetDouble(POSITION_SL);
         ot = (datetime)PositionGetInteger(POSITION_TIME);
        }
      return cnt;
     }

   bool AnyPosition()
     {
      for(int k = 0; k < 2; k++)
         if(e[k].on && CountPositions(e[k].magic) > 0)
            return true;
      return false;
     }

   void CloseEngines()
     {
      for(int k = 0; k < 2; k++)
         if(e[k].on) { CloseAll(e[k].magic); e[k].dir = 0; }
     }

   int RelOf(datetime srv, datetime &nyDay)
     {
      datetime ny = ServerToNY(srv);
      nyDay = DayStart(ny);
      return (int)((ny - nyDay) / 60) - anchor;
     }

   bool PrepareDay(datetime today)
     {
      dayValid = false;
      for(int k = 0; k < 2; k++) { e[k].sigOk = false; e[k].tradesToday = 0; }
      if(USHolidayOrHalf(today))
        { why = "libur / half day US"; return true; }
      why = "";
      datetime anchorSrv = NYToServer(today + anchor * 60);
      int maxLb = MathMax(e[0].on ? e[0].lookback : 0, e[1].on ? e[1].lookback : 0);
      int calDays = (int)MathCeil(maxLb * 1.6) + 12;
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int n = CopyRates(_Symbol, PERIOD_M1, anchorSrv - (datetime)calDays * 86400, anchorSrv + L * 60, r);
      if(n <= 0)
         return false;
      datetime dkeys[];
      double C[], Of[];
      int fr[], cnt[];
      int nd = 0;
      for(int i = 0; i < n; i++)
        {
         datetime dk;
         int rel = RelOf(r[i].time, dk);
         if(rel < 0 || rel >= L)
            continue;
         int di = -1;
         if(nd > 0 && dkeys[nd - 1] == dk)
            di = nd - 1;
         else
           {
            nd++;
            ArrayResize(dkeys, nd); ArrayResize(Of, nd); ArrayResize(fr, nd); ArrayResize(cnt, nd);
            ArrayResize(C, nd * L);
            di = nd - 1;
            dkeys[di] = dk; Of[di] = 0; fr[di] = 9999; cnt[di] = 0;
            for(int j = 0; j < L; j++)
               C[di * L + j] = EMPTY_VALUE;
           }
         if(C[di * L + rel] == EMPTY_VALUE)
            cnt[di]++;
         C[di * L + rel] = r[i].close;
         if(rel < fr[di]) { fr[di] = rel; Of[di] = r[i].open; }
        }
      int ti = -1;
      for(int d = 0; d < nd; d++)
         if(dkeys[d] == today)
            ti = d;
      if(ti < 0)
         return false;
      if(fr[ti] > 5)
         return true;
      O = Of[ti];
      int vi[];
      int nv = 0;
      for(int d = 0; d < nd; d++)
        {
         if(dkeys[d] >= today) continue;
         if((double)cnt[d] / L < 0.9 || fr[d] > 5) continue;
         double last = EMPTY_VALUE;
         for(int j = 0; j < L; j++)
           {
            if(C[d * L + j] == EMPTY_VALUE) C[d * L + j] = last;
            else last = C[d * L + j];
           }
         nv++;
         ArrayResize(vi, nv);
         vi[nv - 1] = d;
        }
      if(nv < 2)
         return true;
      PC = C[vi[nv - 1] * L + L - 1];
      bool any = false;
      for(int k = 0; k < 2; k++)
        {
         if(!e[k].on) continue;
         int lb = e[k].lookback;
         if(nv < lb) continue;
         ArrayResize(e[k].sig, L);
         for(int j = 0; j < L; j++)
           {
            double s = 0;
            int m = 0;
            for(int q = nv - lb; q < nv; q++)
              {
               int d = vi[q];
               double c = C[d * L + j];
               if(c == EMPTY_VALUE || Of[d] <= 0) { m = -1; break; }
               s += MathAbs(c / Of[d] - 1.0);
               m++;
              }
            e[k].sig[j] = (m == lb) ? s / lb : EMPTY_VALUE;
           }
         e[k].sigE = e[k].sig[L - 1];
         e[k].sigOk = !(e[k].sigE == EMPTY_VALUE || e[k].sigE <= 0);
         if(e[k].sigOk) any = true;
        }
      dayValid = any;
      why = any ? "sinyal noise siap" : "belum cukup hari valid untuk sinyal";
      return true;
     }

   void OpenTrade(int k, int dir)
     {
      if(!RegimeAllows(kind)) { why = "regime filter: " + g_regimeTxt; return; }
      double unit = e[k].sigE * O;
      double slDist = e[k].hardK * unit;
      if(slDist <= 0) return;
      double lots = LotsFor(slDist, risk);
      if(lots <= 0) { why = "lot 0: " + g_lotWhy; return; }
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = dir > 0 ? bid - slDist : ask + slDist;
      if(!SendMarket(e[k].magic, dir, lots, sl, 0, tag))
         return;
      e[k].tradesToday++;
      e[k].dir = dir;
      e[k].entry = dir > 0 ? bid : ask;
      e[k].best = e[k].entry;
      e[k].unit = unit;
     }

   void OnNewBar()
     {
      datetime t0 = iTime(_Symbol, PERIOD_M1, 0);
      MqlRates rb[];
      ArraySetAsSeries(rb, true);
      if(CopyRates(_Symbol, PERIOD_M1, 1, 1, rb) != 1)
         return;
      datetime nowDay, barDay;
      int relNow = RelOf(t0, nowDay);
      int relClosed = RelOf(rb[0].time, barDay);
      if(barDay != nowDay)
         relClosed = -9999;
      if(relNow >= L || (barDay != nowDay && AnyPosition()))
        {
         if(AnyPosition())
            CloseEngines();
        }
      if(dayKey != nowDay && relClosed >= 0 && relClosed < L)
        {
         dayKey = nowDay;
         if(!PrepareDay(nowDay) && retry < 30) { dayKey = 0; retry++; }
         else retry = 0;
        }
      if(dayKey != nowDay || !dayValid)
         return;
      if(relClosed < 0 || relClosed >= L - 1)
         return;
      double px = rb[0].close;
      double hiB = MathMax(O, PC);
      double loB = MathMin(O, PC);
      for(int k = 0; k < 2; k++)
        {
         if(!e[k].on || !e[k].sigOk) continue;
         double s = e[k].sig[relClosed];
         ulong tk = 0;
         int pdir = 0;
         double op = 0, psl = 0;
         datetime ot = 0;
         int np = CountPos(e[k].magic, tk, pdir, op, psl, ot);
         if(np == 0)
            e[k].dir = 0;
         if(np > 0 && e[k].trailK > 0)
           {
            if(e[k].dir == 0 || e[k].unit <= 0)
              {
               e[k].dir = pdir;
               e[k].entry = op;
               e[k].unit = e[k].sigE * O;
               e[k].best = op;
               int sh = iBarShift(_Symbol, PERIOD_M1, ot, false);
               if(sh >= 1)
                 {
                  if(pdir > 0)
                     e[k].best = MathMax(op, iHigh(_Symbol, PERIOD_M1, iHighest(_Symbol, PERIOD_M1, MODE_HIGH, sh, 1)));
                  else
                     e[k].best = MathMin(op, iLow(_Symbol, PERIOD_M1, iLowest(_Symbol, PERIOD_M1, MODE_LOW, sh, 1)));
                 }
              }
            if(pdir > 0)
              {
               if(rb[0].high > e[k].best) e[k].best = rb[0].high;
               if(e[k].best - e[k].entry >= e[k].trailAct * e[k].unit)
                 {
                  double ns = NormPrice(e[k].best - e[k].trailK * e[k].unit);
                  if(ns >= SymbolInfoDouble(_Symbol, SYMBOL_BID))
                    { CloseAll(e[k].magic); e[k].dir = 0; np = 0; }
                  else if(ns > psl + g_point)
                    { g_trade.SetExpertMagicNumber(e[k].magic); g_trade.PositionModify(tk, ns, 0); }
                 }
              }
            else
              {
               if(rb[0].low < e[k].best) e[k].best = rb[0].low;
               if(e[k].entry - e[k].best >= e[k].trailAct * e[k].unit)
                 {
                  double ns = NormPrice(e[k].best + e[k].trailK * e[k].unit);
                  if(ns <= SymbolInfoDouble(_Symbol, SYMBOL_ASK))
                    { CloseAll(e[k].magic); e[k].dir = 0; np = 0; }
                  else if(psl == 0 || ns < psl - g_point)
                    { g_trade.SetExpertMagicNumber(e[k].magic); g_trade.PositionModify(tk, ns, 0); }
                 }
              }
           }
         if(s == EMPTY_VALUE) continue;
         int chk = e[k].chk;
         bool isChk = (relClosed >= chk) && ((relClosed - chk) % chk == 0);
         if(!isChk) continue;
         double UB = hiB * (1.0 + e[k].mult * s);
         double LB = loB * (1.0 - e[k].mult * s);
         if(np > 0)
           {
            if((pdir > 0 && px < UB) || (pdir < 0 && px > LB))
              { CloseAll(e[k].magic); e[k].dir = 0; }
            continue;
           }
         if(e[k].tradesToday >= e[k].maxTrades) continue;
         if(px > UB) OpenTrade(k, 1);
         else if(px < LB) OpenTrade(k, -1);
        }
     }

   virtual void Tick(datetime now)
     {
      datetime t0 = iTime(_Symbol, PERIOD_M1, 0);
      if(t0 == 0) return;
      if(t0 != lastBar) { lastBar = t0; OnNewBar(); }
     }

   virtual void OnDeal(ulong deal)
     {
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
        {
         long mg = HistoryDealGetInteger(deal, DEAL_MAGIC);
         for(int k = 0; k < 2; k++)
            if(e[k].magic == mg)
               e[k].dir = 0;
        }
     }

   virtual string Extra() { return dayValid ? "sig ok" : "no sig"; }

   virtual datetime ExitAt(datetime openSrv)
     {
      return NYToServer(DayStart(ServerToNY(openSrv)) + (anchor + L) * 60);
     }

   virtual void Levels(datetime now)
     {
      if(!dayValid || dayKey == 0) return;
      color c = LvC(tag);
      double hiB = MathMax(O, PC), loB = MathMin(O, PC);
      datetime s0 = NYToServer(dayKey + anchor * 60), s1 = NYToServer(dayKey + (anchor + L) * 60);
      double top = 0, bot = 0, cu = 0, cl = 0;
      int prim = -1, chkP = 30;
      for(int k = 0; k < 2; k++)
        {
         if(!e[k].on || !e[k].sigOk) continue;
         if(prim < 0) { prim = k; chkP = e[k].chk; }
         int chk = e[k].chk;
         double pu = 0, pl = 0;
         for(int rel = chk; rel < L; rel += chk)
           {
            double sg = e[k].sig[rel];
            if(sg == EMPTY_VALUE) continue;
            datetime ts = NYToServer(dayKey + (anchor + rel - chk) * 60), te = ts + chk * 60;   // band yang dicek di menit 'rel'
            double ub = hiB * (1.0 + e[k].mult * sg), lb = loB * (1.0 - e[k].mult * sg);
            if(k == prim)
              {
               if(top == 0) { top = ub; bot = lb; }
               top = MathMax(top, ub); bot = MathMin(bot, lb);
               if(cu == 0 || (now >= ts && now < te)) { cu = ub; cl = lb; }
               if(ShowNoiseBands) LvRect(tag + "_c" + IntegerToString(rel), ts, lb, te, ub, CLR_WIN);
              }
            if(ShowNoiseBands)
              {
               string sk = IntegerToString(k) + "_" + IntegerToString(rel);
               LvLine(tag + "_u" + sk, ub, ts, te, c, STYLE_SOLID, 1, "");
               LvLine(tag + "_l" + sk, lb, ts, te, c, STYLE_SOLID, 1, "");
               if(pu > 0) { LvVSeg(tag + "_uv" + sk, ts, pu, ub, c); LvVSeg(tag + "_lv" + sk, ts, pl, lb, c); }
              }
            pu = ub; pl = lb;
           }
        }
      if(top <= 0) return;
      if(!ShowNoiseBands) LvRect(tag + "_win", s0, bot, s1, top, CLR_WIN);
      LvLabel(tag + "_lb", s0, top, " koridor " + SName(tag), c, ANCHOR_LEFT_LOWER);
      if(Positions() > 0) return;   // posisi digambar terpisah
      string rule = "BUY close > " + Px(cu) + "   SELL close < " + Px(cl) + "   cek tiap " + IntegerToString(chkP) + "m";
      if(now < s0)
        {
         CardAdd(0.5 * (cu + cl), s1, c, 1, UpS(SName(tag)) + "  " + U(0x00B7) + "  sesi mulai " + NYhm(s0), rule);
         LvRow(tag, 1, "sesi " + NYhm(s0) + " - " + NYhm(s1) + ", tunggu tembus koridor");
        }
      else if(now < s1)
        {
         CardAdd(0.5 * (cu + cl), s1, c, 1, UpS(SName(tag)) + "  " + U(0x00B7) + "  tunggu tembus koridor", rule);
         LvRow(tag, 1, "sesi s/d " + NYhm(s1) + ", tunggu tembus koridor");
        }
      else LvRow(tag, 3, "selesai: sesi hari ini sudah tutup");
     }

  };

//+------------------------------------------------------------------+
//| B8 Tokyo Momentum (USDJPY, peer GBPUSD)                          |
//+------------------------------------------------------------------+
class CB8 : public CStrat
  {
public:
   string    peer;
   datetime  peerTry;
   CDayTable pdt;
   datetime  setupDay;

   datetime  tryT;
   CB8() { peer = ""; peerTry = 0; setupDay = 0; tryT = 0; }

   string FindPeer(string target)
     {
      string me = _Symbol;
      int p = StringFind(me, "USDJPY");
      if(p >= 0)
        {
         string cand = StringSubstr(me, 0, p) + target + StringSubstr(me, p + 6);
         if(SymbolSelect(cand, true)) return cand;
        }
      if(SymbolSelect(target, true)) return target;
      int tot = SymbolsTotal(false);
      for(int i = 0; i < tot; i++)
        {
         string s = SymbolName(i, false);
         if(StringFind(s, target) >= 0 && SymbolSelect(s, true)) return s;
        }
      return "";
     }

   virtual void Init()
     {
      InitDays(1, 1, 0.5);
      peer = FindPeer("GBPUSD");
      if(peer != "") pdt.Init(peer, 1, 1, 0.5);
      else Print("B8: GBPUSD tidak ditemukan, B8 tidak buka trade baru sampai GBPUSD tersedia");
     }

   bool PeerReady(datetime now)
     {
      if(peer != "") return true;
      if(now - peerTry < 60) return false;
      peerTry = now;
      peer = FindPeer("GBPUSD");
      if(peer == "") return false;
      pdt.Init(peer, 1, 1, 0.5);
      Print("B8: GBPUSD ditemukan: ", peer);
      return true;
     }

   void ManageExits(datetime now)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magic) continue;
         datetime e = DayStart(ServerToLondon((datetime)PositionGetInteger(POSITION_TIME)));
         datetime x = ExitServerTime(e, 12 * 60);
         if(g_sameDay) x = CapToCut(x, e);
         if(now >= x) ClosePositionTicket(tk);
        }
     }

   void TrySetup(datetime now, datetime lday)
     {
      why = "";
      if(IsJPHoliday(lday)) { why = "libur Jepang"; return; }
      if(g_sameDay && FutSession(lday) == 2) return;
      if(CountPositions(magic) > 0) { why = "masih ada posisi"; return; }
      datetime xSrv = ExitServerTime(lday, 12 * 60);
      if(g_sameDay) xSrv = CapToCut(xSrv, lday);
      if(now >= xSrv) return;
      pdt.Update();
      double au = dt.ADRBeforeKey(lday, true);
      double ag = pdt.ADRBeforeKey(lday, true);
      if(au <= 0 || ag <= 0) { why = "ADR belum cukup data"; return; }
      datetime s00 = LondonToServer(lday);
      datetime s07 = LondonToServer(lday + 7 * 3600);
      double u0 = CloseBefore(_Symbol, s00), u7 = CloseBefore(_Symbol, s07);
      double g0 = CloseBefore(peer, s00), g7 = CloseBefore(peer, s07);
      if(u0 <= 0 || u7 <= 0 || g0 <= 0 || g7 <= 0) return;
      double u = (u7 - u0) / au;
      int side = u > 0 ? 1 : (u < 0 ? -1 : 0);
      if(side == 0) return;
      double g = -(g7 - g0) / ag * side;
      if(MathAbs(u) < 0.4) { why = "Tokyo move " + DoubleToString(MathAbs(u), 2) + " ADR < 0.4"; return; }
      if(MathAbs(g) > 0.25) { why = "GBPUSD ikut gerak " + DoubleToString(MathAbs(g), 2) + " ADR"; return; }
      if(!RegimeAllows(kind)) { why = "regime filter: " + g_regimeTxt; return; }
      double sl = u7 - side * 0.25 * au;
      double lots = LotsFor(0.25 * au, risk);
      if(lots <= 0) { why = "lot 0: " + g_lotWhy; return; }
      why = "entry";
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if((side > 0 && bid <= sl) || (side < 0 && ask >= sl)) return;
      SendMarket(magic, side, lots, sl, 0, tag);
     }

   virtual void Tick(datetime now)
     {
      datetime lnow = ServerToLondon(now);
      datetime lday = DayStart(lnow);
      int dw = DayOfWeekOf(lday);
      ManageExits(now);
      if(!PeerReady(now)) return;
      if(dw >= 1 && dw <= 5 && lday != setupDay && lnow >= lday + 7 * 3600 && now - tryT >= 30)
        {
         tryT = now;
         g_dirWhy = ""; g_lotWhy = "";
         TrySetup(now, lday);
         // hambatan sementara (news/spread/cap/antrian kirim/data belum ada) -> coba lagi tiap 30 dtk sampai 07:30 London
         bool temp = why == "" || g_dirWhy != "" || (StringFind(why, "lot 0") == 0 && TempBlocked());
         if(!temp || lnow >= lday + 7 * 3600 + 30 * 60) setupDay = lday;
         else if(why != "") why = "tertunda: " + (g_dirWhy != "" ? g_dirWhy : g_lotWhy);
        }
     }

   virtual string Extra() { return peer == "" ? "NO GBPUSD!" : ""; }

   virtual datetime ExitAt(datetime openSrv)
     {
      return ExitServerTime(DayStart(ServerToLondon(openSrv)), 12 * 60);
     }

   virtual void Levels(datetime now)
     {
      datetime lday = DayStart(ServerToLondon(now));
      int dw = DayOfWeekOf(lday);
      if(dw < 1 || dw > 5 || Positions() > 0) return;
      double au = dt.ADRBeforeKey(lday, true);
      datetime s00 = LondonToServer(lday), s07 = LondonToServer(lday + 7 * 3600);
      double u0 = CloseBefore(_Symbol, s00);
      if(au <= 0 || u0 <= 0) return;
      color c = LvC(tag);
      double up = u0 + 0.4 * au, dn = u0 - 0.4 * au;
      LvRect(tag + "_box", s00, dn, s07, up, CLR_WIN);
      LvLine(tag + "_up", up, s00, s07, c, STYLE_DASH, 1, "");
      LvLine(tag + "_dn", dn, s00, s07, c, STYLE_DASH, 1, "");
      LvLabel(tag + "_lb", s00, up, " " + SName(tag) + " kotak ukur", c, ANCHOR_LEFT_LOWER);
      if(now < s07)
        {
         CardAdd(u0, s07, c, 1, UpS(SName(tag)) + "  " + U(0x00B7) + "  cek jam 07:00 LDN", "BUY > " + Px(up) + "   SELL < " + Px(dn) + "   exit 12:00 NY");
         LvRow(tag, 1, "cek 07:00 LDN: BUY > " + Px(up) + " / SELL < " + Px(dn));
        }
      else LvRow(tag, 3, Rejected() ? "ditolak: " + why : "selesai: tidak ada sinyal jam 07:00");
      LvTime(tag + "_chk", s07, c, tag + " cek entry 07:00 LDN");
     }

  };

//+------------------------------------------------------------------+
//| S009 (Gold) / S009U (USDJPY) Narrow Range Breakout               |
//+------------------------------------------------------------------+
class CS009 : public CStrat
  {
public:
   bool     usdjpy;
   datetime setupDay, lastTry;

   CS009(bool u) { usdjpy = u; setupDay = 0; lastTry = 0; pend = true; }

   virtual void Init()
     {
      if(usdjpy) InitDays(1, 1, 0.5);
      else       InitDays(0, 2, 0.5);
     }

   datetime OrderExpiryFor(datetime setupSrv)
     {
      datetime lday = DayStart(ServerToLondon(setupSrv));
      datetime ex;
      if(usdjpy)
         ex = ExitServerTime(lday, 16 * 60 + 55);
      else
        {
         ex = LondonToServer(lday + 21 * 3600 + 54 * 60);
         datetime nyEx = ServerToNY(ex);
         ex = CapToTradeEnd(NYToServer(CapToSessionClose(nyEx)));
        }
      if(g_sameDay) ex = CapToCut(ex, lday);
      return ex;
     }

   void ManageOrders(datetime now)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != magic) continue;
         if(now >= OrderExpiryFor((datetime)OrderGetInteger(ORDER_TIME_SETUP)))
            g_trade.OrderDelete(tk);
        }
     }

   void ManageExits(datetime now)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magic) continue;
         datetime e = DayStart(ServerToLondon((datetime)PositionGetInteger(POSITION_TIME)));
         datetime x;
         if(usdjpy) x = ExitServerTime(dt.NextDayAfter(e, true), 16 * 60 + 55);
         else       x = ExitServerTime(dt.NextDayAfter(e, false), 16 * 60 + 59);
         if(g_sameDay) x = CapToCut(x, e);
         if(now >= x) ClosePositionTicket(tk);
        }
     }

   void TrySetup(datetime now, datetime lday)
     {
      why = "";
      if(g_sameDay && FutSession(lday) == 2) return;
      if(CountPositions(magic) > 0 || CountOrders(magic) > 0) { why = "masih ada posisi/order"; return; }
      if(EntrySince(magic, LondonToServer(lday))) { why = "sudah trade hari ini"; setupDay = lday; return; }
      datetime expSrv = OrderExpiryFor(now);
      if(now >= expSrv) { why = "sudah lewat jam setup"; return; }
      int y = dt.PrevValid(dt.IndexBefore(lday));
      if(y < 0) { why = "belum ada hari valid"; return; }
      double adr = dt.ADRBeforeKey(dt.days[y].d, true);
      if(adr <= 0) { why = "ADR belum cukup data"; return; }
      double yh = dt.days[y].h, yl = dt.days[y].l;
      double yr = yh - yl;
      double pct = yr / dt.days[y].c * 100.0;
      if(yr <= 0 || yr > 0.6 * adr) { why = "range kemarin " + DoubleToString(yr / adr, 2) + " ADR, bukan hari sempit (<0.6)"; return; }
      if(pct > 3.0) { why = "range kemarin terlalu lebar (" + DoubleToString(pct, 1) + "%)"; return; }
      if(!usdjpy && pct < 0.3) { why = "range kemarin terlalu sempit (" + DoubleToString(pct, 2) + "%)"; return; }
      if(!RegimeAllows(kind)) { why = "regime filter: " + g_regimeTxt; return; }
      double mid = 0.5 * (yh + yl);
      double tpL = yh + 2.0 * (yh - mid);
      double tpS = yl - 2.0 * (mid - yl);
      double lots = LotsFor(yh - mid, risk);
      if(lots <= 0) { why = "lot 0: " + g_lotWhy; return; }
      why = "setup aktif";
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(ask >= yh)
        {
         if(bid < tpL && bid > mid) SendMarket(magic, 1, lots, mid, tpL, tag);
         return;
        }
      if(bid <= yl)
        {
         if(ask > tpS && ask < mid) SendMarket(magic, -1, lots, mid, tpS, tag);
         return;
        }
      SendPending(magic, ORDER_TYPE_BUY_STOP, lots, yh, mid, tpL, expSrv, tag);
      SendPending(magic, ORDER_TYPE_SELL_STOP, lots, yl, mid, tpS, expSrv, tag);
     }

   virtual void Tick(datetime now)
     {
      datetime lday = DayStart(ServerToLondon(now));
      int dw = DayOfWeekOf(lday);
      ManageExits(now);
      ManageOrders(now);
      if(CountPositions(magic) > 0 && CountOrders(magic) > 0) DeleteOrders(magic);   // sisa OCO
      if(dw >= 1 && dw <= 5 && lday != setupDay && now - lastTry >= 60)
        {
         lastTry = now;
         g_lotWhy = ""; g_dirWhy = "";
         TrySetup(now, lday);
         if(TempBlocked()) why = "tertunda: " + (g_dirWhy != "" ? g_dirWhy : g_lotWhy);   // coba lagi menit berikutnya
         else setupDay = lday;
        }
     }

   virtual datetime ExitAt(datetime openSrv)
     {
      datetime e = DayStart(ServerToLondon(openSrv));
      return usdjpy ? ExitServerTime(dt.NextDayAfter(e, true), 16 * 60 + 55) : ExitServerTime(dt.NextDayAfter(e, false), 16 * 60 + 59);
     }

   virtual void Levels(datetime now)
     {
      datetime lday = DayStart(ServerToLondon(now));
      int dw = DayOfWeekOf(lday);
      if(dw < 1 || dw > 5 || Positions() > 0) return;
      int y = dt.PrevValid(dt.IndexBefore(lday));
      if(y < 0) return;
      double adr = dt.ADRBeforeKey(dt.days[y].d, true);
      if(adr <= 0) return;
      double yh = dt.days[y].h, yl = dt.days[y].l, yr = yh - yl;
      double pct = yr / dt.days[y].c * 100.0;
      datetime t1 = LondonToServer(lday), t2 = OrderExpiryFor(now);
      if(t2 <= t1) t2 = t1 + 86400;
      bool ok = yr > 0 && yr <= 0.6 * adr && pct <= 3.0 && (usdjpy || pct >= 0.3);
      if(!ok)
        {
         LvLine(tag + "_h", yh, t1, t2, clrDimGray, STYLE_DOT, 1, "");
         LvLine(tag + "_l", yl, t1, t2, clrDimGray, STYLE_DOT, 1, "");
         LvRow(tag, 3, "libur: range kemarin " + DoubleToString(yr / adr, 2) + " ADR (perlu < 0.6)");
         return;
        }
      double mid = 0.5 * (yh + yl);
      LvTrade(tag + "_b", tag, true,  yh, mid, yh + 2.0 * (yh - mid), t1, t2, PendState(ORDER_TYPE_BUY_STOP),  "BUY STOP",  Rejected() ? why : "");
      LvTrade(tag + "_s", tag, false, yl, mid, yl - 2.0 * (mid - yl), t1, t2, PendState(ORDER_TYPE_SELL_STOP), "SELL STOP", Rejected() ? why : "");
     }


   virtual void OnDeal(ulong deal)
     {
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         DeleteOrders(magic);
     }
  };

//+------------------------------------------------------------------+
//| S015 Weekly Breakout (Gold)                                      |
//+------------------------------------------------------------------+
class CS015 : public CStrat
  {
public:
   datetime day;
   bool     dayOk, actL, actS, traded, hadPos;
   double   wh, wl, adr;
   datetime expT, lastExitMin, lastTry;

   CS015() { day = 0; dayOk = false; actL = false; actS = false; traded = false; hadPos = false; wh = 0; wl = 0; adr = 0; expT = 0; lastExitMin = 0; lastTry = 0; pend = true; }

   virtual void Missed(int type) { if(type == ORDER_TYPE_BUY_STOP) actL = false; else if(type == ORDER_TYPE_SELL_STOP) actS = false; }

   virtual void Init() { InitDays(0, 0, 0.5); }

   void ManageExits(datetime now)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magic) continue;
         datetime e = DayStart(ServerToLondon((datetime)PositionGetInteger(POSITION_TIME)));
         datetime x = ExitServerTime(dt.NextDayAfter(e, false), 16 * 60 + 55);
         if(g_sameDay) x = CapToCut(x, e);
         if(now >= x) ClosePositionTicket(tk);
        }
     }

   bool TradedOn(datetime lday)
     {
      datetime s0 = LondonToServer(lday);
      if(!HistorySelect(s0, TimeCurrent() + 60)) return false;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(d, DEAL_MAGIC) != magic) continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         if(DayStart(ServerToLondon((datetime)HistoryDealGetInteger(d, DEAL_TIME))) == lday) return true;
        }
      return false;
     }

   void NewDay(datetime now, datetime lday)
     {
      day = lday;
      dayOk = false;
      traded = TradedOn(lday);
      DeleteOrders(magic);
      if(g_sameDay && FutSession(lday) == 2) return;
      datetime wk = lday - (DayOfWeekOf(lday) - 1) * 86400;
      double h = -DBL_MAX, l = DBL_MAX;
      int cnt = 0;
      for(int j = dt.n - 1; j >= 0; j--)
        {
         if(dt.days[j].d >= wk) continue;
         if(dt.days[j].d < wk - 7 * 86400) break;
         if(dt.days[j].h > h) h = dt.days[j].h;
         if(dt.days[j].l < l) l = dt.days[j].l;
         cnt++;
        }
      if(cnt == 0) { why = "data minggu lalu belum ada"; return; }
      adr = dt.ADRBeforeKey(lday, false);
      if(adr <= 0) { why = "ADR belum cukup data"; return; }
      wh = h; wl = l;
      actL = true; actS = true;
      if(lday > wk)
        {
         double hi, lo;
         int n;
         datetime ft;
         HighLowBetween(LondonToServer(wk), LondonToServer(lday), hi, lo, n, ft);
         if(n > 0)
           {
            if(hi >= wh) actL = false;
            if(lo <= wl) actS = false;
           }
        }
      expT = ExitServerTime(lday, 16 * 60 + 55);
      if(g_sameDay) expT = CapToCut(expT, lday);
      dayOk = true;
      why = (actL || actS) ? "menunggu breakout" + (actL ? " H " + DoubleToString(wh, g_digits) : "") + (actS ? " L " + DoubleToString(wl, g_digits) : "") : "high/low minggu lalu sudah tersentuh";
     }

   void Arm(datetime now)
     {
      if(!dayOk || traded || now >= expT) return;
      if(!RegimeAllows(kind)) { why = "regime filter: " + g_regimeTxt; return; }
      if(CountPositions(magic) > 0)
        {
         if(CountOrders(magic) > 0) DeleteOrders(magic);
         return;
        }
      if(now - (now % 60) == lastExitMin) return;
      if((actL && !HasOrderOfType(magic, ORDER_TYPE_BUY_STOP)) || (actS && !HasOrderOfType(magic, ORDER_TYPE_SELL_STOP)))
        {
         if(now - lastTry < 60) return;            // throttle: maksimal 1 percobaan per menit
         lastTry = now;
        }
      double dist = 0.35 * adr;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(actL && !HasOrderOfType(magic, ORDER_TYPE_BUY_STOP))
        {
         double sl = wh - dist, tp = wh + 2.0 * dist;
         g_dirWhy = "";
         double lots = LotsFor(dist, risk);
         if(lots <= 0) { if(!TempBlocked()) actL = false; else why = "tertunda: " + (g_dirWhy != "" ? g_dirWhy : g_lotWhy); }
         else if(ask >= wh)
           {
            if(bid < tp && bid > sl && ask - wh <= LateFillADR * ChartADR())
              {
               if(SendMarket(magic, 1, lots, sl, tp, tag)) { actL = false; return; }
               if(g_dirWhy == "") actL = false;
              }
            else actL = false;
           }
         else SendPending(magic, ORDER_TYPE_BUY_STOP, lots, wh, sl, tp, expT, tag);
        }
      if(actS && !HasOrderOfType(magic, ORDER_TYPE_SELL_STOP))
        {
         double sl = wl + dist, tp = wl - 2.0 * dist;
         g_dirWhy = "";
         double lots = LotsFor(dist, risk);
         if(lots <= 0) { if(!TempBlocked()) actS = false; else why = "tertunda: " + (g_dirWhy != "" ? g_dirWhy : g_lotWhy); }
         else if(bid <= wl)
           {
            if(ask > tp && ask < sl && wl - bid <= LateFillADR * ChartADR())
              {
               if(SendMarket(magic, -1, lots, sl, tp, tag)) { actS = false; return; }
               if(g_dirWhy == "") actS = false;
              }
            else actS = false;
           }
         else SendPending(magic, ORDER_TYPE_SELL_STOP, lots, wl, sl, tp, expT, tag);
        }
     }

   virtual void Tick(datetime now)
     {
      datetime lday = DayStart(ServerToLondon(now));
      int dw = DayOfWeekOf(lday);
      ManageExits(now);
      int np = CountPositions(magic);
      if(hadPos && np == 0) lastExitMin = now - (now % 60);
      if(!hadPos && np > 0) traded = true;
      hadPos = np > 0;
      if(dw >= 1 && dw <= 5 && lday != day) NewDay(now, lday);
      if(dayOk && now >= expT && CountOrders(magic) > 0) DeleteOrders(magic);
      if(dw >= 1 && dw <= 5) Arm(now);
     }

   virtual void OnDeal(ulong deal)
     {
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         traded = true;
         DeleteOrders(magic);
        }
     }

   virtual string Extra() { return traded ? "done today" : (dayOk ? "armed" : ""); }

   virtual datetime ExitAt(datetime openSrv)
     {
      datetime e = DayStart(ServerToLondon(openSrv));
      return ExitServerTime(dt.NextDayAfter(e, false), 16 * 60 + 55);
     }

   virtual void Levels(datetime now)
     {
      if(!dayOk || Positions() > 0) return;
      datetime t1 = LondonToServer(day), t2 = expT;
      double dist = 0.35 * adr;
      if(traded) { LvRow(tag, 3, "selesai: sudah 1 trade hari ini"); return; }
      if(!actL && !actS) LvRow(tag, 3, "libur: high & low minggu lalu sudah tersentuh");
      if(actL) LvTrade(tag + "_b", tag, true, wh, wh - dist, wh + 2.0 * dist, t1, t2, PendState(ORDER_TYPE_BUY_STOP), "BUY STOP", Rejected() ? why : "");
      else { LvLine(tag + "_wh", wh, t1, t2, clrDimGray, STYLE_DOT, 1, ""); }
      if(actS) LvTrade(tag + "_s", tag, false, wl, wl + dist, wl - 2.0 * dist, t1, t2, PendState(ORDER_TYPE_SELL_STOP), "SELL STOP", Rejected() ? why : "");
      else { LvLine(tag + "_wl", wl, t1, t2, clrDimGray, STYLE_DOT, 1, ""); }
     }

  };

//+------------------------------------------------------------------+
//| S017 Round Number Break (Gold)                                   |
//+------------------------------------------------------------------+
class CS017 : public CStrat
  {
public:
   datetime day;
   bool     dayOk, actU, actD, hadPos;
   double   uLvl, uSL, uTP, dLvl, dSL, dTP, dist;
   datetime expT, lastExitMin, lastTry;

   CS017() { day = 0; dayOk = false; actU = false; actD = false; hadPos = false; uLvl = 0; uSL = 0; uTP = 0; dLvl = 0; dSL = 0; dTP = 0; dist = 0; expT = 0; lastExitMin = 0; lastTry = 0; pend = true; }

   virtual void Missed(int type) { if(type == ORDER_TYPE_BUY_STOP) actU = false; else if(type == ORDER_TYPE_SELL_STOP) actD = false; }

   virtual void Init() { InitDays(0, 1, 0.7); }

   void ManageExits(datetime now)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magic) continue;
         datetime e = DayStart(ServerToLondon((datetime)PositionGetInteger(POSITION_TIME)));
         if(now >= ExitServerTime(e, 16 * 60 + 30)) ClosePositionTicket(tk);
        }
     }

   bool SideTradedOn(datetime lday, int dir)
     {
      datetime s0 = LondonToServer(lday);
      if(!HistorySelect(s0, TimeCurrent() + 60)) return false;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(d, DEAL_MAGIC) != magic) continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         int t = (int)HistoryDealGetInteger(d, DEAL_TYPE);
         if((dir > 0 && t == DEAL_TYPE_BUY) || (dir < 0 && t == DEAL_TYPE_SELL)) return true;
        }
      return false;
     }

   void NewDay(datetime now, datetime lday)
     {
      day = lday;
      dayOk = false; actU = false; actD = false;
      DeleteOrders(magic);
      double adr = dt.ADRBeforeKey(lday, true);
      if(adr <= 0) return;
      datetime s00 = LondonToServer(lday);
      double px = CloseBefore(_Symbol, s00);
      if(px <= 0) return;
      double hi, lo;
      int n;
      datetime ft;
      HighLowBetween(s00 - 24 * 3600, s00, hi, lo, n, ft);
      double lu = MathFloor(px / 50.0) * 50.0 + 50.0;
      double ld = MathCeil(px / 50.0) * 50.0 - 50.0;
      dist = 0.2 * adr;
      if(MathAbs(lu - px) <= adr && !(n > 0 && hi >= lu && lo <= lu))
        {
         uLvl = lu + 0.05 * adr;
         uSL = lu - 0.15 * adr;
         uTP = uLvl + 2.0 * (uLvl - uSL);
         actU = !SideTradedOn(lday, 1);
        }
      if(MathAbs(ld - px) <= adr && !(n > 0 && hi >= ld && lo <= ld))
        {
         dLvl = ld - 0.05 * adr;
         dSL = ld + 0.15 * adr;
         dTP = dLvl - 2.0 * (dSL - dLvl);
         actD = !SideTradedOn(lday, -1);
        }
      expT = ExitServerTime(lday, 16 * 60 + 30);
      dayOk = actU || actD;
      why = dayOk ? "menunggu level" + (actU ? " " + DoubleToString(uLvl, g_digits) : "") + (actD ? " / " + DoubleToString(dLvl, g_digits) : "") : "tidak ada level bulat dalam 1 ADR / sudah tersentuh";
     }

   void Arm(datetime now)
     {
      if(!dayOk || now >= expT) return;
      if(!RegimeAllows(kind)) { why = "regime filter: " + g_regimeTxt; return; }
      if(CountPositions(magic) > 0)
        {
         if(CountOrders(magic) > 0) DeleteOrders(magic);
         return;
        }
      if(now - (now % 60) == lastExitMin) return;
      if((actU && !HasOrderOfType(magic, ORDER_TYPE_BUY_STOP)) || (actD && !HasOrderOfType(magic, ORDER_TYPE_SELL_STOP)))
        {
         if(now - lastTry < 60) return;            // throttle: maksimal 1 percobaan per menit
         lastTry = now;
        }
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(actU && !HasOrderOfType(magic, ORDER_TYPE_BUY_STOP))
        {
         g_dirWhy = "";
         double lots = LotsFor(uLvl - uSL, risk);
         if(lots <= 0) { if(!TempBlocked()) actU = false; else why = "tertunda: " + (g_dirWhy != "" ? g_dirWhy : g_lotWhy); }
         else if(ask >= uLvl)
           {
            if(bid > uSL && bid < uTP && ask - uLvl <= LateFillADR * ChartADR())
              {
               if(SendMarket(magic, 1, lots, uSL, uTP, tag)) { actU = false; return; }
               if(g_dirWhy == "") actU = false;
              }
            else actU = false;
           }
         else SendPending(magic, ORDER_TYPE_BUY_STOP, lots, uLvl, uSL, uTP, expT, tag);
        }
      if(actD && !HasOrderOfType(magic, ORDER_TYPE_SELL_STOP))
        {
         g_dirWhy = "";
         double lots = LotsFor(dSL - dLvl, risk);
         if(lots <= 0) { if(!TempBlocked()) actD = false; else why = "tertunda: " + (g_dirWhy != "" ? g_dirWhy : g_lotWhy); }
         else if(bid <= dLvl)
           {
            if(ask < dSL && ask > dTP && dLvl - bid <= LateFillADR * ChartADR())
              {
               if(SendMarket(magic, -1, lots, dSL, dTP, tag)) { actD = false; return; }
               if(g_dirWhy == "") actD = false;
              }
            else actD = false;
           }
         else SendPending(magic, ORDER_TYPE_SELL_STOP, lots, dLvl, dSL, dTP, expT, tag);
        }
     }

   virtual void Tick(datetime now)
     {
      datetime lday = DayStart(ServerToLondon(now));
      int dw = DayOfWeekOf(lday);
      ManageExits(now);
      int np = CountPositions(magic);
      if(hadPos && np == 0) lastExitMin = now - (now % 60);
      hadPos = np > 0;
      if(dw >= 1 && dw <= 5 && lday != day) NewDay(now, lday);
      if(dayOk && now >= expT && CountOrders(magic) > 0) DeleteOrders(magic);
      if(dw >= 1 && dw <= 5) Arm(now);
     }

   virtual void OnDeal(ulong deal)
     {
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         if(HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY) actU = false;
         else actD = false;
         DeleteOrders(magic);
        }
     }

   virtual string Extra() { return dayOk ? "armed" : "no level"; }

   virtual datetime ExitAt(datetime openSrv)
     {
      return ExitServerTime(DayStart(ServerToLondon(openSrv)), 16 * 60 + 30);
     }

   virtual void Levels(datetime now)
     {
      if(!dayOk || Positions() > 0) return;
      datetime t1 = LondonToServer(day), t2 = expT;
      if(actU) LvTrade(tag + "_b", tag, true,  uLvl, uSL, uTP, t1, t2, PendState(ORDER_TYPE_BUY_STOP),  "BUY STOP",  Rejected() ? why : "");
      if(actD) LvTrade(tag + "_s", tag, false, dLvl, dSL, dTP, t1, t2, PendState(ORDER_TYPE_SELL_STOP), "SELL STOP", Rejected() ? why : "");
     }

  };

//+------------------------------------------------------------------+
//| S018 Big Day Pullback (Gold / Silver)                            |
//+------------------------------------------------------------------+
class CS018 : public CStrat
  {
public:
   datetime setupDay, lastTry;

   CS018() { setupDay = 0; lastTry = 0; pend = true; }

   virtual void Init() { InitDays(1, 1, 0.5); }

   datetime OrderExpiryFor(datetime setupSrv)
     {
      datetime lday = DayStart(ServerToLondon(setupSrv));
      return ExitServerTime(lday, 16 * 60 + 55);
     }

   void ManageOrders(datetime now)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != magic) continue;
         if(now >= OrderExpiryFor((datetime)OrderGetInteger(ORDER_TIME_SETUP)))
            g_trade.OrderDelete(tk);
        }
     }

   void ManageExits(datetime now)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magic) continue;
         datetime e = DayStart(ServerToLondon((datetime)PositionGetInteger(POSITION_TIME)));
         datetime x = dt.NextDayAfter(e, true);
         if(now >= ExitServerTime(x, 16 * 60 + 55)) ClosePositionTicket(tk);
        }
     }

   void TrySetup(datetime now, datetime lday)
     {
      why = "";
      if(CountPositions(magic) > 0 || CountOrders(magic) > 0) { why = "masih ada posisi/order"; return; }
      if(EntrySince(magic, LondonToServer(lday))) { why = "sudah trade hari ini"; setupDay = lday; return; }
      datetime expSrv = OrderExpiryFor(now);
      if(now >= expSrv) { why = "sudah lewat jam setup"; return; }
      int y = dt.PrevValid(dt.IndexBefore(lday));
      if(y < 0) { why = "belum ada hari valid"; return; }
      double adr = dt.ADRBeforeKey(dt.days[y].d, true);
      if(adr <= 0) { why = "ADR belum cukup data"; return; }
      double yr = dt.days[y].h - dt.days[y].l;
      if(yr < 1.5 * adr || yr <= 0) { why = "range kemarin " + DoubleToString(yr / adr, 2) + " ADR, bukan big day (>=1.5)"; return; }
      double pos = (dt.days[y].c - dt.days[y].l) / yr;
      int side = 0;
      if(pos >= 0.75) side = 1;
      else if(pos <= 0.25) side = -1;
      if(side == 0) { why = "close kemarin di tengah range (" + DoubleToString(pos * 100, 0) + "%)"; return; }
      if(!RegimeAllows(kind)) { why = "regime filter: " + g_regimeTxt; return; }
      double lvl = dt.days[y].c - side * 0.25 * adr;
      double stop = lvl - side * 0.5 * adr;
      double lots = LotsFor(0.5 * adr, risk);
      if(lots <= 0) { why = "lot 0: " + g_lotWhy; return; }
      why = "limit order dipasang";
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(side > 0)
        {
         if(ask <= lvl)
           {
            if(bid > stop) SendMarket(magic, 1, lots, stop, 0, tag);
            return;
           }
         SendPending(magic, ORDER_TYPE_BUY_LIMIT, lots, lvl, stop, 0, expSrv, tag);
        }
      else
        {
         if(bid >= lvl)
           {
            if(ask < stop) SendMarket(magic, -1, lots, stop, 0, tag);
            return;
           }
         SendPending(magic, ORDER_TYPE_SELL_LIMIT, lots, lvl, stop, 0, expSrv, tag);
        }
     }

   virtual datetime ExitAt(datetime openSrv)
     {
      datetime e = DayStart(ServerToLondon(openSrv));
      return ExitServerTime(dt.NextDayAfter(e, true), 16 * 60 + 55);
     }

   virtual void Levels(datetime now)
     {
      datetime lday = DayStart(ServerToLondon(now));
      int dw = DayOfWeekOf(lday);
      if(dw < 1 || dw > 5 || Positions() > 0) return;
      int y = dt.PrevValid(dt.IndexBefore(lday));
      if(y < 0) return;
      double adr = dt.ADRBeforeKey(dt.days[y].d, true);
      double yr = dt.days[y].h - dt.days[y].l;
      datetime t1 = LondonToServer(lday), t2 = OrderExpiryFor(now);
      if(adr <= 0) return;
      if(yr < 1.5 * adr)
        { LvRow(tag, 3, "libur: range kemarin " + DoubleToString(yr / adr, 2) + " ADR (perlu >= 1.5)"); return; }
      double pos = (dt.days[y].c - dt.days[y].l) / yr;
      int side = pos >= 0.75 ? 1 : (pos <= 0.25 ? -1 : 0);
      if(side == 0)
        { LvRow(tag, 3, "libur: close kemarin di tengah range"); return; }
      double lvl = dt.days[y].c - side * 0.25 * adr;
      double stop = lvl - side * 0.5 * adr;
      LvTrade(tag + "_p", tag, side > 0, lvl, stop, 0, t1, t2, PendState(side > 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT),
              side > 0 ? "BUY LIMIT" : "SELL LIMIT", Rejected() ? why : "");
     }


   virtual void Tick(datetime now)
     {
      datetime lday = DayStart(ServerToLondon(now));
      int dw = DayOfWeekOf(lday);
      ManageExits(now);
      ManageOrders(now);
      if(CountPositions(magic) > 0 && CountOrders(magic) > 0) DeleteOrders(magic);   // sisa OCO
      if(dw >= 1 && dw <= 5 && lday != setupDay && now - lastTry >= 60)
        {
         lastTry = now;
         g_lotWhy = ""; g_dirWhy = "";
         TrySetup(now, lday);
         if(TempBlocked()) why = "tertunda: " + (g_dirWhy != "" ? g_dirWhy : g_lotWhy);   // coba lagi menit berikutnya
         else setupDay = lday;
        }
     }
  };

//+------------------------------------------------------------------+
//| Prop-firm guard (account-wide via Global Variables)              |
//+------------------------------------------------------------------+
CStrat  *g_s[];
datetime g_guardDay = 0;
double   g_dayRef = 0;
bool     g_haltDaily = false, g_haltTotal = false, g_haltGoal = false, g_haltActed = false;
string   g_guardWhy = "";

string GVP() { return "ALGO9_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_"; }

//--- total deposit (deal balance positif) di history -> saldo awal otomatis
double DepositsTotal()
  {
   if(!HistorySelect(0, TimeCurrent() + 60)) return 0;
   double s = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetInteger(d, DEAL_TYPE) != DEAL_TYPE_BALANCE) continue;
      double p = HistoryDealGetDouble(d, DEAL_PROFIT);
      if(p > 0) s += p;
     }
   return s;
  }

bool     g_lockDaily = false, g_weekendCut = false;

//--- news filter
bool     g_newsBlock = false, g_newsOk = false, g_newsWarned = false, g_newsHard = false;
datetime g_newsFetch = 0, g_newsCloseDone = 0;
datetime g_newsT[];
string   g_newsN[];
string   g_newsCur = "";
string   g_newsNextTxt = "";
string   g_newsNowTxt = "";

struct AccStats
  {
   int    trades, wins, losses;
   double net, grossProfit, grossLoss, best, worst, expectancy, avgAbs, winRate, pf;
   int    profitableDays;
   double bestDay;
   int    daysSinceTrade;
   datetime lastTrade;
   double todayClosed;
  };
AccStats g_st;

bool     g_consLock = false;
double   g_consBestDay = 0, g_consBestPct = 0, g_consTodayPct = 0, g_consRoomToday = 0, g_consRef = 0;

bool EntriesBlocked()
  {
   return !g_marketMatch || g_haltDaily || g_haltTotal || g_haltGoal || g_lockDaily || g_weekendCut || g_newsHard || g_newsBlock || g_consLock;
  }

string BlockReason()
  {
   if(!g_marketMatch) return "simbol tidak dikenali";
   if(g_haltTotal) return "guard Max Loss aktif";
   if(g_haltDaily) return "guard Max Daily Loss aktif";
   if(g_haltGoal) return "profit goal tercapai";
   if(g_lockDaily) return "daily profit lock";
   if(g_weekendCut) return "weekend";
   if(g_newsHard) return "news +-" + IntegerToString(NewsHardMin) + "m (aturan firm)";
   if(g_newsBlock) return "news window";
   if(g_consLock) return "consistency guard (best day)";
   if(g_progLockHit) return "progress lock";
   return "";
  }

// Consistency: best day (closed P/L per hari) <= ConsistencyMaxPct dari total profit.
void ConsistencyUpdate(datetime now)
  {
   if(!ConsistencyGuard || g_phase != Phase_Funded) { g_consLock = false; g_consBestPct = 0; g_consTodayPct = 0; g_consRoomToday = 1e9; return; }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double today = g_st.todayClosed + (eq - bal);
   double total = g_st.net + (eq - bal);
   g_consBestDay = MathMax(g_st.bestDay, today);
   // best day harus <= X% dari total profit SAAT LOLOS/PAYOUT; total saat itu >= goal -> pakai max(goal, total)
   double goalRef = (g_phase == Phase_Funded) ? g_initBal * ProfitGoalPct / 100.0 : ProfitGoalMoneyCalc();   // funded: pakai skala target challenge
   double ref = MathMax(goalRef, total);
   g_consRef = ref;
   g_consBestPct = ref > 0 ? 100.0 * MathMax(g_consBestDay, 0) / ref : 0;
   g_consTodayPct = ref > 0 ? 100.0 * MathMax(today, 0) / ref : 0;
   double dayCap = ConsistencyMaxPct / 100.0 * ConsistencySafety * ref;
   g_consRoomToday = dayCap - today;
   bool lock = (ref > 0 && today > 0 && today >= dayCap);
   if(lock && !g_consLock)
      Notify("Consistency guard: profit hari ini " + DoubleToString(g_consTodayPct, 0) + "% dari total, entry baru stop sampai besok");
   g_consLock = lock;
  }

string NewsCurrencies()
  {
   string c = "USD";
   if(g_market == MKT_USDJPY) c += ",JPY";
   if(NewsExtraCurrencies != "") c += "," + NewsExtraCurrencies;
   StringToUpper(c);
   return c;
  }

void NewsFetch(datetime now)
  {
   if((!NewsFilter && NewsHardMin <= 0) || MQLInfoInteger(MQL_TESTER))
      return;
   if(now - g_newsFetch < 600)
      return;
   g_newsFetch = now;
   g_newsCur = NewsCurrencies();
   MqlCalendarValue v[];
   ResetLastError();
   int n = CalendarValueHistory(v, now - 86400, now + 3 * 86400);
   if(n < 0 || (n == 0 && GetLastError() != 0))
     {
      if(!g_newsWarned) { Print("9algo: kalender ekonomi tidak tersedia (err ", GetLastError(), "), filter news nonaktif"); g_newsWarned = true; }
      g_newsOk = false;
      return;
     }
   g_newsOk = true;
   ArrayResize(g_newsT, 0);
   ArrayResize(g_newsN, 0);
   string cur[];
   StringSplit(g_newsCur, ',', cur);
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(v[i].event_id, ev)) continue;
      if(ev.importance == CALENDAR_IMPORTANCE_NONE) continue;
      if(NewsImportance == News_HighOnly && ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      if(NewsImportance == News_MediumHigh && ev.importance == CALENDAR_IMPORTANCE_LOW) continue;
      if(ev.type == CALENDAR_TYPE_HOLIDAY) continue;
      MqlCalendarCountry ct;
      if(!CalendarCountryById(ev.country_id, ct)) continue;
      bool match = false;
      for(int k = 0; k < ArraySize(cur); k++)
         if(cur[k] == ct.currency) { match = true; break; }
      if(!match) continue;
      int m = ArraySize(g_newsT);
      ArrayResize(g_newsT, m + 1);
      ArrayResize(g_newsN, m + 1);
      g_newsT[m] = v[i].time;
      g_newsN[m] = ct.currency + " " + ev.name;
     }
  }

void NewsUpdate(datetime now)
  {
   NewsFetch(now);
   g_newsHard = false;
   for(int i = 0; i < ArraySize(g_newsT); i++)
      if(NewsHardMin > 0 && MathAbs((double)(now - g_newsT[i])) <= NewsHardMin * 60) g_newsHard = true;
   if(!NewsFilter) { g_newsBlock = false; return; }
   bool blk = false;
   g_newsNowTxt = "";
   g_newsNextTxt = "";
   datetime best = 0;
   for(int i = 0; i < ArraySize(g_newsT); i++)
     {
      datetime t = g_newsT[i];
      if(now >= t - NewsBeforeMin * 60 && now <= t + NewsAfterMin * 60)
        {
         blk = true;
         if(g_newsNowTxt == "") g_newsNowTxt = g_newsN[i] + " " + TimeToString(ServerToNY(t), TIME_MINUTES) + " NY";
        }
      if(t > now && (best == 0 || t < best)) { best = t; g_newsNextTxt = g_newsN[i] + " " + TimeToString(ServerToNY(t), TIME_MINUTES) + " NY (" + IntegerToString((int)((t - now) / 60)) + "m)"; }
     }
   if(blk && !g_newsBlock)
     {
      Notify("News window: " + g_newsNowTxt + " -> entry baru diblok");
      if(NewsClosePositions)
         for(int i = 0; i < ArraySize(g_s); i++)
            if(g_s[i].on) { g_s[i].DeleteAllOrders(); g_s[i].CloseAllPositions(); }
     }
   g_newsBlock = blk;
  }

// leader = chart 9algo dengan ChartID terkecil di terminal ini (cek ulang tiap 60 detik)
bool IsLeader()
  {
   static datetime chk = 0;
   static bool lead = true;
   if(TimeLocal() - chk < 60) return lead;
   chk = TimeLocal();
   long me = ChartID(), id = ChartFirst();
   lead = true;
   while(id >= 0)
     {
      if(id < me && StringFind(ChartGetString(id, CHART_EXPERT_NAME), "9algo") >= 0) { lead = false; break; }
      id = ChartNext(id);
     }
   return lead;
  }

// notifikasi per chart (entry/exit strategi di chart ini). Prefix login -> jelas akun mana saat multi-akun
void NotifyTrade(string msg)
  {
   Print("9algo: ", msg);
   if(PushAlerts && !MQLInfoInteger(MQL_TESTER))
      SendNotification("9algo #" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " " + _Symbol + ": " + msg);
  }

// notifikasi level akun (guard, fase, news, ...) hanya dari leader -> tidak dobel per chart
void Notify(string msg)
  {
   if(!IsLeader()) { Print("9algo: ", msg); return; }
   NotifyTrade(msg);
  }

double DailyLimitMoney()
  {
   if(PropMaxDailyLossMoney > 0)
      return PropMaxDailyLossMoney;
   double base = (DailyLossBase == DailyBase_StartOfDay) ? g_dayRef : g_initBal;
   return base * PropMaxDailyLossPct / 100.0;
  }

double TotalLimitMoney()
  {
   if(PropMaxLossMoney > 0)
      return PropMaxLossMoney;
   return g_initBal * PropMaxLossPct / 100.0;
  }

double ProfitGoalMoneyCalc()
  {
   if(g_phase == Phase_Funded) return 0;
   if(g_phase == Phase_Verification) return g_initBal * VerificationGoalPct / 100.0;
   if(ProfitGoalMoney > 0)
      return ProfitGoalMoney;
   return g_initBal * ProfitGoalPct / 100.0;
  }

datetime g_statsFrom = 0;

datetime StatsFrom()
  {
   if(ChallengeStartDate > 0)
      return ChallengeStartDate;
   if(g_statsFrom > 0)
      return g_statsFrom;
   string sn = GVP() + "START";
   if(GlobalVariableCheck(sn))
      g_statsFrom = (datetime)GlobalVariableGet(sn);
   else
     {
      g_statsFrom = TimeCurrent();
      GlobalVariableSet(sn, (double)g_statsFrom);
     }
   return g_statsFrom;
  }

double   g_hwm = 0;   // all-time high-water-mark equity (persisten via GV)

//--- level equity di mana prop firm menganggap Max Loss breached
double MaxLossFloor()
  {
   if(MaxLossMode == MaxLoss_StaticFromInitial)
      return g_initBal - TotalLimitMoney();
   double f = g_hwm - TotalLimitMoney();
   if(TrailingFloorCapAtInitial && f > g_initBal)
      f = g_initBal;
   return f;
  }

//--- level equity di mana EA berhenti (GuardFraction dari limit)
double MaxLossGuardFloor()
  {
   return MaxLossFloor() + TotalLimitMoney() * (1.0 - GuardFraction);
  }

//+------------------------------------------------------------------+
//| Statistik akun (dari history, semua deal akun = seperti dashboard)|
//+------------------------------------------------------------------+

void ComputeStats(datetime now)
  {
   ZeroMemory(g_st);
   g_st.daysSinceTrade = -1;
   datetime from = StatsFrom();
   if(!HistorySelect(from, now + 60))
      return;
   datetime dayKeys[];
   double   dayPnl[];
   int nd = 0;
   datetime todayKey = DayKeyOf(now);
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY) continue;
      long type = HistoryDealGetInteger(d, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
      double p = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
      datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      g_st.trades++;
      g_st.net += p;
      g_st.avgAbs += MathAbs(p);
      if(p > 0) { g_st.wins++; g_st.grossProfit += p; if(p > g_st.best) g_st.best = p; }
      else      { g_st.losses++; g_st.grossLoss += p; if(p < g_st.worst) g_st.worst = p; }
      if(t > g_st.lastTrade) g_st.lastTrade = t;
      datetime dk = DayKeyOf(t);
      int di = -1;
      for(int q = 0; q < nd; q++) if(dayKeys[q] == dk) { di = q; break; }
      if(di < 0)
        {
         nd++;
         ArrayResize(dayKeys, nd); ArrayResize(dayPnl, nd);
         dayKeys[nd - 1] = dk; dayPnl[nd - 1] = 0; di = nd - 1;
        }
      dayPnl[di] += p;
      if(dk == todayKey) g_st.todayClosed += p;
     }
   double minDay = g_initBal * ProfitableDayMinPct / 100.0;
   for(int q = 0; q < nd; q++)
     {
      if(dayPnl[q] > 0 && dayPnl[q] >= minDay)
         g_st.profitableDays++;
      if(dayKeys[q] != todayKey && dayPnl[q] > g_st.bestDay)
         g_st.bestDay = dayPnl[q];
     }
   if(g_st.trades > 0)
     {
      g_st.expectancy = g_st.net / g_st.trades;
      g_st.avgAbs /= g_st.trades;
      g_st.winRate = 100.0 * g_st.wins / g_st.trades;
     }
   g_st.pf = (g_st.grossLoss < 0) ? g_st.grossProfit / -g_st.grossLoss : (g_st.grossProfit > 0 ? 999 : 0);
   if(g_st.lastTrade > 0)
      g_st.daysSinceTrade = (int)((now - g_st.lastTrade) / 86400);
  }

void GuardHaltActions(string why)
  {
   if(g_haltActed) return;
   g_haltActed = true;
   g_guardWhy = why;
   Notify("GUARD HALT - " + why + (CloseAllOnGuard ? " (posisi & order ditutup)" : " (pending dihapus)"));
   for(int i = 0; i < ArraySize(g_s); i++)
     {
      if(!g_s[i].on) continue;
      g_s[i].DeleteAllOrders();
      if(CloseAllOnGuard) g_s[i].CloseAllPositions();
     }
  }

void WriteHedgeFile();
void WriteRegistry();
datetime g_statsAt = 0;
void PhaseSync();
bool EpochStable();
void GuardUpdate(datetime now)
  {
   PhaseSync();
   if(now - g_statsAt >= 60) { g_statsAt = now; ComputeStats(now); }
   // baca ulang flag halt (bisa di-reset dari chart lain lewat tombol RESET HALT)
   bool ht = GlobalVariableCheck(GVP() + "HALTTOTAL");
   if(!ht && g_haltTotal) { g_haltTotal = false; g_haltActed = g_haltDaily; g_guardWhy = g_haltDaily ? "Max Daily Loss" : ""; }
   if(ht) g_haltTotal = true;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   // high-water-mark equity (persisten)
   string hn = GVP() + "HWM";
   if(g_hwm <= 0)
      g_hwm = GlobalVariableCheck(hn) ? GlobalVariableGet(hn) : MathMax(g_initBal, eq);
   if(MathMax(eq, bal) > g_hwm)
     {
      g_hwm = MathMax(eq, bal);
      GlobalVariableSet(hn, g_hwm);
     }
   datetime dk = DayKeyOf(now);
   if(dk != g_guardDay)
     {
      g_guardDay = dk;
      string nm = GVP() + "DAY_" + IntegerToString((long)dk);
      if(GlobalVariableCheck(nm))
         g_dayRef = GlobalVariableGet(nm);
      else
        {
         // saldo awal hari = balance sekarang - P/L closed sejak awal hari (aman walau EA baru dipasang siang hari)
         double closedToday = 0;
         datetime d0 = DayKeyStartServer(now);
         if(HistorySelect(d0, now + 60))
            for(int i = 0; i < HistoryDealsTotal(); i++)
              {
               ulong dl = HistoryDealGetTicket(i);
               if(dl == 0) continue;
               long ty = HistoryDealGetInteger(dl, DEAL_TYPE);
               if(ty == DEAL_TYPE_BALANCE || ty == DEAL_TYPE_CREDIT) { closedToday = 0; continue; }   // reset/payout/deposit: mulai hitung dari sini
               if(ty != DEAL_TYPE_BUY && ty != DEAL_TYPE_SELL) continue;
               closedToday += HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP) + HistoryDealGetDouble(dl, DEAL_COMMISSION);
              }
         g_dayRef = bal - closedToday;
         // EA hidup saat pergantian hari: firm memakai yang lebih tinggi dari balance/equity penutupan -> ikut (lebih ketat)
         if(now - d0 < 600 && closedToday == 0) g_dayRef = MathMax(g_dayRef, eq);
         GlobalVariableSet(nm, g_dayRef);
        }
      string hd = GVP() + "HALTDAY_" + IntegerToString((long)dk);
      g_haltDaily = GlobalVariableCheck(hd);
      g_haltActed = g_haltDaily;
      // bersihkan variabel hari-hari sebelumnya
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
        {
         string n = GlobalVariableName(i);
         if(StringFind(n, GVP()) != 0) continue;
         if(n == nm || n == hd || n == hn || n == GVP() + "START" || n == GVP() + "INITBAL" || n == GVP() + "PROGFLOOR" || n == GVP() + "ROLE" || StringFind(n, GVP() + "PHASE_") == 0 || n == GVP() + "PASSED" || n == GVP() + "RESETDONE" || n == GVP() + "DEPLOYLOCK" || n == GVP() + "CAPLOCK" || StringFind(n, GVP() + "HALTTOTAL") == 0 || StringFind(n, GVP() + "PAUSE_") == 0) continue;
         GlobalVariableDel(n);
        }
     }
   bool hd2 = GlobalVariableCheck(GVP() + "HALTDAY_" + IntegerToString((long)dk));
   if(!hd2 && g_haltDaily) { g_haltDaily = false; g_haltActed = g_haltTotal; }
   if(hd2 && !g_haltDaily) { g_haltDaily = true; g_haltActed = false; g_guardWhy = "Max Daily Loss (dari chart lain)"; GuardHaltActions(g_guardWhy); }
   if(DailyLimitMoney() > 0 && !g_haltDaily && g_dayRef - eq >= DailyLimitMoney() * GuardFraction && EpochStable())
     {
      g_haltDaily = true;
      GlobalVariableSet(GVP() + "HALTDAY_" + IntegerToString((long)dk), 1);
      GuardHaltActions("Max Daily Loss " + DoubleToString(GuardFraction * 100, 0) + "% tercapai");
     }
   if(TotalLimitMoney() > 0 && !g_haltTotal && eq <= MaxLossGuardFloor() && EpochStable())
     {
      g_haltTotal = true;
      GlobalVariableSet(GVP() + "HALTTOTAL", 1);
      GuardHaltActions("Max Loss " + DoubleToString(GuardFraction * 100, 0) + "% tercapai (flag persisten)");
     }
   if(StopEntriesAtProfitPct > 0 && !g_haltGoal)
      g_haltGoal = (bal - g_initBal) >= g_initBal * StopEntriesAtProfitPct / 100.0;
   if(DailyProfitLockPct > 0)
     {
      bool was = g_lockDaily;
      g_lockDaily = (eq - g_dayRef) >= g_dayRef * DailyProfitLockPct / 100.0;
      if(g_lockDaily && !was) Notify("Daily profit lock " + DoubleToString(DailyProfitLockPct, 2) + "% tercapai, entry baru stop sampai reset harian");
     }
   else g_lockDaily = false;
   NewsUpdate(now);
   ConsistencyUpdate(now);
   ChallengeUpdate(now);
   RegimeUpdate(now);
   if(ExportState) ExportStateJson(now);
   static datetime lastHedge = 0;
   if(now - lastHedge >= 10 || now < lastHedge) { lastHedge = now; WriteHedgeFile(); }
   static datetime lastReg = 0;
   if(now - lastReg >= 600 || now < lastReg) { lastReg = now; WriteRegistry(); }
   if(CloseBeforeWeekend)
     {
      datetime ny = ServerToNY(now);
      int nyMin = (int)((ny % 86400) / 60);
      bool cut = DayOfWeekOf(ny) == 5 && nyMin >= WeekendCloseNYMin;
      if(cut && !g_weekendCut)
        {
         Notify("Weekend close: semua posisi/order ditutup");
         for(int i = 0; i < ArraySize(g_s); i++)
            if(g_s[i].on) { g_s[i].DeleteAllOrders(); g_s[i].CloseAllPositions(); }
        }
      g_weekendCut = cut || (DayOfWeekOf(ny) == 6);
     }
   else g_weekendCut = false;
   if(g_haltTotal && !g_haltActed)
      GuardHaltActions("Max Loss flag aktif");
  }

//+------------------------------------------------------------------+
//| Challenge Mode: risk by phase, cushion, target-days, progress    |
//| lock, auto-pause, Monte Carlo P(lolos)                           |
//+------------------------------------------------------------------+
void StrategyStatsUpdate()
  {
   if(!HistorySelect(StatsFrom(), TimeCurrent() + 60)) return;
   for(int i = 0; i < ArraySize(g_s); i++) { g_s[i].stTrades = 0; g_s[i].stNet = 0; }
   for(int k = 0; k < HistoryDealsTotal(); k++)
     {
      ulong d = HistoryDealGetTicket(k);
      if(d == 0) continue;
      long e = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_INOUT && e != DEAL_ENTRY_OUT_BY) continue;
      long mg = HistoryDealGetInteger(d, DEAL_MAGIC);
      for(int i = 0; i < ArraySize(g_s); i++)
         if(g_s[i].Mine(mg))
           {
            g_s[i].stTrades++;
            g_s[i].stNet += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
           }
     }
   for(int i = 0; i < ArraySize(g_s); i++)
     {
      bool ap = AutoPauseNegative && !IsEval() && g_s[i].stTrades >= AutoPauseMinTrades && g_s[i].stNet < 0;   // challenge: jangan matikan strategi karena sampel kecil
      if(ap && !g_s[i].autoPaused) NotifyTrade(g_s[i].tag + " auto-pause: " + IntegerToString(g_s[i].stTrades) + " trade, net " + DoubleToString(g_s[i].stNet, 0));
      g_s[i].autoPaused = ap;
     }
  }

double GaussRand()
  {
   double u1 = (MathRand() + 1.0) / 32769.0, u2 = (MathRand() + 1.0) / 32769.0;
   return MathSqrt(-2.0 * MathLog(u1)) * MathCos(2 * M_PI * u2);
  }

// Monte Carlo: P(capai goal) vs P(bust) dalam `days` hari dengan return harian ~N(mu*mult, sd*mult)
void MonteCarlo(double mu, double sd, double mult, int days, double startFrac, double goalFrac, double &pPass, double &pBust)
  {
   int N = 400, pass = 0, bust = 0;
   double dailyStop = -DailyLimitMoney() * GuardFraction / g_initBal;
   double totalStop = (MaxLossGuardFloor() - g_initBal) / g_initBal;
   for(int n = 0; n < N; n++)
     {
      double cum = startFrac;
      bool done = false;
      for(int d = 0; d < days && !done; d++)
        {
         double r = mu * mult + sd * mult * GaussRand();
         if(r < dailyStop) r = dailyStop;
         cum += r;
         if(cum >= goalFrac) { pass++; done = true; }
         else if(cum <= totalStop) { bust++; done = true; }
        }
     }
   pPass = (double)pass / N;
   pBust = (double)bust / N;
  }

void ChallengeUpdate(datetime now)
  {
   static datetime lastMC = 0;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double goal = ProfitGoalMoneyCalc();
   double prog = bal - g_initBal;
   double progFrac = goal > 0 ? prog / goal : 0;
   g_challengeDay = (int)((now - StatsFrom()) / 86400) + 1;

   // spread EMA
   double sp = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(sp > 0 && MarketOpenNow()) g_spreadAvg = (g_spreadAvg <= 0) ? sp : g_spreadAvg + (sp - g_spreadAvg) / 720.0;

   // --- estimasi return harian (dipakai target-days & Monte Carlo)
   bool realized = (g_st.trades >= 20 && g_challengeDay >= 5);
   if(realized)
     {
      g_dailyRet = (g_st.net / g_initBal) / g_challengeDay;          // sudah pada risk yang dipakai
      g_dailySd = MathMax(0.001, (g_st.avgAbs / g_initBal) * MathSqrt((double)g_st.trades / g_challengeDay));
     }
   else { g_dailyRet = 0.0005; g_dailySd = 0.0025; }               // asumsi pada risk preset x1 (dari simulasi)

   // --- pengali risk
   double mult = 1.0;
   if(g_phase == Phase_Funded)
      mult = FundedRiskScale;
   else if(ChallengeMode && ChallengeStyle == Style_Fast)
     {
      // risk tetap: rata-rata FastRiskPct per trade (bobot preset tiap strategi), separuh setelah 90% goal
      double meanPreset = (NMG_Risk + S009_Risk + S015_Risk + S017_Risk + S018G_Risk + S018S_Risk + B8_Risk + S009U_Risk + NMN_Risk) / 9.0;
      mult = (meanPreset > 0 ? FastRiskPct / (meanPreset * RiskScale) : 1.0) * (progFrac >= 0.9 ? 0.5 : 1.0);
      g_autoScale = mult;
     }
   else if(ChallengeMode)
     {
      mult = (progFrac < 0.5) ? PhaseRiskA : (progFrac < 0.9 ? PhaseRiskB : PhaseRiskC);
      double cushion = MathMax(0, prog) / g_initBal * 100.0;    // % saldo awal
      mult += cushion * CushionK / 100.0;
      // target hari: butuh return harian = sisa / hari tersisa
      g_autoScale = 1.0;
      if(g_targetDays > 0 && g_dailyRet > 0)
        {
         int daysLeft = MathMax(1, g_targetDays - g_challengeDay + 1);
         double need = (goal - prog) / g_initBal / daysLeft;    // return harian yang dibutuhkan (fraksi)
         g_autoScale = need / g_dailyRet;
         g_autoScale = MathMax(0.5, MathMin(g_autoScale, g_capScale));
         if(progFrac < 0.9) mult = MathMax(mult, g_autoScale);
        }
      mult = MathMin(mult, g_capScale);
     }
   g_effMult = mult;
   bool fast = (IsEval() && ChallengeMode && ChallengeStyle == Style_Fast);
   g_fast = fast;
   g_openCapPct = fast ? FastOpenRiskPct : MaxTotalOpenRiskPct;
   g_dirCapPct  = fast ? FastDirCapPct : DirectionalCapPct;

   // --- goal tercapai: kunci. Tutup semua posisi (jangan beri pasar kesempatan ambil balik), stop entry.
   double goalBuf = goal + g_initBal * 0.002;   // +0.2% cadangan untuk slippage/komisi saat semua posisi ditutup
   if(IsEval() && ChallengeMode && goal > 0 && (eq - g_initBal) >= goal && g_st.profitableDays < MinProfitableDays)
      g_effMult = fast ? g_effMult : g_effMult * 0.5;   // target sudah, hari profit belum cukup: Fast sudah separuh sejak 90% goal, tetap cukup untuk hari profit >= 0.5%
   // halt target dipasang tapi setelah posisi ditutup saldo ternyata masih di bawah target -> lanjut trading
   if(g_haltGoal && StopEntriesAtProfitPct <= 0 && IsEval() && goal > 0 && (bal - g_initBal) < goal && (bal - g_initBal) >= 0.5 * goal && OurTicketsAll() == 0)   // bukan reset saldo fase baru
     {
      g_haltGoal = false;
      GlobalVariableDel(GVP() + "PASSED");
      Notify("Saldo setelah tutup posisi masih di bawah target -> lanjut trading");
     }
   if(IsEval() && ChallengeMode && goal > 0 && (eq - g_initBal) >= goalBuf && g_st.profitableDays >= MinProfitableDays && !g_haltGoal)
     {
      g_haltGoal = true;
      GlobalVariableSet(GVP() + "PASSED", g_phase);
      Notify("TARGET " + PhaseName(g_phase) + " TERCAPAI: +" + DoubleToString(eq - g_initBal, 0) + ". Posisi ditutup, entry stop. Fase berikutnya diaktifkan otomatis saat firm reset saldo / akun baru dipasang.");
      for(int i = 0; i < ArraySize(g_s); i++)
         if(g_s[i].on) { g_s[i].DeleteAllOrders(); g_s[i].CloseAllPositions(); }
     }

   // --- progress lock
   if(ProgressLock && IsEval() && !(ChallengeMode && ChallengeStyle == Style_Fast))
     {
      string gv = GVP() + "PROGFLOOR";
      if(g_progFloor <= 0 && GlobalVariableCheck(gv)) g_progFloor = GlobalVariableGet(gv);
      double step = g_initBal * ProgressLockStepPct / 100.0;
      if(step > 0 && prog >= step)
        {
         double locked = MathFloor(prog / step) * step;
         double fl = g_initBal + 0.5 * locked;
         if(fl > g_progFloor) { g_progFloor = fl; GlobalVariableSet(gv, fl); Notify("Progress lock: floor naik ke " + DoubleToString(fl, 0)); }
        }
      datetime dk = DayKeyOf(now);
      if(g_progLockDay != dk) { g_progLockDay = dk; g_progLockHit = false; }
      if(g_progFloor > 0 && eq <= g_progFloor && !g_progLockHit)
        {
         g_progLockHit = true;
         Notify("Progress lock kena: equity " + DoubleToString(eq, 0) + " <= floor " + DoubleToString(g_progFloor, 0) + " -> posisi ditutup, entry stop s/d besok");
         for(int i = 0; i < ArraySize(g_s); i++)
            if(g_s[i].on) { g_s[i].DeleteAllOrders(); g_s[i].CloseAllPositions(); }
        }
     }
   else g_progLockHit = false;

   // --- auto-pause + Monte Carlo tiap 60 detik
   if(now - lastMC >= 60)
     {
      lastMC = now;
      StrategyStatsUpdate();
      if(IsEval() && goal > 0)
        {
         int days = g_targetDays > 0 ? MathMax(1, g_targetDays - g_challengeDay + 1) : 60;
         MonteCarlo(g_dailyRet, g_dailySd, realized ? 1.0 : g_effMult, days, prog / g_initBal, goal / g_initBal, g_pPass, g_pBust);
        }
     }
  }

//+------------------------------------------------------------------+
//| Regime filter ONNX                                               |
//|  Model: input float[1,8], output float[1,2] (p_choppy, p_trend). |
//|  Fitur: lihat tools/train_regime.py.                             |
//+------------------------------------------------------------------+
long     g_onnx = INVALID_HANDLE;
bool     g_onnxTried = false;
datetime g_regimeDay = 0;
double   g_pTrend = 0.5;

void RegimeLoad()
  {
   if(g_onnxTried) return;
   g_onnxTried = true;
   string f = "9algo\\regime.onnx";
   g_onnx = OnnxCreate(f, ONNX_COMMON_FOLDER);
   if(g_onnx == INVALID_HANDLE) g_onnx = OnnxCreate(f, 0);
   if(g_onnx == INVALID_HANDLE) { g_regimeTxt = "model tidak ditemukan (Common/Files/9algo/regime.onnx)"; return; }
   const long inShape[] = {1, 8};
   const long outShape[] = {1, 2};
   if(!OnnxSetInputShape(g_onnx, 0, inShape) || !OnnxSetOutputShape(g_onnx, 0, outShape))
     { g_regimeTxt = "shape model tidak cocok"; OnnxRelease(g_onnx); g_onnx = INVALID_HANDLE; return; }
   g_regimeTxt = "model siap";
  }

bool RegimeFeatures(float &x[])
  {
   MqlRates d[];
   ArraySetAsSeries(d, true);
   if(CopyRates(_Symbol, PERIOD_D1, 1, 21, d) < 21) return false;
   double adr = 0;
   for(int i = 0; i < 20; i++) adr += d[i].high - d[i].low;
   adr /= 20;
   if(adr <= 0) return false;
   double r1 = d[0].high - d[0].low, r2 = d[1].high - d[1].low, r3 = d[2].high - d[2].low;
   double body1 = MathAbs(d[0].close - d[0].open);
   double gap = MathAbs(d[0].open - d[1].close);
   double mom5 = d[0].close - d[5].close;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   ArrayResize(x, 8);
   x[0] = (float)(r1 / adr);
   x[1] = (float)(r2 / adr);
   x[2] = (float)(r3 / adr);
   x[3] = (float)(r1 > 0 ? body1 / r1 : 0);
   x[4] = (float)(gap / adr);
   x[5] = (float)(mom5 / adr);
   x[6] = (float)(r1 > 0 ? (d[0].close - d[0].low) / r1 : 0.5);
   x[7] = (float)t.day_of_week;
   return true;
  }

void RegimeUpdate(datetime now)
  {
   if(!RegimeFilter) return;
   RegimeLoad();
   if(g_onnx == INVALID_HANDLE) return;
   datetime dk = DayStart(ServerToLondon(now));
   if(dk == g_regimeDay) return;
   float x[];
   float out[];
   ArrayResize(out, 2);
   if(!RegimeFeatures(x)) { g_regimeTxt = "data D1 belum cukup"; return; }
   if(!OnnxRun(g_onnx, ONNX_DEFAULT, x, out)) { g_regimeTxt = "OnnxRun gagal " + IntegerToString(GetLastError()); return; }
   g_regimeDay = dk;
   g_pTrend = out[1];
   g_regimeTxt = (g_pTrend >= 0.5 ? "TRENDING " : "CHOPPY ") + DoubleToString(100 * g_pTrend, 0) + "% trend";
  }

bool RegimeAllows(int kind)
  {
   if(!RegimeFilter || g_onnx == INVALID_HANDLE || g_regimeDay == 0) return true;
   if(kind == 0) return g_pTrend >= RegimeTrendMin;
   return (1.0 - g_pTrend) >= RegimeChopMin;
  }

//+------------------------------------------------------------------+
//| Deteksi fase akun otomatis                                       |
//|  1) input manual  2) pilihan dari tombol panel  3) progres       |
//|  tersimpan (lolos + reset saldo)  4) kata kunci di komentar      |
//|  deposit / nama akun / server  5) trade mode  6) default         |
//+------------------------------------------------------------------+
int KwScore(string t, string list)
  {
   string k[];
   int n = StringSplit(list, ',', k), sc = 0;
   for(int i = 0; i < n; i++)
      if(StringLen(k[i]) > 0 && StringFind(t, k[i]) >= 0) sc++;
   return sc;
  }

string BalanceComments()
  {
   string t = "";
   if(!HistorySelect(0, TimeCurrent() + 60)) return t;
   for(int i = 0; i < HistoryDealsTotal() && i < 400; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      long ty = HistoryDealGetInteger(d, DEAL_TYPE);
      if(ty == DEAL_TYPE_BALANCE || ty == DEAL_TYPE_CREDIT || ty == DEAL_TYPE_BONUS)
         t += " " + HistoryDealGetString(d, DEAL_COMMENT);
     }
   StringToLower(t);
   return t;
  }

int DetectPhase(string &src)
  {
   if(AccountPhase != Phase_Auto) { src = "input"; return AccountPhase; }
   string gm = GVP() + "PHASE_MANUAL";
   if(GlobalVariableCheck(gm)) { src = "dipilih di panel"; return (int)GlobalVariableGet(gm); }
   string gp = GVP() + "PHASE_PROG";
   if(GlobalVariableCheck(gp)) { src = "lolos + reset saldo"; return (int)GlobalVariableGet(gp); }

   string dc = BalanceComments();
   string nm = AccountInfoString(ACCOUNT_NAME), sv = AccountInfoString(ACCOUNT_SERVER);
   StringToLower(nm); StringToLower(sv);
   string kF = "funded,master,payout,profit split,live account,trader account";
   string kV = "verification,phase 2,phase2,phase-2,step 2,step2,stage 2,p2 ";
   string kC = "challenge,evaluation,phase 1,phase1,phase-1,step 1,step1,stage 1,assessment,audition,trial";
   // funded HANYA dari bukti kuat (komentar deposit / nama akun). Nama server "Real/Live" dan trade mode REAL
   // tidak dipakai: banyak prop firm menaruh akun challenge di server bernama Real/Live.
   int f = 3 * KwScore(dc, kF) + 2 * KwScore(nm, kF);
   int v = 3 * KwScore(dc, kV) + 2 * KwScore(nm, kV) + KwScore(sv, kV);
   int c = 3 * KwScore(dc, kC) + 2 * KwScore(nm, kC) + KwScore(sv, kC);
   long tm = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(tm == ACCOUNT_TRADE_MODE_CONTEST) c += 2;
   if(f > v && f > c) { src = "terdeteksi (kata kunci/server: funded)"; return Phase_Funded; }
   if(v > c && v >= f && v > 0) { src = "terdeteksi (kata kunci: phase 2)"; return Phase_Verification; }
   if(c > 0) { src = "terdeteksi (kata kunci: challenge)"; return Phase_Challenge; }
   src = "default: dianggap CHALLENGE (akun funded? klik tombol fase)";
   return Phase_Challenge;
  }

int NextPhase(int ph)
  {
   if(ph == Phase_Challenge) return ChallengeSteps >= 2 ? Phase_Verification : Phase_Funded;
   if(ph == Phase_Verification) return Phase_Funded;
   return Phase_Funded;
  }

// dipanggil saat init & tiap deal balance: lolos + saldo di-reset firm -> naik fase di login yang sama
void PhaseProgressCheck()
  {
   string gp = GVP() + "PASSED";
   if(!GlobalVariableCheck(gp)) return;
   int passedPh = (int)GlobalVariableGet(gp);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_initBal > 0 && MathAbs(bal - g_initBal) <= g_initBal * 0.01)   // saldo kembali ~ saldo awal = firm reset untuk fase baru
     {
      int nx = NextPhase(passedPh);
      // reset state guard untuk fase baru (kecuali peran, pause, saldo awal)
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
        {
         string n = GlobalVariableName(i);
         if(StringFind(n, GVP()) != 0) continue;
         if(n == GVP() + "ROLE" || n == GVP() + "INITBAL" || StringFind(n, GVP() + "PAUSE_") == 0 || n == GVP() + "PHASE_EPOCH" || n == GVP() + "CAPLOCK") continue;
         GlobalVariableDel(n);
        }
      GlobalVariableSet(GVP() + "PHASE_PROG", nx);
      g_phase = nx; g_phaseSrc = "lolos + reset saldo";
      string ep = GVP() + "PHASE_EPOCH";
      GlobalVariableSet(ep, (GlobalVariableCheck(ep) ? GlobalVariableGet(ep) : 0) + 1);   // semua chart akun ini reset lokal via epoch
      Notify("Fase naik otomatis -> " + PhaseName(nx) + " (saldo di-reset firm ke " + DoubleToString(bal, 0) + ")");
     }
  }

// reset state lokal chart ini saat epoch fase berubah (dipanggil di awal GuardUpdate, sebelum guard dievaluasi)
void PhaseSync()
  {
   string ep = GVP() + "PHASE_EPOCH";
   int e = GlobalVariableCheck(ep) ? (int)GlobalVariableGet(ep) : 0;
   if(g_phaseEpoch < 0) { g_phaseEpoch = e; }
   else if(e != g_phaseEpoch)
     {
      g_phaseEpoch = e;
      g_phase = DetectPhase(g_phaseSrc);
      double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_hwm = MathMax(g_initBal, MathMax(eq, bal));
      GlobalVariableSet(GVP() + "HWM", g_hwm);          // tulis ulang supaya HWM lama dari chart lain tertimpa
      g_haltGoal = false; g_haltTotal = false; g_haltDaily = false; g_haltActed = false;
      g_progFloor = 0; g_statsFrom = 0; g_guardDay = 0; g_progLockHit = false; g_statsAt = 0;
      GlobalVariableDel(GVP() + "HALTTOTAL");
     }
   // pilihan fase manual dari panel (bisa diklik di chart lain)
   string gm = GVP() + "PHASE_MANUAL";
   int mv = GlobalVariableCheck(gm) ? (int)GlobalVariableGet(gm) : -9;
   if(mv != g_manualSeen)
     {
      if(g_manualSeen != -99) g_phase = DetectPhase(g_phaseSrc);
      g_manualSeen = mv;
     }
  }

bool EpochStable()
  {
   string ep = GVP() + "PHASE_EPOCH";
   int e = GlobalVariableCheck(ep) ? (int)GlobalVariableGet(ep) : 0;
   return e == g_phaseEpoch;
  }

void PhaseInit()
  {
   g_phase = DetectPhase(g_phaseSrc);
   PhaseProgressCheck();
   string last = GVP() + "PHASE_LAST";
   if(!GlobalVariableCheck(last) || (int)GlobalVariableGet(last) != g_phase)
     {
      GlobalVariableSet(last, g_phase);
      Notify("Fase akun: " + PhaseName(g_phase) + " (" + g_phaseSrc + "). Kalau salah, klik tombol fase di panel.");
     }
  }

//+------------------------------------------------------------------+
//| ZERO CONFIG: saldo awal otomatis, firm tag otomatis, peran akun  |
//| otomatis (registry bersama di Common/Files/9algo/reg_*.txt)      |
//+------------------------------------------------------------------+
string Slug(string v)
  {
   string o = "";
   StringToLower(v);
   for(int i = 0; i < StringLen(v); i++)
     {
      ushort c = StringGetCharacter(v, i);
      if((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) o += ShortToString(c);
     }
   return StringLen(o) > 24 ? StringSubstr(o, 0, 24) : o;
  }

// saldo awal: 1) input, 2) GV tersimpan, 3) total deposit, 4) snap ke ukuran akun prop standar
double AutoInitialBalance()
  {
   if(InitialBalance > 0) return InitialBalance;
   string gv = GVP() + "INITBAL";
   if(GlobalVariableCheck(gv) && GlobalVariableGet(gv) > 0) return GlobalVariableGet(gv);
   double dep = DepositsTotal();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(dep > 0 && bal > 0 && MathAbs(dep - bal) / dep < 0.25) return dep;
   double sizes[] = {1000, 2000, 2500, 5000, 6000, 10000, 15000, 20000, 25000, 40000, 50000, 60000, 80000, 100000, 150000, 200000, 250000, 300000, 400000, 500000, 1000000};
   double best = 0, bestD = 1e18;
   for(int i = 0; i < ArraySize(sizes); i++)
     {
      double r = bal / sizes[i];
      if(r < 0.85 || r > 1.15) continue;      // toleransi +-15% (profit/rugi berjalan)
      double d = MathAbs(bal - sizes[i]);
      if(d < bestD) { bestD = d; best = sizes[i]; }
     }
   if(best > 0) return best;
   return bal;
  }

string RoleName(int r) { return r == Role_Sprint ? "Sprint" : r == Role_Counter ? "Counter" : r == Role_Index ? "Index" : r == Role_Steady ? "Steady" : "-"; }

bool RoleAllows(int role, string key)
  {
   if(role == Role_Steady || role < 0) return true;
   if(role == Role_Sprint)  return key == "NMG" || key == "S009" || key == "S015" || key == "S017";
   if(role == Role_Counter) return key == "S018G" || key == "S018S" || key == "B8" || key == "S009U" || key == "NMN";
   if(role == Role_Index)   return key == "NMN" || key == "S015" || key == "S017";
   return true;
  }

void RoleParams(int role, int &days, double &cap)
  {
   if(role == Role_Sprint)       { days = 14; cap = 3.0; }
   else if(role == Role_Counter) { days = 30; cap = 2.5; }
   else if(role == Role_Index)   { days = 30; cap = 2.5; }
   else if(role == Role_Steady)  { days = 45; cap = 1.5; }
   else { days = TargetDays; cap = MaxRiskScaleAuto; }
  }

void WriteRegistry()
  {
   string fn = "9algo\\reg_" + g_firm + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt";
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, IntegerToString(g_role) + "\n" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\n" + DoubleToString(g_initBal, 0) + "\n");
   FileClose(h);
  }

// hitung peran akun lain (tag sama) -> pilih peran yang paling sedikit, urutan Sprint, Counter, Steady, Index
int AssignRole()
  {
   int cnt[4] = {0, 0, 0, 0};
   g_firmAccounts = 0;
   string me = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string fname;
   long hf = FileFindFirst("9algo\\reg_" + g_firm + "_*.txt", fname, FILE_COMMON);
   if(hf != INVALID_HANDLE)
     {
      do
        {
         if(StringFind(fname, "_" + me + ".txt") >= 0) continue;
         int h = FileOpen("9algo\\" + fname, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
         if(h == INVALID_HANDLE) continue;
         int r = (int)StringToInteger(FileReadString(h));
         datetime ts = StringToTime(FileReadString(h));
         FileClose(h);
         if(ts > 0 && TimeCurrent() - ts > 3 * 86400) continue;      // akun lama/mati tidak dihitung
         if(r >= 0 && r < 4) { cnt[r]++; g_firmAccounts++; }
        }
      while(FileFindNext(hf, fname));
      FileFindClose(hf);
     }
   int order[4] = {Role_Steady, Role_Sprint, Role_Counter, Role_Index};
   int best = order[0], bestC = 1 << 30;
   for(int i = 0; i < 4; i++)
      if(cnt[order[i]] < bestC) { bestC = cnt[order[i]]; best = order[i]; }
   g_firmAccounts++;
   return best;
  }

void ZeroConfigInit()
  {
   // firm tag
   g_firm = FirmTag != "" ? Slug(FirmTag) : Slug(AccountInfoString(ACCOUNT_COMPANY));
   if(g_firm == "") g_firm = Slug(AccountInfoString(ACCOUNT_SERVER));
   // peran
   g_role = -1;
   string gv = GVP() + "ROLE";
   if(RoleOverride != Role_Auto) g_role = RoleOverride;
   else if(AutoRole)
     {
      int fresh = AssignRole();                       // juga menghitung jumlah akun di firm ini
      if(g_firmAccounts <= 1) g_role = Role_Steady;   // akun tunggal: semua strategi (terbaik di simulasi)
      else if(GlobalVariableCheck(gv)) g_role = (int)GlobalVariableGet(gv);
      else g_role = fresh;
     }
   if(g_role >= 0) GlobalVariableSet(gv, g_role);
   RoleParams(g_role, g_targetDays, g_capScale);
   g_roleTxt = g_role < 0 ? "manual" : RoleName(g_role) + " (auto)";
   WriteRegistry();
   Print("9algo zero-config: firm=", g_firm, " peran=", g_roleTxt, " akun di firm ini=", g_firmAccounts, " target ", g_targetDays, " hari, cap x", DoubleToString(g_capScale, 1), ", saldo awal ", DoubleToString(g_initBal, 0));
  }

//+------------------------------------------------------------------+
//| Group-hedge guard antar akun (file bersama di Common/Files)      |
//+------------------------------------------------------------------+
string MarketKey(ENUM_MARKET m)
  {
   return m == MKT_GOLD ? "GOLD" : m == MKT_SILVER ? "SILVER" : m == MKT_USDJPY ? "USDJPY" : m == MKT_NQ ? "NQ" : "OTHER";
  }

// tulis posisi terbuka (semua simbol akun ini) : "MARKET dir" per baris
void WriteHedgeFile()
  {
   if(g_firm == "") return;
   string fn = "9algo\\hedge_" + g_firm + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt";
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\n");
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      string mk = MarketKey(MarketOfName(PositionGetString(POSITION_SYMBOL)));
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      FileWriteString(h, mk + " " + IntegerToString(dir) + "\n");
     }
   FileClose(h);
  }

// true kalau akun lain (tag sama) punya posisi berlawanan arah di market ini
bool GroupHedgeConflict(int dir, string &who)
  {
   if(!GroupHedgeGuard || g_firm == "") return false;
   string me = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string myKey = MarketKey(g_market);
   string fname;
   long hf = FileFindFirst("9algo\\hedge_" + g_firm + "_*.txt", fname, FILE_COMMON);
   if(hf == INVALID_HANDLE) return false;
   bool conflict = false;
   do
     {
      if(StringFind(fname, "_" + me + ".txt") >= 0) continue;
      int h = FileOpen("9algo\\" + fname, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(h == INVALID_HANDLE) continue;
      string stamp = FileReadString(h);
      datetime ts = StringToTime(stamp);
      bool fresh = (TimeCurrent() - ts) < 600;
      while(fresh && !FileIsEnding(h))
        {
         string line = FileReadString(h);
         string parts[];
         if(StringSplit(line, ' ', parts) != 2) continue;
         if(parts[0] == myKey && (int)StringToInteger(parts[1]) == -dir) { conflict = true; who = fname; break; }
        }
      FileClose(h);
      if(conflict) break;
     }
   while(FileFindNext(hf, fname));
   FileFindClose(hf);
   return conflict;
  }

//+------------------------------------------------------------------+
//| Export state JSON (dibaca tools/9algo_mcp.py)                    |
//+------------------------------------------------------------------+
string JQ(string v)
  {
   StringReplace(v, "\\", "/");
   StringReplace(v, "\"", "'");
   return "\"" + v + "\"";
  }
string JB(bool b) { return b ? "true" : "false"; }
string JN(double v, int d = 2) { return DoubleToString(v, d); }

void ExportStateJson(datetime now)
  {
   static datetime last = 0;
   if(now - last < 30) return;
   last = now;
   color c;
   string st = StatusText(c);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   string j = "{";
   j += "\"ea\":\"9algo by Singularity\",\"symbol\":" + JQ(_Symbol) + ",\"market\":" + JQ(g_marketName) + ",\"updated\":" + JQ(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)) + ",";
   j += "\"status\":" + JQ(st) + ",\"blocked_reason\":" + JQ(BlockReason()) + ",";
   j += "\"account\":{\"login\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ",\"currency\":" + JQ(AccountInfoString(ACCOUNT_CURRENCY)) +
        ",\"initial\":" + JN(g_initBal) + ",\"balance\":" + JN(bal) + ",\"equity\":" + JN(eq) + ",\"hwm\":" + JN(g_hwm) + "},";
   j += "\"limits\":{\"daily_limit\":" + JN(DailyLimitMoney()) + ",\"daily_used\":" + JN(MathMax(0, g_dayRef - eq)) +
        ",\"daily_ea_stop\":" + JN(DailyLimitMoney() * GuardFraction) + ",\"maxloss_limit\":" + JN(TotalLimitMoney()) +
        ",\"maxloss_floor\":" + JN(MaxLossFloor()) + ",\"maxloss_ea_stop\":" + JN(MaxLossGuardFloor()) +
        ",\"open_risk\":" + JN(OpenRiskTotal()) + ",\"open_risk_cap\":" + JN(RiskBase() * g_openCapPct / 100.0) + "},";
   j += "\"targets\":{\"profit_goal\":" + JN(ProfitGoalMoneyCalc()) + ",\"profit_now\":" + JN(bal - g_initBal) +
        ",\"profitable_days\":" + IntegerToString(g_st.profitableDays) + ",\"profitable_days_min\":" + IntegerToString(MinProfitableDays) +
        ",\"days_since_trade\":" + IntegerToString(g_st.daysSinceTrade) + ",\"inactivity_days\":" + IntegerToString(InactivityDays) +
        ",\"consistency_best_pct\":" + JN(g_consBestPct, 1) + ",\"consistency_today_pct\":" + JN(g_consTodayPct, 1) + ",\"consistency_max_pct\":" + JN(ConsistencyMaxPct, 1) + "},";
   j += "\"stats\":{\"net\":" + JN(g_st.net) + ",\"gross_profit\":" + JN(g_st.grossProfit) + ",\"gross_loss\":" + JN(g_st.grossLoss) +
        ",\"pf\":" + JN(g_st.pf) + ",\"trades\":" + IntegerToString(g_st.trades) + ",\"wins\":" + IntegerToString(g_st.wins) + ",\"win_rate\":" + JN(g_st.winRate, 1) +
        ",\"best\":" + JN(g_st.best) + ",\"worst\":" + JN(g_st.worst) + ",\"expectancy\":" + JN(g_st.expectancy) + ",\"today_closed\":" + JN(g_st.todayClosed) + "},";
   j += "\"news\":{\"filter\":" + JB(NewsFilter) + ",\"available\":" + JB(g_newsOk) + ",\"blocked\":" + JB(g_newsBlock) +
        ",\"now\":" + JQ(g_newsNowTxt) + ",\"next\":" + JQ(g_newsNextTxt) + "},";
   j += "\"firm_tag\":" + JQ(g_firm) + ",";
   j += "\"challenge\":{\"phase\":" + JQ(PhaseName(g_phase)) + ",\"phase_source\":" + JQ(g_phaseSrc) + ",\"day\":" + IntegerToString(g_challengeDay) + ",\"target_days\":" + IntegerToString(g_targetDays) + ",\"role\":" + JQ(g_roleTxt) +
        ",\"risk_mult\":" + JN(g_effMult, 2) + ",\"auto_scale\":" + JN(g_autoScale, 2) + ",\"p_pass\":" + JN(g_pPass, 3) + ",\"p_bust\":" + JN(g_pBust, 3) +
        ",\"daily_ret_base\":" + JN(g_dailyRet, 5) + ",\"daily_sd_base\":" + JN(g_dailySd, 5) + ",\"progress_floor\":" + JN(g_progFloor) + ",\"spread_avg\":" + JN(g_spreadAvg, 1) + "},";
   j += "\"regime\":{\"filter\":" + JB(RegimeFilter) + ",\"p_trend\":" + JN(g_pTrend, 3) + ",\"text\":" + JQ(g_regimeTxt) + "},";
   j += "\"strategies\":[";
   for(int i = 0; i < ArraySize(g_s); i++)
     {
      if(i > 0) j += ",";
      j += "{\"name\":" + JQ(g_s[i].tag) + ",\"on\":" + JB(g_s[i].on) + ",\"paused\":" + JB(g_s[i].paused) +
           ",\"risk_pct\":" + JN(g_s[i].risk * RiskScale, 3) + ",\"magic\":" + IntegerToString(g_s[i].magic) +
           ",\"positions\":" + IntegerToString(g_s[i].Positions()) + ",\"orders\":" + IntegerToString(g_s[i].Orders()) +
           ",\"state\":" + JQ(g_s[i].Extra()) + ",\"why\":" + JQ(g_s[i].Why()) + "}";
     }
   j += "]}";
   string fn = "9algo\\state_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + Slug(_Symbol) + ".json";
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, j);
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Panel interaktif                                                 |
//+------------------------------------------------------------------+
bool     g_panelOn = false;
datetime g_panelCheck = 0;
string   g_panelText = "";
string   g_pfx = "ALGO9_";
bool     g_collapsed = false;
datetime g_resetArm = 0;
double   g_sc = 1.0;

#define CLR_BG    C'22,24,30'
#define CLR_BG2   C'34,37,45'
#define CLR_TXT   C'230,232,236'
#define CLR_DIM   C'150,155,165'
#define CLR_OK    C'38,166,91'
#define CLR_WARN  C'230,160,30'
#define CLR_BAD   C'204,36,36'
#define CLR_BLUE  C'70,130,220'

int S(double v) { return (int)MathRound(v * g_sc); }

void PRect(string n, int x, int y, int w, int h, color c)
  {
   string nm = g_pfx + n;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, MathMax(w, 1));
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, MathMax(h, 1));
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, "\n");
  }

void PText(string n, string t, int x, int y, int size, color c, bool bold = false)
  {
   string nm = g_pfx + n;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, nm, OBJPROP_TEXT, t);
   ObjectSetString(0, nm, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, "\n");
  }

void PButton(string n, string t, int x, int y, int w, int h, color bg, color fg, string tip)
  {
   string nm = g_pfx + n;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetString(0, nm, OBJPROP_TEXT, t);
   ObjectSetString(0, nm, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_STATE, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
  }

// bar: used/limit. frac warna: hijau <50%, amber <80%, merah >=80%
void PBar(string n, int x, int y, int w, int h, double frac, color fill)
  {
   if(frac < 0) frac = 0;
   if(frac > 1) frac = 1;
   PRect(n + "_bg", x, y, w, h, CLR_BG2);
   PRect(n + "_fg", x, y, (int)(w * frac), h, fill);
  }

color BarColor(double frac)
  {
   if(frac >= GuardFraction) return CLR_BAD;
   if(frac >= 0.5) return CLR_WARN;
   return CLR_OK;
  }

string Money(double v) { return DoubleToString(v, 0); }
string Pct(double v) { return DoubleToString(v, 0) + "%"; }

string StatusText(color &bg)
  {
   bool hedging = AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   if(g_haltTotal || g_haltDaily) { bg = CLR_BAD;  return "GUARD HALT  -  " + g_guardWhy; }
   if(!g_marketMatch)             { bg = CLR_BAD;  return "CHECK SYMBOL  -  bukan XAUUSD / XAGUSD / USDJPY / NQ"; }
   if(!hedging)                   { bg = CLR_BAD;  return "NETTING ACCOUNT  -  9algo butuh akun hedging"; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
                                  { bg = CLR_BAD;  return "ALGO TRADING OFF  -  klik tombol Algo Trading di toolbar MT5"; }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
                                  { bg = CLR_BAD;  return "DISCONNECTED  -  tidak ada koneksi ke server broker"; }
   if(g_haltGoal)                 { bg = CLR_WARN; return "PROFIT GOAL  -  entry baru dihentikan"; }
   if(g_lockDaily)                { bg = CLR_WARN; return "DAILY LOCK  -  target harian tercapai, entry stop s/d reset"; }
   if(g_weekendCut)               { bg = CLR_WARN; return "WEEKEND  -  tidak ada entry sampai Senin"; }
   if(g_newsBlock)                { bg = CLR_WARN; return "NEWS  -  " + g_newsNowTxt; }
   if(g_consLock)                 { bg = CLR_WARN; return "CONSISTENCY  -  hari ini " + DoubleToString(g_consTodayPct, 0) + "% dari total profit, entry stop"; }
   if(g_progLockHit)              { bg = CLR_WARN; return "PROGRESS LOCK  -  equity jatuh ke floor " + Money(g_progFloor) + ", entry stop s/d besok"; }
   if(g_initBal > 0 && MathAbs(AccountInfoDouble(ACCOUNT_BALANCE) - g_initBal) > g_initBal * 0.5)
                                  { bg = CLR_WARN; return "CEK InitialBalance  -  balance jauh dari saldo awal yang di-set"; }
   bg = CLR_OK;
   return "LIVE  -  " + g_marketName;
  }

string PanelSignature()
  {
   color c;
   string s = StatusText(c) + "|" + Money(AccountInfoDouble(ACCOUNT_EQUITY)) + "|" + Money(OpenRiskTotal()) + "|" +
              IntegerToString(g_st.trades) + "|" + IntegerToString(g_st.profitableDays) + "|" + (g_collapsed ? "c" : "e") +
              "|" + Money(g_hwm) + "|" + (g_resetArm > 0 ? "r" : "") + "|" + g_newsNowTxt + "|" + g_newsNextTxt + "|" + DoubleToString(g_consTodayPct, 0) + "|" + g_regimeTxt + "|" + IntegerToString(OurTicketsHere()) + "|" + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 0) + "|" + DoubleToString(g_effMult, 2) + "|" + IntegerToString(g_phase) + g_phaseSrc + "|" + DoubleToString(g_pPass, 2) + "|" + IntegerToString(ChartGetInteger(0, CHART_WIDTH_IN_PIXELS)) + "|" + TimeToString(TimeCurrent(), TIME_MINUTES);
   for(int i = 0; i < ArraySize(g_s); i++)
      s += "|" + IntegerToString(g_s[i].Positions()) + "," + IntegerToString(g_s[i].Orders()) + "," + (g_s[i].paused ? "p" : "") + "," + g_s[i].Extra() + "," + g_s[i].Why();
   return s;
  }

int OurTicketsHere()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && IsOurMagic(PositionGetInteger(POSITION_MAGIC))) c++;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && IsOurMagic(OrderGetInteger(ORDER_MAGIC))) c++;
     }
   return c;
  }

string StratNameOfMagic(long m)
  {
   for(int i = 0; i < ArraySize(g_s); i++)
      if(g_s[i].Mine(m)) return g_s[i].tag;
   return "?";
  }

int TW(string t, int size, bool bold)
  {
   uint w, h;
   TextSetFont(bold ? "Arial Bold" : "Arial", -size * 10, bold ? FW_BOLD : FW_NORMAL);
   TextGetSize(t, w, h);
   return (int)w;
  }

string Fit(string t, int size, bool bold, int maxW)
  {
   if(maxW <= 0 || TW(t, size, bold) <= maxW) return t;
   int n = StringLen(t);
   while(n > 3 && TW(StringSubstr(t, 0, n) + "...", size, bold) > maxW) n -= 2;
   return StringSubstr(t, 0, n) + "...";
  }

bool MarketOpenNow()
  {
   datetime srv = TimeCurrent();
   int dw = DayOfWeekOf(srv);
   int sec = (int)(srv % 86400);
   datetime f, t;
   bool any = false;
   for(int k = 0; k < 10; k++)
     {
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dw, k, f, t)) break;
      any = true;
      int fs = (int)f, te = (int)t;
      if(te <= 0 || te > 86400) te = 86400;
      if(sec >= fs && sec < te) return true;
     }
   return !any;
  }

void DrawPanel()
  {
   g_panelOn = !MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE);
   if(!g_panelOn)
      return;
   ObjectsDeleteAll(0, g_pfx);
   g_sc = TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;
   g_panelText = PanelSignature();

   int x0 = S(10), y0 = S(26), pad = S(8), rh = S(17), hh = S(40);
   int labW = S(88), bw = S(130), gap = S(10);
   int cx1 = x0 + pad, cx2 = cx1 + labW, cx3 = cx2 + bw + gap;
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int maxW = MathMax(S(420), chartW - x0 - S(10));
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   color stC;
   string st = StatusText(stC);
   int ns = ArraySize(g_s);
   int nt = OurTicketsHere();

   //--- 1) susun semua teks dulu
   double goal = ProfitGoalMoneyCalc(), gnow = bal - g_initBal, gfrac = goal > 0 ? gnow / goal : 0;
   string inact = g_st.daysSinceTrade < 0 ? "-" : IntegerToString(g_st.daysSinceTrade);
   double cfrac = ConsistencyMaxPct > 0 ? g_consBestPct / ConsistencyMaxPct : 0;
   double dLim = DailyLimitMoney(), dUsed = MathMax(0, g_dayRef - eq), dfrac = dLim > 0 ? dUsed / dLim : 0;
   double tLim = TotalLimitMoney(), tUsed = MathMax(0, (MaxLossFloor() + tLim) - eq), tfrac = tLim > 0 ? tUsed / tLim : 0;
   double rCap = RiskBase() * g_openCapPct / 100.0, rUsed = OpenRiskTotal(), rfrac = rCap > 0 ? rUsed / rCap : 0;
   double bufStop = eq - MaxLossGuardFloor(), ddHist = g_initBal * 0.06;
   double bfrac = ddHist > 0 ? 1.0 - MathMin(1.0, bufStop / (2 * ddHist)) : 0;

   string v1  = (g_phase == Phase_Funded) ? "FUNDED - tidak ada target, profit " + (gnow >= 0 ? "+" : "") + Money(gnow) + " " + cur
                : Money(gnow) + " / " + Money(goal) + " " + cur + "  (" + Pct(gfrac * 100) + ")";
   string v2  = IntegerToString(g_st.profitableDays) + " / " + IntegerToString(MinProfitableDays) + "    inactivity " + inact + " / " + IntegerToString(InactivityDays) + " hari";
   string v2b = !ConsistencyGuard ? "off" : g_phase != Phase_Funded ? "tidak berlaku di fase evaluasi (hanya funded)" : "best day " + Money(g_consBestDay) + " = " + Pct(g_consBestPct) + " dari " + Money(g_consRef) + " / max " + Pct(ConsistencyMaxPct) + "    ruang hari ini +" + (g_consRoomToday > 1e8 ? "bebas" : Money(g_consRoomToday));
   string v3  = "-" + Money(dUsed) + " / " + Money(dLim) + "    sisa " + Money(dLim - dUsed) + "    EA stop -" + Money(dLim * GuardFraction) + "    hari ini " + (eq - g_dayRef >= 0 ? "+" : "") + Money(eq - g_dayRef);
   string v4  = "-" + Money(tUsed) + " / " + Money(tLim) + "    floor " + Money(MaxLossFloor()) + "    EA stop " + Money(MaxLossGuardFloor()) + (MaxLossMode == MaxLoss_TrailingFromHWM ? "    HWM " + Money(g_hwm) : "");
   string v5  = Money(rUsed) + " / " + Money(rCap) + "  (cap " + DoubleToString(g_openCapPct, 1) + "%)";
   string v6  = Money(bufStop) + " sebelum EA stop  =  " + DoubleToString(ddHist > 0 ? bufStop / ddHist : 0, 1) + "x DD historis 6% (" + Money(ddHist) + ")";
   string s1  = "Equity " + Money(eq) + "   Balance " + Money(bal) + "   Net " + Money(g_st.net) + "   Gross +" + Money(g_st.grossProfit) + " / " + Money(g_st.grossLoss) + "   PF " + DoubleToString(g_st.pf, 2) + "   Win " + Pct(g_st.winRate) + " (" + IntegerToString(g_st.wins) + "/" + IntegerToString(g_st.trades) + ")";
   string s2  = "Best +" + Money(g_st.best) + "   Worst " + Money(g_st.worst) + "   Expectancy " + Money(g_st.expectancy) + "   Avg trade " + Money(g_st.avgAbs) + "   Today closed " + Money(g_st.todayClosed);
   string ch1, ch2;
   if(g_phase == Phase_Funded)
     { ch1 = "Mode FUNDED   risk x" + DoubleToString(g_effMult, 2) + "   progress lock off"; ch2 = "Jaga akun: daily lock & consistency aktif, target tidak dikejar"; }
   else if(!ChallengeMode)
     { ch1 = "Challenge mode off   risk x" + DoubleToString(g_effMult, 2); ch2 = ""; }
   else
     {
      double progFrac = goal > 0 ? gnow / goal : 0;
      string fase = (StringFind(g_phaseSrc, "default") >= 0 ? "otomatis (FUNDED? klik tombol)  " : "") + (ChallengeStyle == Style_Fast ? "FAST " : "") + (progFrac < 0.5 ? "A (0-50%)" : (progFrac < 0.9 ? "B (50-90%)" : "C (>90%)"));
      ch1 = "Hari " + IntegerToString(g_challengeDay) + (g_targetDays > 0 ? " / " + IntegerToString(g_targetDays) : "") + "   fase " + fase +
            "   target-days butuh x" + DoubleToString(g_autoScale, 1) + "   risk efektif x" + DoubleToString(g_effMult, 2) + " (cap " + DoubleToString(g_capScale, 1) + ")   peran " + g_roleTxt;
      ch2 = "P(lolos) " + (g_pPass < 0 ? "-" : Pct(g_pPass * 100)) + "   P(bust) " + (g_pBust < 0 ? "-" : Pct(g_pBust * 100)) +
            "   base " + DoubleToString(g_dailyRet * 100, 2) + "%/hari sd " + DoubleToString(g_dailySd * 100, 2) + "%" + (g_st.trades >= 20 ? " (riil)" : " (asumsi)") +
            "   progress floor " + (g_progFloor > 0 ? Money(g_progFloor) : "-") + "   spread avg " + DoubleToString(g_spreadAvg, 0);
     }
   string nw  = !NewsFilter ? "off" : (!g_newsOk ? "kalender tidak tersedia" : (g_newsBlock ? "BLOK: " + g_newsNowTxt : "next: " + (g_newsNextTxt == "" ? "-" : g_newsNextTxt)));
   string nh  = "NEWS  (" + (NewsImportance == News_HighOnly ? "high" : "medium+high") + " " + g_newsCur + ", -" + IntegerToString(NewsBeforeMin) + " / +" + IntegerToString(NewsAfterMin) + " menit)   |   regime: " + (!RegimeFilter ? "off" : g_regimeTxt);
   string sl[]; ArrayResize(sl, ns);
   for(int i = 0; i < ns; i++)
     {
      int np = g_s[i].Positions(), no = g_s[i].Orders();
      sl[i] = g_s[i].tag + "   risk " + DoubleToString(g_s[i].risk * RiskScale * g_effMult, 2) + "%   pos " + IntegerToString(np) + (g_s[i].stTrades > 0 ? "   " + IntegerToString(g_s[i].stTrades) + "t " + (g_s[i].stNet >= 0 ? "+" : "") + Money(g_s[i].stNet) : "");
      if(no > 0) sl[i] += "   ord " + IntegerToString(no);
      string x = g_s[i].Extra();
      if(x != "") sl[i] += "   " + x;
      if(np == 0 && no == 0 && g_s[i].Why() != "") sl[i] += "   >  " + g_s[i].Why();
     }
   string pl[]; color plc[]; int npl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || !IsOurMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double p = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double op = PositionGetDouble(POSITION_PRICE_OPEN), slp = PositionGetDouble(POSITION_SL), tpp = PositionGetDouble(POSITION_TP);
      ArrayResize(pl, npl + 1); ArrayResize(plc, npl + 1);
      pl[npl] = StratNameOfMagic(PositionGetInteger(POSITION_MAGIC)) + "   " + (buy ? "BUY " : "SELL ") + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + " @ " + DoubleToString(op, g_digits) +
                "   SL " + (slp > 0 ? DoubleToString(slp, g_digits) : "-") + "   TP " + (tpp > 0 ? DoubleToString(tpp, g_digits) : "-") +
                "   risk " + Money(TicketRiskMoney(_Symbol, buy, PositionGetDouble(POSITION_VOLUME), op, slp)) + "   P/L " + (p >= 0 ? "+" : "") + DoubleToString(p, 2) +
                "   sejak " + TimeToString(ServerToNY((datetime)PositionGetInteger(POSITION_TIME)), TIME_DATE | TIME_MINUTES) + " NY";
      plc[npl] = p >= 0 ? CLR_OK : CLR_BAD; npl++;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol || !IsOurMagic(OrderGetInteger(ORDER_MAGIC))) continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      string tn = (ot == ORDER_TYPE_BUY_STOP ? "BUY STOP" : ot == ORDER_TYPE_SELL_STOP ? "SELL STOP" : ot == ORDER_TYPE_BUY_LIMIT ? "BUY LIMIT" : ot == ORDER_TYPE_SELL_LIMIT ? "SELL LIMIT" : "ORDER");
      datetime ex = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      ArrayResize(pl, npl + 1); ArrayResize(plc, npl + 1);
      pl[npl] = StratNameOfMagic(OrderGetInteger(ORDER_MAGIC)) + "   " + tn + " " + DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 2) + " @ " + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), g_digits) +
                "   SL " + DoubleToString(OrderGetDouble(ORDER_SL), g_digits) + "   TP " + (OrderGetDouble(ORDER_TP) > 0 ? DoubleToString(OrderGetDouble(ORDER_TP), g_digits) : "-") +
                (ex > 0 ? "   exp " + TimeToString(ServerToNY(ex), TIME_MINUTES) + " NY" : "");
      plc[npl] = CLR_DIM; npl++;
     }
   string rb = (RiskMode == Compounding_PercentOfCurrentEquity) ? "equity" : Money(g_initBal) + " " + cur;
   string ft = (UsePresetTerbaru ? "v2.86 preset otomatis   risk base " : "v2.86 preset manual   risk base ") + rb + "   x" + DoubleToString(RiskScale, 2) + "   Max Loss " + (MaxLossMode == MaxLoss_TrailingFromHWM ? "trailing HWM" : "statis") +
               "   push " + (PushAlerts ? "on" : "off") + "   weekend close " + (CloseBeforeWeekend ? "on" : "off");
   long tickAge = (long)(TimeCurrent() - (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME));
   string clk = "NY " + TimeToString(ServerToNY(TimeCurrent()), TIME_MINUTES) + "   LDN " + TimeToString(ServerToLondon(TimeCurrent()), TIME_MINUTES) +
                "   spread " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) +
                (!MarketOpenNow() ? "   market tutup" : (tickAge > 120 ? "   tanpa tick " + IntegerToString((int)(tickAge / 60)) + "m!" : "")) +
                "   " + TimeToString(TimeLocal(), TIME_MINUTES) + " lokal";

   //--- 2) lebar panel = teks terlebar
   int need = S(460);
   string vals[7];
   vals[0] = v1; vals[1] = v2; vals[2] = v2b; vals[3] = v3; vals[4] = v4; vals[5] = v5; vals[6] = v6;
   for(int i = 0; i < 7; i++) need = MathMax(need, cx3 - x0 + TW(vals[i], 8, false) + pad);
   string fulls[8];
   fulls[0] = s1; fulls[1] = s2; fulls[2] = nw; fulls[3] = nh; fulls[4] = ft; fulls[5] = clk; fulls[6] = ch1; fulls[7] = ch2;
   for(int i = 0; i < 8; i++) need = MathMax(need, cx1 - x0 + TW(fulls[i], 8, false) + pad);
   for(int i = 0; i < ns; i++) need = MathMax(need, cx1 - x0 + S(52) + TW(sl[i], 8, false) + pad);
   for(int i = 0; i < npl; i++) need = MathMax(need, cx1 - x0 + TW(pl[i], 8, false) + pad);
   int W = MathMin(need, maxW);
   int valW = W - (cx3 - x0) - pad;
   int fullW = W - (cx1 - x0) - pad;

   int H = hh;
   if(!g_collapsed)
      H += pad + rh * 4 + S(6) + rh * 5 + S(6) + rh * 3 + S(6) + rh * 3 + S(6) + rh * 2 + S(6) + rh * (ns + 1) + S(6) + (npl > 0 ? rh * (npl + 1) + S(6) : 0) + rh + pad;

   //--- 3) gambar
   PRect("bg", x0, y0, W, H, CLR_BG);
   PRect("hd", x0, y0, W, hh, stC);
   PText("title", "9algo", cx1, y0 + S(4), 9, clrWhite, true);
   PText("st", Fit(st, 8, true, W - S(48) - S(150) - pad), cx1 + S(48), y0 + S(5), 8, clrWhite, true);
   color phC = g_phase == Phase_Funded ? CLR_BLUE : (g_phase == Phase_Verification ? CLR_WARN : CLR_BG2);
   PButton("btn_phase", PhaseName(g_phase) + (StringFind(g_phaseSrc, "default") >= 0 ? " (auto)" : ""), x0 + W - S(146), y0 + S(3), S(114), S(18), phC, clrWhite,
           "Fase: " + PhaseName(g_phase) + " - sumber: " + g_phaseSrc + ". Klik untuk ganti: Challenge > Verification > Funded > Auto");
   PText("clk", Fit(clk, 7, false, W - S(34) - pad), cx1, y0 + S(23), 7, clrWhite);
   PButton("btn_collapse", g_collapsed ? "+" : "-", x0 + W - S(26), y0 + S(3), S(20), S(18), CLR_BG2, clrWhite, g_collapsed ? "Tampilkan detail" : "Sembunyikan detail");
   if(g_collapsed) { ChartRedraw(0); return; }

   int y = y0 + hh + pad;
   PText("h1", "TARGET", cx1, y, 7, CLR_DIM, true); y += rh;
   PText("t1", "Profit goal", cx1, y, 8, CLR_TXT);   PBar("b1", cx2, y + S(3), bw, S(9), gfrac, gnow >= 0 ? CLR_BLUE : CLR_BAD);   PText("v1", Fit(v1, 8, false, valW), cx3, y, 8, CLR_TXT); y += rh;
   PText("t2", "Profitable days", cx1, y, 8, CLR_TXT); PBar("b2", cx2, y + S(3), bw, S(9), MinProfitableDays > 0 ? (double)g_st.profitableDays / MinProfitableDays : 0, CLR_BLUE); PText("v2", Fit(v2, 8, false, valW), cx3, y, 8, CLR_TXT); y += rh;
   PText("t2b", "Consistency", cx1, y, 8, CLR_TXT);  PBar("b2b", cx2, y + S(3), bw, S(9), ConsistencyGuard ? cfrac : 0, BarColor(cfrac)); PText("v2b", Fit(v2b, 8, false, valW), cx3, y, 8, CLR_TXT); y += rh;
   y += S(6);
   PText("h2", "LIMIT  (EA berhenti di " + Pct(GuardFraction * 100) + " dari limit prop firm)", cx1, y, 7, CLR_DIM, true); y += rh;
   PText("t3", "Daily loss", cx1, y, 8, CLR_TXT);    PBar("b3", cx2, y + S(3), bw, S(9), dfrac, BarColor(dfrac)); PText("v3", Fit(v3, 8, false, valW), cx3, y, 8, CLR_TXT); y += rh;
   PText("t4", "Max loss", cx1, y, 8, CLR_TXT);      PBar("b4", cx2, y + S(3), bw, S(9), tfrac, BarColor(tfrac)); PText("v4", Fit(v4, 8, false, valW), cx3, y, 8, CLR_TXT); y += rh;
   PText("t5", "Open risk", cx1, y, 8, CLR_TXT);     PBar("b5", cx2, y + S(3), bw, S(9), rfrac, BarColor(rfrac)); PText("v5", Fit(v5, 8, false, valW), cx3, y, 8, CLR_TXT); y += rh;
   PText("t6", "Buffer", cx1, y, 8, CLR_TXT);        PBar("b6", cx2, y + S(3), bw, S(9), bfrac, BarColor(bfrac)); PText("v6", Fit(v6, 8, false, valW), cx3, y, 8, bufStop < ddHist ? CLR_WARN : CLR_TXT); y += rh;
   y += S(6);
   PText("hc", "CHALLENGE", cx1, y, 7, CLR_DIM, true); y += rh;
   PText("c1", Fit(ch1, 8, false, fullW), cx1, y, 8, CLR_TXT); y += rh;
   PText("c2", Fit(ch2, 8, false, fullW), cx1, y, 8, g_pBust > 0.3 ? CLR_WARN : CLR_TXT); y += rh;
   y += S(6);
   PText("h3", "STATS  (sejak " + TimeToString(StatsFrom(), TIME_DATE) + ")", cx1, y, 7, CLR_DIM, true); y += rh;
   PText("s1", Fit(s1, 8, false, fullW), cx1, y, 8, CLR_TXT); y += rh;
   PText("s2", Fit(s2, 8, false, fullW), cx1, y, 8, CLR_TXT); y += rh;
   y += S(6);
   PText("h5", Fit(nh, 7, true, fullW), cx1, y, 7, CLR_DIM, true); y += rh;
   PText("n1", Fit(nw, 8, false, fullW), cx1, y, 8, g_newsBlock ? CLR_WARN : CLR_TXT); y += rh;
   y += S(6);
   PText("h4", "STRATEGI   (tombol = pause / lanjut entry baru; posisi tetap dikelola)", cx1, y, 7, CLR_DIM, true); y += rh;
   for(int i = 0; i < ns; i++)
     {
      bool live = g_s[i].on && !g_s[i].paused && !g_s[i].autoPaused;
      PButton("btn_s" + IntegerToString(i), !g_s[i].on ? "OFF" : (g_s[i].autoPaused ? "AUTO" : (live ? "LIVE" : "PAUSE")), cx1, y + S(1), S(44), rh - S(3),
              !g_s[i].on ? CLR_BG2 : (live ? CLR_OK : CLR_WARN), clrWhite,
              !g_s[i].on ? "Dimatikan di input" : (live ? "Klik untuk pause entry baru" : "Klik untuk lanjut entry"));
      PRect("sc" + IntegerToString(i), cx1 + S(47), y + S(3), S(3), S(10), LvC(g_s[i].tag));
      PText("sl" + IntegerToString(i), Fit(sl[i], 8, false, fullW - S(52)), cx1 + S(52), y, 8, g_s[i].on ? CLR_TXT : CLR_DIM);
      y += rh;
     }
   y += S(6);
   if(npl > 0)
     {
      PText("h6", "POSISI & ORDER  (chart ini)", cx1, y, 7, CLR_DIM, true); y += rh;
      for(int i = 0; i < npl; i++) { PText("p" + IntegerToString(i), Fit(pl[i], 8, false, fullW), cx1, y, 8, plc[i]); y += rh; }
      y += S(6);
     }
   int ftW = fullW - ((g_haltTotal || g_haltDaily) ? S(110) : 0);
   PText("ft", Fit(ft, 7, false, ftW), cx1, y + S(2), 7, CLR_DIM);
   if(g_haltTotal || g_haltDaily)
      PButton("btn_reset", g_resetArm > 0 ? "KLIK LAGI: RESET" : "RESET HALT", x0 + W - S(110), y, S(100), rh - S(2),
              g_resetArm > 0 ? CLR_BAD : CLR_BG2, clrWhite, "Hapus flag halt (daily & total). Pastikan limit prop firm memang belum kena.");
   ChartRedraw(0);
  }

void DeletePanel() { ObjectsDeleteAll(0, g_pfx); ChartRedraw(0); }

void ApplyChartStyle()
  {
   if(!ChartStyle || MQLInfoInteger(MQL_TESTER)) return;
   int sh = ChartShiftPct < 10 ? 10 : (ChartShiftPct > 50 ? 50 : ChartShiftPct);
   ChartSetInteger(0, CHART_SHIFT, true);
   ChartSetDouble(0, CHART_SHIFT_SIZE, sh);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, CHART_VOLUME_HIDE);
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, true);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'16,20,28');
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'150,156,168');
   ChartSetInteger(0, CHART_COLOR_GRID, C'42,49,64');
   ChartSetInteger(0, CHART_COLOR_CHART_UP, C'38,166,154');
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, C'239,83,80');
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, C'38,166,154');
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, C'239,83,80');
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, C'150,156,168');
   ChartSetInteger(0, CHART_COLOR_BID, C'90,98,112');
   ChartSetInteger(0, CHART_COLOR_ASK, C'70,76,88');
  }

int TH(int size, bool bold)
  {
   uint w, h;
   TextSetFont(bold ? "Arial Bold" : "Arial", -size * 10, bold ? FW_BOLD : FW_NORMAL);
   TextGetSize("Ag", w, h);
   return (int)h;
  }

void UiBox(string nm, int x, int y, int w, int h, color bg, color edge)
  {
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, MathMax(1, w));
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, MathMax(1, h));
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, edge);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }

void UiTxt(string nm, int x, int y, string text, color c, int size, bool bold, ENUM_ANCHOR_POINT anc)
  {
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
   ObjectSetString(0, nm, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }

// garis 1 px (horizontal / vertikal) dalam koordinat layar
void UiHL(string nm, int x1, int x2, int y, color c) { if(x2 > x1) UiBox(nm, x1, y, x2 - x1, 1, c, c); }
void UiVL(string nm, int x, int y1, int y2, color c) { UiBox(nm, x, MathMin(y1, y2), 1, MathAbs(y2 - y1) + 1, c, c); }

// Kartu "Rencana hari ini" (kanan atas) + kartu setup sejajar harga entry di ruang kosong kanan.
// Semua ukuran diukur dari font sebenarnya x skala DPI layar, jadi tidak tumpang tindih di 100%/125%/150%.
void LayoutLabels()
  {
   ObjectsDeleteAll(0, "9AL_LB");
   if(!ShowLevels) return;
   g_sc = TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;
   int W = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int H = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(W < S(300) || H < S(150)) return;
   int padx = S(8), pady = S(5), acc = S(3), lg = S(2), gap = S(6);
   int h1 = TH(8, true), h2 = TH(7, false);

   //--- 1) Rencana hari ini
   int nr = ArraySize(g_rwTag);
   int rh = MathMax(h1, h2) + S(3);
   string title = _Symbol + "  " + U(0x00B7) + "  RENCANA HARI INI";
   string leg = U(0x25CF) + " order di broker / posisi    " + U(0x25CB) + " siaga / menunggu    " + U(0x00D7) + " ditolak    " + U(0x2013) + " libur/selesai";
   int nameW = 0, dotW = S(14);
   for(int r = 0; r < nr; r++) nameW = MathMax(nameW, TW(SName(g_rwTag[r]), 8, true));
   int sw = padx + MathMax(TW(title, 7, true), TW(leg, 7, false)) + padx;
   for(int r = 0; r < nr; r++) sw = MathMax(sw, padx + dotW + nameW + S(10) + TW(g_rwTx[r], 7, false) + padx);
   sw = MathMin(sw, MathMax(S(320), W * 45 / 100));
   int sh = pady + h2 + S(5) + nr * rh + S(3) + h2 + pady;
   int sx = W - sw - S(8), sy = S(26);
   int txW = sw - (padx + dotW + nameW + S(10)) - padx;
   UiBox("9AL_LBs_bg", sx, sy, sw, sh, CLR_CARD, CLR_EDGE);
   UiTxt("9AL_LBs_t", sx + padx, sy + pady, title, CLR_GRY, 7, true, ANCHOR_LEFT_UPPER);
   int y = sy + pady + h2 + S(5);
   for(int r = 0; r < nr; r++)
     {
      int k = g_rwK[r];
      color dc = k <= 1 ? LvC(g_rwTag[r]) : (k == 2 ? CLR_GRY : CLR_LDIM);
      string dot = k == 0 ? U(0x25CF) : (k == 1 ? U(0x25CB) : (k == 2 ? U(0x00D7) : U(0x2013)));
      string ix = IntegerToString(r);
      UiTxt("9AL_LBs_d" + ix, sx + padx, y, dot, dc, 8, true, ANCHOR_LEFT_UPPER);
      UiTxt("9AL_LBs_n" + ix, sx + padx + dotW, y, SName(g_rwTag[r]), k == 3 ? CLR_GRY : dc, 8, true, ANCHOR_LEFT_UPPER);
      UiTxt("9AL_LBs_x" + ix, sx + padx + dotW + nameW + S(10), y + (h1 - h2) / 2, Fit(g_rwTx[r], 7, false, txW), k == 3 ? CLR_LDIM : CLR_TXT2, 7, false, ANCHOR_LEFT_UPPER);
      y += rh;
     }
   UiTxt("9AL_LBs_lg", sx + padx, y + S(3), leg, CLR_LDIM, 7, false, ANCHOR_LEFT_UPPER);

   //--- 2) kartu setup
   int n = ArraySize(g_cdP);
   if(n == 0) return;
   int ch = 2 * pady + h1 + lg + h2;
   string pill[] = {"AKTIF", "MENUNGGU", "DITOLAK", "POSISI", "SIAGA"};
   int cw = 0;
   for(int i = 0; i < n; i++)
     {
      int pw = TW(pill[g_cdK[i]], 7, true) + S(8);
      cw = MathMax(cw, acc + padx + TW(U(0x25BC) + " " + g_cdA[i], 8, true) + S(12) + pw + padx);
      cw = MathMax(cw, acc + padx + TW(g_cdB[i], 7, false) + padx);
     }
   int cx = 0;
   int top = sy + sh + S(8), bot = H - S(8);
   double pMax = ChartGetDouble(0, CHART_PRICE_MAX, 0), pMin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   datetime tl = iTime(_Symbol, _Period, 0);
   int xl = 0, yd = 0;
   if(tl <= 0 || !ChartTimePriceToXY(0, 0, tl, SymbolInfoDouble(_Symbol, SYMBOL_BID), xl, yd)) xl = W / 2;
   cw = MathMin(cw, MathMax(S(260), W - xl - S(30)));   // kartu tinggal di ruang kosong kanan, tidak menutupi candle
   cw = MathMin(cw, W - S(16));
   cx = W - cw - S(8);

   int ys[], ord[], fl[], yp[], py[];
   ArrayResize(ys, n); ArrayResize(ord, n); ArrayResize(fl, n); ArrayResize(yp, n); ArrayResize(py, n);
   for(int i = 0; i < n; i++)
     {
      int xx = 0, yv = 0;
      if(!ChartTimePriceToXY(0, 0, tl, g_cdP[i], xx, yv)) yv = H / 2;
      fl[i] = pMax <= pMin ? 0 : (g_cdP[i] > pMax ? 1 : (g_cdP[i] < pMin ? -1 : 0));
      yp[i] = yv;
      ys[i] = yv - ch / 2;
      ord[i] = i;
     }
   for(int a = 1; a < n; a++)          // urutkan atas -> bawah
     {
      int k = ord[a], b = a - 1;
      while(b >= 0 && ys[ord[b]] > ys[k]) { ord[b + 1] = ord[b]; b--; }
      ord[b + 1] = k;
     }
   for(int a = 0; a < n; a++)          // dorong ke bawah supaya tidak menumpuk
     {
      int v = MathMax(ys[ord[a]], top);
      if(a > 0) v = MathMax(v, py[a - 1] + ch + gap);
      py[a] = v;
     }
   for(int a = n - 1; a >= 0; a--)     // lalu dorong ke atas kalau mentok bawah
     {
      py[a] = MathMin(py[a], bot - ch);
      if(a < n - 1) py[a] = MathMin(py[a], py[a + 1] - ch - gap);
     }
   for(int a = 0; a < n; a++)
     {
      int i = ord[a], y0 = py[a];
      string ix = IntegerToString(i);
      color c = g_cdC[i];
      int k = g_cdK[i];
      // garis penghubung: dari ujung zona -> belok -> tengah kartu
      if(fl[i] == 0)
        {
         int xs = 0, yy = 0;
         if(!ChartTimePriceToXY(0, 0, g_cdT[i], g_cdP[i], xs, yy)) xs = xl;
         xs = MathMax(xs, xl);
         int xe = cx - S(12), ym = y0 + ch / 2;
         color lc = k == 2 ? CLR_LDIM : c;
         if(xs < xe) UiHL("9AL_LBc1_" + ix, xs, xe, yp[i], lc);
         UiVL("9AL_LBc2_" + ix, xe, yp[i], ym, lc);
         UiHL("9AL_LBc3_" + ix, xe, cx, ym, lc);
        }
      UiBox("9AL_LBk_" + ix, cx, y0, cw, ch, CLR_CARD, CLR_EDGE);
      UiBox("9AL_LBa_" + ix, cx, y0, acc, ch, k == 2 ? CLR_GRY : c, k == 2 ? CLR_GRY : c);
      int pw = TW(pill[k], 7, true) + S(8), ph = h2 + S(2), pxl = cx + cw - padx - pw;
      color pb = k == 0 ? c : (k == 1 ? C'40,52,70' : (k == 2 ? C'110,58,63' : (k == 3 ? C'47,129,247' : C'40,52,70')));
      color pt = k == 0 ? C'16,20,28' : (k == 1 ? c : (k == 2 ? C'240,176,181' : (k == 3 ? clrWhite : c)));
      string arrow = fl[i] == 1 ? U(0x25B2) + " " : (fl[i] == -1 ? U(0x25BC) + " " : "");
      int w1 = pxl - S(8) - (cx + acc + padx);
      UiTxt("9AL_LB1_" + ix, cx + acc + padx, y0 + pady, Fit(arrow + g_cdA[i], 8, true, w1), k == 2 ? CLR_GRY : c, 8, true, ANCHOR_LEFT_UPPER);
      UiBox("9AL_LBp_" + ix, pxl, y0 + pady, pw, ph, pb, pb);
      UiTxt("9AL_LBq_" + ix, pxl + pw / 2, y0 + pady + ph / 2, pill[k], pt, 7, true, ANCHOR_CENTER);
      UiTxt("9AL_LB2_" + ix, cx + acc + padx, y0 + pady + h1 + lg, Fit(g_cdB[i], 7, false, cw - acc - 2 * padx), CLR_TXT2, 7, false, ANCHOR_LEFT_UPPER);
     }
  }

void DrawLevels()
  {
   ObjectsDeleteAll(0, "9AL_");
   LbReset();
   if(!ShowLevels || (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))) return;
   datetime now = TimeCurrent();
   for(int i = 0; i < ArraySize(g_s); i++)
     {
      if(!g_s[i].on) { LvRow(g_s[i].tag, 3, "nonaktif (peran akun / setelan)"); continue; }
      if(g_s[i].paused) { LvRow(g_s[i].tag, 3, "dijeda manual (tombol panel)"); continue; }
      if(g_s[i].autoPaused) { LvRow(g_s[i].tag, 3, "dijeda otomatis (hasil negatif)"); continue; }
      g_s[i].Levels(now);
     }
   // posisi terbuka: kotak dari jam entry sampai batas waktu exit, dengan P/L berjalan
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong tk = PositionGetTicket(p);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      for(int i = 0; i < ArraySize(g_s); i++)
        {
         if(!g_s[i].Mine(mg)) continue;
         bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
         datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
         datetime xt = g_s[i].ExitAt(ot);
         if(xt <= now) xt = now + 3600;
         double pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         LvTrade("pos" + IntegerToString((long)tk), g_s[i].tag, buy, PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP),
                 ot, xt, 2, (buy ? "BUY " : "SELL ") + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2),
                 "P/L " + (pl >= 0 ? "+" : "") + DoubleToString(pl, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
         break;
        }
     }
   bool mOpen = MarketOpenNow();
   for(int i = 0; i < ArraySize(g_s); i++)
      if(!LvHasRow(g_s[i].tag))
         LvRow(g_s[i].tag, 3, !mOpen ? "pasar tutup" : (g_s[i].Why() != "" ? g_s[i].Why() : "tidak ada setup hari ini"));
   LayoutLabels();
   ChartRedraw(0);
  }

void LayoutLabels();
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE) { g_panelCheck = 0; LayoutLabels(); ChartRedraw(0); return; }
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, g_pfx + "btn_") != 0)
      return;
   string b = StringSubstr(sparam, StringLen(g_pfx));
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   if(b == "btn_collapse")
      g_collapsed = !g_collapsed;
   else if(b == "btn_phase")
     {
      string gm = GVP() + "PHASE_MANUAL";
      int cur = GlobalVariableCheck(gm) ? (int)GlobalVariableGet(gm) : -9;
      int nx = cur == -9 ? Phase_Challenge : cur == Phase_Challenge ? Phase_Verification : cur == Phase_Verification ? Phase_Funded : -9;
      if(nx == -9) GlobalVariableDel(gm); else GlobalVariableSet(gm, nx);
      g_phase = DetectPhase(g_phaseSrc);
      Notify("Fase diubah manual: " + PhaseName(g_phase) + " (" + g_phaseSrc + ")");
     }
   else if(b == "btn_reset")
     {
      if(g_resetArm > 0 && TimeLocal() - g_resetArm <= 8)
        {
         GlobalVariableDel(GVP() + "HALTTOTAL");
         GlobalVariableDel(GVP() + "HALTDAY_" + IntegerToString((long)g_guardDay));
         g_haltTotal = false; g_haltDaily = false; g_haltActed = false; g_guardWhy = "";
         g_resetArm = 0;
         Print("9algo: flag halt dihapus manual dari panel");
        }
      else
         g_resetArm = TimeLocal();
     }
   else if(StringFind(b, "btn_s") == 0)
     {
      int i = (int)StringToInteger(StringSubstr(b, 5));
      if(i >= 0 && i < ArraySize(g_s) && g_s[i].on)
        {
         g_s[i].paused = !g_s[i].paused;
         string gv = GVP() + "PAUSE_" + IntegerToString(g_s[i].magic);
         if(g_s[i].paused) { GlobalVariableSet(gv, 1); g_s[i].DeleteAllOrders(); }
         else GlobalVariableDel(gv);
        }
     }
   DrawPanel();
  }

//+------------------------------------------------------------------+
//| Maintain                                                         |
//+------------------------------------------------------------------+
datetime g_lastDayUpd = 0;

void DrawLevels();
void MaintainCommon()
  {
   datetime now = TimeCurrent();
   static datetime lastLv = 0;
   if(TimeLocal() - lastLv >= 60) { lastLv = TimeLocal(); DrawLevels(); }
   static datetime lastDeploy = 0;
   // ulang cek pemasangan tiap 60 detik, hanya 30 menit pertama setelah EA start (supaya tidak "melawan" kalau user sengaja menutup chart)
   if(AutoDeployOtherCharts && g_marketMatch && !MQLInfoInteger(MQL_TESTER) && TimeLocal() - lastDeploy >= 60 && TimeLocal() < g_deployUntil)
     {
      lastDeploy = TimeLocal();
      if(IsLeader()) AutoDeploy();
     }
   if(DayStart(now) != g_closeLearnDay && now >= g_closeRetryAt)
     {
      g_closeRetryAt = now + 300;   // history belum lengkap -> coba lagi paling cepat 5 menit
      if(DayOfWeekOf(now) == 1 || g_closeLearnDay < 0 || !g_tzOk)
         DetectTimeZone(_Symbol);
      LearnSessionClose();
     }
   datetime ld = DayStart(ServerToLondon(now));
   if(ld != g_lastDayUpd)
     {
      g_lastDayUpd = ld;
      for(int i = 0; i < ArraySize(g_s); i++)
         if(g_s[i].on) g_s[i].DayChange();
     }
   if(g_initBal <= 0)
      g_initBal = InitialBalance > 0 ? InitialBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   GuardUpdate(now);
   if(g_panelOn && now - g_panelCheck >= 30)
     {
      g_panelCheck = now;
      ComputeStats(now);
      if(g_resetArm > 0 && TimeLocal() - g_resetArm > 8) g_resetArm = 0;
      if(ObjectFind(0, g_pfx + "bg") < 0 || PanelSignature() != g_panelText)
         DrawPanel();
     }
  }

//+------------------------------------------------------------------+
//| Auto deploy ke chart lain                                        |
//+------------------------------------------------------------------+
ENUM_MARKET MarketOfName(string name)
  {
   string u = name;
   StringToUpper(u);
   string exMetal = "EUR,AUD,GBP,CHF,JPY,CAD,NZD,CNH,SGD,HKD,TRY,ZAR,MXN,INR";
   if(HasToken(u, "XAU,GOLD") && !HasToken(u, exMetal + ",XAG,SILVER")) return MKT_GOLD;
   if(HasToken(u, "XAG,SILVER") && !HasToken(u, exMetal + ",XAU,GOLD")) return MKT_SILVER;
   if(HasToken(u, "USDJPY,USD/JPY,USD_JPY,USD.JPY,USD-JPY")) return MKT_USDJPY;
   if(HasToken(u, "NDX,NAS,NQ,US100,US 100,USTEC,UST100,USTECH,US TECH,USATECH,TECH100,NSDQ,NDAQ")) return MKT_NQ;
   return MKT_UNKNOWN;
  }

// cari simbol broker untuk market tertentu (prefer yang sudah di Market Watch, lalu nama terpendek)
string FindSymbolFor(ENUM_MARKET m)
  {
   string best = "";
   int bestScore = -1;
   for(int pass = 0; pass < 2; pass++)
     {
      bool selectedOnly = (pass == 0);
      int tot = SymbolsTotal(selectedOnly);
      for(int i = 0; i < tot; i++)
        {
         string n = SymbolName(i, selectedOnly);
         if(MarketOfName(n) != m) continue;
         if(SymbolInfoInteger(n, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) continue;
         int score = 1000 - StringLen(n) + (selectedOnly ? 100 : 0);
         if(score > bestScore) { bestScore = score; best = n; }
        }
      if(best != "") break;
     }
   return best;
  }

// status chart untuk market m (selain chart ini): 2 = ada chart dengan 9algo, 1 = ada chart tanpa EA (id dikembalikan),
// 3 = hanya ada chart dengan EA LAIN (tidak disentuh), 0 = tidak ada chart
int ChartStateFor(ENUM_MARKET m, long &emptyId)
  {
   int st = 0;
   emptyId = 0;
   long id = ChartFirst();
   while(id >= 0)
     {
      if(id != ChartID() && MarketOfName(ChartSymbol(id)) == m)
        {
         string en = ChartGetString(id, CHART_EXPERT_NAME);
         if(StringFind(en, "9algo") >= 0) return 2;
         if(en == "") { if(emptyId == 0) emptyId = id; st = MathMax(st, 1); }
         else st = MathMax(st, 3);
        }
      id = ChartNext(id);
     }
   if(emptyId != 0) return 1;
   return st;
  }

int  g_deployTries[4] = {0, 0, 0, 0};
bool g_deployWarned[4] = {false, false, false, false};

// pasang 9algo ke market lain: pakai chart yang sudah terbuka tapi kosong, atau buka chart baru.
// Dipanggil saat init dan diulang tiap 60 detik oleh leader sampai semua market terpasang (maks 5x per market).
void AutoDeploy()
  {
   string tpl = "9algo_auto";
   if(!ChartSaveTemplate(0, tpl))
     {
      Print("9algo: gagal simpan template auto (err ", GetLastError(), "), auto deploy dilewati");
      return;
     }
   ENUM_MARKET mk[4] = { MKT_GOLD, MKT_SILVER, MKT_USDJPY, MKT_NQ };
   for(int k = 0; k < 4; k++)
     {
      if(mk[k] == g_market) continue;
      long emptyId = 0;
      int st = ChartStateFor(mk[k], emptyId);
      if(st == 2) { g_deployTries[k] = 0; continue; }                 // sudah jalan
      if(st == 3)
        {
         if(!g_deployWarned[k]) { Print("9algo: chart ", MarketKey(mk[k]), " sudah dipakai EA lain, tidak disentuh"); g_deployWarned[k] = true; }
         continue;
        }
      if(g_deployTries[k] >= 5)
        {
         if(!g_deployWarned[k]) { Notify("Auto-deploy " + MarketKey(mk[k]) + " gagal 5x. Pasang 9algo manual di chart itu dan cek tab Experts."); g_deployWarned[k] = true; }
         continue;
        }
      g_deployTries[k]++;
      long id = emptyId;
      string sym = "";
      if(id == 0)
        {
         sym = FindSymbolFor(mk[k]);
         if(sym == "") { g_deployTries[k] = 5; g_deployWarned[k] = true; Print("9algo: simbol ", MarketKey(mk[k]), " tidak ada di broker, dilewati"); continue; }
         SymbolSelect(sym, true);
         id = ChartOpen(sym, AutoChartPeriod);
         if(id == 0) { Print("9algo: gagal buka chart ", sym, " (err ", GetLastError(), ")"); continue; }
        }
      else sym = ChartSymbol(id);
      // pastikan history simbol termuat dulu (indeks sering lambat) supaya template tidak gagal diam-diam
      for(int w = 0; w < 10 && Bars(sym, AutoChartPeriod) < 100; w++) Sleep(200);
      if(!ChartApplyTemplate(id, tpl))
         Print("9algo: gagal pasang template ke ", sym, " (err ", GetLastError(), "), dicoba lagi 60 detik");
      else
         Print("9algo: dipasang otomatis di ", sym, emptyId != 0 ? " (chart yang sudah terbuka)" : " (chart baru)", " percobaan ", g_deployTries[k]);
     }
  }

//+------------------------------------------------------------------+
//| Registrasi strategi per market                                   |
//+------------------------------------------------------------------+
void AddStrat(CStrat *s, string t, bool o, long m, int mc, double r, int kind = 0, string key = "")
  {
   if(key != "" && !RoleAllows(g_role, key)) o = false;
   s.Setup(t, o, m, mc, r);
   s.kind = kind;
   int n = ArraySize(g_s);
   ArrayResize(g_s, n + 1);
   g_s[n] = s;
  }

void BuildStrategies()
  {
   // semua magic didaftarkan (untuk hitung risk account-wide), tapi hanya
   // strategi di market chart ini yang dimasukkan ke g_s dan dijalankan
   switch(g_market)
     {
      case MKT_GOLD:
         AddStrat(new CNoiseMomentum(true), "Noise-AU", NMG_On, NMG_Magic, 2, NMG_Risk, 0, "NMG");
         AddStrat(new CS009(false),         "Narrow-AU", S009_On, S009_Magic, 1, S009_Risk, 0, "S009");
         AddStrat(new CS015(),              "Week-AU", S015_On, S015_Magic, 1, S015_Risk, 0, "S015");
         AddStrat(new CS017(),              "Round-AU", S017_On, S017_Magic, 1, S017_Risk, 0, "S017");
         AddStrat(new CS018(),              "BigDay-AU", S018G_On, S018G_Magic, 1, S018G_Risk, 1, "S018G");
         RegisterMagic(S018S_Magic, 1); RegisterMagic(B8_Magic, 1); RegisterMagic(S009U_Magic, 1); RegisterMagic(NMN_Magic, 2);
         break;
      case MKT_SILVER:
         AddStrat(new CS018(), "BigDay-AG", S018S_On, S018S_Magic, 1, S018S_Risk, 1, "S018S");
         RegisterMagic(NMG_Magic, 2); RegisterMagic(S009_Magic, 1); RegisterMagic(S015_Magic, 1); RegisterMagic(S017_Magic, 1);
         RegisterMagic(S018G_Magic, 1); RegisterMagic(B8_Magic, 1); RegisterMagic(S009U_Magic, 1); RegisterMagic(NMN_Magic, 2);
         break;
      case MKT_USDJPY:
         AddStrat(new CB8(),       "Tokyo-JPY", B8_On, B8_Magic, 1, B8_Risk, 0, "B8");
         AddStrat(new CS009(true), "Narrow-JPY", S009U_On, S009U_Magic, 1, S009U_Risk, 0, "S009U");
         RegisterMagic(NMG_Magic, 2); RegisterMagic(S009_Magic, 1); RegisterMagic(S015_Magic, 1); RegisterMagic(S017_Magic, 1);
         RegisterMagic(S018G_Magic, 1); RegisterMagic(S018S_Magic, 1); RegisterMagic(NMN_Magic, 2);
         break;
      case MKT_NQ:
         AddStrat(new CNoiseMomentum(false), "Noise-NQ", NMN_On, NMN_Magic, 2, NMN_Risk, 0, "NMN");
         RegisterMagic(NMG_Magic, 2); RegisterMagic(S009_Magic, 1); RegisterMagic(S015_Magic, 1); RegisterMagic(S017_Magic, 1);
         RegisterMagic(S018G_Magic, 1); RegisterMagic(S018S_Magic, 1); RegisterMagic(B8_Magic, 1); RegisterMagic(S009U_Magic, 1);
         break;
      default:
         break;
     }
  }

//+------------------------------------------------------------------+
// UsePresetTerbaru=false -> pakai nilai yang diisi di jendela input chart; true -> nilai rekomendasi bawaan versi ini
// nilai efektif di-set ulang tiap init (global tidak selalu di-reset MT5 saat ganti input/TF)
// UsePresetTerbaru=true -> rekomendasi bawaan versi ini; false -> nilai di jendela input chart
void ApplyPresetMode()
  {
   RiskMode = UsePresetTerbaru ? (ENUM_RISK_MODE)(NonCompounding_PercentOfInitialBalance) : I_RiskMode;
   PropMaxDailyLossMoney = UsePresetTerbaru ? (double)(0) : I_PropMaxDailyLossMoney;
   PropMaxDailyLossPct = UsePresetTerbaru ? (double)(5.0) : I_PropMaxDailyLossPct;
   DailyLossBase = UsePresetTerbaru ? (ENUM_DAILY_BASE)(DailyBase_StartOfDay) : I_DailyLossBase;
   DailyResetHourUTC = UsePresetTerbaru ? (int)(-1) : I_DailyResetHourUTC;
   PropMaxLossMoney = UsePresetTerbaru ? (double)(0) : I_PropMaxLossMoney;
   PropMaxLossPct = UsePresetTerbaru ? (double)(10.0) : I_PropMaxLossPct;
   MaxLossMode = UsePresetTerbaru ? (ENUM_MAXLOSS)(MaxLoss_StaticFromInitial) : I_MaxLossMode;
   TrailingFloorCapAtInitial = UsePresetTerbaru ? (bool)(true) : I_TrailingFloorCapAtInitial;
   GuardFraction = UsePresetTerbaru ? (double)(0.80) : I_GuardFraction;
   CloseAllOnGuard = UsePresetTerbaru ? (bool)(true) : I_CloseAllOnGuard;
   MaxTotalOpenRiskPct = UsePresetTerbaru ? (double)(2.5) : I_MaxTotalOpenRiskPct;
   RiskScale = UsePresetTerbaru ? (double)(1.0) : I_RiskScale;
   MinLotFallback = UsePresetTerbaru ? (bool)(true) : I_MinLotFallback;
   MinLotMaxRiskPct = UsePresetTerbaru ? (double)(0.75) : I_MinLotMaxRiskPct;
   MinLotMaxRiskFastPct = UsePresetTerbaru ? (double)(2.0) : I_MinLotMaxRiskFastPct;
   StopEntriesAtProfitPct = UsePresetTerbaru ? (double)(0) : I_StopEntriesAtProfitPct;
   DailyProfitLockPct = UsePresetTerbaru ? (double)(0) : I_DailyProfitLockPct;
   CloseBeforeWeekend = UsePresetTerbaru ? (bool)(false) : I_CloseBeforeWeekend;
   WeekendCloseNYMin = UsePresetTerbaru ? (int)(16 * 60 + 45) : I_WeekendCloseNYMin;
   NewsFilter = UsePresetTerbaru ? (bool)(true) : I_NewsFilter;
   NewsBeforeMin = UsePresetTerbaru ? (int)(60) : I_NewsBeforeMin;
   NewsAfterMin = UsePresetTerbaru ? (int)(60) : I_NewsAfterMin;
   NewsImportance = UsePresetTerbaru ? (ENUM_NEWS_IMP)(News_HighOnly) : I_NewsImportance;
   NewsClosePositions = UsePresetTerbaru ? (bool)(false) : I_NewsClosePositions;
   NewsHardMin = UsePresetTerbaru ? (int)(3) : I_NewsHardMin;
   ConsistencyGuard = UsePresetTerbaru ? (bool)(true) : I_ConsistencyGuard;
   ConsistencyMaxPct = UsePresetTerbaru ? (double)(40.0) : I_ConsistencyMaxPct;
   ConsistencySafety = UsePresetTerbaru ? (double)(0.85) : I_ConsistencySafety;
   LotConsistency = UsePresetTerbaru ? (bool)(false) : I_LotConsistency;
   LotConsistencyPct = UsePresetTerbaru ? (double)(50.0) : I_LotConsistencyPct;
   NetOfCommission = UsePresetTerbaru ? (bool)(true) : I_NetOfCommission;
   RegimeFilter = UsePresetTerbaru ? (bool)(false) : I_RegimeFilter;
   RegimeTrendMin = UsePresetTerbaru ? (double)(0.55) : I_RegimeTrendMin;
   RegimeChopMin = UsePresetTerbaru ? (double)(0.55) : I_RegimeChopMin;
   ChallengeSteps = UsePresetTerbaru ? (int)(2) : I_ChallengeSteps;
   VerificationGoalPct = UsePresetTerbaru ? (double)(5.0) : I_VerificationGoalPct;
   ChallengeMode = UsePresetTerbaru ? (bool)(true) : I_ChallengeMode;
   ChallengeStyle = UsePresetTerbaru ? (ENUM_CSTYLE)(Style_Fast) : I_ChallengeStyle;
   FastRiskPct = UsePresetTerbaru ? (double)(1.0) : I_FastRiskPct;
   FastOpenRiskPct = UsePresetTerbaru ? (double)(3.5) : I_FastOpenRiskPct;
   FastDirCapPct = UsePresetTerbaru ? (double)(2.0) : I_FastDirCapPct;
   TargetDays = UsePresetTerbaru ? (int)(14) : I_TargetDays;
   MaxRiskScaleAuto = UsePresetTerbaru ? (double)(3.0) : I_MaxRiskScaleAuto;
   PhaseRiskA = UsePresetTerbaru ? (double)(1.5) : I_PhaseRiskA;
   PhaseRiskB = UsePresetTerbaru ? (double)(1.0) : I_PhaseRiskB;
   PhaseRiskC = UsePresetTerbaru ? (double)(0.5) : I_PhaseRiskC;
   CushionK = UsePresetTerbaru ? (double)(8.0) : I_CushionK;
   ProgressLock = UsePresetTerbaru ? (bool)(true) : I_ProgressLock;
   ProgressLockStepPct = UsePresetTerbaru ? (double)(2.5) : I_ProgressLockStepPct;
   DirectionalCapPct = UsePresetTerbaru ? (double)(1.2) : I_DirectionalCapPct;
   SpreadFilter = UsePresetTerbaru ? (bool)(true) : I_SpreadFilter;
   SpreadMaxMult = UsePresetTerbaru ? (double)(2.0) : I_SpreadMaxMult;
   AutoPauseNegative = UsePresetTerbaru ? (bool)(true) : I_AutoPauseNegative;
   AutoPauseMinTrades = UsePresetTerbaru ? (int)(15) : I_AutoPauseMinTrades;
   FundedRiskScale = UsePresetTerbaru ? (double)(0.6) : I_FundedRiskScale;
   AutoRole = UsePresetTerbaru ? (bool)(true) : I_AutoRole;
   GroupHedgeGuard = UsePresetTerbaru ? (bool)(true) : I_GroupHedgeGuard;
   VirtualPending = UsePresetTerbaru ? (bool)(true) : I_VirtualPending;
   ArmDistADR = UsePresetTerbaru ? (double)(0.25) : I_ArmDistADR;
   DisarmDistADR = UsePresetTerbaru ? (double)(0.60) : I_DisarmDistADR;
   LateFillADR = UsePresetTerbaru ? (double)(0.10) : I_LateFillADR;
   ProfitGoalMoney = UsePresetTerbaru ? (double)(0) : I_ProfitGoalMoney;
   ProfitGoalPct = UsePresetTerbaru ? (double)(10.0) : I_ProfitGoalPct;
   MinProfitableDays = UsePresetTerbaru ? (int)(3) : I_MinProfitableDays;
   ProfitableDayMinPct = UsePresetTerbaru ? (double)(0.5) : I_ProfitableDayMinPct;
   InactivityDays = UsePresetTerbaru ? (int)(30) : I_InactivityDays;
   NMG_On = UsePresetTerbaru ? (bool)(true) : I_NMG_On;
   NMG_Risk = UsePresetTerbaru ? (double)(0.18) : I_NMG_Risk;
   S009_On = UsePresetTerbaru ? (bool)(true) : I_S009_On;
   S009_Risk = UsePresetTerbaru ? (double)(0.32) : I_S009_Risk;
   S015_On = UsePresetTerbaru ? (bool)(true) : I_S015_On;
   S015_Risk = UsePresetTerbaru ? (double)(0.20) : I_S015_Risk;
   S017_On = UsePresetTerbaru ? (bool)(true) : I_S017_On;
   S017_Risk = UsePresetTerbaru ? (double)(0.27) : I_S017_Risk;
   S018G_On = UsePresetTerbaru ? (bool)(true) : I_S018G_On;
   S018G_Risk = UsePresetTerbaru ? (double)(0.18) : I_S018G_Risk;
   S018S_On = UsePresetTerbaru ? (bool)(true) : I_S018S_On;
   S018S_Risk = UsePresetTerbaru ? (double)(0.32) : I_S018S_Risk;
   B8_On = UsePresetTerbaru ? (bool)(true) : I_B8_On;
   B8_Risk = UsePresetTerbaru ? (double)(0.23) : I_B8_Risk;
   S009U_On = UsePresetTerbaru ? (bool)(true) : I_S009U_On;
   S009U_Risk = UsePresetTerbaru ? (double)(0.26) : I_S009U_Risk;
   NMN_On = UsePresetTerbaru ? (bool)(true) : I_NMN_On;
   NMN_Risk = UsePresetTerbaru ? (double)(0.15) : I_NMN_Risk;
  }

int OnInit()
  {
   ApplyPresetMode();
   // --- validasi input (zero divide / nilai tidak masuk akal -> tolak dengan pesan jelas)
   if(RiskScale <= 0 || FastRiskPct <= 0 || GuardFraction <= 0 || GuardFraction > 1 || FundedRiskScale <= 0 ||
      DailyResetHourUTC < -1 || DailyResetHourUTC > 23 || ChallengeSteps < 1 || ChallengeSteps > 2)
     {
      Print("9algo: input tidak valid (RiskScale/FastRiskPct/FundedRiskScale > 0; GuardFraction 0..1; DailyResetHourUTC -1..23; ChallengeSteps 1/2).");
      return INIT_PARAMETERS_INCORRECT;
     }
   // --- reset state di memori (OnInit bisa dipanggil ulang tanpa global di-reset: ganti TF/simbol/input)
   g_onnxTried = false; g_hwm = 0; g_progFloor = 0; g_statsFrom = 0; g_haltGoal = false; g_haltDaily = false;
   g_haltTotal = false; g_haltActed = false; g_spreadAvg = 0; g_guardDay = 0; g_closeLearnDay = -1; g_closeRetryAt = 0;
   g_phaseEpoch = -1; g_manualSeen = -99; g_regimeDay = 0; g_newsFetch = 0; g_pTrend = 0.5;
   ArrayResize(g_mgBase, 0); ArrayResize(g_mgCount, 0);
   for(int k = 0; k < 4; k++) { g_deployTries[k] = 0; g_deployWarned[k] = false; }
   g_deployUntil = TimeLocal() + 1800;
   string rdn = GVP() + "RESETDONE";
   if(ResetGuardState && (!GlobalVariableCheck(rdn) || TimeLocal() - (datetime)GlobalVariableGet(rdn) > 600))
     {
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
        {
         string n = GlobalVariableName(i);
         if(StringFind(n, GVP()) == 0 && n != GVP() + "PHASE_EPOCH" && n != GVP() + "ROLE" && n != GVP() + "CAPLOCK") GlobalVariableDel(n);
        }
      GlobalVariableSet(rdn, (double)TimeLocal());
      string ep = GVP() + "PHASE_EPOCH";
      GlobalVariableSet(ep, (GlobalVariableCheck(ep) ? GlobalVariableGet(ep) : 0) + 1);   // chart lain ikut reset lokal
      Print("9algo: semua state guard dihapus (ResetGuardState=true). Set kembali ke false.");
     }
   DetectMarket();
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tick <= 0)
      g_tick = g_point;
   g_initBal = AutoInitialBalance();
   if(InitialBalance <= 0)
      Print("9algo: InitialBalance=0 -> saldo awal otomatis = ", DoubleToString(g_initBal, 0), " (balance ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 0), "). Cek cocok dengan dashboard firm.");
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(DeviationPts());
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   DetectTimeZone(_Symbol);
   for(int i = 0; i < 7; i++)
      g_closeMin[i] = 24 * 60;
   LearnSessionClose();

   // fingerprint saldo awal: kalau InitialBalance berubah, state lama (HWM, halt, hari) tidak valid -> reset otomatis
   string fp = GVP() + "INITBAL";
   if(!GlobalVariableCheck(fp) || MathAbs(GlobalVariableGet(fp) - g_initBal) > 0.5)
     {
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
        {
         string n = GlobalVariableName(i);
         if(StringFind(n, GVP()) == 0 && StringFind(n, GVP() + "PAUSE_") != 0 && n != GVP() + "ROLE" && StringFind(n, GVP() + "PHASE_MANUAL") != 0 &&
            n != GVP() + "PHASE_EPOCH" && n != GVP() + "RESETDONE" && n != GVP() + "DEPLOYLOCK" && n != GVP() + "CAPLOCK") GlobalVariableDel(n);
        }
      Print("9algo: saldo awal ", DoubleToString(g_initBal, 0), " belum cocok dengan state tersimpan -> state guard di-reset otomatis");
     }
   GlobalVariableSet(fp, g_initBal);
   g_haltTotal = GlobalVariableCheck(GVP() + "HALTTOTAL");
   if(g_haltTotal)
      g_guardWhy = "Max Loss flag aktif (tombol RESET HALT di panel)";

   PhaseInit();
   ZeroConfigInit();
   BuildStrategies();
   for(int i = 0; i < ArraySize(g_s); i++)
      if(g_s[i].on)
         g_s[i].Init();

   g_guardDay = 0;
   VoLoad();                 // sebelum guard: kalau guard halt, antrean ikut dibersihkan
   GuardUpdate(TimeCurrent());
   ComputeStats(TimeCurrent());
   DrawPanel();
   if(AutoDeployOtherCharts && g_marketMatch && !MQLInfoInteger(MQL_TESTER) && IsLeader())
     {
      string lk = GVP() + "DEPLOYLOCK";
      if(!GlobalVariableCheck(lk) || TimeLocal() - (datetime)GlobalVariableGet(lk) > 120)
        {
         GlobalVariableSet(lk, (double)TimeLocal());
         AutoDeploy();
        }
     }
   ApplyChartStyle();
   EventSetTimer(5);   // panel, guard, news, export tetap jalan walau tidak ada tick (market tutup)
   return INIT_SUCCEEDED;
  }

string VoFile()
  {
   string sy = _Symbol;
   string bad[] = {"/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "};
   for(int i = 0; i < ArraySize(bad); i++) StringReplace(sy, bad[i], "_");
   return "9algo\\vo_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + sy + ".csv";
  }

void VoSave()
  {
   if(!g_voDirty || MQLInfoInteger(MQL_TESTER)) return;
   int h = FileOpen(VoFile(), FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
   if(h == INVALID_HANDLE) return;                    // dirty tetap true -> dicoba lagi
   FileWrite(h, "9AVO2");                             // versi format
   for(int i = 0; i < ArraySize(g_vo); i++)
      FileWrite(h, g_vo[i].magic, g_vo[i].type, DoubleToString(g_vo[i].lots, 2), DoubleToString(g_vo[i].price, g_digits), DoubleToString(g_vo[i].sl, g_digits),
                DoubleToString(g_vo[i].tp, g_digits), DoubleToString(g_vo[i].rdist, g_digits), DoubleToString(g_vo[i].rpct, 4), (long)g_vo[i].expAt, (long)g_vo[i].tk,
                (long)g_vo[i].created, g_vo[i].cmt);
   FileClose(h);
   g_voDirty = false;
  }

// ada entry (posisi dibuka) untuk magic ini di simbol ini sejak waktu t?
bool EntrySince(long magic, datetime t)
  {
   if(t <= 0 || !HistorySelect(t - 60, TimeCurrent() + 60)) return false;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetInteger(d, DEAL_MAGIC) != magic || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN && (datetime)HistoryDealGetInteger(d, DEAL_TIME) >= t) return true;
     }
   return false;
  }

// order asli milik magic+tipe ini yang sudah ada di broker (mis. kirim sebelumnya timeout tapi sebenarnya masuk)
ulong FindRealOrder(long magic, int type)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != magic) continue;
      if((int)OrderGetInteger(ORDER_TYPE) == type) return tk;
     }
   return 0;
  }

void VoLoad()
  {
   ArrayResize(g_vo, 0);
   if(MQLInfoInteger(MQL_TESTER) || !FileIsExist(VoFile())) return;
   int h = FileOpen(VoFile(), FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
   if(h == INVALID_HANDLE) return;
   datetime now = TimeCurrent();
   if(FileReadString(h) != "9AVO2") { FileClose(h); g_voDirty = true; return; }   // format lama -> abaikan, ditulis ulang
   long gone[]; int ng = 0;                            // magic yang sudah entry selama EA mati -> semua saudaranya dibuang
   while(!FileIsEnding(h))
     {
      VOrd v;
      v.magic = StringToInteger(FileReadString(h)); v.type = (int)StringToInteger(FileReadString(h));
      v.lots = StringToDouble(FileReadString(h)); v.price = StringToDouble(FileReadString(h)); v.sl = StringToDouble(FileReadString(h));
      v.tp = StringToDouble(FileReadString(h)); v.rdist = StringToDouble(FileReadString(h)); v.rpct = StringToDouble(FileReadString(h));
      v.expAt = (datetime)StringToInteger(FileReadString(h)); v.tk = (ulong)StringToInteger(FileReadString(h));
      v.created = (datetime)StringToInteger(FileReadString(h)); v.cmt = FileReadString(h);
      v.lastTry = 0; v.armedAt = now; v.why = "";
      if(v.magic <= 0 || v.price <= 0 || v.expAt <= now) continue;
      if(CountPositions(v.magic) > 0 || EntrySince(v.magic, v.created))
        { ArrayResize(gone, ng + 1); gone[ng++] = v.magic; continue; }
      if(v.tk > 0 && !OrderSelect(v.tk))
        {
         ulong t2 = FindRealOrder(v.magic, v.type);
         if(t2 > 0) v.tk = t2;
         else if(HistoryOrderSelect(v.tk))
           {
            // order sudah selesai saat EA mati: terisi -> buang semua saudaranya; batal/kedaluwarsa -> buang entri ini saja
            if(HistoryOrderGetInteger(v.tk, ORDER_STATE) == ORDER_STATE_FILLED) { ArrayResize(gone, ng + 1); gone[ng++] = v.magic; }
            continue;
           }
         // belum terlihat (terminal baru start, order belum sinkron): simpan, VoProcess yang memutuskan setelah jeda
        }
      int n = ArraySize(g_vo); ArrayResize(g_vo, n + 1); g_vo[n] = v;
     }
   FileClose(h);
   for(int k = 0; k < ng; k++)
      for(int i = ArraySize(g_vo) - 1; i >= 0; i--)
         if(g_vo[i].magic == gone[k])
           {
            if(g_vo[i].tk > 0 && OrderSelect(g_vo[i].tk)) g_trade.OrderDelete(g_vo[i].tk);
            VoRemove(i);
           }
   g_voDirty = true;
  }

int StratOfMagic(long m)
  {
   for(int i = 0; i < ArraySize(g_s); i++) if(g_s[i].Mine(m)) return i;
   return -1;
  }

// alasan entry sedang diblokir (order asli yang sudah di broker ditarik lagi ke antrean)
string VoBlockWhy(int si)
  {
   if(EntriesBlocked())
     {
      string r = BlockReason();
      if(!(r == "news window" && g_phase != Phase_Funded)) return r;   // challenge: order yang sudah terpasang tetap dibiarkan saat news
     }
   if(g_s[si].paused) return "di-pause dari panel";
   if(g_s[si].autoPaused) return "auto-pause";
   if(SpreadFilter && g_spreadAvg > 0 && (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > SpreadMaxMult * g_spreadAvg) return "spread melebar";
   return "";
  }

// Inti antrean: setup siaga dipasang jadi order asli hanya kalau harga sudah dekat (paling dekat = duluan)
// dan semua rule lolos saat itu (guard, news, spread, cap total risk, cap arah, anti-hedge grup).
// Budget penuh -> tetap siaga (antre) dan dicoba lagi. Harga menjauh / entry diblokir -> order asli ditarik, budget dilepas.
void VoProcess()
  {
   if(ArraySize(g_vo) == 0) { VoSave(); return; }
   datetime now = TimeCurrent();
   double adr = ChartADR();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return;
   if(adr <= 0) adr = 0.01 * 0.5 * (ask + bid);
   int n = ArraySize(g_vo);
   int ord[]; double dd[];
   ArrayResize(ord, n); ArrayResize(dd, n);
   for(int i = 0; i < n; i++)
     {
      bool buy = g_vo[i].type == ORDER_TYPE_BUY_STOP || g_vo[i].type == ORDER_TYPE_BUY_LIMIT;
      dd[i] = MathAbs(g_vo[i].price - (buy ? ask : bid));
      ord[i] = i;
     }
   for(int a = 1; a < n; a++)                         // terdekat dulu
     {
      int k = ord[a], b = a - 1;
      while(b >= 0 && dd[ord[b]] > dd[k]) { ord[b + 1] = ord[b]; b--; }
      ord[b + 1] = k;
     }
   long dropMg[]; int dropTy[]; int nd = 0;
   ArrayResize(dropMg, n); ArrayResize(dropTy, n);
   for(int a = 0; a < n; a++)
     {
      int i = ord[a];
      VOrd v = g_vo[i];
      bool buy = v.type == ORDER_TYPE_BUY_STOP || v.type == ORDER_TYPE_BUY_LIMIT;
      bool stop = v.type == ORDER_TYPE_BUY_STOP || v.type == ORDER_TYPE_SELL_STOP;
      double ref = buy ? ask : bid;
      int si = StratOfMagic(v.magic);
      bool drop = false;
      if(si < 0 || !g_s[si].on || CountPositions(v.magic) > 0) drop = true;   // strategi mati / sisi OCO lain sudah terisi
      else if(v.tk > 0)
        {
         if(!OrderSelect(v.tk))
           {
            // hilang dari daftar order: terisi / kedaluwarsa / dihapus. Beri jeda 15 dtk (cache terminal) sebelum dilepas
            if(now - v.armedAt > 15 || HistoryOrderSelect(v.tk)) drop = true;
           }
         else
           {
            string bw = VoBlockWhy(si);
            bool far = dd[i] > DisarmDistADR * adr && now - v.armedAt > 300;
            if(bw != "" || far)
              {
               if(g_trade.OrderDelete(v.tk)) { g_vo[i].tk = 0; g_vo[i].why = bw != "" ? "ditarik: " + bw : ""; g_voDirty = true; }
              }
           }
        }
      else if(now >= v.expAt) drop = true;
      else if(now - v.lastTry >= 10)
        {
         g_vo[i].lastTry = now;
         bool trig = stop ? (buy ? ask >= v.price : bid <= v.price) : (buy ? ask <= v.price : bid >= v.price);
         if(trig || dd[i] <= ArmDistADR * adr)
           {
            if(EntrySince(v.magic, v.created)) { drop = true; }                      // sudah pernah entry hari ini (OCO / restart)
            else
              {
               ulong ex = FindRealOrder(v.magic, v.type);
               if(ex > 0) { g_vo[i].tk = ex; g_vo[i].armedAt = now; g_vo[i].why = ""; g_voDirty = true; }   // adopsi, jangan kirim dobel
               else
                 {
                  g_curPaused = g_s[si].paused; g_curAuto = g_s[si].autoPaused; g_curTrades = g_s[si].stTrades; g_curNet = g_s[si].stNet;
                  g_curVirt = false; g_armCtx = true; g_dirWhy = "";
                  if(trig)
                    {
                     // stop: harga sudah melewati entry; limit: harga sudah lebih baik dari entry
                     double beyond = stop ? (buy ? ref - v.price : v.price - ref) : (buy ? v.price - ref : ref - v.price);
                     double slRef = buy ? bid : ask;                                       // SL buy kena di bid, SL sell kena di ask
                     bool slHit = v.sl > 0 && (buy ? slRef <= v.sl : slRef >= v.sl);
                     if(beyond > LateFillADR * adr || slHit)
                       { drop = true; g_s[si].why = "terlewat: harga lompat melewati entry"; g_s[si].Missed(v.type); }
                     else
                       {
                        long cm = g_capMagic; g_capMagic = v.magic;      // sisi OCO lain akan dihapus saat terisi
                        double lots = LotsFor(MathMax(v.rdist, MathAbs(ref - v.sl)), v.rpct);
                        bool okm = lots > 0 && SendMarket(v.magic, buy ? 1 : -1, lots, v.sl, v.tp, v.cmt);
                        g_capMagic = cm;
                        if(okm) { drop = true; g_s[si].Missed(v.type); }                // sudah masuk; strategi jangan kirim lagi
                        else g_vo[i].why = "antre: " + (g_dirWhy != "" ? g_dirWhy : (g_lotWhy != "" ? g_lotWhy : g_trade.ResultRetcodeDescription()));
                       }
                    }
                  else
                    {
                     long cm = g_capMagic; g_capMagic = v.magic;
                     double lots = LotsFor(v.rdist, v.rpct);
                     g_capMagic = cm;
                     if(lots > 0 && SendPendingReal(v.magic, (ENUM_ORDER_TYPE)v.type, lots, v.price, v.sl, v.tp, v.expAt, v.cmt))
                       {
                        ulong t = g_trade.ResultOrder();
                        if(t == 0) t = FindRealOrder(v.magic, v.type);
                        g_vo[i].tk = t; g_vo[i].armedAt = now; g_vo[i].why = ""; g_voDirty = true;
                       }
                     else g_vo[i].why = "antre: " + (g_dirWhy != "" ? g_dirWhy : (g_lotWhy != "" ? g_lotWhy : g_trade.ResultRetcodeDescription()));
                    }
                  g_armCtx = false; g_curPaused = false; g_curAuto = false; g_dirWhy = "";
                 }
              }
           }
         else if(StringFind(v.why, "ditarik") != 0) g_vo[i].why = "";
        }
      if(drop)
        {
         if(g_vo[i].tk > 0 && OrderSelect(g_vo[i].tk)) g_trade.OrderDelete(g_vo[i].tk);
         dropMg[nd] = v.magic; dropTy[nd] = v.type; nd++;
        }
     }
   for(int k = 0; k < nd; k++)
     {
      int i = VoFind(dropMg[k], dropTy[k]);
      if(i >= 0) VoRemove(i);
     }
   VoSave();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_voDirty = true;
   VoSave();
   DeletePanel();
   ObjectsDeleteAll(0, "9AL_");
   if(g_onnx != INVALID_HANDLE) { OnnxRelease(g_onnx); g_onnx = INVALID_HANDLE; }
   for(int i = 0; i < ArraySize(g_s); i++)
      if(CheckPointer(g_s[i]) == POINTER_DYNAMIC)
         delete g_s[i];
   ArrayResize(g_s, 0);
  }

void OnTimer()
  {
   MaintainCommon();
   VoProcess();
  }

void OnTick()
  {
   MaintainCommon();
   datetime now = TimeCurrent();
   for(int i = 0; i < ArraySize(g_s); i++)
      if(g_s[i].on)
        {
         g_curPaused = g_s[i].paused;
         g_curAuto = g_s[i].autoPaused; g_curTrades = g_s[i].stTrades; g_curNet = g_s[i].stNet;
         g_curVirt = g_s[i].pend;
         g_dirWhy = "";
         g_s[i].Tick(now);
         if(g_dirWhy != "" && StringFind(g_s[i].why, "tertunda") != 0) g_s[i].why = (g_s[i].pend ? "tertunda: " : "") + g_dirWhy;
        }
   g_curPaused = false; g_curAuto = false; g_curVirt = false;
   VoProcess();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BALANCE)
     {
      PhaseProgressCheck();
      g_panelCheck = 0;
      return;
     }
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   long mg = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   for(int i = 0; i < ArraySize(g_s); i++)
      if(g_s[i].on && g_s[i].Mine(mg))
        {
         g_s[i].OnDeal(trans.deal);
         long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         string side = HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY ? "BUY" : "SELL";
         if(entry == DEAL_ENTRY_IN)
            NotifyTrade(g_s[i].tag + " " + side + " " + DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), 2) + " @ " + DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), g_digits));
         else
            NotifyTrade(g_s[i].tag + " close P/L " + DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION), 2));
         g_panelCheck = 0;
        }
  }
//+------------------------------------------------------------------+
