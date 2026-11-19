//+------------------------------------------------------------------+
//| 10algo.mq5                                                       |
//| Algoritma: A10 London Auction v1.23 (Trade By Data) - TIDAK diubah |
//| Tambahan 10algo: panel, tombol, statistik, lot risiko, rem lapis, |
//| statistik, garis jendela, status JSON untuk 9algo_sync.          |
//+------------------------------------------------------------------+
#property version   "1.13"
#property description "10algo - London Auction XAUUSD (algoritma A10 v1.23) dengan panel"

#include <Trade/Trade.mqh>

input long   InpMagic  = 261114;
input double InpLotLapis = 0.5;   // Lot per lapis TETAP (dipakai hanya jika InpRisiko = 0)
input string InpSymbol = "";

input group "=== 10algo: lot & pengaman (v1.13) ==="
input double InpRisiko     = 2.0;   // Lot dari saldo & U: 1U per lapis = X% saldo (compounding + ikut U). 0 = pakai InpLotLapis
input double InpLonjakanU  = 3.0;   // Pengaman A: lewati hari jika harga 10:20 London >= harga 09:00 + X U. 0 = mati
input double InpSLU        = 1.5;   // Pengaman B: SL per lapis dalam U (A10 asli 3.0)
input int    InpRezimHari  = 40;    // Pengaman C: istirahat jika jumlah hasil bayangan N hari aktif terakhir < 0. 0 = mati

input group "=== 10algo: tampilan ==="
input int    InpPanelX               = 10;        // Posisi panel X
input int    InpPanelY               = 26;        // Posisi panel Y
input double InpPanelScale           = 0.0;       // Skala panel (0 = otomatis ikut DPI layar; mis. 0.85 = lebih kecil)
input bool   InpTheme                = true;      // Tema chart gelap ala 9algo
input bool   InpDrawWindow           = true;      // Garis jendela 10:20 / 10:31 London di chart
input int    InpLocalUTCOffset       = 7;         // Jam lokal di panel: selisih dari UTC (WIB = 7, WITA = 8, WIT = 9)
input string InpLocalName            = "WIB";     // Nama jam lokal di panel
input bool   InpWriteState           = true;      // Tulis status JSON ke Common\Files\9algo (dibaca 9algo_sync)

const int    A10_LAYERS        = 10;
const double A10_TP_U          = 0.3;
const double A10_SL_U          = 3.0;
const double A10_MAX_COST_U    = 0.0597;
const int    A10_SWITCH_DAYS   = 120;
const int    A10_SWITCH_MIN    = 96;
const double A10_SWITCH_THRESH = 0.20;
const int    A10_SWITCH_SPAN   = 220;
const bool   A10_ASYNC_CLOSE   = true;
const int    A10_CLOSE_RETRY   = 20;
const int    A10_ENTRY_RETRY   = 2;
const int    A10_TZ_SCAN_DAYS  = 260;
const int    T_MULAI = 10 * 60 + 20;
const int    T_TUTUP = 10 * 60 + 31;

CTrade   trade;
double   g_lots     = 0.0;
bool     g_fatal    = false;
string   g_fatalMsg = "";
bool     g_manualSym = false;
int      g_ymd      = 0;
bool     g_prepared = false;
bool     g_active   = false;
int      g_layers   = 0;
int      g_lastMin  = -1;
int      g_tryMin   = -1;
int      g_tryCnt   = 0;
double   g_switch   = 0.0;
int      g_switchN  = 0;
double   g_u        = 0.0;
double   g_cost     = 0.0;
double   g_kom      = 0.0;
bool     g_komKnown = false;
string   g_dayNote  = "menunggu 10:20 London";
ulong    g_closeTk[];
datetime g_closeAt[];
ulong    g_vtTk[];
double   g_vtTP[];
bool     g_vtPerlu  = true;
datetime g_wkStart[];
int      g_wkOff[];
int      g_wkVotes[];
datetime g_tzScanAt  = 0;
datetime g_tzTryAt   = 0;
int      g_clockOff  = 0;
bool     g_clockOK   = false;
string   g_tzNote    = "jam server belum dikenali";
datetime g_rDay[];
double   g_rVal[];
string   g_rFile = "";
datetime g_lastComment = 0;

datetime g_libur[] = {D'2025.01.01', D'2025.04.18', D'2025.04.21', D'2025.05.05', D'2025.05.26', D'2025.08.25', D'2025.12.25', D'2025.12.26',
                      D'2026.01.01', D'2026.04.03', D'2026.04.06', D'2026.05.04', D'2026.05.25', D'2026.08.31', D'2026.12.25', D'2026.12.28',
                      D'2027.01.01', D'2027.03.26', D'2027.03.29', D'2027.05.03', D'2027.05.31', D'2027.08.30', D'2027.12.27', D'2027.12.28',
                      D'2028.01.03', D'2028.04.14', D'2028.04.17', D'2028.05.01', D'2028.05.29', D'2028.08.28', D'2028.12.25', D'2028.12.26',
                      D'2029.01.01', D'2029.03.30', D'2029.04.02', D'2029.05.07', D'2029.05.28', D'2029.08.27', D'2029.12.25', D'2029.12.26',
                      D'2030.01.01', D'2030.04.19', D'2030.04.22', D'2030.05.06', D'2030.05.27', D'2030.08.26', D'2030.12.25', D'2030.12.26'};

int    g_seedDay[] = {20260501, 20260504, 20260505, 20260506, 20260507, 20260508, 20260511, 20260512, 20260513, 20260514,
                      20260515, 20260518, 20260519, 20260520, 20260521, 20260522, 20260525, 20260526, 20260527, 20260528,
                      20260529, 20260601, 20260602, 20260603, 20260604, 20260605, 20260608, 20260609, 20260610, 20260611,
                      20260612, 20260615, 20260616, 20260617, 20260618, 20260619, 20260622, 20260623, 20260624, 20260625,
                      20260626, 20260629, 20260630, 20260701, 20260702, 20260703, 20260706, 20260707, 20260708, 20260709,
                      20260710, 20260713, 20260714, 20260715, 20260716, 20260717, 20260720, 20260721, 20260722, 20260723,
                      20260724, 20260727, 20260728, 20260729, 20260730, 20260731, 20260803, 20260804, 20260805, 20260806,
                      20260807, 20260810, 20260811, 20260812, 20260813, 20260814, 20260817, 20260818, 20260819, 20260820,
                      20260821, 20260824, 20260825, 20260826, 20260827, 20260828, 20260831, 20260901, 20260902, 20260903,
                      20260904, 20260907, 20260908, 20260909, 20260910, 20260911, 20260914, 20260915, 20260916, 20260917,
                      20260918, 20260921, 20260922, 20260923, 20260924, 20260925, 20260928, 20260929, 20260930, 20261001,
                      20261002, 20261005, 20261006, 20261007, 20261008, 20261009, 20261012, 20261013, 20261014, 20261015,
                      20261016, 20261019, 20261020, 20261021, 20261022, 20261023, 20261026, 20261027, 20261028, 20261029,
                      20261030, 20261102, 20261103, 20261104, 20261105, 20261106, 20261109, 20261110, 20261111, 20261112};
double g_seedVal[] = {-0.142368, -0.104494, 0.261736, 1.079417, -0.511997, -0.681956, -1.237466, 0.487018,
                      0.078179, -0.668233, 0.882149, -1.126634, -0.483119, -0.505925, -0.154444, -0.612061,
                      0.703673, 0.176128, -0.533799, -0.330518, 1.155383, -0.949633, -0.810687, -1.722901,
                      -0.528865, -1.196774, -1.767745, -1.138601, 0.254958, -0.973291, 0.187870, -0.834739,
                      0.130143, 0.689742, -0.546941, -0.654464, -0.604918, -0.258461, -0.776851, 0.127309,
                      -0.060651, -0.266957, -0.563612, -0.002246, -0.793712, -0.587673, -1.446113, -0.452062,
                      -1.299189, -0.060532, 0.084047, -0.286163, -0.862382, -0.325975, -0.179116, -0.257849,
                      -0.888541, -0.808376, -0.547134, -0.870954, -0.528362, -0.540595, -1.128337, -0.584528,
                      -1.185988, 0.107863, -0.637062, -0.156883, -0.421486, -0.436686, -1.018036, -0.889568,
                      -0.280979, -1.517764, 0.295929, 0.277293, -0.274064, -0.054208, 0.280585, -0.178023,
                      -0.724433, -0.364761, -1.091166, -0.162587, 0.053464, -0.145626, 0.508958, -1.421998,
                      -0.159854, 0.326085, 0.149813, -0.774942, -0.288748, -0.065588, -0.333274, -0.479957,
                      -0.085666, 0.340041, 0.880829, -1.027429, -0.902168, -1.200987, -0.799618, -0.117925,
                      -1.181082, -0.269330, -0.463187, -0.025295, 0.489648, 0.133945, 0.675565, -0.695618,
                      -0.012677, -0.423434, -0.320149, -0.038896, -0.643091, -0.723508, -0.088859, 0.469538,
                      -1.351619, -0.440868, -0.924305, 0.637603, -0.598232, -0.194958, -0.258321, -0.413418,
                      -0.275185, -1.116507, -0.552746, -0.182498, -0.266106, -0.524234, -0.053930, 0.483635,
                      -0.737062, -0.854913, 0.163767, -0.631601};

datetime DayStart(datetime t) { return t - (t % 86400); }

datetime NthSunday(int year, int month, int n)
  {
   MqlDateTime s; ZeroMemory(s);
   s.year = year; s.mon = month; s.day = 1;
   datetime t = StructToTime(s);
   MqlDateTime d; TimeToStruct(t, d);
   return t + ((7 - d.day_of_week) % 7 + 7 * (n - 1)) * 86400;
  }

datetime LastSunday(int year, int month)
  {
   MqlDateTime s; ZeroMemory(s);
   s.year = year; s.mon = month; s.day = 31;
   datetime t = StructToTime(s);
   MqlDateTime d; TimeToStruct(t, d);
   return t - d.day_of_week * 86400;
  }

bool IsBST(datetime utc)
  {
   MqlDateTime d; TimeToStruct(utc, d);
   datetime a = LastSunday(d.year, 3) + 3600;
   datetime b = LastSunday(d.year, 10) + 3600;
   return (utc >= a && utc < b);
  }

bool USDSTLocal(datetime nyLocal)
  {
   MqlDateTime d; TimeToStruct(nyLocal, d);
   datetime a = NthSunday(d.year, 3, 2) + 7200;
   datetime b = NthSunday(d.year, 11, 1) + 7200;
   return (nyLocal >= a && nyLocal < b);
  }

bool USDSTUtc(datetime utc)
  {
   MqlDateTime d; TimeToStruct(utc, d);
   datetime a = NthSunday(d.year, 3, 2) + 7 * 3600;
   datetime b = NthSunday(d.year, 11, 1) + 6 * 3600;
   return (utc >= a && utc < b);
  }

datetime LondonFromUTC(datetime utc) { return utc + (IsBST(utc) ? 3600 : 0); }
datetime UTCFromLondon(datetime ldn) { return IsBST(ldn - 3600) ? ldn - 3600 : ldn; }

bool IsUKHoliday(datetime londonDay)
  {
   for(int i = 0; i < ArraySize(g_libur); i++)
      if(g_libur[i] == londonDay)
         return true;
   return false;
  }

