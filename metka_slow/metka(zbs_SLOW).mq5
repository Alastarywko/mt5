//+------------------------------------------------------------------+
//|                                                        metka.mq5 |
//|           Non-repainting indicator v12                            |
//|           Точки-предупреждения за 10 сек + стрелки по закрытию    |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "22.00"
#property description "Индикатор: точка за 10 сек, стрелка по закрытию"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_width2  2

#property indicator_label3  "Strong Buy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_width3  5

#property indicator_label4  "Strong Sell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDeepPink
#property indicator_width4  5

input int              InpFastPeriod  = 20;             // Период быстрой EMA
input int              InpSlowPeriod  = 50;             // Период медленной EMA
input int              InpADXPeriod   = 15;             // Период ADX
input int              InpADXMin      = 30;             // Мин. ADX для свингов
input int              InpATRPeriod   = 20;             // Период ATR
input int              InpSwingSize   = 2;              // Размер свинга
input double           InpSpikeATR    = 2;            // Шпилька: мин. размер в ATR
input ENUM_TIMEFRAMES  InpHTF         = PERIOD_CURRENT; // Старший ТФ (Current = авто)
input int              InpCooldown    = 10;             // Мин. баров между сигналами
int              InpPreSignalSec = 10;            // Предупреждение за N секунд
input bool             InpAlerts      = true;           // Алерты
bool             InpPush        = false;          // Push-уведомления

double BuyBuf[], SellBuf[];
double StrongBuyBuf[], StrongSellBuf[];

int hEmaFast, hEmaSlow, hADX, hATR;
int hHTFEmaFast, hHTFEmaSlow;
ENUM_TIMEFRAMES htfPeriod;
datetime lastDotBarTime;
bool     dotAlerted;

