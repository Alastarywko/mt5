//+------------------------------------------------------------------+
//|                                              FiboProjection.mq5   |
//|           Автоматичні Fibonacci Extensions від свінг-структури     |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "1.00"
#property description "Auto Fibonacci Extension Levels"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input int    InpSwingPeriod = 10;          // Swing Period
input color  InpFiboColor   = clrDodgerBlue; // Fibo line color
input color  InpStructColor = clrGray;     // ABC structure color
input int    InpLineWidth   = 1;           // Line width
input int    InpMaxBars     = 500;         // Max bars

string g_prefix = "FIB_";
int    g_lastBars = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Fibo Projection");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, g_prefix); }

//+------------------------------------------------------------------+
bool IsSwHigh(const double &h[], int idx, int prd)
{
   double v = h[idx];
   int j = 0;
   for(j = 1; j <= prd; j++)
   { if(h[idx-j] >= v || h[idx+j] >= v) return(false); }
   return(true);
}

bool IsSwLow(const double &l[], int idx, int prd)
{
   double v = l[idx];
   int j = 0;
   for(j = 1; j <= prd; j++)
   { if(l[idx-j] <= v || l[idx+j] <= v) return(false); }
   return(true);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   int prd = InpSwingPeriod;
   if(rates_total <= 2 * prd + 1) return(0);
   if(rates_total == g_lastBars) return(rates_total);
   g_lastBars = rates_total;

   ObjectsDeleteAll(0, g_prefix);

   //--- Find last 3 swing points (A, B, C)
   double swPrice[];
   datetime swTime[];
   bool swIsHigh[];
   ArrayResize(swPrice, 0);
   ArrayResize(swTime, 0);
   ArrayResize(swIsHigh, 0);

   int startBar = MathMax(prd, rates_total - InpMaxBars);
   int endBar = rates_total - 1 - prd;
   int i = 0;

   for(i = endBar; i >= startBar; i--)
   {
      if(i < prd) break;
      int cnt = ArraySize(swPrice);
      if(cnt >= 3) break;

      if(IsSwHigh(high, i, prd))
      {
         if(cnt == 0 || swIsHigh[cnt-1] != true)
         {
            ArrayResize(swPrice, cnt+1);
            ArrayResize(swTime, cnt+1);
            ArrayResize(swIsHigh, cnt+1);
            swPrice[cnt] = high[i];
            swTime[cnt] = time[i];
            swIsHigh[cnt] = true;
         }
         else if(high[i] > swPrice[cnt-1])
         {
            swPrice[cnt-1] = high[i];
            swTime[cnt-1] = time[i];
         }
      }

      if(IsSwLow(low, i, prd))
      {
         int cnt2 = ArraySize(swPrice);
         if(cnt2 == 0 || swIsHigh[cnt2-1] != false)
         {
            ArrayResize(swPrice, cnt2+1);
            ArrayResize(swTime, cnt2+1);
            ArrayResize(swIsHigh, cnt2+1);
            swPrice[cnt2] = low[i];
            swTime[cnt2] = time[i];
            swIsHigh[cnt2] = false;
         }
         else if(low[i] < swPrice[cnt2-1])
         {
            swPrice[cnt2-1] = low[i];
            swTime[cnt2-1] = time[i];
         }
      }
   }

   if(ArraySize(swPrice) < 3) return(rates_total);

   double pA = swPrice[2], pB = swPrice[1], pC = swPrice[0];
   datetime tA = swTime[2], tB = swTime[1], tC = swTime[0];
   double swingAB = MathAbs(pB - pA);
   bool projDown = swIsHigh[0];

   //--- Draw ABC structure
   ObjectCreate(0, g_prefix+"AB", OBJ_TREND, 0, tA, pA, tB, pB);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_COLOR, InpStructColor);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_BACK, true);

   ObjectCreate(0, g_prefix+"BC", OBJ_TREND, 0, tB, pB, tC, pC);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_COLOR, InpStructColor);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_BACK, true);

   //--- Labels A, B, C
   ObjectCreate(0, g_prefix+"LA", OBJ_TEXT, 0, tA, pA);
   ObjectSetString(0, g_prefix+"LA", OBJPROP_TEXT, " A");
   ObjectSetInteger(0, g_prefix+"LA", OBJPROP_COLOR, InpStructColor);
   ObjectSetInteger(0, g_prefix+"LA", OBJPROP_FONTSIZE, 10);

   ObjectCreate(0, g_prefix+"LB", OBJ_TEXT, 0, tB, pB);
   ObjectSetString(0, g_prefix+"LB", OBJPROP_TEXT, " B");
   ObjectSetInteger(0, g_prefix+"LB", OBJPROP_COLOR, InpStructColor);
   ObjectSetInteger(0, g_prefix+"LB", OBJPROP_FONTSIZE, 10);

   ObjectCreate(0, g_prefix+"LC", OBJ_TEXT, 0, tC, pC);
   ObjectSetString(0, g_prefix+"LC", OBJPROP_TEXT, " C");
   ObjectSetInteger(0, g_prefix+"LC", OBJPROP_COLOR, InpStructColor);
   ObjectSetInteger(0, g_prefix+"LC", OBJPROP_FONTSIZE, 10);

   //--- Fibonacci levels
   double fiboLvl[] = {0.618, 0.786, 1.0, 1.272, 1.618, 2.0, 2.618};
   string fiboNm[]  = {"61.8%", "78.6%", "100%", "127.2%", "161.8%", "200%", "261.8%"};
   datetime futTime = time[rates_total-1] + PeriodSeconds() * 10;
   int f = 0;

   for(f = 0; f < 7; f++)
   {
      double target = projDown ? pC - swingAB * fiboLvl[f] : pC + swingAB * fiboLvl[f];
      string nm = g_prefix + "F" + IntegerToString(f);

      ObjectCreate(0, nm, OBJ_TREND, 0, tC, target, futTime, target);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, InpFiboColor);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, f == 2 ? InpLineWidth + 1 : InpLineWidth);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, f == 2 ? STYLE_SOLID : STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

      ObjectCreate(0, nm+"_L", OBJ_TEXT, 0, futTime, target);
      ObjectSetString(0, nm+"_L", OBJPROP_TEXT, "  " + fiboNm[f] + " " + DoubleToString(target, _Digits));
      ObjectSetInteger(0, nm+"_L", OBJPROP_COLOR, InpFiboColor);
      ObjectSetInteger(0, nm+"_L", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nm+"_L", OBJPROP_ANCHOR, ANCHOR_LEFT);
   }

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