bool ScanServerTime()
  {
   datetime to = TimeCurrent();
   if(to <= 0)
      return false;
   datetime t[];
   ArraySetAsSeries(t, false);
   int n = CopyTime(_Symbol, PERIOD_M1, to - (datetime)A10_TZ_SCAN_DAYS * 86400, to, t);
   if(n < 3000)
      return false;
   datetime ss[]; int sg[]; int ns = 0;
   for(int i = 1; i < n; i++)
     {
      long gap = (long)t[i] - (long)t[i - 1];
      if(gap >= 1800)
        {
         ArrayResize(ss, ns + 1, 512); ArrayResize(sg, ns + 1, 512);
         ss[ns] = t[i]; sg[ns] = (int)MathMin(gap, 2000000000); ns++;
        }
     }
   datetime ws[]; int wo[]; int wv[]; int nw = 0;
   int prev = INT_MIN;
   int k = 0;
   while(k < ns)
     {
      if(sg[k] < 40 * 3600) { k++; continue; }
      int kEnd = k + 1;
      while(kEnd < ns && sg[kEnd] < 40 * 3600)
         kEnd++;
      datetime s0 = ss[k];
      MqlDateTime d; TimeToStruct(s0, d);
      long x = (long)d.day_of_week * 86400 + (long)((long)s0 % 86400) - 18 * 3600;
      if(x > 302400)
         x -= 604800;
      long xr = (long)MathRound((double)x / 1800.0) * 1800;
      bool baseOK = (x >= -12 * 3600 && x <= 14 * 3600 && MathAbs(x - xr) <= 1200);
      int ref = (baseOK ? (int)xr : prev);
      int cand[24]; int cnt[24]; int nc = 0;
      if(baseOK) { cand[0] = (int)xr; cnt[0] = 1; nc = 1; }
      for(int q = k + 1; q < kEnd; q++)
        {
         long c = (long)((long)ss[q] % 86400) - 18 * 3600;
         if(ref != INT_MIN)
            c += (long)MathRound((double)(ref - c) / 86400.0) * 86400;
         else if(c < -6 * 3600)
            c += 86400;
         long cr = (long)MathRound((double)c / 1800.0) * 1800;
         if(MathAbs(c - cr) > 1200)
            continue;
         int j = 0;
         for(; j < nc; j++)
            if(cand[j] == (int)cr)
               break;
         if(j == nc)
           {
            if(nc >= 24)
               continue;
            cand[nc] = (int)cr; cnt[nc] = 0; nc++;
           }
         cnt[j]++;
        }
      int best = -1;
      for(int j = 0; j < nc; j++)
         if(best < 0 || cnt[j] > cnt[best] || (cnt[j] == cnt[best] && cand[j] == ref))
            best = j;
      int off = (best >= 0 ? cand[best] : prev);
      if(off != INT_MIN)
        {
         ArrayResize(ws, nw + 1, 64); ArrayResize(wo, nw + 1, 64); ArrayResize(wv, nw + 1, 64);
         ws[nw] = s0; wo[nw] = off; wv[nw] = (best >= 0 ? cnt[best] : 0); nw++;
         prev = off;
        }
      k = kEnd;
     }
   if(nw == 0)
      return false;
   ArrayResize(g_wkStart, nw); ArrayResize(g_wkOff, nw); ArrayResize(g_wkVotes, nw);
   for(int i = 0; i < nw; i++) { g_wkStart[i] = ws[i]; g_wkOff[i] = wo[i]; g_wkVotes[i] = wv[i]; }
   g_tzScanAt = to;
   return true;
  }

bool ReadClock()
  {
   g_clockOK = false;
   if(MQLInfoInteger(MQL_TESTER) != 0 || TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
      return false;
   datetime ts = TimeTradeServer(), tg = TimeGMT();
   if(ts <= 0 || tg <= 0)
      return false;
   long diff = (long)ts - (long)tg;
   long r = (long)MathRound((double)diff / 1800.0) * 1800;
   if(MathAbs(diff - r) > 600 || MathAbs(r) > 14 * 3600)
      return false;
   g_clockOff = (int)r; g_clockOK = true;
   return true;
  }

int WeekIndex(datetime server)
  {
   int n = ArraySize(g_wkStart);
   if(n == 0 || server < g_wkStart[0])
      return -1;
   int lo = 0, hi = n - 1;
   while(lo < hi)
     {
      int mid = (lo + hi + 1) / 2;
      if(g_wkStart[mid] <= server)
         lo = mid;
      else
         hi = mid - 1;
     }
   return lo;
  }

bool ServerToLondon(datetime server, datetime &ldn)
  {
   int k = WeekIndex(server);
   if(k >= 0)
     {
      datetime ny = server - g_wkOff[k];
      ldn = LondonFromUTC(ny + (USDSTLocal(ny) ? 4 : 5) * 3600);
      return true;
     }
   if(g_clockOK && MathAbs((long)server - (long)TimeCurrent()) < 3 * 86400)
     {
      ldn = LondonFromUTC(server - g_clockOff);
      return true;
     }
   return false;
  }

bool LondonToServer(datetime ldnWall, datetime &server)
  {
   datetime utc = UTCFromLondon(ldnWall);
   datetime ny = utc - (USDSTUtc(utc) ? 4 : 5) * 3600;
   int n = ArraySize(g_wkStart);
   for(int k = n - 1; k >= 0; k--)
     {
      datetime cand = ny + g_wkOff[k];
      if(cand >= g_wkStart[k])
        {
         if(k == n - 1 || cand < g_wkStart[k + 1])
           {
            server = cand;
            return true;
           }
         return false;
        }
     }
   if(n == 0 && g_clockOK && MathAbs((long)utc + g_clockOff - (long)TimeCurrent()) < 3 * 86400)
     {
      server = utc + g_clockOff;
      return true;
     }
   return false;
  }

bool EnsureServerTime(bool force)
  {
   datetime now = TimeCurrent();
   bool perlu = (force || ArraySize(g_wkStart) == 0 || now - g_tzScanAt > 6 * 3600);
   if(perlu && (force || now - g_tzTryAt >= 30 || now < g_tzTryAt))
     {
      g_tzTryAt = now;
      ScanServerTime();
      ReadClock();
     }
   return (ArraySize(g_wkStart) > 0 || g_clockOK);
  }

bool CheckServerTime(datetime now)
  {
   int k = WeekIndex(now);
   if(k < 0)
     {
      if(g_clockOK)
        {
         g_tzNote = StringFormat("server = UTC%+.1f menurut jam komputer (jeda pasar tidak ditemukan di riwayat M1)", g_clockOff / 3600.0);
         return true;
        }
      g_tzNote = "jam server tidak bisa dikenali (riwayat M1 belum cukup)";
      return false;
     }
   datetime ny = now - g_wkOff[k];
   int gapUTC = g_wkOff[k] - (USDSTLocal(ny) ? 4 : 5) * 3600;
   if(g_clockOK && MathAbs(gapUTC - g_clockOff) >= 1800)
     {
      g_tzNote = StringFormat("JAM TIDAK COCOK: jeda pasar -> server = UTC%+.1f, jam komputer -> UTC%+.1f", gapUTC / 3600.0, g_clockOff / 3600.0);
      return false;
     }
   g_tzNote = StringFormat("server = UTC%+.1f (New York %+.1f jam; %d pembukaan sesi minggu ini%s)", gapUTC / 3600.0, g_wkOff[k] / 3600.0, g_wkVotes[k],
                           g_clockOK ? "; cocok dengan jam komputer" : (MQLInfoInteger(MQL_TESTER) != 0 ? "" : "; jam komputer tidak tersedia"));
   return true;
  }

double CalcU(datetime serverTime)
  {
   datetime a = serverTime - 60;
   datetime blok = a - (a % 300);
   datetime terakhir = blok - 600;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, PERIOD_M5, terakhir, 1381, r);
   if(n < 691)
      return 0.0;
   double sum = 0.0; int cnt = 0;
   for(int i = 0; i < n - 1 && cnt < 1380; i++)
     {
      double pc = r[i + 1].close;
      sum += MathMax(r[i].high, pc) - MathMin(r[i].low, pc);
      cnt++;
     }
   return (cnt >= 690 ? sum / cnt : 0.0);
  }

int RFind(datetime day)
  {
   int lo = 0, hi = ArraySize(g_rDay) - 1;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      if(g_rDay[mid] == day)
         return mid;
      if(g_rDay[mid] < day)
         lo = mid + 1;
      else
         hi = mid - 1;
     }
   return -1;
  }

void RAdd(datetime day, double r, bool persist)
  {
   if(RFind(day) >= 0)
      return;
   int n = ArraySize(g_rDay);
   ArrayResize(g_rDay, n + 1, 256); ArrayResize(g_rVal, n + 1, 256);
   int i = n;
   while(i > 0 && g_rDay[i - 1] > day)
     {
      g_rDay[i] = g_rDay[i - 1]; g_rVal[i] = g_rVal[i - 1]; i--;
     }
   g_rDay[i] = day; g_rVal[i] = r;
   if(persist && g_rFile != "")
     {
      int h = FileOpen(g_rFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
      if(h != INVALID_HANDLE)
        {
         FileSeek(h, 0, SEEK_END);
         MqlDateTime d; TimeToStruct(day, d);
         FileWriteString(h, StringFormat("%04d%02d%02d;%.6f\r\n", d.year, d.mon, d.day, r));
         FileClose(h);
        }
     }
  }

datetime DayFromYmd(int ymd)
  {
   MqlDateTime s; ZeroMemory(s);
   s.year = ymd / 10000; s.mon = (ymd / 100) % 100; s.day = ymd % 100;
   return StructToTime(s);
  }

void RLoad()
  {
#ifndef A10_TANPA_BENIH
   for(int i = 0; i < ArraySize(g_seedDay); i++)
      if(g_seedDay[i] > 20000000)
         RAdd(DayFromYmd(g_seedDay[i]), g_seedVal[i], false);
#endif
   if(MQLInfoInteger(MQL_TESTER) != 0)
      return;
   string nm = _Symbol + "_" + AccountInfoString(ACCOUNT_SERVER);
   StringReplace(nm, "\\", "_"); StringReplace(nm, "/", "_"); StringReplace(nm, ":", "_"); StringReplace(nm, " ", "_");
   g_rFile = "A10_gerak_" + nm + ".csv";
   int h = FileOpen(g_rFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
     {
      string ln = FileReadString(h);
      string p[];
      if(StringSplit(ln, ';', p) == 2)
        {
         int ymd = (int)StringToInteger(p[0]);
         if(ymd > 20000000)
            RAdd(DayFromYmd(ymd), StringToDouble(p[1]), false);
        }
     }
   FileClose(h);
  }

bool ComputeR(datetime dL, double &r)
  {
   datetime t24, t31;
   if(!LondonToServer(dL + 10 * 3600 + 24 * 60, t24) || !LondonToServer(dL + 10 * 3600 + 31 * 60, t31))
      return false;
   int i0 = iBarShift(_Symbol, PERIOD_M1, t24 - 60, true);
   if(i0 < 0)
      return false;
   int i1 = iBarShift(_Symbol, PERIOD_M1, t31 - 60, false);
   if(i1 < 0)
      return false;
   datetime tb = iTime(_Symbol, PERIOD_M1, i1);
   if(tb < t24 - 60 || tb > t31 - 60)
      return false;
   double u = CalcU(t24);
   if(u <= 0.0)
      return false;
   r = (iClose(_Symbol, PERIOD_M1, i1) - iClose(_Symbol, PERIOD_M1, i0)) / u;
   return true;
  }

bool SwitchOn(datetime ldnToday, double &m, int &cnt)
  {
   for(int back = 1; back <= A10_SWITCH_SPAN; back++)
     {
      datetime dL = ldnToday - back * 86400;
      MqlDateTime s; TimeToStruct(dL, s);
      if(s.day_of_week == 0 || s.day_of_week == 6 || RFind(dL) >= 0)
         continue;
      double r;
      if(ComputeR(dL, r))
         RAdd(dL, r, true);
     }
   double sum = 0.0; cnt = 0; m = 0.0;
   for(int i = ArraySize(g_rDay) - 1; i >= 0 && cnt < A10_SWITCH_DAYS; i--)
     {
      if(g_rDay[i] >= ldnToday)
         continue;
      if(g_rDay[i] < ldnToday - A10_SWITCH_SPAN * 86400)
         break;
      sum += g_rVal[i]; cnt++;
     }
   if(cnt < A10_SWITCH_MIN)
      return false;
   m = sum / cnt;
   return (m <= -A10_SWITCH_THRESH);
  }

double Median(double &a[], int n)
  {
   if(n <= 0)
      return 0.0;
   double b[];
   ArrayResize(b, n);
   for(int i = 0; i < n; i++)
      b[i] = a[i];
   ArraySort(b);
   return (n % 2 == 1 ? b[n / 2] : 0.5 * (b[n / 2 - 1] + b[n / 2]));
  }

double DetectCommission()
  {
   datetime now = TimeCurrent();
   if(HistorySelect(now - 90 * 86400, now + 86400))
     {
      double cin[], cout[]; int ni = 0, no = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0 && (ni < 60 || no < 60); i--)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0 || HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)
            continue;
         long typ = HistoryDealGetInteger(tk, DEAL_TYPE);
         if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL)
            continue;
         double vol = HistoryDealGetDouble(tk, DEAL_VOLUME);
         if(vol <= 0.0)
            continue;
         double c = -(HistoryDealGetDouble(tk, DEAL_COMMISSION) + HistoryDealGetDouble(tk, DEAL_FEE)) / vol;
         long ent = HistoryDealGetInteger(tk, DEAL_ENTRY);
         if(ent == DEAL_ENTRY_IN && ni < 60) { ArrayResize(cin, ni + 1, 64); cin[ni++] = c; }
         else if(ent == DEAL_ENTRY_OUT && no < 60) { ArrayResize(cout, no + 1, 64); cout[no++] = c; }
        }
      if(ni + no > 0)
        {
         double perLot = MathMax(Median(cin, ni) + Median(cout, no), 0.0);
         double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), tsz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double perHarga = (tv > 0.0 && tsz > 0.0 ? tv / tsz : SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
         g_kom = (perHarga > 0.0 ? perLot / perHarga : 0.0);
         g_komKnown = true;
        }
     }
   return g_kom;
  }

