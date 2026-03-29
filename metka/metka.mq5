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
input int              InpStreakLen   = 3;              // Мін. довжина серії (streak)

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
int      g_lastHour = -1;

const int REV_LOOKBACK  = 5;
const int SQZ_LOOKBACK  = 6;
const int DIV_SW        = 3;
const int MAX_SPREAD    = 70;
const int RSI_PERIOD    = 14;
const string g_statPfx  = "MtkSt_";
const string g_curPfx   = "MtkCur_";
const string g_pageBtnMain = "MtkPageMain";
const string g_pageBtnMove = "MtkPageMove";
const string g_pageBtnDD   = "MtkPageDD";
const string g_pageBtnOpt  = "MtkPageOpt";
const string g_pageBtnLoss = "MtkPageLoss";
const string g_toggleBtnName = "MtkToggleBtn";
int g_statsPage = 1;
bool g_pageChanged = false;
bool g_statsOn = false;

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
   g_statsOn      = InpShowStats;
   g_pageChanged  = true;
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
   ObjectsDeleteAll(0, g_curPfx);
   ObjectDelete(0, "MtkProb");
   ObjectDelete(0, g_pageBtnMain);
   ObjectDelete(0, g_pageBtnMove);
   ObjectDelete(0, g_pageBtnDD);
   ObjectDelete(0, g_pageBtnOpt);
   ObjectDelete(0, g_pageBtnLoss);
   ObjectDelete(0, g_toggleBtnName);
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
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      int newPage = 0;
      if(sparam == g_pageBtnMain) newPage = 1;
      else if(sparam == g_pageBtnMove) newPage = 2;
      else if(sparam == g_pageBtnDD)   newPage = 3;
      else if(sparam == g_pageBtnOpt)  newPage = 4;
      else if(sparam == g_pageBtnLoss) newPage = 5;
      if(newPage > 0 && newPage != g_statsPage)
      {
         g_statsPage = newPage;
         g_pageChanged = true;
      }
      ObjectSetInteger(0, g_pageBtnMain, OBJPROP_STATE, false);
      ObjectSetInteger(0, g_pageBtnMove, OBJPROP_STATE, false);
      ObjectSetInteger(0, g_pageBtnDD,   OBJPROP_STATE, false);
      ObjectSetInteger(0, g_pageBtnOpt,  OBJPROP_STATE, false);
      ObjectSetInteger(0, g_pageBtnLoss, OBJPROP_STATE, false);
   }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_toggleBtnName)
   {
      g_statsOn = !g_statsOn;
      ObjectSetString(0, g_toggleBtnName, OBJPROP_TEXT, g_statsOn ? "Disable Stat" : "Enable Stat");
      ObjectSetInteger(0, g_toggleBtnName, OBJPROP_BGCOLOR, g_statsOn ? clrOrangeRed : clrGreen);
      ObjectSetInteger(0, g_toggleBtnName, OBJPROP_BORDER_COLOR, g_statsOn ? clrOrangeRed : clrGreen);
      ObjectSetInteger(0, g_toggleBtnName, OBJPROP_STATE, false);
      g_pageChanged = true;
   }
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
   // auto-recalc on hour change
   MqlDateTime nowDt;
   TimeToStruct(TimeCurrent(), nowDt);
   if(g_lastHour >= 0 && nowDt.hour != g_lastHour)
      g_pageChanged = true;
   g_lastHour = nowDt.hour;

   if(g_pageChanged)
   {
      g_pageChanged = false;
      int bars = iBars(_Symbol, _Period);
      int warmup  = MathMax(InpSlowPeriod, InpATRPeriod) + 2;
      int maxLook = MathMax(MathMax(REV_LOOKBACK, SQZ_LOOKBACK),
                    MathMax(MathMax(InpSwingBars, InpDivLookback + DIV_SW),
                    InpVolPeriod));
      int minStart = maxLook + warmup + 1;
      if(bars > minStart + 2)
      {
         double tmpO[], tmpH[], tmpL[];
         datetime tmpT[];
         if(CopyOpen(_Symbol, _Period, 0, bars, tmpO) == bars &&
            CopyHigh(_Symbol, _Period, 0, bars, tmpH) == bars &&
            CopyLow(_Symbol, _Period, 0, bars, tmpL)  == bars &&
            CopyTime(_Symbol, _Period, 0, bars, tmpT)  == bars)
         {
            UpdateStatsPanel(bars, bars - 2, minStart, tmpO, tmpH, tmpL, tmpT);
         }
      }
   }

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
      // check if previous signal is a loss
      int prevSigBar = -1;
      bool prevIsBuy = false;
      int totalBars = ArraySize(BuyBuf);
      for(int b = totalBars - 2; b >= 0; b--)
      {
         if(BuyBuf[b] != EMPTY_VALUE || StrongBuyBuf[b] != EMPTY_VALUE)
         { prevSigBar = b; prevIsBuy = true; break; }
         if(SellBuf[b] != EMPTY_VALUE || StrongSellBuf[b] != EMPTY_VALUE)
         { prevSigBar = b; prevIsBuy = false; break; }
      }

      if(prevSigBar >= 0 && prevSigBar + 1 < bars)
      {
         double entry = o[prevSigBar + 1];
         double target = InpStatTarget * _Point;
         bool hit = false;
         for(int b = prevSigBar + 1; b < bars; b++)
         {
            if(prevIsBuy && h[b] >= entry + target)  { hit = true; break; }
            if(!prevIsBuy && l[b] <= entry - target) { hit = true; break; }
         }
         if(!hit)
            SetArrowColor(prevSigBar, 1);
      }

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

double CalcMFEPct(const double &vals[], const int &hrs[], const int &dirs[],
                  int total, int hrFilter, int dirFilter, double pct)
{
   double tmp[];
   int cnt = 0;
   for(int i = 0; i < total; i++)
   {
      if(hrFilter >= 0 && hrs[i] != hrFilter) continue;
      if(dirFilter != 0 && dirs[i] != dirFilter) continue;
      ArrayResize(tmp, cnt + 1);
      tmp[cnt] = vals[i];
      cnt++;
   }
   if(cnt == 0) return(0);
   ArraySort(tmp);
   int idx = (int)MathFloor(cnt * pct / 100.0);
   if(idx >= cnt) idx = cnt - 1;
   if(idx < 0) idx = 0;
   return(tmp[idx]);
}

int CalcDDPct(const int &allDD[], const int &allHr[], const int &allDir[],
             int total, int hrFilter, int dirFilter, double pct)
{
   int tmp[];
   int cnt = 0;
   for(int i = 0; i < total; i++)
   {
      if(hrFilter >= 0 && allHr[i] != hrFilter) continue;
      if(dirFilter != 0 && allDir[i] != dirFilter) continue;
      ArrayResize(tmp, cnt + 1);
      tmp[cnt] = allDD[i];
      cnt++;
   }
   if(cnt == 0) return(0);
   ArraySort(tmp);
   int idx = (int)MathFloor(cnt * pct / 100.0);
   if(idx >= cnt) idx = cnt - 1;
   if(idx < 0) idx = 0;
   return(tmp[idx]);
}

