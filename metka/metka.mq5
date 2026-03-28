//+------------------------------------------------------------------+
//|                                                        metka.mq5 |
//|           Non-repainting indicator v27                            |
//|           Развороты + сжатия + дивергенция + 4 фильтра            |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "28.00"
#property description "Неперерисовывающийся индикатор с комплексной фильтрацией"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   4

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_COLOR_ARROW
#property indicator_color1  clrDodgerBlue,clrBlack
#property indicator_width1  2

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_COLOR_ARROW
#property indicator_color2  clrOrangeRed,clrBlack
#property indicator_width2  2

#property indicator_label3  "Strong Buy"
#property indicator_type3   DRAW_COLOR_ARROW
#property indicator_color3  clrLime,clrBlack
#property indicator_width3  5

#property indicator_label4  "Strong Sell"
#property indicator_type4   DRAW_COLOR_ARROW
#property indicator_color4  clrDeepPink,clrBlack
#property indicator_width4  5

//═══════════════════════════════════════════════════════════════
// ОСНОВНІ ПАРАМЕТРИ
//═══════════════════════════════════════════════════════════════
input int              InpFastPeriod  = 20;             // EMA швидка
input int              InpSlowPeriod  = 50;             // EMA повільна
input int              InpATRPeriod   = 20;             // ATR період
input double           InpSpikeATR    = 1.2;            // Pin Bar: мін. розмір в ATR
input ENUM_TIMEFRAMES  InpHTF         = PERIOD_CURRENT; // Старший ТФ (Current = авто)
input int              InpCooldown    = 5;              // Мін. барів між сигналами
input bool             InpTrendFilter = false;          // Тренд фільтр (блок контр-тренд)

//═══════════════════════════════════════════════════════════════
// МЕТОД 5: RSI ДИВЕРГЕНЦІЯ
//═══════════════════════════════════════════════════════════════
input bool             InpDivEnabled  = true;           // ── Дивергенція: вкл/викл
input int              InpDivLookback = 30;             // ── Дивергенція: вікно пошуку

//═══════════════════════════════════════════════════════════════
// ФІЛЬТР 1: ОБ'ЄМ (блокує слабкі свічки)
//═══════════════════════════════════════════════════════════════
input bool             InpVolEnabled  = true;           // ── Об'єм: вкл/викл
input int              InpVolPeriod   = 10;             // ── Об'єм: період середнього
input double           InpVolMin      = 1.0;            // ── Об'єм: мін. відношення до сер.

//═══════════════════════════════════════════════════════════════
// ФІЛЬТР 2: ADX (блокує контр-тренд при сильному тренді)
//═══════════════════════════════════════════════════════════════
bool                   InpADXEnabled  = false;
int                    InpADXPeriod   = 14;
double                 InpADXLevel    = 30.0;

//═══════════════════════════════════════════════════════════════
// ФІЛЬТР 3: BOLLINGER BANDS (сигнал тільки біля крайніх зон)
//═══════════════════════════════════════════════════════════════
bool                   InpBBEnabled   = false;
int                    InpBBPeriod    = 20;
double                 InpBBDeviation = 2.0;
double                 InpBBBuyBelow  = 0.35;
double                 InpBBSellAbove = 0.65;

//═══════════════════════════════════════════════════════════════
// ФІЛЬТР 4: СВИНГ (сигнал тільки біля екстремумів)
//═══════════════════════════════════════════════════════════════
input bool             InpSwingEnabled = true;          // ── Свинг: вкл/викл
input int              InpSwingBars    = 15;            // ── Свинг: вікно пошуку
input double           InpSwingATR     = 1.5;           // ── Свинг: толеранс в ATR

//═══════════════════════════════════════════════════════════════
// АЛЕРТИ
//═══════════════════════════════════════════════════════════════
input int              InpPreSignalSec = 10;            // Попередження за N секунд
input bool             InpAlerts      = true;           // Алерти
input bool             InpPush        = false;          // Push-повідомлення

//═══════════════════════════════════════════════════════════════
// СТАТИСТИКА
//═══════════════════════════════════════════════════════════════
input bool             InpShowStats   = false;          // Панель статистики
input int              InpStatHours   = 168;            // Період аналізу (годин)
input int              InpStatTarget  = 100;            // Ціль (пунктів)
input int              InpStatPct     = 85;             // Перцентиль просадки (%)

double BuyBuf[], SellBuf[];
double StrongBuyBuf[], StrongSellBuf[];
double BuyClrBuf[], SellClrBuf[];
double StrongBuyClrBuf[], StrongSellClrBuf[];

int hEmaFast, hEmaSlow, hATR, hADX, hBB, hRSI;
int hHTFEmaFast, hHTFEmaSlow;
ENUM_TIMEFRAMES htfPeriod;
datetime lastAlertTime;
datetime lastDotBarTime;
bool     dotAlerted;