bool IsMine(ulong tk)
  {
   return (tk > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(IsMine(PositionGetTicket(i)))
         n++;
   return n;
  }

bool TradingAllowed()
  {
   return (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 && MQLInfoInteger(MQL_TRADE_ALLOWED) != 0 &&
           AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0 && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0);
  }

bool PriceNotGold()
  {
   if(SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE) == "XAU")
      return false;
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(px <= 0.0)
      px = iClose(_Symbol, PERIOD_D1, 0);
   return (px > 0.0 && px < 500.0);
  }

bool SellAllowed()
  {
   long m = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   return (m == SYMBOL_TRADE_MODE_FULL || m == SYMBOL_TRADE_MODE_SHORTONLY);
  }

bool EntryRetryable(uint rc)
  {
   return (rc == TRADE_RETCODE_INVALID_STOPS || rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
           rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_INVALID_PRICE || rc == TRADE_RETCODE_REJECT);
  }

void EntryFailed(string ket)
  {
   uint rc = trade.ResultRetcode();
   bool lagi = (EntryRetryable(rc) && g_tryCnt <= A10_ENTRY_RETRY);
   if(lagi)
      g_lastMin = -1;
   PrintFormat("10algo: gagal membuka lapis %s - %s%s", ket, trade.ResultRetcodeDescription(),
               lagi ? StringFormat(" - dicoba lagi dengan harga terbaru bila menitnya belum lewat (percobaan %d dari %d)", g_tryCnt + 1, 1 + A10_ENTRY_RETRY) : "");
  }

int ClosePendingIndex(ulong tk)
  {
   for(int i = ArraySize(g_closeTk) - 1; i >= 0; i--)
      if(g_closeTk[i] == tk)
         return i;
   return -1;
  }

void MarkCloseSent(ulong tk, datetime at)
  {
   int i = ClosePendingIndex(tk);
   if(i < 0)
     {
      i = ArraySize(g_closeTk);
      ArrayResize(g_closeTk, i + 1);
      ArrayResize(g_closeAt, i + 1);
      g_closeTk[i] = tk;
     }
   g_closeAt[i] = at;
  }

void CloseAll()
  {
   if(!A10_ASYNC_CLOSE)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(IsMine(tk))
            trade.PositionClose(tk);
        }
      return;
     }
   datetime now = TimeCurrent();
   int tunggu = MathMax(A10_CLOSE_RETRY, 2);
   trade.SetAsyncMode(true);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(!IsMine(tk))
         continue;
      int k = ClosePendingIndex(tk);
      if(k >= 0 && now - g_closeAt[k] < tunggu)
         continue;
      if(trade.PositionClose(tk))
         MarkCloseSent(tk, now);
      else
         MarkCloseSent(tk, now - tunggu + 1);
     }
   trade.SetAsyncMode(false);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      g_statsDirty = true;                               // 10algo: statistik panel
   if(!A10_ASYNC_CLOSE || trans.type != TRADE_TRANSACTION_REQUEST)
      return;
   if(request.action != TRADE_ACTION_DEAL || request.position == 0 || request.magic != (ulong)InpMagic)
      return;
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL || result.retcode == TRADE_RETCODE_PLACED)
      return;
   if(!PositionSelectByTicket(request.position))
      return;
   int k = ClosePendingIndex(request.position);
   if(k >= 0)
      g_closeAt[k] = TimeCurrent() - MathMax(A10_CLOSE_RETRY, 2) + 1;
   PrintFormat("10algo: perintah tutup posisi #%I64u ditolak (%u %s) - akan dicoba lagi", request.position, result.retcode, result.comment);
  }

double MinStopDist()
  {
#ifdef A10_UJI_TP_MAYA
   return 1000000.0;
#endif
   return (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
  }

int VtIndex(ulong tk)
  {
   for(int i = ArraySize(g_vtTk) - 1; i >= 0; i--)
      if(g_vtTk[i] == tk)
         return i;
   return -1;
  }

void VtAdd(ulong tk, double tp)
  {
   if(tk == 0 || VtIndex(tk) >= 0)
      return;
   int n = ArraySize(g_vtTk);
   ArrayResize(g_vtTk, n + 1); ArrayResize(g_vtTP, n + 1);
   g_vtTk[n] = tk; g_vtTP[n] = tp;
  }

void ManageVirtualTP()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int tanpaTP = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(!IsMine(tk) || PositionGetDouble(POSITION_TP) > 0.0)
         continue;
      tanpaTP++;
      int k = VtIndex(tk);
      if(k < 0)
        {
         double u = CalcU(TimeCurrent());
         if(u <= 0.0)
            continue;
         VtAdd(tk, PositionGetDouble(POSITION_PRICE_OPEN) - A10_TP_U * u - g_kom);
         k = VtIndex(tk);
         if(k < 0)
            continue;
        }
      if(ask <= g_vtTP[k])
         trade.PositionClose(tk);
     }
   if(tanpaTP == 0 && MinStopDist() <= 0.0)
      g_vtPerlu = false;
  }

//+------------------------------------------------------------------+
//| 10algo: tambahan di luar algoritma A10                           |
//|  - panel grafis, tombol PAUSE / TUTUP SEMUA / ringkas            |
//|  - penjaga risiko (opsional): batas rugi terburuk per hari,      |
//|    batas drawdown dari puncak ekuitas, lot dari risiko           |
//|  - statistik hasil, garis jendela lelang di chart                |
//|  - file status JSON untuk 9algo_sync (Common\Files\9algo)        |
//| Algoritma entry/exit A10 (jam, lapis, TP/SL dalam U, sakelar,    |
//| gerbang biaya, penutupan 10:31) TIDAK diubah.                    |
//+------------------------------------------------------------------+
#define C_BG    C'22,24,30'
#define C_CARD  C'28,32,42'
#define C_EDGE  C'46,52,68'
#define C_TXT   C'230,232,236'
#define C_DIM   C'156,162,172'
#define C_MUTE  C'110,117,130'
#define C_OK    C'38,166,91'
#define C_WARN  C'230,160,30'
#define C_BAD   C'220,64,64'
#define C_BLUE  C'70,130,220'
#define C_GOLD  C'227,179,65'
#define C_TRACK C'44,48,58'

string   g_pfx        = "10A_";
double   g_sc         = 1.0;
bool     g_mini       = false;
bool     g_paused     = false;
datetime g_confirmUntil = 0;
double   g_stToday = 0, g_stWeek = 0, g_stMonth = 0, g_stAll = 0;
int      g_stDays = 0, g_stWin = 0;
double   g_last10[];
datetime g_last10d[];
datetime g_statsAt    = 0;
bool     g_statsDirty = true;
double   g_pvSwitch = 0.0, g_pvU = 0.0, g_pvCost = 0.0;
// v1.13 pengaman
bool     g_candidate = false;   // sakelar nyala & gerbang terbuka hari ini (sebelum pengaman A/C)
bool     g_skipA = false, g_skipC = false;
double   g_pre80 = 0.0;
bool     g_shPending = false;
datetime g_shDayL = 0;
double   g_shU = 0.0;
int      g_shDay[];
double   g_shVal[];
const int    SH_SEED_DAY[] = {20260914,20260915,20260916,20260917,20260918,20260921,20260922,20260923,20260924,20260925,20260928,20260929,20260930,20261001,20261002,20261005,20261006,20261007,20261008,20261009,20261012,20261013,20261014,20261015,20261016,20261019,20261020,20261021,20261022,20261023,20261026,20261027,20261028,20261029,20261030,20261102,20261103,20261104,20261105,20261106,20261109,20261110,20261111,20261112,20261113,20261116,20261117,20261118,20261119};
const double SH_SEED_VAL[] = {-0.809,-3.188,-0.665,3.114,2.261,3.120,0.000,1.061,3.133,0.000,1.439,1.667,0.932,-0.879,-2.175,3.134,0.000,3.147,2.927,-0.341,3.010,3.168,1.383,0.000,3.164,2.483,1.653,-6.225,2.503,0.000,2.299,1.225,2.086,2.982,3.156,3.150,2.962,3.132,1.973,-1.458,3.120,3.119,-2.820,0.000,0.385,3.138,2.896,-1.545,2.964};
int      g_pvN = 0;
bool     g_pvOK = false;
datetime g_pvAt = 0;
datetime g_stateAt = 0;
string   g_guardNote = "";
datetime g_vlDay = 0;

int S(double v) { return (int)MathRound(v * g_sc); }

string PauseKey() { return "10algo_pause_" + IntegerToString(InpMagic) + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)); }

string Usd(double v, bool sign = false)
  {
   string s = DoubleToString(MathAbs(v), 2);
   return (v < -0.004 ? "-" : (sign && v > 0.004 ? "+" : "")) + "$" + s;
  }

color PLColor(double v) { return v > 0.004 ? C_OK : (v < -0.004 ? C_BAD : C_DIM); }

string HariPendek(int dow)
  {
   string h[7] = {"Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"};
   return (dow >= 0 && dow < 7 ? h[dow] : "");
  }

string BulanPendek(int m)
  {
   string b[12] = {"Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"};
   return (m >= 1 && m <= 12 ? b[m - 1] : "");
  }

void PRect(string n, int x, int y, int w, int h, color c, color edge = clrNONE, string tip = "\n")
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
   ObjectSetInteger(0, nm, OBJPROP_COLOR, edge == clrNONE ? c : edge);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
  }

// kartu: dibuat sekali (tinggi diisi di akhir DrawPanel); jangan diubah ke 1 piksel tiap redraw -> berkedip
void PCard(string n, int x, int y, int w)
  {
   if(ObjectFind(0, g_pfx + n) < 0) PRect(n, x, y, w, 1, C_CARD, C_EDGE);
  }