void FindOptimalTPSL(const double &mfe[], const int &mae[],
                     const int &hrs[], const int &dirs[],
                     int total, int hrFilter, int dirFilter,
                     int &bestTP, int &bestSL, double &bestE, double &bestWR, int &bestCnt)
{
   double flt[];
   int    alt[];
   int n = 0;
   for(int i = 0; i < total; i++)
   {
      if(hrFilter >= 0 && hrs[i] != hrFilter) continue;
      if(dirFilter != 0 && dirs[i] != dirFilter) continue;
      ArrayResize(flt, n + 1);
      ArrayResize(alt, n + 1);
      flt[n] = mfe[i];
      alt[n] = mae[i];
      n++;
   }
   bestTP = 0; bestSL = 0; bestE = -999999; bestWR = 0; bestCnt = n;
   if(n < 2) return;

   double maxMfe = 0;
   int maxMae = 0;
   for(int i = 0; i < n; i++)
   {
      if(flt[i] > maxMfe) maxMfe = flt[i];
      if(alt[i] > maxMae) maxMae = alt[i];
   }
   int step = (int)MathMax(10, MathRound(maxMfe / 40.0));
   int slMax = (int)MathMin(maxMae, maxMfe * 2);

   for(int tp = step; tp <= (int)maxMfe; tp += step)
   {
      for(int sl = step; sl <= slMax; sl += step)
      {
         int wins = 0, losses = 0;
         for(int i = 0; i < n; i++)
         {
            if(alt[i] >= sl) losses++;
            else if(flt[i] >= tp) wins++;
         }
         if(wins + losses == 0) continue;
         double e = ((double)wins * tp - (double)losses * sl) / n;
         if(e > bestE)
         {
            bestE  = e;
            bestTP = tp;
            bestSL = sl;
            bestWR = 100.0 * wins / (wins + losses);
         }
      }
   }
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

   ObjectDelete(0, "MtkProb");

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

   bool sigHit[];
   ArrayResize(sigHit, sigCount);
   double target = InpStatTarget * _Point;

   int buyTotal = 0, buyHit = 0, buyMaxDD = 0;
   int sellTotal = 0, sellHit = 0, sellMaxDD = 0;
   int sessTotal[3] = {0, 0, 0};
   int sessHit[3]   = {0, 0, 0};
   int sessMaxDD[3] = {0, 0, 0};
   int hourTotal[24], hourHit[24], hourMaxDD[24];
   int hourBuyTotal[24], hourBuyHit[24], hourBuyDD[24];
   int hourSellTotal[24], hourSellHit[24], hourSellDD[24];
   double hourBuyMFE[24], hourSellMFE[24];
   double hourBuyMinMFE[24], hourBuyMaxMFE[24];
   double hourSellMinMFE[24], hourSellMaxMFE[24];
   double hourBuyMFEAll[24], hourSellMFEAll[24];
   double hourBuyMinAll[24], hourBuyMaxAll[24];
   double hourSellMinAll[24], hourSellMaxAll[24];
   ArrayInitialize(hourTotal, 0);
   ArrayInitialize(hourHit, 0);
   ArrayInitialize(hourMaxDD, 0);
   ArrayInitialize(hourBuyTotal, 0);
   ArrayInitialize(hourBuyHit, 0);
   ArrayInitialize(hourBuyDD, 0);
   ArrayInitialize(hourSellTotal, 0);
   ArrayInitialize(hourSellHit, 0);
   ArrayInitialize(hourSellDD, 0);
   ArrayInitialize(hourBuyMFE, 0);
   ArrayInitialize(hourSellMFE, 0);
   ArrayInitialize(hourBuyMinMFE, 999999);
   ArrayInitialize(hourBuyMaxMFE, 0);
   ArrayInitialize(hourSellMinMFE, 999999);
   ArrayInitialize(hourSellMaxMFE, 0);
   ArrayInitialize(hourBuyMFEAll, 0);
   ArrayInitialize(hourSellMFEAll, 0);
   ArrayInitialize(hourBuyMinAll, 999999);
   ArrayInitialize(hourBuyMaxAll, 0);
   ArrayInitialize(hourSellMinAll, 999999);
   ArrayInitialize(hourSellMaxAll, 0);
   int ddVals[], ddHrs[], ddDirs[], ddSesses[];
   int ddCount = 0;
   double mfeVals[];
   int mfeHrs[], mfeDirs[];
   int mfeCount = 0;
   double optMfe[];
   int optMae[], optHr[], optDir[];
   int optCount = 0;

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
         double maxHi = entry;
         double maxHiAtHit = entry;
         for(int b = bar + 1; b <= nextSigBar && b < rates_total; b++)
         {
            if(high[b] > maxHi) maxHi = high[b];
            if(!hit && high[b] >= entry + target) { hit = true; hitBar = b; maxHiAtHit = maxHi; }
         }
         if(hit)
         {
            double fullBuyMfe = (maxHi - entry) / _Point;
            hourBuyMFEAll[hr] += fullBuyMfe;
            if(fullBuyMfe < hourBuyMinAll[hr]) hourBuyMinAll[hr] = fullBuyMfe;
            if(fullBuyMfe > hourBuyMaxAll[hr]) hourBuyMaxAll[hr] = fullBuyMfe;
            hourBuyMFE[hr] += fullBuyMfe;
            ArrayResize(mfeVals, mfeCount + 1);
            ArrayResize(mfeHrs, mfeCount + 1);
            ArrayResize(mfeDirs, mfeCount + 1);
            mfeVals[mfeCount] = fullBuyMfe;
            mfeHrs[mfeCount] = hr;
            mfeDirs[mfeCount] = 1;
            mfeCount++;
            double buyMfeAtHit = (maxHiAtHit - entry) / _Point;
            if(buyMfeAtHit < hourBuyMinMFE[hr]) hourBuyMinMFE[hr] = buyMfeAtHit;
            if(fullBuyMfe > hourBuyMaxMFE[hr]) hourBuyMaxMFE[hr] = fullBuyMfe;
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
         double buyFullMfe = (maxHi - entry) / _Point;
         double buyMinLow = entry;
         for(int b = bar + 1; b <= nextSigBar && b < rates_total; b++)
            if(low[b] < buyMinLow) buyMinLow = low[b];
         int buyFullMae = (int)MathRound((entry - buyMinLow) / _Point);
         ArrayResize(optMfe, optCount + 1);
         ArrayResize(optMae, optCount + 1);
         ArrayResize(optHr, optCount + 1);
         ArrayResize(optDir, optCount + 1);
         optMfe[optCount] = buyFullMfe;
         optMae[optCount] = buyFullMae;
         optHr[optCount]  = hr;
         optDir[optCount] = 1;
         optCount++;
      }
      else
      {
         sellTotal++;
         sessTotal[sess]++;
         hourTotal[hr]++;
         hourSellTotal[hr]++;
         double minLo = entry;
         double minLoAtHit = entry;
         for(int b = bar + 1; b <= nextSigBar && b < rates_total; b++)
         {
            if(low[b] < minLo) minLo = low[b];
            if(!hit && low[b] <= entry - target) { hit = true; hitBar = b; minLoAtHit = minLo; }
         }
         if(hit)
         {
            double fullSellMfe = (entry - minLo) / _Point;
            hourSellMFEAll[hr] += fullSellMfe;
            if(fullSellMfe < hourSellMinAll[hr]) hourSellMinAll[hr] = fullSellMfe;
            if(fullSellMfe > hourSellMaxAll[hr]) hourSellMaxAll[hr] = fullSellMfe;
            hourSellMFE[hr] += fullSellMfe;
            ArrayResize(mfeVals, mfeCount + 1);
            ArrayResize(mfeHrs, mfeCount + 1);
            ArrayResize(mfeDirs, mfeCount + 1);
            mfeVals[mfeCount] = fullSellMfe;
            mfeHrs[mfeCount] = hr;
            mfeDirs[mfeCount] = -1;
            mfeCount++;
            double sellMfeAtHit = (entry - minLoAtHit) / _Point;
            if(sellMfeAtHit < hourSellMinMFE[hr]) hourSellMinMFE[hr] = sellMfeAtHit;
            if(fullSellMfe > hourSellMaxMFE[hr]) hourSellMaxMFE[hr] = fullSellMfe;
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
         double sellFullMfe = (entry - minLo) / _Point;
         double sellMaxHigh = entry;
         for(int b = bar + 1; b <= nextSigBar && b < rates_total; b++)
            if(high[b] > sellMaxHigh) sellMaxHigh = high[b];
         int sellFullMae = (int)MathRound((sellMaxHigh - entry) / _Point);
         ArrayResize(optMfe, optCount + 1);
         ArrayResize(optMae, optCount + 1);
         ArrayResize(optHr, optCount + 1);
         ArrayResize(optDir, optCount + 1);
         optMfe[optCount] = sellFullMfe;
         optMae[optCount] = sellFullMae;
         optHr[optCount]  = hr;
         optDir[optCount] = -1;
         optCount++;
      }
      sigHit[s] = hit;
   }

   //--- probability label above last arrow (always visible)
   if(sigCount > 0)
   {
      int lastDir = sigDirs[0];

      bool dirHits[];
      int  dirHitCnt = 0;
      for(int s = sigCount - 1; s >= 0; s--)
      {
         if(sigDirs[s] == lastDir)
         {
            ArrayResize(dirHits, dirHitCnt + 1);
            dirHits[dirHitCnt] = sigHit[s];
            dirHitCnt++;
         }
      }

      int curStrk = 0;
      if(dirHitCnt > 1)
      {
         for(int i = dirHitCnt - 2; i >= 0; i--)
         {
            if(dirHits[i]) curStrk++;
            else break;
         }
      }

      double prob = 0;
      string probText = "";
      int afterK_total = 0, afterK_win = 0;
      if(curStrk == 0)
      {
         for(int i = 0; i < dirHitCnt; i++)
         {
            afterK_total++;
            if(dirHits[i]) afterK_win++;
         }
         prob = afterK_total > 0 ? 100.0 * afterK_win / afterK_total : 0;
         probText = StringFormat("%dh P=%.0f%% (%d/%d)", InpStatHours, prob, afterK_win, afterK_total);
      }
      else
      {
         int stk = 0;
         for(int i = 0; i < dirHitCnt; i++)
         {
            if(stk >= curStrk)
            {
               afterK_total++;
               if(dirHits[i]) afterK_win++;
            }
            if(dirHits[i]) stk++;
            else stk = 0;
         }
         if(afterK_total > 0)
            prob = 100.0 * afterK_win / afterK_total;
         else
         {
            for(int i = 0; i < dirHitCnt; i++)
            {
               afterK_total++;
               if(dirHits[i]) afterK_win++;
            }
            prob = afterK_total > 0 ? 100.0 * afterK_win / afterK_total : 0;
         }
         probText = StringFormat("%dh W%d→%.0f%% (%d/%d)", InpStatHours, curStrk, prob, afterK_win, afterK_total);
      }

      int lastBar = sigBars[0];
      double arrowPrice;
      if(lastDir == 1)
         arrowPrice = low[lastBar] - _Point * 400;
      else
         arrowPrice = high[lastBar] + _Point * 400;

      ObjectCreate(0, "MtkProb", OBJ_TEXT, 0, time[lastBar], arrowPrice);
      ObjectSetString(0, "MtkProb",  OBJPROP_TEXT, probText);
      ObjectSetString(0, "MtkProb",  OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, "MtkProb", OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, "MtkProb", OBJPROP_COLOR,
         prob >= 70 ? clrGreen : (prob >= 50 ? clrGold : clrRed));
      ObjectSetInteger(0, "MtkProb", OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, "MtkProb", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, "MtkProb", OBJPROP_BACK, false);
   }

   //--- toggle button (always visible, right side)
   ObjectDelete(0, g_toggleBtnName);
   ObjectCreate(0, g_toggleBtnName, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_YDISTANCE, 15);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_XSIZE, 90);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_YSIZE, 22);
   ObjectSetString(0, g_toggleBtnName, OBJPROP_TEXT, g_statsOn ? "Disable Stat" : "Enable Stat");
   ObjectSetString(0, g_toggleBtnName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_BGCOLOR, g_statsOn ? clrOrangeRed : clrGreen);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_BORDER_COLOR, g_statsOn ? clrOrangeRed : clrGreen);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_STATE, false);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_SELECTABLE, false);

   //--- stats panel (only when enabled)
   if(!g_statsOn)
   {
      ObjectsDeleteAll(0, g_statPfx);
      ObjectDelete(0, g_pageBtnMain);
      ObjectDelete(0, g_pageBtnMove);
      ObjectDelete(0, g_pageBtnDD);
      ObjectDelete(0, g_pageBtnOpt);
      ObjectDelete(0, g_pageBtnLoss);
   }

   s_needReset = true;

   for(int s = 0; s < sigCount; s++)
      SetArrowColor(sigBars[s], 0);
   for(int s = 0; s < sigCount; s++)
   {
      if(!sigHit[s])
         SetArrowColor(sigBars[s], 1);
   }

   if(!g_statsOn)
   {
      // skip to persistent block at the bottom
   }
   else
   {
   //--- count streaks >= InpStreakLen per hour (chronological order)
   int buyStreakCnt[24], sellStreakCnt[24];
   ArrayInitialize(buyStreakCnt, 0);
   ArrayInitialize(sellStreakCnt, 0);
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
         if(sigHit[s])
            buyCurStrk[hr2]++;
         else
         {
            if(buyCurStrk[hr2] >= InpStreakLen)
               buyStreakCnt[hr2]++;
            buyCurStrk[hr2] = 0;
         }
      }
      else
      {
         if(sigHit[s])
            sellCurStrk[hr2]++;
         else
         {
            if(sellCurStrk[hr2] >= InpStreakLen)
               sellStreakCnt[hr2]++;
            sellCurStrk[hr2] = 0;
         }
      }
   }
   for(int h = 0; h < 24; h++)
   {
      if(buyCurStrk[h] >= InpStreakLen)  buyStreakCnt[h]++;
      if(sellCurStrk[h] >= InpStreakLen) sellStreakCnt[h]++;
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

   //--- очистити старі лейбли перед малюванням поточної сторінки
   ObjectsDeleteAll(0, g_statPfx);

   //--- повний білий фон
   DrawBgPanel(g_statPfx + "BG0", CORNER_LEFT_UPPER, 0, 0, 5000, 5000);

   //--- пересоздати toggle поверх фону
   ObjectDelete(0, g_toggleBtnName);
   ObjectCreate(0, g_toggleBtnName, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_YDISTANCE, 15);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_XSIZE, 90);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_YSIZE, 22);
   ObjectSetString(0, g_toggleBtnName, OBJPROP_TEXT, "Disable Stat");
   ObjectSetString(0, g_toggleBtnName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_BGCOLOR, clrOrangeRed);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_BORDER_COLOR, clrOrangeRed);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_STATE, false);
   ObjectSetInteger(0, g_toggleBtnName, OBJPROP_SELECTABLE, false);

   //--- pagination buttons
   string pageBtns[] = {g_pageBtnMain, g_pageBtnMove, g_pageBtnDD, g_pageBtnOpt, g_pageBtnLoss};
   string pageLbls[] = {"Main", "Move", "Drawdown", "Optimal", "Loss"};
   int    pageNums[] = {1, 2, 3, 4, 5};
   int    btnW[]     = {60, 60, 90, 75, 55};
   int    btnX       = 165;
   for(int pb = 0; pb < 5; pb++)
   {
      ObjectDelete(0, pageBtns[pb]);
      ObjectCreate(0, pageBtns[pb], OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_XDISTANCE, btnX);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_YDISTANCE, 15);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_XSIZE, btnW[pb]);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_YSIZE, 22);
      ObjectSetString(0, pageBtns[pb], OBJPROP_TEXT, pageLbls[pb]);
      ObjectSetString(0, pageBtns[pb], OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_FONTSIZE, 9);
      bool active = (g_statsPage == pageNums[pb]);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_COLOR, active ? clrWhite : clrGray);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_BGCOLOR, active ? clrDodgerBlue : clrWhiteSmoke);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_BORDER_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_STATE, false);
      ObjectSetInteger(0, pageBtns[pb], OBJPROP_SELECTABLE, false);
      btnX += btnW[pb] + 4;
   }

   if(g_statsPage == 1)
   {
   //--- верхня ліва панель
   int y = 40;

   DrawStatLabel(g_statPfx + "H",
      StringFormat("STATS  %d sig / %dh / %d pt target", sigCount, InpStatHours, InpStatTarget), clrBlack, y);
   y += 20;
   DrawStatLabel(g_statPfx + "GD",
      StringFormat("                        [100%%] {%d%%}", InpStatPct), clrGray, y, CORNER_LEFT_UPPER, 7);
   y += 18;
   DrawStatLabel(g_statPfx + "B",
      StringFormat("BUY   %d/%d (%.1f%%) %s", buyHit, buyTotal, buyPct, buyDD), clrGreen, y);
   y += 20;
   DrawStatLabel(g_statPfx + "S",
      StringFormat("SELL  %d/%d (%.1f%%) %s", sellHit, sellTotal, sellPct, sellDD), clrOrangeRed, y);
   y += 20;
   DrawStatLabel(g_statPfx + "A",
      StringFormat("ALL   %d/%d (%.1f%%) %s", allHit, allTotal, allPct, allDD), clrBlack, y);
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
      DrawStatLabel(g_statPfx + sessIds[k],
         StringFormat("%s %d/%d (%.0f%%) %s", sessNames[k], sessHit[k], sessTotal[k], pct, sdd),
         clrBlack, y);
      y += 22;
   }

   //--- TOP streaks — BUY left, SELL right side by side
   int stx = 330;
   y += 28;
   DrawStatLabel(g_statPfx + "TBH",
      StringFormat("── TOP BUY STREAKS (%d+) ──", InpStreakLen), clrGreen, y);
   DrawStatLabel(g_statPfx + "TSH",
      StringFormat("── TOP SELL STREAKS (%d+) ──", InpStreakLen), clrOrangeRed, y,
      CORNER_LEFT_UPPER, 10, stx);
   y += 16;

   int bUsed[5]; ArrayInitialize(bUsed, -1);
   int sUsed[5]; ArrayInitialize(sUsed, -1);
   for(int n = 0; n < 5; n++)
   {
      int bestBHr = -1, bestBVal = 0;
      for(int h = 0; h < 24; h++)
      {
         if(hourBuyTotal[h] == 0 || hourBuyHit[h] == hourBuyTotal[h]) continue;
         bool skip = false;
         for(int u = 0; u < n; u++) if(bUsed[u] == h) { skip = true; break; }
         if(skip) continue;
         if(buyStreakCnt[h] > bestBVal) { bestBVal = buyStreakCnt[h]; bestBHr = h; }
      }
      if(bestBHr >= 0)
      {
         bUsed[n] = bestBHr;
         DrawStatLabel(g_statPfx + "TB" + IntegerToString(n),
            StringFormat("%dh-%dh  %dx  %d/%d", bestBHr, (bestBHr + 1) % 24,
               bestBVal, hourBuyHit[bestBHr], hourBuyTotal[bestBHr]),
            clrBlack, y);
      }

      int bestSHr = -1, bestSVal = 0;
      for(int h = 0; h < 24; h++)
      {
         if(hourSellTotal[h] == 0 || hourSellHit[h] == hourSellTotal[h]) continue;
         bool skip = false;
         for(int u = 0; u < n; u++) if(sUsed[u] == h) { skip = true; break; }
         if(skip) continue;
         if(sellStreakCnt[h] > bestSVal) { bestSVal = sellStreakCnt[h]; bestSHr = h; }
      }
      if(bestSHr >= 0)
      {
         sUsed[n] = bestSHr;
         DrawStatLabel(g_statPfx + "TS" + IntegerToString(n),
            StringFormat("%dh-%dh  %dx  %d/%d", bestSHr, (bestSHr + 1) % 24,
               bestSVal, hourSellHit[bestSHr], hourSellTotal[bestSHr]),
            clrBlack, y, CORNER_LEFT_UPPER, 10, stx);
      }

      y += 16;
   }

   //--- правая сторона: BUY и SELL по часам рядом
   int ry = 40;
   int rxBuy  = 450;
   int rxSell = 15;

   DrawStatLabel(g_statPfx + "BHH", "──── BUY BY HOUR ────", clrGreen, ry,
                 CORNER_RIGHT_UPPER, 8, rxBuy);
   DrawStatLabel(g_statPfx + "SHH", "──── SELL BY HOUR ────", clrOrangeRed, ry,
                 CORNER_RIGHT_UPPER, 8, rxSell);
   ry += 16;
   string hdrDD2 = StringFormat("hr       hit/tot  win%%  [max] {%d%%}  profit", InpStatPct);
   DrawStatLabel(g_statPfx + "BHD", hdrDD2, clrGray, ry,
                 CORNER_RIGHT_UPPER, 7, rxBuy);
   DrawStatLabel(g_statPfx + "SHD", hdrDD2, clrGray, ry,
                 CORNER_RIGHT_UPPER, 7, rxSell);
   ry += 14;

   for(int r = 0; r < 24; r++)
   {
      int bp70 = CalcP85(ddVals, ddHrs, ddDirs, ddSesses, ddCount, r, 1, -1);
      int bProf = hourBuyTotal[r] > 0 ? CalcProfit(hourBuyHit[r], hourBuyTotal[r], bp70) : 0;
      color bc = (hourBuyTotal[r] > 0 && hourBuyHit[r] == hourBuyTotal[r]) ? clrGreen : clrBlack;
      if(hourBuyTotal[r] > 0)
         DrawStatLabel(g_statPfx + "BH" + IntegerToString(r),
            StringFormat("%dh-%dh  %2d/%-3d %4.0f%%  [%4d] {%4d}  %5d",
               r, (r + 1) % 24, hourBuyHit[r], hourBuyTotal[r],
               100.0 * hourBuyHit[r] / hourBuyTotal[r],
               hourBuyDD[r], bp70, bProf),
            bc, ry, CORNER_RIGHT_UPPER, 8, rxBuy);
      else
         DrawStatLabel(g_statPfx + "BH" + IntegerToString(r),
            StringFormat("%dh-%dh   0/0     --", r, (r + 1) % 24),
            clrGray, ry, CORNER_RIGHT_UPPER, 8, rxBuy);

      int sp70s = CalcP85(ddVals, ddHrs, ddDirs, ddSesses, ddCount, r, -1, -1);
      int sProf2 = hourSellTotal[r] > 0 ? CalcProfit(hourSellHit[r], hourSellTotal[r], sp70s) : 0;
      color sc = (hourSellTotal[r] > 0 && hourSellHit[r] == hourSellTotal[r]) ? clrGreen : clrBlack;
      if(hourSellTotal[r] > 0)
         DrawStatLabel(g_statPfx + "SH" + IntegerToString(r),
            StringFormat("%dh-%dh  %2d/%-3d %4.0f%%  [%4d] {%4d}  %5d",
               r, (r + 1) % 24, hourSellHit[r], hourSellTotal[r],
               100.0 * hourSellHit[r] / hourSellTotal[r],
               hourSellDD[r], sp70s, sProf2),
            sc, ry, CORNER_RIGHT_UPPER, 8, rxSell);
      else
         DrawStatLabel(g_statPfx + "SH" + IntegerToString(r),
            StringFormat("%dh-%dh   0/0     --", r, (r + 1) % 24),
            clrGray, ry, CORNER_RIGHT_UPPER, 8, rxSell);

      ry += 16;
   }

   //--- TOP hours by move (MFE) sorted by winrate — under hourly stats, right side
   ry += 20;
   DrawStatLabel(g_statPfx + "MBH", "── TOP BUY MOVE ──", clrGreen, ry,
                 CORNER_RIGHT_UPPER, 9, rxBuy);
   DrawStatLabel(g_statPfx + "MSH", "── TOP SELL MOVE ──", clrOrangeRed, ry,
                 CORNER_RIGHT_UPPER, 9, rxSell);
   ry += 16;
   DrawStatLabel(g_statPfx + "MBD", "hr      win%  avg   min   max", clrGray, ry,
                 CORNER_RIGHT_UPPER, 7, rxBuy);
   DrawStatLabel(g_statPfx + "MSD", "hr      win%  avg   min   max", clrGray, ry,
                 CORNER_RIGHT_UPPER, 7, rxSell);
   ry += 14;

   int mbUsed[5]; ArrayInitialize(mbUsed, -1);
   int msUsed[5]; ArrayInitialize(msUsed, -1);

   for(int n = 0; n < 5; n++)
   {
      int bestBHr = -1; double bestBWr = -1;
      for(int h = 0; h < 24; h++)
      {
         if(hourBuyTotal[h] < 2) continue;
         bool skip = false;
         for(int u = 0; u < n; u++) if(mbUsed[u] == h) { skip = true; break; }
         if(skip) continue;
         double wr = 100.0 * hourBuyHit[h] / hourBuyTotal[h];
         double avgM = hourBuyHit[h] > 0 ? hourBuyMFE[h] / hourBuyHit[h] : 0;
         double bestAvgM = (bestBHr >= 0 && hourBuyHit[bestBHr] > 0) ? hourBuyMFE[bestBHr] / hourBuyHit[bestBHr] : 0;
         if(wr > bestBWr || (wr == bestBWr && avgM > bestAvgM))
         { bestBWr = wr; bestBHr = h; }
      }
      if(bestBHr >= 0)
      {
         mbUsed[n] = bestBHr;
         double bMin = hourBuyMinMFE[bestBHr] < 999990 ? hourBuyMinMFE[bestBHr] : 0;
         double bAvg = hourBuyHit[bestBHr] > 0 ? hourBuyMFE[bestBHr] / hourBuyHit[bestBHr] : 0;
         DrawStatLabel(g_statPfx + "MB" + IntegerToString(n),
            StringFormat("%02dh-%02dh  %3.0f%%  %4.0f  %4.0f  %4.0f",
               bestBHr, (bestBHr + 1) % 24,
               100.0 * hourBuyHit[bestBHr] / hourBuyTotal[bestBHr],
               bAvg,
               bMin, hourBuyMaxMFE[bestBHr]),
            clrBlack, ry, CORNER_RIGHT_UPPER, 8, rxBuy);
      }

      int bestSHr = -1; double bestSWr = -1;
      for(int h = 0; h < 24; h++)
      {
         if(hourSellTotal[h] < 2) continue;
         bool skip = false;
         for(int u = 0; u < n; u++) if(msUsed[u] == h) { skip = true; break; }
         if(skip) continue;
         double wr = 100.0 * hourSellHit[h] / hourSellTotal[h];
         double avgM = hourSellHit[h] > 0 ? hourSellMFE[h] / hourSellHit[h] : 0;
         double bestAvgM = (bestSHr >= 0 && hourSellHit[bestSHr] > 0) ? hourSellMFE[bestSHr] / hourSellHit[bestSHr] : 0;
         if(wr > bestSWr || (wr == bestSWr && avgM > bestAvgM))
         { bestSWr = wr; bestSHr = h; }
      }
      if(bestSHr >= 0)
      {
         msUsed[n] = bestSHr;
         double sMin = hourSellMinMFE[bestSHr] < 999990 ? hourSellMinMFE[bestSHr] : 0;
         double sAvg = hourSellHit[bestSHr] > 0 ? hourSellMFE[bestSHr] / hourSellHit[bestSHr] : 0;
         DrawStatLabel(g_statPfx + "MS" + IntegerToString(n),
            StringFormat("%02dh-%02dh  %3.0f%%  %4.0f  %4.0f  %4.0f",
               bestSHr, (bestSHr + 1) % 24,
               100.0 * hourSellHit[bestSHr] / hourSellTotal[bestSHr],
               sAvg,
               sMin, hourSellMaxMFE[bestSHr]),
            clrBlack, ry, CORNER_RIGHT_UPPER, 8, rxSell);
      }

      ry += 16;
   }

   } // end page 1
   else if(g_statsPage == 2)
   {
   //=== PAGE 2: hourly MFE distribution (percentiles) ===
   int y2 = 40;
   DrawStatLabel(g_statPfx + "P2H",
      StringFormat("MOVE STATS  %d sig / %dh / %d pt target", sigCount, InpStatHours, InpStatTarget), clrBlack, y2);
   y2 += 18;

   int p2xBuy  = 15;
   int p2xSell = 15;

   DrawStatLabel(g_statPfx + "P2BH", "────── BUY BY HOUR (MOVE) ──────", clrGreen, y2,
                 CORNER_LEFT_UPPER, 9, p2xBuy);
   DrawStatLabel(g_statPfx + "P2SH", "────── SELL BY HOUR (MOVE) ──────", clrOrangeRed, y2,
                 CORNER_RIGHT_UPPER, 9, p2xSell);
   y2 += 16;
   DrawStatLabel(g_statPfx + "P2BD",
      "hr     w%   min  90%  80%  70%  60%  50%  40%  30%  20%  10%", clrGray, y2, CORNER_LEFT_UPPER, 9, p2xBuy);
   DrawStatLabel(g_statPfx + "P2SD",
      "hr     w%   min  90%  80%  70%  60%  50%  40%  30%  20%  10%", clrGray, y2, CORNER_RIGHT_UPPER, 9, p2xSell);
   y2 += 16;

   for(int r = 0; r < 24; r++)
   {
      if(hourBuyHit[r] > 0)
      {
         double bMin = hourBuyMinAll[r] < 999990 ? hourBuyMinAll[r] : 0;
         double bp10 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 10);
         double bp20 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 20);
         double bp30 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 30);
         double bp40 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 40);
         double bp50 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 50);
         double bp60 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 60);
         double bp70 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 70);
         double bp80 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 80);
         double bp90 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, 1, 90);
         DrawStatLabel(g_statPfx + "P2B" + IntegerToString(r),
            StringFormat("%dh-%dh %3.0f%% %5.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f",
               r, (r + 1) % 24,
               100.0 * hourBuyHit[r] / hourBuyTotal[r],
               bMin, bp10, bp20, bp30, bp40, bp50, bp60, bp70, bp80, bp90),
            clrBlack, y2, CORNER_LEFT_UPPER, 9, p2xBuy);
      }
      else
      {
         DrawStatLabel(g_statPfx + "P2B" + IntegerToString(r),
            StringFormat("%dh-%dh  --    --   --   --   --   --   --   --   --   --   --", r, (r + 1) % 24),
            clrGray, y2, CORNER_LEFT_UPPER, 9, p2xBuy);
      }

      if(hourSellHit[r] > 0)
      {
         double sMin = hourSellMinAll[r] < 999990 ? hourSellMinAll[r] : 0;
         double sp10 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 10);
         double sp20 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 20);
         double sp30 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 30);
         double sp40 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 40);
         double sp50 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 50);
         double sp60 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 60);
         double sp70 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 70);
         double sp80 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 80);
         double sp90 = CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, r, -1, 90);
         DrawStatLabel(g_statPfx + "P2S" + IntegerToString(r),
            StringFormat("%dh-%dh %3.0f%% %5.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f",
               r, (r + 1) % 24,
               100.0 * hourSellHit[r] / hourSellTotal[r],
               sMin, sp10, sp20, sp30, sp40, sp50, sp60, sp70, sp80, sp90),
            clrBlack, y2, CORNER_RIGHT_UPPER, 9, p2xSell);
      }
      else
      {
         DrawStatLabel(g_statPfx + "P2S" + IntegerToString(r),
            StringFormat("%dh-%dh  --    --   --   --   --   --   --   --   --   --   --", r, (r + 1) % 24),
            clrGray, y2, CORNER_RIGHT_UPPER, 9, p2xSell);
      }

      y2 += 16;
   }

   } // end page 2
   else if(g_statsPage == 3)
   {
   //=== PAGE 3: hourly DRAWDOWN distribution (percentiles) ===
   int y3 = 40;
   DrawStatLabel(g_statPfx + "P3H",
      StringFormat("DRAWDOWN STATS  %d sig / %dh / %d pt target", sigCount, InpStatHours, InpStatTarget), clrBlack, y3);
   y3 += 18;

   int p3xBuy  = 15;
   int p3xSell = 15;

   DrawStatLabel(g_statPfx + "P3BH", "────── BUY BY HOUR (DD) ──────", clrGreen, y3,
                 CORNER_LEFT_UPPER, 9, p3xBuy);
   DrawStatLabel(g_statPfx + "P3SH", "────── SELL BY HOUR (DD) ──────", clrOrangeRed, y3,
                 CORNER_RIGHT_UPPER, 9, p3xSell);
   y3 += 16;
   DrawStatLabel(g_statPfx + "P3BD",
      "hr     w%   10%  20%  30%  40%  50%  60%  70%  80%  90% 100%", clrGray, y3, CORNER_LEFT_UPPER, 9, p3xBuy);
   DrawStatLabel(g_statPfx + "P3SD",
      "hr     w%   10%  20%  30%  40%  50%  60%  70%  80%  90% 100%", clrGray, y3, CORNER_RIGHT_UPPER, 9, p3xSell);
   y3 += 16;

   for(int r = 0; r < 24; r++)
   {
      if(hourBuyHit[r] > 0)
      {
         int dp10 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 10);
         int dp20 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 20);
         int dp30 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 30);
         int dp40 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 40);
         int dp50 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 50);
         int dp60 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 60);
         int dp70 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 70);
         int dp80 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 80);
         int dp90 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 90);
         int dp100= CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, 1, 100);
         DrawStatLabel(g_statPfx + "P3B" + IntegerToString(r),
            StringFormat("%dh-%dh %3.0f%% %5d %4d %4d %4d %4d %4d %4d %4d %4d %4d",
               r, (r + 1) % 24,
               100.0 * hourBuyHit[r] / hourBuyTotal[r],
               dp10, dp20, dp30, dp40, dp50, dp60, dp70, dp80, dp90, dp100),
            clrBlack, y3, CORNER_LEFT_UPPER, 9, p3xBuy);
      }
      else
      {
         DrawStatLabel(g_statPfx + "P3B" + IntegerToString(r),
            StringFormat("%dh-%dh  --    --   --   --   --   --   --   --   --   --", r, (r + 1) % 24),
            clrGray, y3, CORNER_LEFT_UPPER, 9, p3xBuy);
      }

      if(hourSellHit[r] > 0)
      {
         int dp10 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 10);
         int dp20 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 20);
         int dp30 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 30);
         int dp40 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 40);
         int dp50 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 50);
         int dp60 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 60);
         int dp70 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 70);
         int dp80 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 80);
         int dp90 = CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 90);
         int dp100= CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, r, -1, 100);
         DrawStatLabel(g_statPfx + "P3S" + IntegerToString(r),
            StringFormat("%dh-%dh %3.0f%% %5d %4d %4d %4d %4d %4d %4d %4d %4d %4d",
               r, (r + 1) % 24,
               100.0 * hourSellHit[r] / hourSellTotal[r],
               dp10, dp20, dp30, dp40, dp50, dp60, dp70, dp80, dp90, dp100),
            clrBlack, y3, CORNER_RIGHT_UPPER, 9, p3xSell);
      }
      else
      {
         DrawStatLabel(g_statPfx + "P3S" + IntegerToString(r),
            StringFormat("%dh-%dh  --    --   --   --   --   --   --   --   --   --", r, (r + 1) % 24),
            clrGray, y3, CORNER_RIGHT_UPPER, 9, p3xSell);
      }

      y3 += 16;
   }

   } // end page 3
   else if(g_statsPage == 4)
   {
   //=== PAGE 4: optimal TP/SL per hour ===
   int y4 = 40;
   DrawStatLabel(g_statPfx + "P4H",
      StringFormat("OPTIMAL TP/SL  %d sig / %dh", sigCount, InpStatHours), clrBlack, y4);
   y4 += 18;

   int p4xBuy  = 15;
   int p4xSell = 15;

   DrawStatLabel(g_statPfx + "P4BH", "────── BUY OPTIMAL ──────", clrGreen, y4,
                 CORNER_LEFT_UPPER, 9, p4xBuy);
   DrawStatLabel(g_statPfx + "P4SH", "────── SELL OPTIMAL ──────", clrOrangeRed, y4,
                 CORNER_RIGHT_UPPER, 9, p4xSell);
   y4 += 16;
   DrawStatLabel(g_statPfx + "P4BD",
      "hr   signals   TP    SL  profit  w%", clrGray, y4, CORNER_LEFT_UPPER, 9, p4xBuy);
   DrawStatLabel(g_statPfx + "P4SD",
      "hr   signals   TP    SL  profit  w%", clrGray, y4, CORNER_RIGHT_UPPER, 9, p4xSell);
   y4 += 16;

   for(int r = 0; r < 24; r++)
   {
      int bTP, bSL, bCnt;
      double bE, bWR;
      FindOptimalTPSL(optMfe, optMae, optHr, optDir, optCount, r, 1,
                      bTP, bSL, bE, bWR, bCnt);
      if(bCnt > 0 && bTP > 0)
      {
         DrawStatLabel(g_statPfx + "P4B" + IntegerToString(r),
            StringFormat("%dh-%dh %4d %5d %5d %6.0f %4.0f%%",
               r, (r + 1) % 24, bCnt, bTP, bSL, bE, bWR),
            clrBlack, y4, CORNER_LEFT_UPPER, 9, p4xBuy);
      }
      else
      {
         DrawStatLabel(g_statPfx + "P4B" + IntegerToString(r),
            StringFormat("%dh-%dh %4d    --    --     --   --", r, (r + 1) % 24, bCnt),
            clrGray, y4, CORNER_LEFT_UPPER, 9, p4xBuy);
      }

      int sTP, sSL, sCnt;
      double sE, sWR;
      FindOptimalTPSL(optMfe, optMae, optHr, optDir, optCount, r, -1,
                      sTP, sSL, sE, sWR, sCnt);
      if(sCnt > 0 && sTP > 0)
      {
         DrawStatLabel(g_statPfx + "P4S" + IntegerToString(r),
            StringFormat("%dh-%dh %4d %5d %5d %6.0f %4.0f%%",
               r, (r + 1) % 24, sCnt, sTP, sSL, sE, sWR),
            clrBlack, y4, CORNER_RIGHT_UPPER, 9, p4xSell);
      }
      else
      {
         DrawStatLabel(g_statPfx + "P4S" + IntegerToString(r),
            StringFormat("%dh-%dh %4d    --    --     --   --", r, (r + 1) % 24, sCnt),
            clrGray, y4, CORNER_RIGHT_UPPER, 9, p4xSell);
      }

      y4 += 16;
   }

   } // end page 4
   else if(g_statsPage == 5)
   {
   //=== PAGE 5: LOSS analysis ===
   int y5 = 40;
   DrawStatLabel(g_statPfx + "P5H",
      StringFormat("LOSS ANALYSIS  %d sig / %dh", sigCount, InpStatHours), clrBlack, y5);
   y5 += 22;

   // --- Table 1: consecutive loss streaks ---
   int lossStreakCnt[8]; // [1..7+] -> index 0=unused, 1..7
   ArrayInitialize(lossStreakCnt, 0);
   int curLossStreak = 0;
   int maxLossStreak = 0;

   // --- Table 2: consecutive win streaks between losses ---
   int curWinStreak = 0;
   int minWinStreak = 999999;
   int maxWinStreak = 0;
   int winStreakCount = 0;
   int winStreakCnt[31];
   ArrayInitialize(winStreakCnt, 0);

   // --- Loss streak hours: lossStreakHrs[streakLen][hour] = count ---
   int lossStreakHrs[8][24];
   ArrayInitialize(lossStreakHrs, 0);
   int curLossHrs[24];
   ArrayInitialize(curLossHrs, 0);

   // --- Losses per hour (split by direction) ---
   int lossPerHour[24];
   int lossBuyHour[24], lossSellHour[24];
   ArrayInitialize(lossPerHour, 0);
   ArrayInitialize(lossBuyHour, 0);
   ArrayInitialize(lossSellHour, 0);
   int totalLosses = 0;

   for(int s = 0; s < sigCount; s++)
   {
      MqlDateTime mdt5;
      TimeToStruct(time[sigBars[s]], mdt5);
      int hr5 = mdt5.hour;

      if(!sigHit[s])
      {
         lossPerHour[hr5]++;
         if(sigDirs[s] == 1) lossBuyHour[hr5]++;
         else lossSellHour[hr5]++;
         totalLosses++;
         if(curWinStreak > 0)
         {
            if(curWinStreak < minWinStreak) minWinStreak = curWinStreak;
            if(curWinStreak > maxWinStreak) maxWinStreak = curWinStreak;
            if(curWinStreak < 31) winStreakCnt[curWinStreak]++;
            winStreakCount++;
            curWinStreak = 0;
         }
         curLossStreak++;
         curLossHrs[hr5]++;
         if(curLossStreak > maxLossStreak) maxLossStreak = curLossStreak;
      }
      else
      {
         if(curLossStreak > 0)
         {
            int idx = curLossStreak <= 7 ? curLossStreak : 7;
            lossStreakCnt[idx]++;
            for(int h = 0; h < 24; h++)
            {
               lossStreakHrs[idx][h] += curLossHrs[h];
               curLossHrs[h] = 0;
            }
            curLossStreak = 0;
         }
         curWinStreak++;
      }
   }
   if(curLossStreak > 0)
   {
      int idx = curLossStreak <= 7 ? curLossStreak : 7;
      lossStreakCnt[idx]++;
      for(int h = 0; h < 24; h++)
         lossStreakHrs[idx][h] += curLossHrs[h];
   }
   if(curWinStreak > 0)
   {
      if(curWinStreak < minWinStreak) minWinStreak = curWinStreak;
      if(curWinStreak > maxWinStreak) maxWinStreak = curWinStreak;
      if(curWinStreak < 31) winStreakCnt[curWinStreak]++;
      winStreakCount++;
   }
   if(minWinStreak == 999999) minWinStreak = 0;

   int p5xL = 15;
   int p5xH = 365;
   int p5xW = 15;
   int yL = y5;
   int yH = y5;
   int yW = y5;

   // Left: CONSECUTIVE LOSSES
   DrawStatLabel(g_statPfx + "P5L", "──── CONSECUTIVE LOSSES ────", clrRed, yL,
                 CORNER_LEFT_UPPER, 9, p5xL);
   // Middle: LOSSES BY HOUR
   DrawStatLabel(g_statPfx + "P5HH", "──── LOSSES BY HOUR BUY ────", clrGreen, yH,
                 CORNER_LEFT_UPPER, 9, p5xH);
   // Right: CONSECUTIVE WINS
   DrawStatLabel(g_statPfx + "P5W", "──── CONSECUTIVE WINS ────", clrGreen, yW,
                 CORNER_RIGHT_UPPER, 9, p5xW);
   yL += 16; yH += 16; yW += 16;

   DrawStatLabel(g_statPfx + "P5LH", "streak    count", clrGray, yL, CORNER_LEFT_UPPER, 9, p5xL);
   DrawStatLabel(g_statPfx + "P5HD", "hour        count     %", clrGray, yH,
                 CORNER_LEFT_UPPER, 9, p5xH);
   DrawStatLabel(g_statPfx + "P5WH", "streak    count", clrGray, yW, CORNER_RIGHT_UPPER, 9, p5xW);
   yL += 14; yH += 14; yW += 14;

   for(int k = 1; k <= 7; k++)
   {
      string lbl = k < 7 ? StringFormat("  %d", k) : " 7+";
      DrawStatLabel(g_statPfx + "P5L" + IntegerToString(k),
         StringFormat("%s        %d", lbl, lossStreakCnt[k]),
         clrBlack, yL, CORNER_LEFT_UPPER, 9, p5xL);
      yL += 14;
   }
   DrawStatLabel(g_statPfx + "P5LM",
      StringFormat("max streak: %d", maxLossStreak),
      clrRed, yL, CORNER_LEFT_UPPER, 9, p5xL);
   yL += 22;

   // Loss streak distribution by hour (columns = streak 2..7, rows = hours)
   DrawStatLabel(g_statPfx + "P5DH", "──── LOSS STREAK BY HOUR ────", clrRed, yL,
                 CORNER_LEFT_UPPER, 9, p5xL);
   yL += 16;

   // header row: streak numbers
   string dHdr = "      2   3   4   5   6  7+";
   DrawStatLabel(g_statPfx + "P5DHH", dHdr, clrGray, yL, CORNER_LEFT_UPPER, 9, p5xL);
   yL += 14;

   for(int h = 0; h < 24; h++)
   {
      bool hasData = false;
      for(int k = 2; k <= 7; k++)
         if(lossStreakHrs[k][h] > 0) hasData = true;
      if(!hasData) continue;

      DrawStatLabel(g_statPfx + "P5DL" + IntegerToString(h),
         StringFormat("%2dh  %3d %3d %3d %3d %3d %3d",
            h,
            lossStreakHrs[2][h], lossStreakHrs[3][h], lossStreakHrs[4][h],
            lossStreakHrs[5][h], lossStreakHrs[6][h], lossStreakHrs[7][h]),
         clrBlack, yL, CORNER_LEFT_UPPER, 9, p5xL);
      yL += 14;
   }

   // Middle: LOSSES BY HOUR BUY
   int p5xHS = p5xH + 310;
   int yHS = y5;
   DrawStatLabel(g_statPfx + "P5HHS", "──── LOSSES BY HOUR SELL ────", clrOrangeRed, yHS,
                 CORNER_LEFT_UPPER, 9, p5xHS);
   yHS += 16;
   DrawStatLabel(g_statPfx + "P5HDS", "hour       count     %", clrGray, yHS,
                 CORNER_LEFT_UPPER, 9, p5xHS);
   yHS += 14;

   for(int r = 0; r < 24; r++)
   {
      // BUY losses
      if(hourBuyTotal[r] > 0)
      {
         double bPct = 100.0 * lossBuyHour[r] / hourBuyTotal[r];
         DrawStatLabel(g_statPfx + "P5HB" + IntegerToString(r),
            StringFormat("%dh-%dh :   %3d  | %4.0f%%", r, (r + 1) % 24, lossBuyHour[r], bPct),
            clrBlack, yH, CORNER_LEFT_UPPER, 9, p5xH);
      }
      else
         DrawStatLabel(g_statPfx + "P5HB" + IntegerToString(r),
            StringFormat("%dh-%dh :     0  |   0%%", r, (r + 1) % 24),
            clrGray, yH, CORNER_LEFT_UPPER, 9, p5xH);
      yH += 14;

      // SELL losses
      if(hourSellTotal[r] > 0)
      {
         double sPct = 100.0 * lossSellHour[r] / hourSellTotal[r];
         DrawStatLabel(g_statPfx + "P5HS" + IntegerToString(r),
            StringFormat("%dh-%dh :   %3d  | %4.0f%%", r, (r + 1) % 24, lossSellHour[r], sPct),
            clrBlack, yHS, CORNER_LEFT_UPPER, 9, p5xHS);
      }
      else
         DrawStatLabel(g_statPfx + "P5HS" + IntegerToString(r),
            StringFormat("%dh-%dh :     0  |   0%%", r, (r + 1) % 24),
            clrGray, yHS, CORNER_LEFT_UPPER, 9, p5xHS);
      yHS += 14;
   }

   // Right: CONSECUTIVE WINS data
   int maxWS = maxWinStreak < 30 ? maxWinStreak : 30;
   for(int k = 1; k <= maxWS; k++)
   {
      DrawStatLabel(g_statPfx + "P5W" + IntegerToString(k),
         StringFormat(" %2d        %d", k, winStreakCnt[k]),
         clrBlack, yW, CORNER_RIGHT_UPPER, 9, p5xW);
      yW += 14;
   }
   yW += 4;
   DrawStatLabel(g_statPfx + "P5WS",
      StringFormat("min: %d   max: %d   total: %d", minWinStreak, maxWinStreak, winStreakCount),
      clrGreen, yW, CORNER_RIGHT_UPPER, 9, p5xW);

   } // end page 5

   } // end if(g_statsOn)

   //--- bottom-left: current hour Move & DD table (always visible)
   ObjectsDeleteAll(0, g_curPfx);
   MqlDateTime nowDt;
   TimeToStruct(time[rates_total - 1], nowDt);
   int curHr = nowDt.hour;
   int yBot = 112;
   int ln = 14;

   // Winrate + Losses
   double bWR = hourBuyTotal[curHr] > 0 ? 100.0 * hourBuyHit[curHr] / hourBuyTotal[curHr] : 0;
   double sWR = hourSellTotal[curHr] > 0 ? 100.0 * hourSellHit[curHr] / hourSellTotal[curHr] : 0;
   int totalHr = hourBuyTotal[curHr] + hourSellTotal[curHr];
   int lossHr = totalHr - hourBuyHit[curHr] - hourSellHit[curHr];
   double lossPct = totalHr > 0 ? 100.0 * lossHr / totalHr : 0;
   DrawStatLabel(g_curPfx + "WR",
      StringFormat("Winrate %dh:  BUY %.0f%%   SELL %.0f%%   LOSSES: %.0f%%", curHr, bWR, sWR, lossPct),
      clrDodgerBlue, yBot, CORNER_LEFT_LOWER, 9);
   yBot -= ln + 2;

   // MOVE header
   DrawStatLabel(g_curPfx + "MH",
      "MOVE  90%  80%  70%  60%  50%  40%  30%  20%  10%",
      clrGray, yBot, CORNER_LEFT_LOWER, 9);
   yBot -= ln;

   // BUY MOVE
   if(hourBuyHit[curHr] > 0)
   {
      DrawStatLabel(g_curPfx + "MB",
         StringFormat("BUY  %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f",
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 10),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 20),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 30),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 40),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 50),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 60),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 70),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 80),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, 1, 90)),
         clrGreen, yBot, CORNER_LEFT_LOWER, 9);
   }
   else
      DrawStatLabel(g_curPfx + "MB",
         "BUY    --   --   --   --   --   --   --   --   --",
         clrGray, yBot, CORNER_LEFT_LOWER, 9);
   yBot -= ln;

   // SELL MOVE
   if(hourSellHit[curHr] > 0)
   {
      DrawStatLabel(g_curPfx + "MS",
         StringFormat("SELL %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f %4.0f",
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 10),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 20),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 30),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 40),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 50),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 60),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 70),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 80),
            CalcMFEPct(mfeVals, mfeHrs, mfeDirs, mfeCount, curHr, -1, 90)),
         clrOrangeRed, yBot, CORNER_LEFT_LOWER, 9);
   }
   else
      DrawStatLabel(g_curPfx + "MS",
         "SELL   --   --   --   --   --   --   --   --   --",
         clrGray, yBot, CORNER_LEFT_LOWER, 9);
   yBot -= ln + 4;

   // DD header
   DrawStatLabel(g_curPfx + "DH",
      "DD    20%  30%  40%  50%  60%  70%  80%  90% 100%",
      clrGray, yBot, CORNER_LEFT_LOWER, 9);
   yBot -= ln;

   // BUY DD
   if(hourBuyHit[curHr] > 0)
   {
      DrawStatLabel(g_curPfx + "DB",
         StringFormat("BUY  %4d %4d %4d %4d %4d %4d %4d %4d %4d",
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 20),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 30),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 40),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 50),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 60),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 70),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 80),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 90),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, 1, 100)),
         clrGreen, yBot, CORNER_LEFT_LOWER, 9);
   }
   else
      DrawStatLabel(g_curPfx + "DB",
         "BUY    --   --   --   --   --   --   --   --   --",
         clrGray, yBot, CORNER_LEFT_LOWER, 9);
   yBot -= ln;

   // SELL DD
   if(hourSellHit[curHr] > 0)
   {
      DrawStatLabel(g_curPfx + "DS",
         StringFormat("SELL %4d %4d %4d %4d %4d %4d %4d %4d %4d",
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 20),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 30),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 40),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 50),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 60),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 70),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 80),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 90),
            CalcDDPct(ddVals, ddHrs, ddDirs, ddCount, curHr, -1, 100)),
         clrOrangeRed, yBot, CORNER_LEFT_LOWER, 9);
   }
   else
      DrawStatLabel(g_curPfx + "DS",
         "SELL   --   --   --   --   --   --   --   --   --",
         clrGray, yBot, CORNER_LEFT_LOWER, 9);

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

   //--- recalc probability label when a new arrow just formed on the previous bar
   int prevBar = barLimit;
   bool newArrow = (BuyBuf[prevBar] != EMPTY_VALUE || SellBuf[prevBar] != EMPTY_VALUE ||
                    StrongBuyBuf[prevBar] != EMPTY_VALUE || StrongSellBuf[prevBar] != EMPTY_VALUE);
   if(newArrow && prev_calculated > 0 && prev_calculated < rates_total)
      g_pageChanged = true;

   if(g_pageChanged)
   {
      g_pageChanged = false;
      UpdateStatsPanel(rates_total, barLimit, minStart, open, high, low, time);
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