const int REV_LOOKBACK = 5;
const int SQZ_LOOKBACK = 6;
const int VOL_LOOKBACK = 10;

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
   SetIndexBuffer(0, BuyBuf,        INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf,       INDICATOR_DATA);
   SetIndexBuffer(2, StrongBuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(3, StrongSellBuf, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);

   for(int p = 0; p < 4; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(InpHTF == PERIOD_CURRENT || InpHTF <= _Period)
      htfPeriod = AutoHTF(_Period);
   else
      htfPeriod = InpHTF;

   hEmaFast    = iMA(_Symbol,  _Period,   InpFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow    = iMA(_Symbol,  _Period,   InpSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hADX        = iADX(_Symbol, _Period,   InpADXPeriod);
   hATR        = iATR(_Symbol, _Period,   InpATRPeriod);
   hHTFEmaFast = iMA(_Symbol,  htfPeriod, InpFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hHTFEmaSlow = iMA(_Symbol,  htfPeriod, InpSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(hEmaFast == INVALID_HANDLE || hEmaSlow == INVALID_HANDLE ||
      hADX == INVALID_HANDLE     || hATR == INVALID_HANDLE     ||
      hHTFEmaFast == INVALID_HANDLE || hHTFEmaSlow == INVALID_HANDLE)
   {
      Print("Metka: ошибка создания хэндлов");
      return(INIT_FAILED);
   }

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("Metka v22 (%s)", EnumToString(htfPeriod)));

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
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaSlow);
   IndicatorRelease(hADX);
   IndicatorRelease(hATR);
   IndicatorRelease(hHTFEmaFast);
   IndicatorRelease(hHTFEmaSlow);
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
// Предварительная точка за N секунд до закрытия бара
//+------------------------------------------------------------------+
void OnTimer()
{
   datetime barStart = iTime(_Symbol, _Period, 0);
   int elapsed   = (int)(TimeCurrent() - barStart);
   int remaining = PeriodSeconds(_Period) - elapsed;

   if(barStart != lastDotBarTime)
   {
      ObjectDelete(0, "MetkaDotUp");
      ObjectDelete(0, "MetkaDotDn");
      dotAlerted     = false;
      lastDotBarTime = barStart;
   }

   if(remaining > InpPreSignalSec || remaining <= 0 || dotAlerted)
      return;

   double curClose = iClose(_Symbol, _Period, 0);
   double curOpen  = iOpen(_Symbol, _Period, 0);
   double curHigh  = iHigh(_Symbol, _Period, 0);
   double curLow   = iLow(_Symbol, _Period, 0);
   long   curVol   = iTickVolume(_Symbol, _Period, 0);
   double rng      = curHigh - curLow;

   if(rng < _Point) return;

   double atrVal[];
   if(CopyBuffer(hATR, 0, 0, 1, atrVal) <= 0) return;
   double curATR = atrVal[0];
   if(curATR < _Point) return;

   double avgVol = 0;
   for(int j = 1; j <= VOL_LOOKBACK; j++)
      avgVol += (double)iTickVolume(_Symbol, _Period, j);
   avgVol /= VOL_LOOKBACK;

   bool closeHigh = curClose > curHigh - rng / 3.0;
   bool closeLow  = curClose < curLow  + rng / 3.0;
   bool volOk     = (double)curVol >= avgVol;

   bool preBuy  = false;
   bool preSell = false;

   // Pin bar
   double lowerW = MathMin(curOpen, curClose) - curLow;
   double upperW = curHigh - MathMax(curOpen, curClose);
   if(rng > curATR * InpSpikeATR)
   {
      if(lowerW > rng * 0.6 && closeHigh && volOk) preBuy  = true;
      if(upperW > rng * 0.6 && closeLow  && volOk) preSell = true;
   }

   // Reversal
   if(!preBuy && !preSell)
   {
      double mom = 0; int bc = 0, uc = 0;
      for(int j = 1; j <= REV_LOOKBACK; j++)
      {
         double b = iClose(_Symbol,_Period,j) - iOpen(_Symbol,_Period,j);
         mom += b;
         if(b < 0) bc++; else if(b > 0) uc++;
      }
      double body = curClose - curOpen;
      if(bc >= 4 && mom < -curATR*1.0 && body > 0 && body > curATR*0.4 && closeHigh && volOk)
         preBuy = true;
      if(uc >= 4 && mom > curATR*1.0 && body < 0 && MathAbs(body) > curATR*0.4 && closeLow && volOk)
         preSell = true;
   }

   // Squeeze breakout
   if(!preBuy && !preSell)
   {
      double sqz = 0;
      for(int j = 1; j <= SQZ_LOOKBACK; j++)
         sqz += iHigh(_Symbol,_Period,j) - iLow(_Symbol,_Period,j);
      sqz /= SQZ_LOOKBACK;
      double body = MathAbs(curClose - curOpen);
      if(sqz < curATR * 0.5 && rng > curATR && body > rng * 0.6)
      {
         if(curClose > curOpen && closeHigh && volOk) preBuy  = true;
         if(curClose < curOpen && closeLow  && volOk) preSell = true;
      }
   }

   if(!preBuy && !preSell) return;

   string dir = preBuy ? "BUY" : "SELL";
   string name = preBuy ? "MetkaDotUp" : "MetkaDotDn";
   double price = preBuy ? curLow - curATR * 0.5 : curHigh + curATR * 0.5;

   ObjectCreate(0, name, OBJ_ARROW, 0, barStart, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ChartRedraw(0);

   string text = StringFormat("Metka ГОТОВИТСЯ %s | %s %s | %d сек",
                              dir, _Symbol, EnumToString(_Period), remaining);
   if(InpAlerts) Alert(text);
   if(InpPush)   SendNotification(text);
   dotAlerted = true;
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
   int sw      = InpSwingSize;
   int warmup  = MathMax(InpSlowPeriod, MathMax(InpADXPeriod, InpATRPeriod)) + 2;
   int maxLook = MathMax(sw, MathMax(REV_LOOKBACK, MathMax(SQZ_LOOKBACK, VOL_LOOKBACK)));
   int minStart = maxLook + warmup + 1;

   if(rates_total < minStart + sw + 2)
      return(0);

   double ef[], es[], adx[], atr[];
   if(CopyBuffer(hEmaFast, 0, 0, rates_total, ef)  <= 0) return(0);
   if(CopyBuffer(hEmaSlow, 0, 0, rates_total, es)  <= 0) return(0);
   if(CopyBuffer(hADX,     0, 0, rates_total, adx) <= 0) return(0);
   if(CopyBuffer(hATR,     0, 0, rates_total, atr) <= 0) return(0);

   int htfBars = iBars(_Symbol, htfPeriod);
   if(htfBars <= InpSlowPeriod + 1)
      return(0);

   double htfEf[], htfEs[];
   if(CopyBuffer(hHTFEmaFast, 0, 0, htfBars, htfEf) <= 0) return(0);
   if(CopyBuffer(hHTFEmaSlow, 0, 0, htfBars, htfEs) <= 0) return(0);

   int barLimit     = rates_total - 2;

   int start;
   if(prev_calculated == 0)
   {
      ArrayInitialize(BuyBuf,        EMPTY_VALUE);
      ArrayInitialize(SellBuf,       EMPTY_VALUE);
      ArrayInitialize(StrongBuyBuf,  EMPTY_VALUE);
      ArrayInitialize(StrongSellBuf, EMPTY_VALUE);
      start = minStart;
   }
   else
      start = MathMax(prev_calculated - 2, minStart);


   for(int i = start; i <= barLimit; i++)
   {
      BuyBuf[i]        = EMPTY_VALUE;
      SellBuf[i]       = EMPTY_VALUE;
      StrongBuyBuf[i]  = EMPTY_VALUE;
      StrongSellBuf[i] = EMPTY_VALUE;

      bool buySignal  = false;
      bool sellSignal = false;

      double barRng = high[i] - low[i];
      bool closeAtHigh = barRng > _Point && close[i] > high[i] - barRng / 3.0;
      bool closeAtLow  = barRng > _Point && close[i] < low[i]  + barRng / 3.0;

      double avgVol = 0;
      for(int j = 1; j <= VOL_LOOKBACK; j++)
         avgVol += (double)tick_volume[i - j];
      avgVol /= VOL_LOOKBACK;
      bool hotVol = (double)tick_volume[i] >= avgVol;

      double sqzAvgRange = 0;
      for(int j = 1; j <= SQZ_LOOKBACK; j++)
         sqzAvgRange += high[i - j] - low[i - j];
      sqzAvgRange /= SQZ_LOOKBACK;
      bool squeezed = sqzAvgRange < atr[i] * 0.5;

      // --- МЕТОД 1: ФРАКТАЛ (подтверждение на текущем баре) ---
      {
         int fi = i - sw;
         if(fi >= sw)
         {
            bool isLow = true, isHigh = true;
            for(int j = 1; j <= sw; j++)
            {
               if(low[fi]  >= low[fi-j]  || low[fi]  >= low[fi+j])  isLow  = false;
               if(high[fi] <= high[fi-j] || high[fi] <= high[fi+j]) isHigh = false;
               if(!isLow && !isHigh) break;
            }
            if(isLow || isHigh)
            {
               if(adx[i] >= InpADXMin)
               {
                  bool hUp=false, hDn=false;
                  if(GetHTFTrend(time[i], htfEf, htfEs, htfBars, hUp, hDn))
                  {
                     if(isLow  && hUp && close[i] > open[i]) buySignal  = true;
                     if(isHigh && hDn && close[i] < open[i]) sellSignal = true;
                  }
               }
            }
         }
      }

      // --- МЕТОД 2: PIN BAR ---
      if(!buySignal && !sellSignal)
      {
         if(barRng > atr[i] * InpSpikeATR && barRng > _Point)
         {
            double upperW = high[i] - MathMax(open[i], close[i]);
            double lowerW = MathMin(open[i], close[i]) - low[i];
            bool hammer = (lowerW > barRng*0.6) && closeAtHigh && hotVol;
            bool star   = (upperW > barRng*0.6) && closeAtLow  && hotVol;
            if(hammer || star)
            {
               bool hUp=false, hDn=false;
               if(GetHTFTrend(time[i], htfEf, htfEs, htfBars, hUp, hDn))
               {
                  if(hammer && hUp) buySignal  = true;
                  if(star   && hDn) sellSignal = true;
               }
            }
         }
      }

      // --- МЕТОД 3: РАЗВОРОТ ---
      if(!buySignal && !sellSignal)
      {
         double priorMom=0, sumBody=0; int bearC=0, bullC=0;
         for(int j=1; j<=REV_LOOKBACK; j++)
         {
            double b = close[i-j]-open[i-j];
            priorMom += b; sumBody += MathAbs(b);
            if(b<0) bearC++; if(b>0) bullC++;
         }
         double avgBody = sumBody/REV_LOOKBACK;
         double curBody = close[i]-open[i];
         double absBody = MathAbs(curBody);
         bool strongBar = absBody > atr[i]*0.4 && absBody > avgBody
                       && barRng > _Point && absBody > barRng*0.4;

         if(bearC>=4 && priorMom < -atr[i]*1.0 && curBody>0 && strongBar && closeAtHigh && hotVol)
            buySignal = true;
         if(bullC>=4 && priorMom > atr[i]*1.0 && curBody<0 && strongBar && closeAtLow && hotVol)
            sellSignal = true;
      }

      // --- МЕТОД 4: СЖАТИЕ ---
      if(!buySignal && !sellSignal && squeezed)
      {
         double body = MathAbs(close[i]-open[i]);
         if(barRng > atr[i] && body > barRng*0.6)
         {
            if(close[i]>open[i] && closeAtHigh && hotVol) buySignal  = true;
            if(close[i]<open[i] && closeAtLow  && hotVol) sellSignal = true;
         }
      }

      if(!buySignal && !sellSignal) continue;

      bool isStrong = squeezed || barRng > atr[i] * 1.8;

      bool buyCool=true, sellCool=true;
      for(int j=1; j<=InpCooldown && (i-j)>=0; j++)
      {
         if(BuyBuf[i-j]!=EMPTY_VALUE || StrongBuyBuf[i-j]!=EMPTY_VALUE)  buyCool=false;
         if(SellBuf[i-j]!=EMPTY_VALUE|| StrongSellBuf[i-j]!=EMPTY_VALUE) sellCool=false;
      }

      double offset = atr[i]*0.5;
      if(offset < _Point*10) offset = _Point*10;

      if(buySignal && buyCool)
      {
         if(isStrong) StrongBuyBuf[i] = low[i]-offset;
         else         BuyBuf[i]       = low[i]-offset;
      }
      if(sellSignal && sellCool)
      {
         if(isStrong) StrongSellBuf[i] = high[i]+offset;
         else         SellBuf[i]       = high[i]+offset;
      }
   }

   BuyBuf[rates_total-1]        = EMPTY_VALUE;
   SellBuf[rates_total-1]       = EMPTY_VALUE;
   StrongBuyBuf[rates_total-1]  = EMPTY_VALUE;
   StrongSellBuf[rates_total-1] = EMPTY_VALUE;

   // Убираем точку при закрытии бара (стрелка заменяет)
   ObjectDelete(0, "MetkaDotUp");
   ObjectDelete(0, "MetkaDotDn");

   return(rates_total);
}
//+------------------------------------------------------------------+