void PText(string n, string t, int x, int y, int size, color c, bool bold = false, ENUM_ANCHOR_POINT anc = ANCHOR_LEFT_UPPER, string tip = "\n")
  {
   string nm = g_pfx + n;
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, nm, OBJPROP_TEXT, t);
   ObjectSetString(0, nm, OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
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
   ObjectSetString(0, nm, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_STATE, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
  }

void PBar(string n, int x, int y, int w, int h, double frac, color fill)
  {
   if(frac < 0) frac = 0;
   if(frac > 1) frac = 1;
   PRect(n + "_bg", x, y, w, h, C_TRACK);
   PRect(n + "_fg", x, y, (int)MathMax(1, w * frac), h, frac <= 0 ? C_TRACK : fill);
  }

color FracColor(double f) { return f >= 0.8 ? C_BAD : (f >= 0.5 ? C_WARN : C_OK); }

// pecah teks panjang jadi beberapa baris (maks n baris)
int Wrap(string s, int maxc, string &out[], int maxLines)
  {
   ArrayResize(out, 0);
   string w[];
   int nw = StringSplit(s, ' ', w);
   string line = "";
   int n = 0;
   for(int i = 0; i < nw; i++)
     {
      string cand = (line == "" ? w[i] : line + " " + w[i]);
      if(StringLen(cand) > maxc && line != "")
        {
         ArrayResize(out, n + 1); out[n++] = line;
         line = w[i];
         if(n >= maxLines) break;
        }
      else line = cand;
     }
   if(n < maxLines && line != "") { ArrayResize(out, n + 1); out[n++] = line; }
   else if(n >= maxLines && line != "" && n > 0) out[n - 1] = out[n - 1] + " ...";
   return n;
  }

double ValuePerPrice()
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (tv > 0.0 && ts > 0.0 ? tv / ts : SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
  }

// v1.09: lot dari saldo & U (compounding + ikut volatilitas). 1U per lapis = InpRisiko % saldo.
double RiskLots(double u)
  {
   if(InpRisiko <= 0.0 || u <= 0.0) return g_lots;
   double vpp = ValuePerPrice();
   if(vpp <= 0.0) return g_lots;
   double raw = InpRisiko / 100.0 * AccountInfoDouble(ACCOUNT_BALANCE) / (u * vpp);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = (vmin > 0.0 ? vmin : 0.01);
   double l = MathFloor(raw / step + 1e-9) * step;
   if(vmin > 0.0 && l < vmin) l = vmin;
   if(vmax > 0.0 && l > vmax) l = vmax;
   double vlimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(vlimit > 0.0 && l * A10_LAYERS > vlimit) l = MathMax(vmin, MathFloor(vlimit / A10_LAYERS / step + 1e-9) * step);
   return NormalizeDouble(l, 8);
  }


// rugi kalau SEMUA lapis kena SL (3U + spread per lapis)
double WorstDayLoss(double u, double lots)
  {
   double spr = MathMax(0.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
   return A10_LAYERS * (InpSLU * u + spr) * lots * ValuePerPrice();
  }

// 10algo v1.08: tanpa penjaga tambahan - perilaku trading sama persis dengan A10 asli.
// Satu-satunya pengecualian: tombol PAUSE manual di panel.
string GuardWhy(double u)
  {
   if(g_paused) return "PAUSE dari panel";
   return "";
  }

void ComputeStats()
  {
   datetime now = TimeCurrent();
   g_stToday = 0; g_stWeek = 0; g_stMonth = 0; g_stAll = 0; g_stDays = 0; g_stWin = 0;
   ArrayResize(g_last10, 0); ArrayResize(g_last10d, 0);
   if(!HistorySelect(now - 400 * 86400, now + 60)) return;
   datetime dd[]; double dv[]; int nd = 0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0 || HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;
      double v = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_COMMISSION) + HistoryDealGetDouble(tk, DEAL_FEE);
      datetime d = DayStart((datetime)HistoryDealGetInteger(tk, DEAL_TIME));
      int k = -1;
      for(int j = nd - 1; j >= 0; j--) if(dd[j] == d) { k = j; break; }
      if(k < 0) { ArrayResize(dd, nd + 1); ArrayResize(dv, nd + 1); dd[nd] = d; dv[nd] = 0; k = nd; nd++; }
      dv[k] += v;
     }
   MqlDateTime t; TimeToStruct(now, t);
   datetime today = DayStart(now);
   int dow = (t.day_of_week + 6) % 7;                 // Senin = 0
   datetime wk = today - dow * 86400;
   for(int j = 0; j < nd; j++)
     {
      MqlDateTime q; TimeToStruct(dd[j], q);
      g_stAll += dv[j]; g_stDays++;
      if(dv[j] > 0) g_stWin++;
      if(dd[j] == today) g_stToday += dv[j];
      if(dd[j] >= wk) g_stWeek += dv[j];
      if(q.year == t.year && q.mon == t.mon) g_stMonth += dv[j];
     }
   int from = MathMax(0, nd - 10);
   for(int j = from; j < nd; j++)
     {
      int m = ArraySize(g_last10);
      ArrayResize(g_last10, m + 1); ArrayResize(g_last10d, m + 1);
      g_last10[m] = dv[j]; g_last10d[m] = dd[j];
     }
   g_statsAt = now;
   g_statsDirty = false;
  }

double FloatingPL()
  {
   double s = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(IsMine(tk)) s += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return s;
  }

// pratinjau sakelar / U / biaya sebelum 10:20 (hanya tampilan; keputusan tetap di Prepare)
void Preview()
  {
   datetime now = TimeCurrent();
   if(now - g_pvAt < 300 && g_pvAt > 0) return;
   g_pvAt = now;
   datetime ldn;
   if(!ServerToLondon(now, ldn)) return;
   double m; int cnt;
   SwitchOn(DayStart(ldn), m, cnt);
   g_pvSwitch = m; g_pvN = cnt;
   g_pvU = CalcU(now);
   DetectCommission();
   g_pvCost = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) + g_kom;
   g_pvOK = (g_pvU > 0);
   if(InpRisiko > 0.0 && g_pvU > 0 && !g_prepared) g_lots = RiskLots(g_pvU);
  }

datetime LondonToLocal(datetime ldnWall) { return UTCFromLondon(ldnWall) + InpLocalUTCOffset * 3600; }
string HM(datetime t) { MqlDateTime d; TimeToStruct(t, d); return StringFormat("%02d:%02d", d.hour, d.min); }

string NextStartText(datetime ldn)
  {
   MqlDateTime L; TimeToStruct(ldn, L);
   int mnt = L.hour * 60 + L.min;
   datetime day = DayStart(ldn);
   bool weekday = (L.day_of_week >= 1 && L.day_of_week <= 5);
   if(weekday && mnt >= T_MULAI && mnt < T_TUTUP) return "jendela sedang berjalan";
   datetime target = day + T_MULAI * 60;
   if(!weekday || mnt >= T_MULAI || IsUKHoliday(day))
     {
      target = day + 86400 + T_MULAI * 60;
      for(int i = 0; i < 10; i++)
        {
         MqlDateTime d; TimeToStruct(target, d);
         if(d.day_of_week == 0 || d.day_of_week == 6 || IsUKHoliday(DayStart(target))) target += 86400;
         else break;
        }
     }
   long s = (long)target - (long)ldn;
   MqlDateTime d2; TimeToStruct(target, d2);
   string when = (DayStart(target) == day ? "hari ini" : HariPendek(d2.day_of_week) + " " + IntegerToString(d2.day) + " " + BulanPendek(d2.mon));
   return StringFormat("%s %s %s (%dj %02dm lagi)", when, HM(LondonToLocal(target)), InpLocalName, (int)(s / 3600), (int)((s % 3600) / 60));
  }

void StatusPill(string &txt, color &bg)
  {
   if(g_fatal) { txt = "ERROR"; bg = C_BAD; return; }
   if(g_paused) { txt = "PAUSE"; bg = C_WARN; return; }
   if(!TradingAllowed()) { txt = "ALGO OFF"; bg = C_WARN; return; }
   if(g_active && (g_layers > 0 || CountPositions() > 0)) { txt = "AKTIF"; bg = C_OK; return; }
   if(g_active) { txt = "SIAP"; bg = C_OK; return; }
   if(g_prepared) { txt = "TIDAK TRADE"; bg = C_MUTE; return; }
   txt = "MENUNGGU"; bg = C_BLUE;
  }

void DrawWindowLines(datetime ldn)
  {
   if(!InpDrawWindow) return;
   datetime day = DayStart(ldn);
   if(day == g_vlDay) return;
   datetime a, b;
   if(!LondonToServer(day + T_MULAI * 60, a) || !LondonToServer(day + T_TUTUP * 60, b)) return;
   g_vlDay = day;
   string na = g_pfx + "vl_a", nb = g_pfx + "vl_b";
   if(ObjectFind(0, na) < 0) ObjectCreate(0, na, OBJ_VLINE, 0, a, 0);
   if(ObjectFind(0, nb) < 0) ObjectCreate(0, nb, OBJ_VLINE, 0, b, 0);
   ObjectSetInteger(0, na, OBJPROP_TIME, a);
   ObjectSetInteger(0, nb, OBJPROP_TIME, b);
   ObjectSetInteger(0, na, OBJPROP_COLOR, C_GOLD);
   ObjectSetInteger(0, nb, OBJPROP_COLOR, C_GOLD);
   ObjectSetInteger(0, na, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nb, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, na, OBJPROP_BACK, true);
   ObjectSetInteger(0, nb, OBJPROP_BACK, true);
   ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nb, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, na, OBJPROP_TOOLTIP, "10algo: mulai lelang London 10:20");
   ObjectSetString(0, nb, OBJPROP_TOOLTIP, "10algo: tutup semua 10:31 London");
  }

void Row(string n, string label, string value, int x, int w, int y, color vc, string tip = "\n")
  {
   PText(n + "_l", label, x + S(12), y, 8, C_DIM);
   PText(n + "_v", value, x + w - S(12), y, 8, vc, false, ANCHOR_RIGHT_UPPER, tip);
  }