const int REV_LOOKBACK  = 5;
const int SQZ_LOOKBACK  = 6;
const int DIV_SW        = 3;
const int MAX_SPREAD    = 70;
const int RSI_PERIOD    = 14;
const string g_statPfx  = "MtkSt_";

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES AutoHTF(ENUM_TIMEFRAMES tf)
{
   if(tf <= PERIOD_M1)   return PERIOD_M15;
   if(tf <= PERIOD_M5)   return PERIOD_M30;
   if(tf <= PERIOD_M15)  return PERIOD_H1;
   if(tf <= PERIOD_M30)  return PERIOD_H4;
   if(tf <= PERIOD_H1)   return PERIOD_H4;
   if(tf <= PERIOD_H4)   return PERIOD_D1;
   if(tf <= PERIOD_H12)  return PERIOD_D1;
   if(tf <= PERIOD_D1)   return PERIOD_W1;
   return PERIOD_MN1;
}

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BuyBuf,           INDICATOR_DATA);
   SetIndexBuffer(1, BuyClrBuf,        INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, SellBuf,          INDICATOR_DATA);
   SetIndexBuffer(3, SellClrBuf,       INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, StrongBuyBuf,     INDICATOR_DATA);
   SetIndexBuffer(5, StrongBuyClrBuf,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6, StrongSellBuf,    INDICATOR_DATA);
   SetIndexBuffer(7, StrongSellClrBuf, INDICATOR_COLOR_INDEX);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);

   for(int p = 0; p < 4; p++)
   {
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
      PlotIndexSetInteger(p, PLOT_COLOR_INDEXES, 2);
   }
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrDodgerBlue);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, clrBlack);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, clrOrangeRed);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 1, clrBlack);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 0, clrLime);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 1, clrBlack);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, clrDeepPink);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 1, clrBlack);

   if(InpHTF == PERIOD_CURRENT || InpHTF <= _Period)
      htfPeriod = AutoHTF(_Period);
   else
      htfPeriod = InpHTF;

   hEmaFast    = iMA(_Symbol,  _Period,   InpFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow    = iMA(_Symbol,  _Period,   InpSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hATR        = iATR(_Symbol, _Period,   InpATRPeriod);
   hHTFEmaFast = iMA(_Symbol,  htfPeriod, InpFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hHTFEmaSlow = iMA(_Symbol,  htfPeriod, InpSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hADX        = iADX(_Symbol, _Period,   InpADXPeriod);
   hBB         = iBands(_Symbol, _Period,  InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hRSI        = iRSI(_Symbol, _Period,   RSI_PERIOD, PRICE_CLOSE);

   if(hEmaFast == INVALID_HANDLE || hEmaSlow == INVALID_HANDLE ||
      hATR == INVALID_HANDLE     || hADX == INVALID_HANDLE     ||
      hBB  == INVALID_HANDLE     || hRSI == INVALID_HANDLE     ||
      hHTFEmaFast == INVALID_HANDLE || hHTFEmaSlow == INVALID_HANDLE)
   {
      Print("Metka: помилка створення хендлів");
      return(INIT_FAILED);
   }

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("Metka v28 (%s)", EnumToString(htfPeriod)));

   lastAlertTime  = 0;
   lastDotBarTime = 0;
   dotAlerted     = false;
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectDelete(0, "MetkaDotUp");
   ObjectDelete(0, "MetkaDotDn");
   ObjectsDeleteAll(0, g_statPfx);
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaSlow);
   IndicatorRelease(hATR);
   IndicatorRelease(hHTFEmaFast);
   IndicatorRelease(hHTFEmaSlow);
   IndicatorRelease(hADX);
   IndicatorRelease(hBB);
   IndicatorRelease(hRSI);
}

//+------------------------------------------------------------------+
bool GetHTFTrend(const datetime barTime,
                 const double &htfEf[], const double &htfEs[],
                 int htfBars,
                 bool &htfUp, bool &htfDn)
{
   int shift = iBarShift(_Symbol, htfPeriod, barTime, false);
   int idx   = htfBars - 1 - shift;
   if(idx < 1 || idx >= htfBars)
      return false;

   htfUp = htfEf[idx] > htfEs[idx];
   htfDn = htfEf[idx] < htfEs[idx];
   return true;
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpPreSignalSec <= 0)
      return;

   datetime barStart = iTime(_Symbol, _Period, 0);
   int      barSec   = PeriodSeconds(_Period);
   if(barSec <= 0) return;

   datetime barEnd   = barStart + barSec;
   datetime now      = TimeCurrent();
   int      remain   = (int)(barEnd - now);

   ObjectDelete(0, "MetkaDotUp");
   ObjectDelete(0, "MetkaDotDn");

   if(remain > InpPreSignalSec || remain < 0)
   {
      dotAlerted = false;
      return;
   }

   int bars = iBars(_Symbol, _Period);
   int minBars = MathMax(InpSlowPeriod, InpATRPeriod) +
                 MathMax(InpDivLookback + DIV_SW, MathMax(InpSwingBars, InpVolPeriod)) + 20;
   if(bars < minBars)
      return;

   //--- ціни
   double o[], h[], l[], c[];
   long   tv[];
   datetime t[];
   if(CopyOpen(_Symbol, _Period,  0, bars, o) <= 0) return;
   if(CopyHigh(_Symbol, _Period,  0, bars, h) <= 0) return;
   if(CopyLow(_Symbol, _Period,   0, bars, l) <= 0) return;
   if(CopyClose(_Symbol, _Period, 0, bars, c) <= 0) return;
   if(CopyTickVolume(_Symbol, _Period, 0, bars, tv) <= 0) return;
   if(CopyTime(_Symbol, _Period,  0, bars, t) <= 0) return;

   //--- індикатори
   double ef[], es[], atrArr[];
   if(CopyBuffer(hEmaFast, 0, 0, bars, ef)     <= 0) return;
   if(CopyBuffer(hEmaSlow, 0, 0, bars, es)     <= 0) return;
   if(CopyBuffer(hATR,     0, 0, bars, atrArr) <= 0) return;

   double adxMain[], adxPlus[], adxMinus[];
   if(CopyBuffer(hADX, 0, 0, bars, adxMain)  <= 0) return;
   if(CopyBuffer(hADX, 1, 0, bars, adxPlus)  <= 0) return;
   if(CopyBuffer(hADX, 2, 0, bars, adxMinus) <= 0) return;

   double bbUpper[], bbLower[];
   if(CopyBuffer(hBB, 1, 0, bars, bbUpper) <= 0) return;
   if(CopyBuffer(hBB, 2, 0, bars, bbLower) <= 0) return;

   double rsi[];
   if(CopyBuffer(hRSI, 0, 0, bars, rsi) <= 0) return;

   //--- HTF
   int htfBars = iBars(_Symbol, htfPeriod);
   double htfEf2[], htfEs2[];
   if(CopyBuffer(hHTFEmaFast, 0, 0, htfBars, htfEf2) <= 0) return;
   if(CopyBuffer(hHTFEmaSlow, 0, 0, htfBars, htfEs2) <= 0) return;

   int i = bars - 1;
   bool preBuy = false, preSell = false;

   double sqzAvgRange = 0;
   for(int j = 1; j <= SQZ_LOOKBACK && (i - j) >= 0; j++)
      sqzAvgRange += h[i - j] - l[i - j];
   sqzAvgRange /= SQZ_LOOKBACK;
   bool squeezed = sqzAvgRange < atrArr[i] * 0.5;

   //--- Method 2: Pin bar
   {
      double rng = h[i] - l[i];
      if(rng > atrArr[i] * InpSpikeATR && rng > _Point)
      {
         double upperW = h[i] - MathMax(o[i], c[i]);
         double lowerW = MathMin(o[i], c[i]) - l[i];
         double mid    = (h[i] + l[i]) * 0.5;
         if(lowerW > rng * 0.5 && c[i] > mid) preBuy  = true;
         if(upperW > rng * 0.5 && c[i] < mid) preSell = true;
      }
   }

   //--- Method 3: Momentum reversal
   if(!preBuy && !preSell)
   {
      double priorMom = 0, sumBody = 0;
      int bearC = 0, bullC = 0;
      for(int j = 1; j <= REV_LOOKBACK && (i - j) >= 0; j++)
      {
         double b = c[i - j] - o[i - j];
         priorMom += b;
         sumBody  += MathAbs(b);
         if(b < 0) bearC++;
         if(b > 0) bullC++;
      }
      double avgBody = sumBody / REV_LOOKBACK;
      double curBody = c[i] - o[i];
      double absBody = MathAbs(curBody);
      double rng     = h[i] - l[i];
      bool strongBar = absBody > atrArr[i] * 0.3
                    && absBody > avgBody
                    && rng > _Point
                    && absBody > rng * 0.4;

      if(bearC >= 3 && priorMom < -atrArr[i] * 0.7 && curBody > 0 && strongBar)
         preBuy = true;
      if(bullC >= 3 && priorMom >  atrArr[i] * 0.7 && curBody < 0 && strongBar)
         preSell = true;
   }

   //--- Method 4: Squeeze breakout (с HTF)
   if(!preBuy && !preSell && squeezed)
   {
      double rng  = h[i] - l[i];
      double body = MathAbs(c[i] - o[i]);
      if(rng > atrArr[i] && body > rng * 0.5)
      {
         bool hUp = false, hDn = false;
         if(GetHTFTrend(t[i], htfEf2, htfEs2, htfBars, hUp, hDn))
         {
            if(c[i] > o[i] && hUp) preBuy  = true;
            if(c[i] < o[i] && hDn) preSell = true;
         }
      }
   }

   //--- Method 5: RSI Divergence
   if(!preBuy && !preSell && InpDivEnabled)
   {
      int swLow1 = -1, swLow2 = -1;
      int swHigh1 = -1, swHigh2 = -1;

      for(int k = DIV_SW; k <= InpDivLookback && (i - k) >= DIV_SW; k++)
      {
         int bi = i - k;

         bool isSwLow = true;
         for(int j = 1; j <= DIV_SW; j++)
         {
            if(l[bi] >= l[bi - j] || l[bi] >= l[bi + j])
            { isSwLow = false; break; }
         }
         if(isSwLow)
         {
            if(swLow1 < 0) swLow1 = bi;
            else if(swLow2 < 0) swLow2 = bi;
         }

         bool isSwHigh = true;
         for(int j = 1; j <= DIV_SW; j++)
         {
            if(h[bi] <= h[bi - j] || h[bi] <= h[bi + j])
            { isSwHigh = false; break; }
         }
         if(isSwHigh)
         {
            if(swHigh1 < 0) swHigh1 = bi;
            else if(swHigh2 < 0) swHigh2 = bi;
         }

         if(swLow2 >= 0 && swHigh2 >= 0) break;
      }

      if(swLow1 >= 0 && swLow2 >= 0)
      {
         if(l[swLow1] < l[swLow2] && rsi[swLow1] > rsi[swLow2] + 3.0)
         {
            if(i - swLow1 <= DIV_SW + 2 && c[i] > o[i])
               preBuy = true;
         }
      }
      if(swHigh1 >= 0 && swHigh2 >= 0)
      {
         if(h[swHigh1] > h[swHigh2] && rsi[swHigh1] < rsi[swHigh2] - 3.0)
         {
            if(i - swHigh1 <= DIV_SW + 2 && c[i] < o[i])
               preSell = true;
         }
      }
   }

   if(!preBuy && !preSell)
      return;

   //--- Спред (константа)
   {
      int curSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(curSpread > MAX_SPREAD) return;
   }

   //--- Тренд фільтр
   if(InpTrendFilter)
   {
      if(preBuy  && ef[i] < es[i]) preBuy  = false;
      if(preSell && ef[i] > es[i]) preSell = false;
   }
   if(!preBuy && !preSell) return;

   //--- Фільтр 2: ADX
   if(InpADXEnabled)
   {
      if(adxMain[i] > InpADXLevel)
      {
         if(preBuy  && adxPlus[i] < adxMinus[i]) preBuy  = false;
         if(preSell && adxPlus[i] > adxMinus[i]) preSell = false;
      }
   }
   if(!preBuy && !preSell) return;

   //--- Фільтр 3: BB
   if(InpBBEnabled)
   {
      double bbWidth = bbUpper[i] - bbLower[i];
      if(bbWidth > _Point)
      {
         double bbPct = (c[i] - bbLower[i]) / bbWidth;
         if(preBuy  && bbPct > InpBBBuyBelow)   preBuy  = false;
         if(preSell && bbPct < InpBBSellAbove)  preSell = false;
      }
   }
   if(!preBuy && !preSell) return;

   //--- Фільтр 4: Свинг
   if(InpSwingEnabled)
   {
      if(preBuy)
      {
         double lowestLow = l[i];
         for(int k = 1; k <= InpSwingBars && (i - k) >= 0; k++)
            if(l[i - k] < lowestLow) lowestLow = l[i - k];
         if(l[i] > lowestLow + atrArr[i] * InpSwingATR)
            preBuy = false;
      }
      if(preSell)
      {
         double highestHigh = h[i];
         for(int k = 1; k <= InpSwingBars && (i - k) >= 0; k++)
            if(h[i - k] > highestHigh) highestHigh = h[i - k];
         if(h[i] < highestHigh - atrArr[i] * InpSwingATR)
            preSell = false;
      }
   }
   if(!preBuy && !preSell) return;

   //--- Pre-signal dot
   double price = preBuy ? l[i] - _Point * 200 : h[i] + _Point * 200;
   string name  = preBuy ? "MetkaDotUp" : "MetkaDotDn";
   color  dotClr = preBuy ? clrLime : clrRed;

   ObjectCreate(0, name, OBJ_ARROW, 0, barStart, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, dotClr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);

   if(!dotAlerted && barStart != lastDotBarTime)
   {
      string dir = preBuy ? "BUY" : "SELL";
      string text = StringFormat("Metka PRE-%s | %s %s | %d сек",
                                  dir, _Symbol, EnumToString(_Period), remain);
      if(InpAlerts) Alert(text);
      if(InpPush)   SendNotification(text);
      dotAlerted     = true;
      lastDotBarTime = barStart;
   }
}

//+------------------------------------------------------------------+
void DrawBgPanel(const string name, ENUM_BASE_CORNER corner,
                 int xDist, int yDist, int xSize, int ySize)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xDist);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yDist);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, xSize);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, ySize);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawStatLabel(const string name, const string text, color clr, int yPos,
                   ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER,
                   int fontSize = 10, int xDist = 15)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ENUM_ANCHOR_POINT anch = ANCHOR_LEFT_UPPER;
   if(corner == CORNER_LEFT_LOWER)  anch = ANCHOR_LEFT_LOWER;
   if(corner == CORNER_RIGHT_UPPER) anch = ANCHOR_RIGHT_UPPER;
   if(corner == CORNER_RIGHT_LOWER) anch = ANCHOR_RIGHT_LOWER;

   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xDist);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yPos);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anch);
   ObjectSetString(0, name,  OBJPROP_TEXT, text);
   ObjectSetString(0, name,  OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

int GetSession(const datetime barTime)
{
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   int h = dt.hour;
   if(h >= 0  && h < 8)  return(0); // Asia
   if(h >= 8  && h < 16) return(1); // London
   if(h >= 16 && h < 24) return(2); // New York
   return(0);
}

int CalcP85(const int &allDD[], const int &allHr[], const int &allDir[], const int &allSess[],
            int total, int hrFilter, int dirFilter, int sessFilter)
{
   int tmp[];
   int cnt = 0;
   for(int i = 0; i < total; i++)
   {
      if(hrFilter >= 0   && allHr[i]   != hrFilter)   continue;
      if(dirFilter != 0  && allDir[i]  != dirFilter)  continue;
      if(sessFilter >= 0 && allSess[i] != sessFilter) continue;
      ArrayResize(tmp, cnt + 1);
      tmp[cnt] = allDD[i];
      cnt++;
   }
   if(cnt == 0) return(0);
   ArraySort(tmp);
   int idx = (int)MathFloor(cnt * InpStatPct / 100.0) - 1;
   if(idx < 0) idx = 0;
   return(tmp[idx]);
}

int CalcProfit(int hit, int total, int p85dd)
{
   int win  = (int)MathFloor((double)hit * InpStatPct / 100.0);
   int lose = total - win;
   return(win * InpStatTarget - lose * p85dd);
}

void SetArrowColor(int bar, int clrIdx)
{
   if(BuyBuf[bar] != EMPTY_VALUE)        BuyClrBuf[bar]        = clrIdx;
   if(SellBuf[bar] != EMPTY_VALUE)       SellClrBuf[bar]       = clrIdx;
   if(StrongBuyBuf[bar] != EMPTY_VALUE)  StrongBuyClrBuf[bar]  = clrIdx;
   if(StrongSellBuf[bar] != EMPTY_VALUE) StrongSellClrBuf[bar] = clrIdx;
}

void UpdateStatsPanel(const int rates_total, const int barLimit, const int minStart,
                      const double &open[], const double &high[], const double &low[],
                      const datetime &time[])
{
   static bool s_needReset = false;

   if(!InpShowStats)
   {
      ObjectsDeleteAll(0, g_statPfx);
      if(s_needReset)
      {
         for(int i = minStart; i <= barLimit; i++)
            SetArrowColor(i, 0);
         s_needReset = false;
         ChartRedraw(0);
      }
      return;
   }
   s_needReset = true;

   int sigBars[];
   int sigDirs[];
   int sigSess[];
   int sigCount = 0;

   datetime cutoff = time[barLimit] - InpStatHours * 3600;

   for(int i = barLimit; i >= minStart; i--)
   {
      if(time[i] < cutoff) break;

      bool isBuy  = (BuyBuf[i] != EMPTY_VALUE || StrongBuyBuf[i] != EMPTY_VALUE);
      bool isSell = (SellBuf[i] != EMPTY_VALUE || StrongSellBuf[i] != EMPTY_VALUE);

      if(isBuy || isSell)
      {
         ArrayResize(sigBars, sigCount + 1);
         ArrayResize(sigDirs, sigCount + 1);
         ArrayResize(sigSess, sigCount + 1);
         sigBars[sigCount] = i;
         sigDirs[sigCount] = isBuy ? 1 : -1;
         sigSess[sigCount] = GetSession(time[i]);
         sigCount++;
      }
   }

   for(int s = 0; s < sigCount; s++)
      SetArrowColor(sigBars[s], 0);

   int buyTotal = 0, buyHit = 0, buyMaxDD = 0;
   int sellTotal = 0, sellHit = 0, sellMaxDD = 0;
   int sessTotal[3] = {0, 0, 0};
   int sessHit[3]   = {0, 0, 0};
   int sessMaxDD[3] = {0, 0, 0};
   int hourTotal[24], hourHit[24], hourMaxDD[24];
   int hourBuyTotal[24], hourBuyHit[24], hourBuyDD[24];
   int hourSellTotal[24], hourSellHit[24], hourSellDD[24];
   ArrayInitialize(hourTotal, 0);
   ArrayInitialize(hourHit, 0);
   ArrayInitialize(hourMaxDD, 0);
   ArrayInitialize(hourBuyTotal, 0);
   ArrayInitialize(hourBuyHit, 0);
   ArrayInitialize(hourBuyDD, 0);
   ArrayInitialize(hourSellTotal, 0);
   ArrayInitialize(hourSellHit, 0);
   ArrayInitialize(hourSellDD, 0);
   double target = InpStatTarget * _Point;
   bool sigHit[];
   ArrayResize(sigHit, sigCount);
   int ddVals[], ddHrs[], ddDirs[], ddSesses[];
   int ddCount = 0;

   for(int s = 0; s < sigCount; s++)
   {
      int bar = sigBars[s];
      if(bar + 1 >= rates_total) { sigHit[s] = false; continue; }

      int nextSigBar = (s > 0) ? sigBars[s - 1] : rates_total - 1;
      double entry = open[bar + 1];
      int sess = sigSess[s];
      bool hit = false;
      int hitBar = -1;

      MqlDateTime mdt;
      TimeToStruct(time[bar], mdt);
      int hr = mdt.hour;

      if(sigDirs[s] == 1)
      {
         buyTotal++;
         sessTotal[sess]++;
         hourTotal[hr]++;
         hourBuyTotal[hr]++;
         for(int b = bar + 1; b <= nextSigBar && b < rates_total; b++)
         {
            if(high[b] >= entry + target) { hit = true; hitBar = b; break; }
         }
         if(hit)
         {
            buyHit++; sessHit[sess]++; hourHit[hr]++; hourBuyHit[hr]++;
            double minLow = entry;
            for(int b = bar + 1; b <= hitBar; b++)
               if(low[b] < minLow) minLow = low[b];
            int dd = (int)MathRound((entry - minLow) / _Point);
            if(dd > buyMaxDD)        buyMaxDD = dd;
            if(dd > sessMaxDD[sess]) sessMaxDD[sess] = dd;
            if(dd > hourMaxDD[hr])   hourMaxDD[hr] = dd;
            if(dd > hourBuyDD[hr])   hourBuyDD[hr] = dd;
            ArrayResize(ddVals, ddCount + 1);
            ArrayResize(ddHrs, ddCount + 1);
            ArrayResize(ddDirs, ddCount + 1);
            ArrayResize(ddSesses, ddCount + 1);
            ddVals[ddCount] = dd; ddHrs[ddCount] = hr;
            ddDirs[ddCount] = 1;  ddSesses[ddCount] = sess;
            ddCount++;
         }
      }
      else
      {
         sellTotal++;
         sessTotal[sess]++;
         hourTotal[hr]++;
         hourSellTotal[hr]++;
         for(int b = bar + 1; b <= nextSigBar && b < rates_total; b++)
         {
            if(low[b] <= entry - target) { hit = true; hitBar = b; break; }
         }
         if(hit)
         {
            sellHit++; sessHit[sess]++; hourHit[hr]++; hourSellHit[hr]++;
            double maxHigh = entry;
            for(int b = bar + 1; b <= hitBar; b++)
               if(high[b] > maxHigh) maxHigh = high[b];
            int dd = (int)MathRound((maxHigh - entry) / _Point);
            if(dd > sellMaxDD)       sellMaxDD = dd;
            if(dd > sessMaxDD[sess]) sessMaxDD[sess] = dd;
            if(dd > hourMaxDD[hr])   hourMaxDD[hr] = dd;
            if(dd > hourSellDD[hr])  hourSellDD[hr] = dd;
            ArrayResize(ddVals, ddCount + 1);
            ArrayResize(ddHrs, ddCount + 1);
            ArrayResize(ddDirs, ddCount + 1);
            ArrayResize(ddSesses, ddCount + 1);
            ddVals[ddCount] = dd; ddHrs[ddCount] = hr;
            ddDirs[ddCount] = -1; ddSesses[ddCount] = sess;
            ddCount++;
         }
      }
      sigHit[s] = hit;
   }

   for(int s = 0; s < sigCount; s++)
   {
      if(!sigHit[s])
         SetArrowColor(sigBars[s], 1);
   }

   //--- max consecutive wins per hour
   int buyMaxStrk[24], sellMaxStrk[24];
   ArrayInitialize(buyMaxStrk, 0);
   ArrayInitialize(sellMaxStrk, 0);
   int buyCurStrk[24], sellCurStrk[24];
   ArrayInitialize(buyCurStrk, 0);
   ArrayInitialize(sellCurStrk, 0);

   for(int s = sigCount - 1; s >= 0; s--)
   {
      MqlDateTime mdt2;
      TimeToStruct(time[sigBars[s]], mdt2);
      int hr2 = mdt2.hour;
      if(sigDirs[s] == 1)
      {
         if(sigHit[s]) { buyCurStrk[hr2]++; if(buyCurStrk[hr2] > buyMaxStrk[hr2]) buyMaxStrk[hr2] = buyCurStrk[hr2]; }
         else buyCurStrk[hr2] = 0;
      }
      else
      {
         if(sigHit[s]) { sellCurStrk[hr2]++; if(sellCurStrk[hr2] > sellMaxStrk[hr2]) sellMaxStrk[hr2] = sellCurStrk[hr2]; }
         else sellCurStrk[hr2] = 0;
      }
   }

   int allTotal = buyTotal + sellTotal;
   int allHit   = buyHit + sellHit;
   int allMaxDD = (int)MathMax(buyMaxDD, sellMaxDD);

   double buyPct  = buyTotal  > 0 ? 100.0 * buyHit  / buyTotal  : 0;
   double sellPct = sellTotal > 0 ? 100.0 * sellHit / sellTotal : 0;
   double allPct  = allTotal  > 0 ? 100.0 * allHit  / allTotal  : 0;

   int buyP70  = CalcP85(ddVals, ddHrs, ddDirs, ddSesses, ddCount, -1, 1,  -1);
   int sellP70 = CalcP85(ddVals, ddHrs, ddDirs, ddSesses, ddCount, -1, -1, -1);
   int allP70  = CalcP85(ddVals, ddHrs, ddDirs, ddSesses, ddCount, -1, 0,  -1);

   string buyDD  = buyHit  > 0 ? StringFormat("[%d] {%d}", buyMaxDD, buyP70)   : "[--]";
   string sellDD = sellHit > 0 ? StringFormat("[%d] {%d}", sellMaxDD, sellP70) : "[--]";
   string allDD  = allHit  > 0 ? StringFormat("[%d] {%d}", allMaxDD, allP70)   : "[--]";

   int buyProf  = buyTotal  > 0 ? CalcProfit(buyHit,  buyTotal,  buyP70)  : 0;
   int sellProf = sellTotal > 0 ? CalcProfit(sellHit, sellTotal, sellP70) : 0;
   int allProf  = allTotal  > 0 ? CalcProfit(allHit,  allTotal,  allP70)  : 0;

   //--- повний білий фон
   DrawBgPanel(g_statPfx + "BG0", CORNER_LEFT_UPPER, 0, 0, 5000, 5000);

   //--- верхня ліва панель
   int y = 40;

   DrawStatLabel(g_statPfx + "H",
      StringFormat("STATS  %d sig / %dh / %d pt target", sigCount, InpStatHours, InpStatTarget), clrBlack, y);
   y += 20;
   DrawStatLabel(g_statPfx + "GD",
      StringFormat("                        [100%%] {%d%%}", InpStatPct), clrGray, y, CORNER_LEFT_UPPER, 7);
   y += 18;
   DrawStatLabel(g_statPfx + "B",
      StringFormat("BUY   %d/%d (%.1f%%) %s ^%d^", buyHit, buyTotal, buyPct, buyDD, buyProf), clrGreen, y);
   y += 20;
   DrawStatLabel(g_statPfx + "S",
      StringFormat("SELL  %d/%d (%.1f%%) %s ^%d^", sellHit, sellTotal, sellPct, sellDD, sellProf), clrOrangeRed, y);
   y += 20;
   DrawStatLabel(g_statPfx + "A",
      StringFormat("ALL   %d/%d (%.1f%%) %s ^%d^", allHit, allTotal, allPct, allDD, allProf), clrBlack, y);
   y += 36;

   DrawStatLabel(g_statPfx + "SSH", "── SESSIONS ──", clrBlack, y);
   y += 16;
   DrawStatLabel(g_statPfx + "SD",
      StringFormat("                        [100%%] {%d%%}", InpStatPct), clrGray, y, CORNER_LEFT_UPPER, 7);
   y += 14;

   string sessNames[3] = {"ASIA    ", "LONDON  ", "NEW YORK"};
   string sessIds[3]   = {"SA", "SL", "SN"};

   for(int k = 0; k < 3; k++)
   {
      double pct = sessTotal[k] > 0 ? 100.0 * sessHit[k] / sessTotal[k] : 0;
      int sp85 = CalcP85(ddVals, ddHrs, ddDirs, ddSesses, ddCount, -1, 0, k);
      string sdd = sessHit[k] > 0 ? StringFormat("[%d] {%d}", sessMaxDD[k], sp85) : "[--]";
      int sProf = sessTotal[k] > 0 ? CalcProfit(sessHit[k], sessTotal[k], sp85) : 0;
      DrawStatLabel(g_statPfx + sessIds[k],
         StringFormat("%s %d/%d (%.0f%%) %s ^%d^", sessNames[k], sessHit[k], sessTotal[k], pct, sdd, sProf),
         clrBlack, y);
      y += 22;
   }

   //--- TOP streaks (exclude 100% winrate hours)
   y += 28;
   DrawStatLabel(g_statPfx + "TBH", "── TOP BUY STREAKS ──", clrGreen, y);
   y += 16;
   int bUsed[5]; ArrayInitialize(bUsed, -1);
   for(int n = 0; n < 5; n++)
   {
      int bestHr = -1, bestVal = 0;
      for(int h = 0; h < 24; h++)
      {
         if(hourBuyTotal[h] == 0 || hourBuyHit[h] == hourBuyTotal[h]) continue;
         bool skip = false;
         for(int u = 0; u < n; u++) if(bUsed[u] == h) { skip = true; break; }
         if(skip) continue;
         if(buyMaxStrk[h] > bestVal) { bestVal = buyMaxStrk[h]; bestHr = h; }
      }
      if(bestHr < 0) break;
      bUsed[n] = bestHr;
      DrawStatLabel(g_statPfx + "TB" + IntegerToString(n),
         StringFormat("%dh-%dh  %d streak  %d/%d (%.0f%%)", bestHr, (bestHr + 1) % 24,
            bestVal, hourBuyHit[bestHr], hourBuyTotal[bestHr],
            100.0 * hourBuyHit[bestHr] / hourBuyTotal[bestHr]),
         clrBlack, y);
      y += 16;
   }

   y += 20;
   DrawStatLabel(g_statPfx + "TSH", "── TOP SELL STREAKS ──", clrOrangeRed, y);
   y += 16;
   int sUsed[5]; ArrayInitialize(sUsed, -1);
   for(int n = 0; n < 5; n++)
   {
      int bestHr = -1, bestVal = 0;
      for(int h = 0; h < 24; h++)
      {
         if(hourSellTotal[h] == 0 || hourSellHit[h] == hourSellTotal[h]) continue;
         bool skip = false;
         for(int u = 0; u < n; u++) if(sUsed[u] == h) { skip = true; break; }
         if(skip) continue;
         if(sellMaxStrk[h] > bestVal) { bestVal = sellMaxStrk[h]; bestHr = h; }
      }
      if(bestHr < 0) break;
      sUsed[n] = bestHr;
      DrawStatLabel(g_statPfx + "TS" + IntegerToString(n),
         StringFormat("%dh-%dh  %d streak  %d/%d (%.0f%%)", bestHr, (bestHr + 1) % 24,
            bestVal, hourSellHit[bestHr], hourSellTotal[bestHr],
            100.0 * hourSellHit[bestHr] / hourSellTotal[bestHr]),
         clrBlack, y);
      y += 16;
   }

   //--- правая сторона: BUY и SELL по часам рядом
   int ry = 40;
   int rxBuy  = 420;
   int rxSell = 15;

   DrawStatLabel(g_statPfx + "BHH", "──── BUY BY HOUR ────", clrGreen, ry,
                 CORNER_RIGHT_UPPER, 8, rxBuy);
   DrawStatLabel(g_statPfx + "SHH", "──── SELL BY HOUR ────", clrOrangeRed, ry,
                 CORNER_RIGHT_UPPER, 8, rxSell);
   ry += 16;
   string hdrDD2 = StringFormat("                         [100%%] {%d%%}", InpStatPct);
   DrawStatLabel(g_statPfx + "BHD", hdrDD2, clrGray, ry,
                 CORNER_RIGHT_UPPER, 7, rxBuy);
   DrawStatLabel(g_statPfx + "SHD", hdrDD2, clrGray, ry,
                 CORNER_RIGHT_UPPER, 7, rxSell);
   ry += 14;

   for(int r = 0; r < 24; r++)
   {
      string bp = hourBuyHit[r] > 0 ? StringFormat("%.0f%%", 100.0 * hourBuyHit[r] / hourBuyTotal[r]) : "--";
      int bp70 = CalcP85(ddVals, ddHrs, ddDirs, ddSesses, ddCount, r, 1, -1);
      string bd = hourBuyHit[r] > 0 ? StringFormat("[%d] {%d}", hourBuyDD[r], bp70) : "";
      if(hourBuyTotal[r] == 0) { bp = "--"; bd = ""; }
      color bc = (hourBuyTotal[r] > 0 && hourBuyHit[r] == hourBuyTotal[r]) ? clrGreen : clrBlack;
      int bProf = hourBuyTotal[r] > 0 ? CalcProfit(hourBuyHit[r], hourBuyTotal[r], bp70) : 0;
      string bPrS = hourBuyTotal[r] > 0 ? StringFormat("^%d^", bProf) : "";
      DrawStatLabel(g_statPfx + "BH" + IntegerToString(r),
         StringFormat("%dh-%dh  %d/%-3d %3s %s ", r, (r + 1) % 24, hourBuyHit[r], hourBuyTotal[r], bp, bd) + bPrS,
         bc, ry, CORNER_RIGHT_UPPER, 8, rxBuy);
      if(hourBuyTotal[r] > 0)
         DrawStatLabel(g_statPfx + "PBH" + IntegerToString(r), bPrS,
            bProf >= 0 ? clrGreen : clrRed, ry, CORNER_RIGHT_UPPER, 8, rxBuy);

      string sp = hourSellHit[r] > 0 ? StringFormat("%.0f%%", 100.0 * hourSellHit[r] / hourSellTotal[r]) : "--";
      int sp70s = CalcP85(ddVals, ddHrs, ddDirs, ddSesses, ddCount, r, -1, -1);
      string sd = hourSellHit[r] > 0 ? StringFormat("[%d] {%d}", hourSellDD[r], sp70s) : "";
      if(hourSellTotal[r] == 0) { sp = "--"; sd = ""; }
      color sc = (hourSellTotal[r] > 0 && hourSellHit[r] == hourSellTotal[r]) ? clrGreen : clrBlack;
      int sProf2 = hourSellTotal[r] > 0 ? CalcProfit(hourSellHit[r], hourSellTotal[r], sp70s) : 0;
      string sPrS2 = hourSellTotal[r] > 0 ? StringFormat("^%d^", sProf2) : "";
      DrawStatLabel(g_statPfx + "SH" + IntegerToString(r),
         StringFormat("%dh-%dh  %d/%-3d %3s %s ", r, (r + 1) % 24, hourSellHit[r], hourSellTotal[r], sp, sd) + sPrS2,
         sc, ry, CORNER_RIGHT_UPPER, 8, rxSell);
      if(hourSellTotal[r] > 0)
         DrawStatLabel(g_statPfx + "PSH" + IntegerToString(r), sPrS2,
            sProf2 >= 0 ? clrGreen : clrRed, ry, CORNER_RIGHT_UPPER, 8, rxSell);

      ry += 16;
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int warmup  = MathMax(InpSlowPeriod, InpATRPeriod) + 2;
   int maxLook = MathMax(MathMax(REV_LOOKBACK, SQZ_LOOKBACK),
                 MathMax(MathMax(InpSwingBars, InpDivLookback + DIV_SW),
                 InpVolPeriod));
   int minStart = maxLook + warmup + 1;

   if(rates_total < minStart + 2)
      return(0);

   //--- копіюємо всі буфери одразу
   double ef[], es[], atr[];
   if(CopyBuffer(hEmaFast, 0, 0, rates_total, ef)  <= 0) return(0);
   if(CopyBuffer(hEmaSlow, 0, 0, rates_total, es)  <= 0) return(0);
   if(CopyBuffer(hATR,     0, 0, rates_total, atr) <= 0) return(0);

   double adxMain[], adxPlus[], adxMinus[];
   if(CopyBuffer(hADX, 0, 0, rates_total, adxMain)  <= 0) return(0);
   if(CopyBuffer(hADX, 1, 0, rates_total, adxPlus)  <= 0) return(0);
   if(CopyBuffer(hADX, 2, 0, rates_total, adxMinus) <= 0) return(0);

   double bbUpper[], bbLower[];
   if(CopyBuffer(hBB, 1, 0, rates_total, bbUpper) <= 0) return(0);
   if(CopyBuffer(hBB, 2, 0, rates_total, bbLower) <= 0) return(0);

   double rsi[];
   if(CopyBuffer(hRSI, 0, 0, rates_total, rsi) <= 0) return(0);

   //--- HTF
   int htfBars = iBars(_Symbol, htfPeriod);
   if(htfBars <= InpSlowPeriod + 1)
      return(0);

   double htfEf[], htfEs[];
   if(CopyBuffer(hHTFEmaFast, 0, 0, htfBars, htfEf) <= 0) return(0);
   if(CopyBuffer(hHTFEmaSlow, 0, 0, htfBars, htfEs) <= 0) return(0);

   int barLimit = rates_total - 2;

   int start;
   if(prev_calculated == 0)
   {
      ArrayInitialize(BuyBuf,        EMPTY_VALUE);
      ArrayInitialize(SellBuf,       EMPTY_VALUE);
      ArrayInitialize(StrongBuyBuf,  EMPTY_VALUE);
      ArrayInitialize(StrongSellBuf, EMPTY_VALUE);
      ArrayInitialize(BuyClrBuf,        0);
      ArrayInitialize(SellClrBuf,       0);
      ArrayInitialize(StrongBuyClrBuf,  0);
      ArrayInitialize(StrongSellClrBuf, 0);
      start = minStart;
      lastAlertTime = time[rates_total - 1];
   }
   else
      start = MathMax(prev_calculated - 2, minStart);

   for(int i = start; i <= barLimit; i++)
   {
      BuyBuf[i]        = EMPTY_VALUE;
      SellBuf[i]       = EMPTY_VALUE;
      StrongBuyBuf[i]  = EMPTY_VALUE;
      StrongSellBuf[i] = EMPTY_VALUE;
      BuyClrBuf[i]        = 0;
      SellClrBuf[i]       = 0;
      StrongBuyClrBuf[i]  = 0;
      StrongSellClrBuf[i] = 0;

      bool buySignal  = false;
      bool sellSignal = false;

      double sqzAvgRange = 0;
      for(int j = 1; j <= SQZ_LOOKBACK; j++)
         sqzAvgRange += high[i - j] - low[i - j];
      sqzAvgRange /= SQZ_LOOKBACK;
      bool squeezed = sqzAvgRange < atr[i] * 0.5;

      //============================================================
      // МЕТОД 2: PIN BAR
      //============================================================
      {
         double rng = high[i] - low[i];
         if(rng > atr[i] * InpSpikeATR && rng > _Point)
         {
            double upperW = high[i] - MathMax(open[i], close[i]);
            double lowerW = MathMin(open[i], close[i]) - low[i];
            double mid    = (high[i] + low[i]) * 0.5;

            if(lowerW > rng * 0.5 && close[i] > mid) buySignal  = true;
            if(upperW > rng * 0.5 && close[i] < mid) sellSignal = true;
         }
      }

      //============================================================
      // МЕТОД 3: РАЗВОРОТ ИМПУЛЬСА
      //============================================================
      if(!buySignal && !sellSignal)
      {
         double priorMom  = 0;
         double sumBody   = 0;
         int    bearCount = 0;
         int    bullCount = 0;

         for(int j = 1; j <= REV_LOOKBACK; j++)
         {
            double b = close[i - j] - open[i - j];
            priorMom += b;
            sumBody  += MathAbs(b);
            if(b < 0) bearCount++;
            if(b > 0) bullCount++;
         }

         double avgBody = sumBody / REV_LOOKBACK;
         double curBody = close[i] - open[i];
         double absBody = MathAbs(curBody);
         double rng     = high[i] - low[i];

         bool strongBar = absBody > atr[i] * 0.3
                       && absBody > avgBody
                       && rng > _Point
                       && absBody > rng * 0.4;

         if(bearCount >= 3 && priorMom < -atr[i] * 0.7
            && curBody > 0 && strongBar)
            buySignal = true;

         if(bullCount >= 3 && priorMom > atr[i] * 0.7
            && curBody < 0 && strongBar)
            sellSignal = true;
      }

      //============================================================
      // МЕТОД 4: SQUEEZE BREAKOUT (з HTF фільтром)
      //============================================================
      if(!buySignal && !sellSignal && squeezed)
      {
         double rng  = high[i] - low[i];
         double body = MathAbs(close[i] - open[i]);

         if(rng > atr[i] && body > rng * 0.5)
         {
            bool hUp = false, hDn = false;
            if(GetHTFTrend(time[i], htfEf, htfEs, htfBars, hUp, hDn))
            {
               if(close[i] > open[i] && hUp) buySignal  = true;
               if(close[i] < open[i] && hDn) sellSignal = true;
            }
         }
      }

      //============================================================
      // МЕТОД 5: RSI ДИВЕРГЕНЦІЯ
      //============================================================
      if(!buySignal && !sellSignal && InpDivEnabled)
      {
         int swLow1 = -1, swLow2 = -1;
         int swHigh1 = -1, swHigh2 = -1;

         for(int k = DIV_SW; k <= InpDivLookback && (i - k) >= DIV_SW; k++)
         {
            int bi = i - k;

            bool isSwLow = true;
            for(int j = 1; j <= DIV_SW; j++)
            {
               if(low[bi] >= low[bi - j] || low[bi] >= low[bi + j])
               { isSwLow = false; break; }
            }
            if(isSwLow)
            {
               if(swLow1 < 0) swLow1 = bi;
               else if(swLow2 < 0) swLow2 = bi;
            }

            bool isSwHigh = true;
            for(int j = 1; j <= DIV_SW; j++)
            {
               if(high[bi] <= high[bi - j] || high[bi] <= high[bi + j])
               { isSwHigh = false; break; }
            }
            if(isSwHigh)
            {
               if(swHigh1 < 0) swHigh1 = bi;
               else if(swHigh2 < 0) swHigh2 = bi;
            }

            if(swLow2 >= 0 && swHigh2 >= 0) break;
         }

         if(swLow1 >= 0 && swLow2 >= 0)
         {
            if(low[swLow1] < low[swLow2] && rsi[swLow1] > rsi[swLow2] + 3.0)
            {
               if(i - swLow1 <= DIV_SW + 2 && close[i] > open[i])
                  buySignal = true;
            }
         }
         if(swHigh1 >= 0 && swHigh2 >= 0)
         {
            if(high[swHigh1] > high[swHigh2] && rsi[swHigh1] < rsi[swHigh2] - 3.0)
            {
               if(i - swHigh1 <= DIV_SW + 2 && close[i] < open[i])
                  sellSignal = true;
            }
         }
      }

      if(!buySignal && !sellSignal)
         continue;

      //============================================================
      // СПРЕД (константа MAX_SPREAD)
      //============================================================
      if(spread[i] > MAX_SPREAD)
         continue;

      //============================================================
      // ТРЕНД ФІЛЬТР (EMA fast vs slow)
      //============================================================
      if(InpTrendFilter)
      {
         if(buySignal  && ef[i] < es[i]) buySignal  = false;
         if(sellSignal && ef[i] > es[i]) sellSignal = false;
      }
      if(!buySignal && !sellSignal)
         continue;

      //============================================================
      // ФІЛЬТР 1: ОБ'ЄМ
      //============================================================
      if(InpVolEnabled)
      {
         double avgVol = 0;
         for(int j = 1; j <= InpVolPeriod && (i - j) >= 0; j++)
            avgVol += (double)tick_volume[i - j];
         avgVol /= InpVolPeriod;

         if(avgVol > 0 && (double)tick_volume[i] < avgVol * InpVolMin)
         {
            buySignal  = false;
            sellSignal = false;
         }
      }

      if(!buySignal && !sellSignal)
         continue;

      //============================================================
      // ФІЛЬТР 2: ADX
      //============================================================
      if(InpADXEnabled)
      {
         if(adxMain[i] > InpADXLevel)
         {
            if(buySignal  && adxPlus[i] < adxMinus[i]) buySignal  = false;
            if(sellSignal && adxPlus[i] > adxMinus[i]) sellSignal = false;
         }
      }

      if(!buySignal && !sellSignal)
         continue;

      //============================================================
      // ФІЛЬТР 3: BOLLINGER BANDS
      //============================================================
      if(InpBBEnabled)
      {
         double bbWidth = bbUpper[i] - bbLower[i];
         if(bbWidth > _Point)
         {
            double bbPct = (close[i] - bbLower[i]) / bbWidth;
            if(buySignal  && bbPct > InpBBBuyBelow)   buySignal  = false;
            if(sellSignal && bbPct < InpBBSellAbove)  sellSignal = false;
         }
      }

      if(!buySignal && !sellSignal)
         continue;

      //============================================================
      // ФІЛЬТР 4: СВИНГ
      //============================================================
      if(InpSwingEnabled)
      {
         if(buySignal)
         {
            double lowestLow = low[i];
            for(int k = 1; k <= InpSwingBars && (i - k) >= 0; k++)
               if(low[i - k] < lowestLow) lowestLow = low[i - k];
            if(low[i] > lowestLow + atr[i] * InpSwingATR)
               buySignal = false;
         }
         if(sellSignal)
         {
            double highestHigh = high[i];
            for(int k = 1; k <= InpSwingBars && (i - k) >= 0; k++)
               if(high[i - k] > highestHigh) highestHigh = high[i - k];
            if(high[i] < highestHigh - atr[i] * InpSwingATR)
               sellSignal = false;
         }
      }

      if(!buySignal && !sellSignal)
         continue;

      //============================================================
      // СИЛА СИГНАЛУ
      //============================================================
      bool isStrong = false;
      if(squeezed)
         isStrong = true;
      double barRange = high[i] - low[i];
      if(barRange > atr[i] * 1.8)
         isStrong = true;

      //--- кулдаун
      bool buyCool = true, sellCool = true;
      for(int j = 1; j <= InpCooldown && (i - j) >= 0; j++)
      {
         if(BuyBuf[i - j] != EMPTY_VALUE || StrongBuyBuf[i - j] != EMPTY_VALUE)
            buyCool = false;
         if(SellBuf[i - j] != EMPTY_VALUE || StrongSellBuf[i - j] != EMPTY_VALUE)
            sellCool = false;
      }

      double offset = _Point * 200;

      if(buySignal && buyCool)
      {
         if(isStrong)
            StrongBuyBuf[i] = low[i] - offset;
         else
            BuyBuf[i] = low[i] - offset;
      }

      if(sellSignal && sellCool)
      {
         if(isStrong)
            StrongSellBuf[i] = high[i] + offset;
         else
            SellBuf[i] = high[i] + offset;
      }
   }

   //--- очищаємо поточний бар
   BuyBuf[rates_total - 1]        = EMPTY_VALUE;
   SellBuf[rates_total - 1]       = EMPTY_VALUE;
   StrongBuyBuf[rates_total - 1]  = EMPTY_VALUE;
   StrongSellBuf[rates_total - 1] = EMPTY_VALUE;

   UpdateStatsPanel(rates_total, barLimit, minStart, open, high, low, time);

   return(rates_total);
}
//+------------------------------------------------------------------+