void DrawPanel(datetime ldn, bool ldnOK)
  {
   int X = S(InpPanelX), Y = S(InpPanelY), W = S(340), lh = S(17), pad = S(12);
   int y = Y;
   string st; color stc;
   StatusPill(st, stc);
   // --- header
   PRect("hdr", X, y, W, S(46), C_BG, C_EDGE);
   PRect("hdr_acc", X, y, S(4), S(46), C_GOLD);
   PText("title", "10algo", X + S(14), y + S(5), 13, C_TXT, true);
   PText("sub", "London Auction  |  " + _Symbol + "  |  v1.13", X + S(14), y + S(28), 7, C_MUTE);
   PRect("pill", X + W - S(122), y + S(13), S(84), S(20), stc);
   PText("pill_t", st, X + W - S(80), y + S(16), 8, clrWhite, true, ANCHOR_UPPER);
   PButton("btn_min", g_mini ? "+" : "-", X + W - S(30), y + S(13), S(20), S(20), C_CARD, C_TXT, g_mini ? "Buka panel" : "Ringkas panel");
   y += S(52);
   if(g_mini) { ChartRedraw(); return; }

   // --- kartu 1: hari ini
   int cy = y;
   PCard("c1", X, cy, W);
   PText("c1_t", "HARI INI", X + pad, cy + S(8), 7, C_GOLD, true);
   int r = cy + S(26);
   if(ldnOK)
     {
      MqlDateTime L; TimeToStruct(ldn, L);
      Row("c1r1", "Jam London  |  " + InpLocalName, StringFormat("%s %d %s  %02d:%02d  |  %s", HariPendek(L.day_of_week), L.day, BulanPendek(L.mon), L.hour, L.min, HM(LondonToLocal(ldn))), X, W, r, C_TXT); r += lh;
      Row("c1r2", "Jadwal berikutnya", NextStartText(ldn), X, W, r, C_TXT); r += lh;
     }
   else
     {
      Row("c1r1", "Jam London", "belum dikenali", X, W, r, C_WARN); r += lh;
      Row("c1r2", "Jadwal berikutnya", "-", X, W, r, C_DIM); r += lh;
     }
   if(ldnOK)
     {
      datetime d0 = DayStart(ldn);
      Row("c1r3", "Jendela (" + InpLocalName + ")", StringFormat("entry %s-%s  |  tutup %s  (London 10:20-10:31)", HM(LondonToLocal(d0 + T_MULAI * 60)),
          HM(LondonToLocal(d0 + (T_MULAI + A10_LAYERS - 1) * 60)), HM(LondonToLocal(d0 + T_TUTUP * 60))), X, W, r, C_DIM); r += lh;
     }
   else { Row("c1r3", "Jendela", "entry 10:20-10:29  |  tutup 10:31 London", X, W, r, C_DIM); r += lh; }
   string note = g_fatal ? "TIDAK BISA JALAN: " + g_fatalMsg : g_dayNote;
   if(g_guardNote != "" && !g_fatal) note = note + " (" + g_guardNote + ")";
   string ln[];
   int nl = Wrap(note, 58, ln, 3);
   for(int i = 0; i < 3; i++)
     {
      string nm = "c1n" + IntegerToString(i);
      if(i < nl) { PText(nm, ln[i], X + pad, r, 8, g_fatal ? C_BAD : C_TXT, false, ANCHOR_LEFT_UPPER, note); r += S(15); }
      else ObjectDelete(0, g_pfx + nm);
     }
   r += S(4);
   int pos = CountPositions();
   PText("c1lp", StringFormat("Lapis %d / %d", g_layers, A10_LAYERS), X + pad, r, 8, C_DIM);
   double fl = FloatingPL();
   PText("c1fl", pos > 0 ? "mengambang " + Usd(fl, true) : "tidak ada posisi", X + W - pad, r, 8, pos > 0 ? PLColor(fl) : C_MUTE, false, ANCHOR_RIGHT_UPPER);
   r += S(16);
   PBar("c1bar", X + pad, r, W - 2 * pad, S(6), (double)g_layers / A10_LAYERS, C_GOLD);
   r += S(14);
   PRect("c1", X, cy, W, r - cy, C_CARD, C_EDGE);
   y = r + S(6);

   // --- kartu 2: sinyal A10
   cy = y;
   PCard("c2", X, cy, W);
   bool real = (g_prepared && g_u > 0);
   PText("c2_t", real ? "SINYAL HARI INI" : "SINYAL (PRATINJAU)", X + pad, cy + S(8), 7, C_GOLD, true);
   r = cy + S(26);
   double sw = real ? g_switch : g_pvSwitch, uu = real ? g_u : g_pvU, cost = real ? g_cost : g_pvCost;
   int swn = real ? g_switchN : g_pvN;
   bool have = real || g_pvOK;
   if(have)
     {
      bool swOn = (swn >= A10_SWITCH_MIN && sw <= -A10_SWITCH_THRESH);
      Row("c2r1", "Sakelar arah (120 hari)", StringFormat("%+.3f U  |  %s", sw, swn < A10_SWITCH_MIN ? StringFormat("data %d/%d hari", swn, A10_SWITCH_MIN) : (swOn ? "NYALA" : "MATI")),
          X, W, r, swOn ? C_OK : C_DIM, StringFormat("NYALA jika rata-rata gerak 10:24-10:31 <= -%.2f U (%d hari)", A10_SWITCH_THRESH, swn)); r += lh;
      Row("c2r2", "U (rata-rata range M5)", DoubleToString(uu, 3), X, W, r, C_TXT); r += lh;
      double cu = (uu > 0 ? cost / uu : 0);
      bool gate = (uu > 0 && cu <= A10_MAX_COST_U);
      Row("c2r3", "Biaya / gerbang", StringFormat("%.3f = %.3f U  |  %s", cost, cu, gate ? "TERBUKA" : "TERTUTUP"), X, W, r, gate ? C_OK : C_BAD,
          StringFormat("spread + komisi harus <= %.4f U. Komisi %s", A10_MAX_COST_U, g_komKnown ? DoubleToString(g_kom, 3) + " per unit" : "belum diketahui (0)")); r += lh;
      PBar("c2bar", X + pad, r + S(2), W - 2 * pad, S(5), uu > 0 ? cu / A10_MAX_COST_U : 0, gate ? C_OK : C_BAD);
      r += S(14);
      Row("c2r4", "TP / SL per lapis", StringFormat("%.2f / %.2f  (%.1f U / %.1f U)", A10_TP_U * uu, InpSLU * uu, A10_TP_U, InpSLU), X, W, r, C_DIM); r += lh;
     }
   else
     {
      Row("c2r1", "Sakelar arah (120 hari)", "menghitung...", X, W, r, C_DIM); r += lh;
      for(int i = 2; i <= 4; i++) { ObjectDelete(0, g_pfx + "c2r" + IntegerToString(i) + "_l"); ObjectDelete(0, g_pfx + "c2r" + IntegerToString(i) + "_v"); }
      ObjectDelete(0, g_pfx + "c2bar_bg"); ObjectDelete(0, g_pfx + "c2bar_fg");
     }
   r += S(2);
   PRect("c2", X, cy, W, r - cy, C_CARD, C_EDGE);
   y = r + S(6);

   // --- kartu 3: risiko
   cy = y;
   PCard("c3", X, cy, W);
   PText("c3_t", "RISIKO", X + pad, cy + S(8), 7, C_GOLD, true);
   r = cy + S(26);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   Row("c3r1", "Lot per lapis", StringFormat("%.2f x %d lapis  (%s)", g_lots, A10_LAYERS,
       InpRisiko > 0.0 ? StringFormat("1U = %.2f%% saldo, ikut saldo & U", InpRisiko) : "tetap"), X, W, r, C_TXT,
       InpRisiko > 0.0 ? "lot = risiko% x saldo / (U x nilai per lot), dihitung ulang tiap 10:20 London" : "\n"); r += lh;
   double rz = ShSum(InpRezimHari);
   Row("c3r0", "Pengaman", StringFormat("lonjakan %s | SL %.1fU | rezim %s %+.1fU", InpLonjakanU > 0 ? (g_prepared && g_candidate ? StringFormat("%+.1fU", g_pre80) : "nyala") : "mati",
       InpSLU, InpRezimHari <= 0 ? "mati" : (rz < 0 && ArraySize(g_shVal) >= InpRezimHari ? "ISTIRAHAT" : "ok"), rz), X, W, r, (g_skipA || g_skipC) ? C_WARN : C_DIM,
       StringFormat("A: lewati hari jika naik >= %.1fU sejak 09:00 London | B: SL %.1fU per lapis | C: istirahat jika hasil bayangan %d hari aktif terakhir < 0 (%d catatan)", InpLonjakanU, InpSLU, InpRezimHari, ArraySize(g_shVal))); r += lh;
   if(uu > 0 && bal > 0)
     {
      double w = WorstDayLoss(uu, g_lots);
      Row("c3r2", "Rugi terburuk / hari", StringFormat("%s  (%.2f%% saldo)", Usd(w), 100.0 * w / bal), X, W, r, C_TXT,
          StringFormat("info saja: semua %d lapis kena SL", A10_LAYERS)); r += lh;
     }
   r += S(6);
   PRect("c3", X, cy, W, r - cy, C_CARD, C_EDGE);
   y = r + S(6);

   // --- kartu 4: hasil
   cy = y;
   PCard("c4", X, cy, W);
   PText("c4_t", "HASIL", X + pad, cy + S(8), 7, C_GOLD, true);
   r = cy + S(26);
   Row("c4r1", "Saldo  |  ekuitas", Usd(bal) + "  |  " + Usd(eq), X, W, r, C_TXT); r += lh;
   Row("c4r2", "Hari ini", Usd(g_stToday, true), X, W, r, PLColor(g_stToday)); r += lh;
   Row("c4r3", "Minggu ini  |  bulan ini", Usd(g_stWeek, true) + "  |  " + Usd(g_stMonth, true), X, W, r, PLColor(g_stMonth)); r += lh;
   Row("c4r4", "Total 10algo", StringFormat("%s  |  %d/%d hari profit", Usd(g_stAll, true), g_stWin, g_stDays), X, W, r, PLColor(g_stAll)); r += lh;
   int nc = ArraySize(g_last10);
   PText("c4l10", "10 hari trade terakhir", X + pad, r + S(2), 7, C_MUTE);
   int bx = X + W - pad - 10 * S(16);
   for(int i = 0; i < 10; i++)
     {
      string nm = "c4d" + IntegerToString(i);
      int k = nc - 10 + i;
      if(k >= 0)
        {
         MqlDateTime q; TimeToStruct(g_last10d[k], q);
         PRect(nm, bx + i * S(16), r + S(2), S(12), S(12), PLColor(g_last10[k]), clrNONE,
               StringFormat("%s %d %s: %s", HariPendek(q.day_of_week), q.day, BulanPendek(q.mon), Usd(g_last10[k], true)));
        }
      else PRect(nm, bx + i * S(16), r + S(2), S(12), S(12), C_TRACK);
     }
   r += S(22);
   PRect("c4", X, cy, W, r - cy, C_CARD, C_EDGE);
   y = r + S(6);

   // --- footer: jam server + tombol
   int nz = Wrap("Jam server: " + g_tzNote, 62, ln, 2);
   for(int i = 0; i < 2; i++)
     {
      string nm = "tz" + IntegerToString(i);
      if(i < nz) { PText(nm, ln[i], X + S(4), y, 7, C_MUTE); y += S(13); }
      else ObjectDelete(0, g_pfx + nm);
     }
   y += S(4);
   int bw = (W - S(8)) / 2;
   PButton("btn_pause", g_paused ? "LANJUTKAN" : "PAUSE", X, y, bw, S(26), g_paused ? C_OK : C_WARN, clrWhite,
           g_paused ? "Izinkan lapis baru lagi" : "Hentikan lapis baru (posisi tetap ditutup 10:31)");
   bool conf = (TimeLocal() <= g_confirmUntil);
   PButton("btn_close", conf ? "KLIK LAGI UTK YAKIN" : "TUTUP SEMUA", X + bw + S(8), y, bw, S(26), conf ? C_BAD : C'90,40,46', clrWhite,
           "Tutup semua posisi 10algo di simbol ini (klik 2x dalam 5 detik)");
   y += S(32);
   ChartRedraw();
  }

void JAdd(string &s, string k, string v, bool quote)
  {
   string x = v;
   if(quote) { StringReplace(x, "\\", "\\\\"); StringReplace(x, "\"", "\\\""); x = "\"" + x + "\""; }
   s += (StringLen(s) > 1 ? "," : "") + "\"" + k + "\":" + x;
  }

void WriteState()
  {
   if(!InpWriteState || MQLInfoInteger(MQL_TESTER) != 0) return;
   string fn = "9algo\\state_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_10algo_" + _Symbol + ".json";
   string st; color c; StatusPill(st, c);
   string s = "{";
   JAdd(s, "ea", "10algo", true);
   JAdd(s, "version", "1.13", true);
   JAdd(s, "algo", "A10 London Auction v1.23", true);
   JAdd(s, "symbol", _Symbol, true);
   JAdd(s, "login", IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)), false);
   JAdd(s, "server", AccountInfoString(ACCOUNT_SERVER), true);
   JAdd(s, "time", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), true);
   JAdd(s, "status", st, true);
   JAdd(s, "paused", g_paused ? "true" : "false", false);
   JAdd(s, "fatal", g_fatal ? g_fatalMsg : "", true);
   JAdd(s, "day_note", g_dayNote, true);
   JAdd(s, "guard_note", g_guardNote, true);
   JAdd(s, "tz", g_tzNote, true);
   JAdd(s, "prepared", g_prepared ? "true" : "false", false);
   JAdd(s, "active", g_active ? "true" : "false", false);
   JAdd(s, "layers", IntegerToString(g_layers), false);
   JAdd(s, "lots", DoubleToString(g_lots, 2), false);
   JAdd(s, "risk_per_u", DoubleToString(InpRisiko, 2), false);
   JAdd(s, "term_maxbars", IntegerToString(TerminalInfoInteger(TERMINAL_MAXBARS)), false);
   JAdd(s, "m1_bars", IntegerToString(Bars(_Symbol, PERIOD_M1)), false);
   JAdd(s, "m1_first", TimeToString((datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_FIRSTDATE), TIME_DATE), true);
   JAdd(s, "hist_first_terminal", TimeToString((datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_TERMINAL_FIRSTDATE), TIME_DATE), true);
   JAdd(s, "hist_first_server", TimeToString((datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_SERVER_FIRSTDATE), TIME_DATE), true);
   JAdd(s, "lonjakan_u", DoubleToString(InpLonjakanU, 2), false);
   JAdd(s, "sl_u", DoubleToString(InpSLU, 2), false);
   JAdd(s, "rezim_hari", IntegerToString(InpRezimHari), false);
   JAdd(s, "rezim_sum", DoubleToString(ShSum(InpRezimHari), 3), false);
   JAdd(s, "shadow_n", IntegerToString(ArraySize(g_shVal)), false);
   JAdd(s, "shadow_last", ArraySize(g_shVal) > 0 ? StringFormat("%d:%.3f", g_shDay[ArraySize(g_shDay) - 1], g_shVal[ArraySize(g_shVal) - 1]) : "", true);
   JAdd(s, "pre80", DoubleToString(g_pre80, 3), false);
   JAdd(s, "skip_a", g_skipA ? "true" : "false", false);
   JAdd(s, "skip_c", g_skipC ? "true" : "false", false);
   JAdd(s, "switch", DoubleToString(g_prepared ? g_switch : g_pvSwitch, 4), false);
   JAdd(s, "switch_n", IntegerToString(g_prepared ? g_switchN : g_pvN), false);
   JAdd(s, "u", DoubleToString(g_prepared ? g_u : g_pvU, 4), false);
   JAdd(s, "cost", DoubleToString(g_prepared ? g_cost : g_pvCost, 4), false);
   JAdd(s, "commission", DoubleToString(g_kom, 4), false);
   JAdd(s, "positions", IntegerToString(CountPositions()), false);
   JAdd(s, "floating", DoubleToString(FloatingPL(), 2), false);
   JAdd(s, "balance", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), false);
   JAdd(s, "equity", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), false);
   JAdd(s, "leverage", IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)), false);
   JAdd(s, "margin_used", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2), false);
   JAdd(s, "margin_call_lvl", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL), 1), false);
   JAdd(s, "stopout_lvl", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_SO_SO), 1), false);
   JAdd(s, "bid", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), 2), false);
   double m10 = 0.0;
   if(!OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, g_lots * A10_LAYERS, SymbolInfoDouble(_Symbol, SYMBOL_BID), m10)) m10 = -1;
   JAdd(s, "margin_10_layers", DoubleToString(m10, 2), false);
   JAdd(s, "pl_today", DoubleToString(g_stToday, 2), false);
   JAdd(s, "pl_week", DoubleToString(g_stWeek, 2), false);
   JAdd(s, "pl_month", DoubleToString(g_stMonth, 2), false);
   JAdd(s, "pl_total", DoubleToString(g_stAll, 2), false);
   JAdd(s, "days", IntegerToString(g_stDays), false);
   JAdd(s, "win_days", IntegerToString(g_stWin), false);
   // v1.08: deal 10algo 3 hari terakhir (untuk analisis dari luar)
   string dl = "[";
   datetime nw = TimeCurrent();
   if(HistorySelect(nw - 3 * 86400, nw + 60))
     {
      int nd = HistoryDealsTotal(), cnt = 0;
      for(int i = MathMax(0, nd - 200); i < nd; i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0 || HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic || HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
         dl += (cnt++ > 0 ? "," : "") + StringFormat("[\"%s\",%d,%d,%.2f,%.3f,%.2f,%.2f,%.2f,%d,%I64u,\"%s\"]",
               TimeToString((datetime)HistoryDealGetInteger(tk, DEAL_TIME), TIME_DATE | TIME_SECONDS),
               (int)HistoryDealGetInteger(tk, DEAL_TYPE), (int)HistoryDealGetInteger(tk, DEAL_ENTRY),
               HistoryDealGetDouble(tk, DEAL_VOLUME), HistoryDealGetDouble(tk, DEAL_PRICE),
               HistoryDealGetDouble(tk, DEAL_PROFIT), HistoryDealGetDouble(tk, DEAL_COMMISSION), HistoryDealGetDouble(tk, DEAL_SWAP),
               (int)HistoryDealGetInteger(tk, DEAL_REASON), HistoryDealGetInteger(tk, DEAL_POSITION_ID), HistoryDealGetString(tk, DEAL_COMMENT));
        }
     }
   dl += "]";
   s += ",\"deals_fmt\":\"time,type,entry,vol,price,profit,comm,swap,reason,pos,comment\",\"deals\":" + dl;
   s += "}";
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, s);
   FileClose(h);
  }

void ApplyTheme()
  {
   if(!InpTheme || MQLInfoInteger(MQL_TESTER) != 0) return;
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'16,20,28');
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'150,156,168');
   ChartSetInteger(0, CHART_COLOR_GRID, C'42,49,64');
   ChartSetInteger(0, CHART_COLOR_CHART_UP, C'38,166,154');
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, C'239,83,80');
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, C'38,166,154');
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, C'239,83,80');
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, C'150,156,168');
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHIFT, true);
  }

// 10algo v1.01: dipasang ulang dari VPS (9algo_sync menulis MQL5\Files\10algo_reload.txt) -> EA memuat ulang dirinya
// lewat template chart. DITUNDA selama ada posisi terbuka atau dalam 10:15-10:35 London, supaya hitungan lapis
// hari ini tidak ter-reset di tengah jendela lelang.
string g_reloadSeen = "#";
string ReadReloadFlag()
  {
   if(MQLInfoInteger(MQL_TESTER) != 0 || !FileIsExist("10algo_reload.txt")) return "";
   int h = FileOpen("10algo_reload.txt", FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return g_reloadSeen;
   string v = FileReadString(h);
   FileClose(h);
   return v;
  }

void CheckReloadFlag()
  {
   string v = ReadReloadFlag();
   if(g_reloadSeen == "#") { g_reloadSeen = v; return; }
   if(v == "" || v == g_reloadSeen) return;
   if(CountPositions() > 0) return;
   datetime ldn;
   if(ServerToLondon(TimeCurrent(), ldn))
     {
      MqlDateTime L; TimeToStruct(ldn, L);
      int mnt = L.hour * 60 + L.min;
      if(mnt >= T_MULAI - 5 && mnt <= T_TUTUP + 4) return;
     }
   g_reloadSeen = v;
   ObjectsDeleteAll(0, g_pfx);                          // panel jangan ikut tersimpan di template (urutan lapisan jadi kacau)
   ChartRedraw();
   string tpl = "10algo_reload_" + IntegerToString(ChartID() % 100000);
   if(ChartSaveTemplate(0, tpl))
     {
      Print("10algo: versi baru terpasang (", v, ") -> EA dimuat ulang");
      ChartApplyTemplate(0, tpl);
     }
  }

// v1.08: ekspor riwayat harga untuk analisis dari luar (tidak memengaruhi trading).
// M1 jam server 11:00-14:59 (jendela 10:20-10:31 London jatuh di sini) + semua M5 (untuk U), maks 400 hari.
datetime g_exportDay = 0;
void ExportHistory()
  {
   if(MQLInfoInteger(MQL_TESTER) != 0) return;
   datetime now = TimeCurrent();
   datetime day = now - (now % 86400);
   if(g_exportDay == day) return;
   MqlDateTime t; TimeToStruct(now, t);
   if(t.hour >= 11 && t.hour <= 14) return;          // jangan di sekitar jendela trading
   g_exportDay = day;
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, now - 400 * 86400, now, r);
   int h = FileOpen("9algo\\export_10algo_m1.csv", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(h != INVALID_HANDLE)
     {
      FileWriteString(h, "time,open,high,low,close,spread\r\n");
      for(int i = 0; i < n; i++)
        {
         MqlDateTime q; TimeToStruct(r[i].time, q);
         if(q.hour < 11 || q.hour > 14) continue;
         FileWriteString(h, StringFormat("%s,%.2f,%.2f,%.2f,%.2f,%d\r\n", TimeToString(r[i].time, TIME_DATE | TIME_MINUTES), r[i].open, r[i].high, r[i].low, r[i].close, r[i].spread));
        }
      FileClose(h);
     }
   int m = CopyRates(_Symbol, PERIOD_M5, now - 400 * 86400, now, r);
   h = FileOpen("9algo\\export_10algo_m5.csv", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(h != INVALID_HANDLE)
     {
      FileWriteString(h, "time,high,low,close\r\n");
      for(int i = 0; i < m; i++)
         FileWriteString(h, StringFormat("%s,%.2f,%.2f,%.2f\r\n", TimeToString(r[i].time, TIME_DATE | TIME_MINUTES), r[i].high, r[i].low, r[i].close));
      FileClose(h);
     }
   PrintFormat("10algo: ekspor riwayat M1 (%d bar diambil) & M5 (%d bar) untuk analisis", n, m);
  }

// v1.11: ekspor riwayat panjang atas permintaan (9algo_sync menulis MQL5\Files\10algo_export_req.txt).
// Tidak memengaruhi trading; tidak jalan pada jam server 11-13 (sekitar jendela 10:20-10:31 London).
string   g_expSeen = "#";
string   g_expId   = "";
datetime g_expFrom = 0;
datetime g_expNext = 0;
int      g_expTry  = 0;

string ReadTxtFlag(string fn, string fallback)
  {
   if(!FileIsExist(fn)) return "";
   int h = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return fallback;
   string v = FileReadString(h);
   FileClose(h);
   return v;
  }

string SilverSymbol()
  {
   string s = _Symbol;
   if(StringReplace(s, "XAU", "XAG") <= 0) return "";
   if(!SymbolSelect(s, true)) return "";
   return s;
  }

// Paksa terminal membangun/mengunduh riwayat lama (pola CheckLoadHistory dari dokumentasi MQL5):
// minta blok bar berikutnya per posisi, bukan per tanggal. Dibatasi ~4 detik per panggilan.
bool HistReady(string sym, datetime from)
  {
   datetime tf0 = (datetime)SeriesInfoInteger(sym, PERIOD_M1, SERIES_TERMINAL_FIRSTDATE);
   ENUM_TIMEFRAMES tfs[2] = {PERIOD_M5, PERIOD_M1};
   bool ok = true;
   datetime tt[];
   for(int i = 0; i < 2; i++)
     {
      datetime first = (datetime)SeriesInfoInteger(sym, tfs[i], SERIES_FIRSTDATE);
      if(first > 0 && first <= from + 7 * 86400) continue;
      if(tf0 > 0) CopyTime(sym, tfs[i], tf0 + PeriodSeconds(tfs[i]), 1, tt);
      ulong t0 = GetTickCount64();
      while(GetTickCount64() - t0 < 4000 && !IsStopped())
        {
         first = (datetime)SeriesInfoInteger(sym, tfs[i], SERIES_FIRSTDATE);
         if(first > 0 && first <= from + 7 * 86400) break;
         int bars = Bars(sym, tfs[i]);
         if(CopyTime(sym, tfs[i], bars, 5000, tt) <= 0) Sleep(50);
        }
      first = (datetime)SeriesInfoInteger(sym, tfs[i], SERIES_FIRSTDATE);
      if(!(first > 0 && first <= from + 7 * 86400)) ok = false;
     }
   return ok;
  }

void HistWrite(string sym, datetime from, int &hours[])
  {
   MqlRates m5[];
   ArraySetAsSeries(m5, false);
   int n5 = CopyRates(sym, PERIOD_M5, from - 20 * 86400, TimeCurrent(), m5);
   if(n5 < 2000) { PrintFormat("10algo: ekspor %s gagal - M5 hanya %d bar", sym, n5); return; }
   double P[]; ArrayResize(P, n5 + 1); P[0] = 0.0; P[1] = 0.0;
   for(int i = 1; i < n5; i++)
     {
      double pc = m5[i - 1].close;
      P[i + 1] = P[i] + MathMax(m5[i].high, pc) - MathMin(m5[i].low, pc);
     }
   int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   string nm = sym; int dot = StringFind(nm, "."); if(dot > 0) nm = StringSubstr(nm, 0, dot);
   MqlDateTime a; TimeToStruct(from, a);
   MqlDateTime b; TimeToStruct(TimeCurrent(), b);
   int total = 0;
   for(int y = a.year; y <= b.year; y++)
     {
      MqlDateTime q; ZeroMemory(q); q.year = y; q.mon = 1; q.day = 1;
      datetime y0 = StructToTime(q); q.year = y + 1; datetime y1 = StructToTime(q) - 1;
      if(y0 < from) y0 = from;
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int n = CopyRates(sym, PERIOD_M1, y0, y1, r);
      if(n <= 0) continue;
      int h = FileOpen("9algo\\export_hist_" + nm + "_" + IntegerToString(y) + ".csv", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(h == INVALID_HANDLE) continue;
      FileWriteString(h, "time,open,high,low,close,spread,u\r\n");
      int j = 0, cnt = 0;
      for(int i = 0; i < n; i++)
        {
         MqlDateTime t; TimeToStruct(r[i].time, t);
         bool want = false;
         for(int k = 0; k < ArraySize(hours); k++) if(t.hour == hours[k]) { want = true; break; }
         if(!want) continue;
         datetime aa = r[i].time - 60; datetime blok = aa - (aa % 300); datetime last = blok - 600;
         while(j + 1 < n5 && m5[j + 1].time <= last) j++;
         while(j > 0 && m5[j].time > last) j--;
         double u = (j - 1379 >= 1 && m5[j].time <= last) ? (P[j + 1] - P[j - 1379]) / 1380.0 : 0.0;
         FileWriteString(h, TimeToString(r[i].time, TIME_DATE | TIME_MINUTES) + "," + DoubleToString(r[i].open, dg) + "," + DoubleToString(r[i].high, dg) + "," +
                         DoubleToString(r[i].low, dg) + "," + DoubleToString(r[i].close, dg) + "," + IntegerToString(r[i].spread) + "," + DoubleToString(u, 4) + "\r\n");
         cnt++;
        }
      FileClose(h);
      total += cnt;
     }
   PrintFormat("10algo: ekspor riwayat %s selesai: %d bar M1 (jam server terpilih), M5 %d bar, sejak %s", sym, total, n5, TimeToString(from, TIME_DATE));
  }

void HistExportCheck()
  {
   if(MQLInfoInteger(MQL_TESTER) != 0) return;
   string v = ReadTxtFlag("10algo_export_req.txt", g_expSeen);
   if(g_expSeen == "#") { g_expSeen = v; return; }
   if(v != "" && v != g_expSeen)
     {
      g_expSeen = v; g_expId = (StringFind(v, "batal") >= 0 ? "" : v); g_expTry = 0; g_expNext = 0;
      if(g_expId == "") { Print("10algo: ekspor riwayat dibatalkan"); return; }
      string p[]; g_expFrom = D'2022.05.01';
      if(StringSplit(v, ' ', p) >= 2) { datetime f = StringToTime(p[1]); if(f > 0) g_expFrom = f; }
      PrintFormat("10algo: permintaan ekspor riwayat %s diterima (sejak %s)", v, TimeToString(g_expFrom, TIME_DATE));
     }
   if(g_expId == "") return;
   datetime now = TimeCurrent();
   if(now < g_expNext) return;
   MqlDateTime t; TimeToStruct(now, t);
   if(t.hour >= 11 && t.hour <= 13) { g_expNext = now + 300; return; }
   string ag = (StringFind(g_expId, "perak") >= 0 ? SilverSymbol() : "");
   datetime srvFirst = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_SERVER_FIRSTDATE);
   datetime from = (g_expFrom > srvFirst ? g_expFrom : srvFirst);
   bool ready = HistReady(_Symbol, from) && (ag == "" || HistReady(ag, from));
   if(!ready && g_expTry < 600)
     {
      g_expTry++; g_expNext = now + 3;
      if(g_expTry % 20 == 1)
      PrintFormat("10algo: mengunduh riwayat (%d): M1 %s mulai %s, M5 mulai %s", g_expTry, _Symbol,
                  TimeToString((datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_FIRSTDATE), TIME_DATE),
                  TimeToString((datetime)SeriesInfoInteger(_Symbol, PERIOD_M5, SERIES_FIRSTDATE), TIME_DATE));
      return;
     }
   int hg[6] = {11, 12, 13, 16, 17, 18};
   HistWrite(_Symbol, from, hg);
   if(ag != "")
     {
      int hs[3] = {13, 14, 15};
      HistWrite(ag, from, hs);
     }
   g_expId = "";
  }

// v1.13: catatan hasil "bayangan" A10 + pengaman A/B per hari kandidat (untuk pengaman C)
double ShSum(int n)
  {
   int k = ArraySize(g_shVal);
   if(n <= 0 || k == 0) return 0.0;
   double t = 0.0;
   for(int i = MathMax(0, k - n); i < k; i++) t += g_shVal[i];
   return t;
  }

void ShAdd(int ymd, double v, bool persist)
  {
   int k = ArraySize(g_shDay);
   for(int i = 0; i < k; i++) if(g_shDay[i] == ymd) { g_shVal[i] = v; return; }
   ArrayResize(g_shDay, k + 1); ArrayResize(g_shVal, k + 1);
   int j = k;
   while(j > 0 && g_shDay[j - 1] > ymd) { g_shDay[j] = g_shDay[j - 1]; g_shVal[j] = g_shVal[j - 1]; j--; }
   g_shDay[j] = ymd; g_shVal[j] = v;
   if(persist)
     {
      int h = FileOpen("10algo_shadow_" + IntegerToString(InpMagic) + ".csv", FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
      if(h != INVALID_HANDLE) { FileSeek(h, 0, SEEK_END); FileWriteString(h, StringFormat("%d,%.4f\r\n", ymd, v)); FileClose(h); }
     }
  }

void ShLoad()
  {
   ArrayResize(g_shDay, 0); ArrayResize(g_shVal, 0);
   for(int i = 0; i < ArraySize(SH_SEED_DAY); i++) ShAdd(SH_SEED_DAY[i], SH_SEED_VAL[i], false);
   string fn = "10algo_shadow_" + IntegerToString(InpMagic) + ".csv";
   if(!FileIsExist(fn)) return;
   int h = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
     {
      string ln = FileReadString(h);
      string p[];
      if(StringSplit(ln, ',', p) == 2) ShAdd((int)StringToInteger(p[0]), StringToDouble(p[1]), false);
     }
   FileClose(h);
  }

// hasil hari ini dalam U kalau 10 lapis dibuka dengan aturan A10 + SL InpSLU (bar M1 bid + spread bar + komisi)
bool ShadowResult(datetime londonDay, double u20, double &res)
  {
   double o[12], hi[12], lo[12], sp[12], uk[10];
   for(int m = 0; m < 12; m++)
     {
      datetime t;
      if(!LondonToServer(londonDay + 10 * 3600 + (20 + m) * 60, t)) return false;
      int i = iBarShift(_Symbol, PERIOD_M1, t, true);
      if(i < 0) return false;
      o[m] = iOpen(_Symbol, PERIOD_M1, i); hi[m] = iHigh(_Symbol, PERIOD_M1, i); lo[m] = iLow(_Symbol, PERIOD_M1, i);
      sp[m] = (double)iSpread(_Symbol, PERIOD_M1, i) * _Point;
      if(m < 10) { uk[m] = CalcU(t); if(uk[m] <= 0.0) return false; }
     }
   res = 0.0;
   for(int k = 0; k < 10; k++)
     {
      double tp = o[k] - A10_TP_U * uk[k] - g_kom, sl = o[k] + InpSLU * uk[k] - g_kom, r = 0.0;
      bool done = false;
      for(int m = k; m < 11 && !done; m++)
        {
         if(hi[m] + sp[m] >= sl) { r = (o[k] - sl) / u20; done = true; }
         else if(lo[m] + sp[m] <= tp) { r = (o[k] - tp) / u20; done = true; }
        }
      if(!done) r = (o[k] - (o[11] + sp[11]) - g_kom) / u20;
      res += r;
     }
   return true;
  }

void ShadowCheck()
  {
   if(!g_shPending || MQLInfoInteger(MQL_TESTER) != 0) return;
   datetime ldn;
   if(!ServerToLondon(TimeCurrent(), ldn)) return;
   if(ldn < g_shDayL + 10 * 3600 + 33 * 60) return;
   g_shPending = false;
   MqlDateTime d; TimeToStruct(g_shDayL, d);
   int ymd = d.year * 10000 + d.mon * 100 + d.day;
   double v = 0.0;
   if(!g_skipA && !ShadowResult(g_shDayL, g_shU, v)) { Print("10algo: hasil bayangan hari ini gagal dihitung (bar M1 tidak lengkap)"); return; }
   ShAdd(ymd, v, true);
   PrintFormat("10algo: hasil bayangan %d = %+.3f U%s | jumlah %d hari aktif terakhir = %+.2f U (%s)", ymd, v, g_skipA ? " (dilewati pengaman A)" : "",
               InpRezimHari, ShSum(InpRezimHari), ShSum(InpRezimHari) < 0 ? "pengaman C: ISTIRAHAT besok" : "boleh trading");
  }

void Housekeeping()
  {
   ShadowCheck();
   HistExportCheck();
   ExportHistory();
   if(g_statsDirty || TimeCurrent() - g_statsAt >= 30) ComputeStats();
   if(!g_prepared && !g_fatal && (ArraySize(g_wkStart) > 0 || g_clockOK)) Preview();
   if(TimeCurrent() - g_stateAt >= 30) { g_stateAt = TimeCurrent(); WriteState(); }
   CheckReloadFlag();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, g_pfx) != 0) return;
   string b = StringSubstr(sparam, StringLen(g_pfx));
   if(b == "btn_pause")
     {
      g_paused = !g_paused;
      GlobalVariableSet(PauseKey(), g_paused ? 1.0 : 0.0);
      Print("10algo: ", g_paused ? "PAUSE dari panel - lapis baru dihentikan" : "dilanjutkan dari panel");
     }
   else if(b == "btn_close")
     {
      if(TimeLocal() <= g_confirmUntil)
        {
         g_confirmUntil = 0;
         Print("10algo: TUTUP SEMUA dari panel (", CountPositions(), " posisi)");
         CloseAll();
        }
      else g_confirmUntil = TimeLocal() + 5;
     }
   else if(b == "btn_min")
     {
      g_mini = !g_mini;
      ObjectsDeleteAll(0, g_pfx, 0, OBJ_LABEL);
      ObjectsDeleteAll(0, g_pfx, 0, OBJ_RECTANGLE_LABEL);
      ObjectsDeleteAll(0, g_pfx, 0, OBJ_BUTTON);
     }
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   datetime ldn = 0;
   bool ok = ServerToLondon(TimeCurrent(), ldn);
   DrawPanel(ldn, ok);
  }

void ShowStatus(datetime ldn, bool ldnOK)
  {
   if(MQLInfoInteger(MQL_TESTER) != 0 && MQLInfoInteger(MQL_VISUAL_MODE) == 0)
      return;
   if(ldnOK) DrawWindowLines(ldn);
   DrawPanel(ldn, ldnOK);
  }

void Prepare(datetime nowServer, datetime londonDay)
  {
   g_prepared = true; g_active = false; g_u = 0.0;
   if(!g_fatal && PriceNotGold())
     {
      g_fatal = true;
      g_fatalMsg = StringFormat("simbol %s bukan emas per ons (mata uang dasar %s, harga %.2f); pasang di chart XAUUSD", _Symbol, SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE), SymbolInfoDouble(_Symbol, SYMBOL_BID));
      Print("10algo TIDAK BISA JALAN: ", g_fatalMsg);
     }
   if(InpLotLapis <= 0.0 || g_fatal)
     {
      g_dayNote = "tidak trade (" + g_fatalMsg + ")";
      return;
     }
   if(IsUKHoliday(londonDay))
     {
      g_dayNote = "libur bank Inggris - tidak ada lelang";
      Print("10algo: hari libur bank Inggris - tidak ada lelang, hari ini dilewati");
      return;
     }
   if(!SellAllowed())
     {
      g_dayNote = StringFormat("tidak trade: broker tidak mengizinkan order jual baru di %s saat ini (mode trade simbol %d)", _Symbol, (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE));
      Print("10algo: ", g_dayNote);
      return;
     }
   EnsureServerTime(true);
   if(!CheckServerTime(nowServer))
     {
      g_dayNote = "tidak trade: " + g_tzNote;
      Print("10algo: ", g_dayNote);
      if(MQLInfoInteger(MQL_TESTER) == 0)
         Alert("10algo ", _Symbol, ": ", g_tzNote);
      return;
     }
   bool nyala = SwitchOn(londonDay, g_switch, g_switchN);
   if(g_switchN < A10_SWITCH_MIN)
     {
      g_dayNote = StringFormat("tidak trade: riwayat untuk sakelar baru %d hari (perlu %d). Riwayat M1 broker / terminal kurang panjang%s", g_switchN, A10_SWITCH_MIN,
                               TerminalInfoInteger(TERMINAL_MAXBARS) < 250000 ? " - atur Tools > Options > Charts > Max bars in chart = Unlimited" : "");
      Print("10algo: ", g_dayNote);
      return;
     }
   double u = CalcU(nowServer);
   if(u <= 0.0)
     {
      g_dayNote = "tidak trade: riwayat M5 belum cukup untuk menghitung U";
      Print("10algo: ", g_dayNote);
      return;
     }
   g_u = u;
   DetectCommission();
   g_cost = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) + g_kom;
   bool gerbang = (g_cost / u <= A10_MAX_COST_U);
   trade.SetDeviationInPoints((ulong)MathMax(10.0, MathRound(0.05 * u / _Point)));
   g_active = (nyala && gerbang);
   g_dayNote = (g_active ? "AKTIF" : (!nyala ? "tidak trade: sakelar mati" : "tidak trade: gerbang biaya tertutup"));
   g_candidate = g_active; g_skipA = false; g_skipC = false; g_pre80 = 0.0;
   if(g_candidate)
     {
      g_shPending = true; g_shDayL = londonDay; g_shU = u;
      datetime t9;
      if(LondonToServer(londonDay + 9 * 3600, t9))
        {
         int i9 = iBarShift(_Symbol, PERIOD_M1, t9, false);
         if(i9 >= 0) g_pre80 = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - iOpen(_Symbol, PERIOD_M1, i9)) / u;
        }
      if(InpLonjakanU > 0.0 && g_pre80 >= InpLonjakanU)
        {
         g_skipA = true; g_active = false;
         g_dayNote = StringFormat("tidak trade: PENGAMAN A - emas sudah naik %.1f U sejak 09:00 London (batas %.1f U)", g_pre80, InpLonjakanU);
         Print("10algo: ", g_dayNote);
        }
      double rz = ShSum(InpRezimHari);
      if(!g_skipA && InpRezimHari > 0 && ArraySize(g_shVal) >= InpRezimHari && rz < 0.0)
        {
         g_skipC = true; g_active = false;
         g_dayNote = StringFormat("tidak trade: PENGAMAN C - istirahat, hasil bayangan %d hari aktif terakhir %+.2f U", InpRezimHari, rz);
         Print("10algo: ", g_dayNote);
        }
     }
   if(InpRisiko > 0.0)
     {
      g_lots = RiskLots(u);
      PrintFormat("10algo: lot hari ini %.2f per lapis = %.2f%% x saldo %s / (U %.3f x %.2f per lot)", g_lots, InpRisiko,
                  Usd(AccountInfoDouble(ACCOUNT_BALANCE)), u, ValuePerPrice());
     }
   g_guardNote = "";
   if(g_active)
     {
      string gw = GuardWhy(u);                         // 10algo: hanya PAUSE manual
      if(gw != "")
        {
         g_active = false;
         g_dayNote = "tidak trade: " + gw;
         g_guardNote = gw;
         Print("10algo: hari ini dilewati - ", gw);
        }
     }
   PrintFormat("10algo %s: U = %.3f, sakelar = %+.3f U dari %d hari (%s), biaya = %.3f = %.4f U (gerbang %s), komisi %.3f%s -> %s | %s",
               TimeToString(londonDay, TIME_DATE), u, g_switch, g_switchN, nyala ? "NYALA" : "MATI", g_cost, g_cost / u, gerbang ? "terbuka" : "TERTUTUP",
               g_kom, g_komKnown ? "" : " (belum ada riwayat deal)", g_active ? "AKTIF" : "tidak trade", g_tzNote);
  }

int OnInit()
  {
   trade.SetExpertMagicNumber((ulong)InpMagic);
   if(!trade.SetTypeFillingBySymbol(_Symbol))
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
   g_fatal = false; g_fatalMsg = "";
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vlimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(vstep <= 0.0)
      vstep = (vmin > 0.0 ? vmin : 0.01);
   g_lots = NormalizeDouble(MathRound(InpLotLapis / vstep) * vstep, 8);
   if(InpLotLapis <= 0.0 || g_lots <= 0.0)
     {
      g_fatal = true; g_fatalMsg = "lot harus lebih besar dari nol";
     }
   else if(vmin > 0.0 && g_lots < vmin - 1e-9)
     {
      g_fatal = true; g_fatalMsg = StringFormat("lot %.4f di bawah lot minimum broker %.4f", InpLotLapis, vmin);
     }
   else if(vmax > 0.0 && g_lots > vmax + 1e-9)
     {
      g_fatal = true; g_fatalMsg = StringFormat("lot %.2f di atas lot maksimum broker %.2f", InpLotLapis, vmax);
     }
   else if(vlimit > 0.0 && g_lots * A10_LAYERS > vlimit + 1e-9)
     {
      g_fatal = true; g_fatalMsg = StringFormat("10 lapis x %.2f lot melebihi batas volume simbol %.2f", g_lots, vlimit);
     }
   if(!g_fatal && (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      g_fatal = true; g_fatalMsg = "akun ini netting; A10 butuh akun hedging (tiap lapis punya TP dan stop sendiri)";
     }
   string inSym = InpSymbol;
   StringTrimLeft(inSym);
   StringTrimRight(inSym);
   g_manualSym = (inSym != "");
   if(!g_fatal && g_manualSym && StringCompare(inSym, _Symbol, false) != 0)
     {
      bool custom = false;
      g_fatal = true;
      g_fatalMsg = SymbolExist(inSym, custom) ? "pasang EA di chart " + inSym + " (sesuai input InpSymbol); sekarang di chart " + _Symbol :
                   "simbol " + inSym + " (input InpSymbol) tidak ada di broker ini; tulis persis seperti di Market Watch";
     }
   if(!g_fatal)
     {
      string nm = _Symbol; StringToUpper(nm);
      string dasar = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE), laba = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
      bool emas = (g_manualSym || dasar == "XAU" || StringFind(nm, "XAU") >= 0 || StringFind(nm, "GOLD") >= 0);
      if(!emas || (!g_manualSym && laba != "USD" && laba != "USC"))
        {
         g_fatal = true; g_fatalMsg = "pasang di chart emas terhadap dolar (XAUUSD) atau tulis nama simbol emas broker di input InpSymbol; simbol ini " +
                                      _Symbol + " (" + dasar + "/" + laba + ")";
        }
      else if(PriceNotGold())
        {
         g_fatal = true; g_fatalMsg = "simbol " + _Symbol + " (" + SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION) + ") bukan emas per ons; pasang di chart XAUUSD";
        }
     }
   if(g_fatal)
     {
      Print("10algo TIDAK BISA JALAN: ", g_fatalMsg);
      if(MQLInfoInteger(MQL_TESTER) == 0)
         Alert("10algo ", _Symbol, ": ", g_fatalMsg);
     }
   else
      PrintFormat("10algo v1.13 (A10 v1.23): %s%s, lot %s (masukan %.4f; langkah lot %.4f), kontrak %.2f unit per lot, akun %s, server %s | pengaman %s", _Symbol,
                  g_manualSym ? " (nama simbol dari input InpSymbol, pengecekan nama emas dilewati)" : "",
                  InpRisiko > 0.0 ? StringFormat("dari risiko %.2f%% saldo per 1U (dihitung tiap 10:20 London)", InpRisiko) : StringFormat("%.2f per lapis (tetap)", g_lots),
                  InpLotLapis, vstep,
                  SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), AccountInfoString(ACCOUNT_CURRENCY), AccountInfoString(ACCOUNT_SERVER),
                  StringFormat("A lonjakan %.1fU, B SL %.1fU, C rezim %d hari (%d catatan, jumlah %+.2fU)", InpLonjakanU, InpSLU, InpRezimHari, ArraySize(g_shVal), ShSum(InpRezimHari)));
   ArrayFree(g_rDay); ArrayFree(g_rVal);
   RLoad();
   ShLoad();
   ReadClock();
   ObjectsDeleteAll(0, g_pfx);                          // sisa panel lama / dari template -> gambar ulang dengan urutan benar
   g_sc = (InpPanelScale > 0.0 ? InpPanelScale : MathMax(1.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0));
   g_paused = (MQLInfoInteger(MQL_TESTER) == 0 && GlobalVariableCheck(PauseKey()) && GlobalVariableGet(PauseKey()) > 0.5);
   ApplyTheme();
   Comment("");
   g_statsDirty = true; g_pvAt = 0; g_vlDay = 0;
   if(MQLInfoInteger(MQL_TESTER) == 0)
      EventSetTimer(1);
   ShowStatus(0, false);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
   ObjectsDeleteAll(0, g_pfx);
#ifdef A10_DUMP
   int h = FileOpen("A10_gerak_dump.csv", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h != INVALID_HANDLE)
     {
      for(int i = 0; i < ArraySize(g_rDay); i++)
        {
         MqlDateTime d; TimeToStruct(g_rDay[i], d);
         FileWriteString(h, StringFormat("%04d%02d%02d;%.6f\r\n", d.year, d.mon, d.day, g_rVal[i]));
        }
      FileWriteString(h, "#minggu;jam server - New York (detik);suara\r\n");
      for(int i = 0; i < ArraySize(g_wkStart); i++)
         FileWriteString(h, StringFormat("#%s;%d;%d\r\n", TimeToString(g_wkStart[i], TIME_DATE | TIME_MINUTES), g_wkOff[i], g_wkVotes[i]));
      FileClose(h);
     }
#endif
  }

void OnTimer()
  {
   if(g_fatal)
      return;
   EnsureServerTime(false);
   datetime ldn = 0;
   bool ok = ServerToLondon(TimeCurrent(), ldn);
   if(!g_prepared)
      CheckServerTime(TimeCurrent());
   Housekeeping();
   ShowStatus(ldn, ok);
  }

void OnTick()
  {
   datetime now = TimeCurrent();
#ifdef A10_UJI_JEDA
   if(SimAwalTick())
      return;
#endif
   if(g_fatal)
      return;
   if(!EnsureServerTime(false))
      return;
   datetime ldn;
   if(!ServerToLondon(now, ldn))
      return;
   MqlDateTime L; TimeToStruct(ldn, L);
   int ymd = L.year * 10000 + L.mon * 100 + L.day;
   int mnt = L.hour * 60 + L.min;
   if(ymd != g_ymd)
     {
      g_ymd = ymd; g_prepared = false; g_active = false; g_layers = 0; g_lastMin = -1; g_tryMin = -1; g_tryCnt = 0; g_dayNote = "menunggu 10:20 London"; g_candidate = false; g_skipA = false; g_skipC = false; g_shPending = false;
     }
   if(mnt >= T_TUTUP || mnt < T_MULAI)
     {
      if(CountPositions() > 0)
#ifdef A10_UJI_JEDA
         SimTutup();
#else
         CloseAll();
#endif
      else
        {
         if(ArraySize(g_closeTk) > 0) { ArrayFree(g_closeTk); ArrayFree(g_closeAt); }
         if(ArraySize(g_vtTk) > 0) { ArrayFree(g_vtTk); ArrayFree(g_vtTP); }
        }
     }
   else if(g_vtPerlu || ArraySize(g_vtTk) > 0)
      ManageVirtualTP();
   if(now != g_lastComment)
     {
      g_lastComment = now;
      ShowStatus(ldn, true);
     }
   if(L.day_of_week == 0 || L.day_of_week == 6)
      return;
   if(mnt < T_MULAI || mnt >= T_MULAI + A10_LAYERS)
      return;
   if(!g_prepared)
      Prepare(now, DayStart(ldn));
   if(!g_active || mnt == g_lastMin || g_layers >= A10_LAYERS)
      return;
   double u = CalcU(now);
   if(u <= 0.0)
      return;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = NormalizeDouble(bid + InpSLU * u - g_kom, digits);
   double tp = NormalizeDouble(bid - A10_TP_U * u - g_kom, digits);
   double minD = MinStopDist();
   bool   tpMaya = (minD > 0.0 && ask - tp < minD + _Point);
   if(minD > 0.0 && minD < 1000.0 && sl - ask < minD + _Point)
      sl = NormalizeDouble(ask + minD + _Point, digits);
   string ket = StringFormat("10algo %02d:%02d", L.hour, L.min);
   g_lastMin = mnt;
   if(mnt != g_tryMin)
     {
      g_tryMin = mnt; g_tryCnt = 0;
     }
#ifdef A10_UJI_JEDA
   if(SimJadwalMasuk(sl, tp, ket))
      return;
#endif
   if(g_paused)
     {
      g_dayNote = "AKTIF, tetapi PAUSE dari panel - lapis " + ket + " dilewati";
      return;
     }
   if(!TradingAllowed())
     {
      g_dayNote = "AKTIF, tetapi Algo Trading belum diizinkan - lapis " + ket + " dilewati";
      return;
     }
   g_tryCnt++;
   if(trade.Sell(g_lots, _Symbol, 0.0, sl, tpMaya ? 0.0 : tp, ket))
     {
      g_layers++;
      if(tpMaya)
        {
         VtAdd(trade.ResultOrder(), tp);
         g_vtPerlu = true;
        }
      g_dayNote = StringFormat("AKTIF, lapis terbuka %d dari %d", g_layers, A10_LAYERS);
     }
   else
      EntryFailed(ket);
  }
