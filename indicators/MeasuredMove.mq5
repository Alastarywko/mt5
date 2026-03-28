//+------------------------------------------------------------------+
//|                                                MeasuredMove.mq5   |
//|           Паттерн AB=CD — проекція рівного руху                   |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "1.00"
#property description "Measured Move AB=CD Pattern"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input int    InpSwingPeriod  = 10;         // Swing Period
input color  InpABColor      = clrDarkGray;   // AB leg color
input color  InpCDColor      = clrLime;    // CD projection color
input color  InpTargetColor  = clrLime;    // Target line color
input int    InpLineWidth    = 2;          // Line width
input int    InpMaxBars      = 500;        // Max bars

string g_prefix = "ABCD_";
int    g_lastBars = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Measured Move AB=CD");
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

   //--- Find last 3 alternating swing points
   double swP[];
   datetime swT[];
   bool swH[];
   ArrayResize(swP, 0);
   ArrayResize(swT, 0);
   ArrayResize(swH, 0);

   int startBar = MathMax(prd, rates_total - InpMaxBars);
   int endBar = rates_total - 1 - prd;
   int i = 0;

   for(i = endBar; i >= startBar; i--)
   {
      if(i < prd) break;
      int cnt = ArraySize(swP);
      if(cnt >= 3) break;

      if(IsSwHigh(high, i, prd))
      {
         if(cnt == 0 || swH[cnt-1] != true)
         {
            ArrayResize(swP, cnt+1); ArrayResize(swT, cnt+1); ArrayResize(swH, cnt+1);
            swP[cnt] = high[i]; swT[cnt] = time[i]; swH[cnt] = true;
         }
         else if(high[i] > swP[cnt-1])
         { swP[cnt-1] = high[i]; swT[cnt-1] = time[i]; }
      }

      if(IsSwLow(low, i, prd))
      {
         int cnt2 = ArraySize(swP);
         if(cnt2 == 0 || swH[cnt2-1] != false)
         {
            ArrayResize(swP, cnt2+1); ArrayResize(swT, cnt2+1); ArrayResize(swH, cnt2+1);
            swP[cnt2] = low[i]; swT[cnt2] = time[i]; swH[cnt2] = false;
         }
         else if(low[i] < swP[cnt2-1])
         { swP[cnt2-1] = low[i]; swT[cnt2-1] = time[i]; }
      }
   }

   if(ArraySize(swP) < 3) return(rates_total);

   double pA = swP[2], pB = swP[1], pC = swP[0];
   datetime tA = swT[2], tB = swT[1], tC = swT[0];
   double moveAB = pB - pA;
   double pD = pC + moveAB;
   datetime tNow = time[rates_total - 1];
   datetime tFuture = tNow + PeriodSeconds() * 15;

   //--- AB leg
   ObjectCreate(0, g_prefix+"AB", OBJ_TREND, 0, tA, pA, tB, pB);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_COLOR, InpABColor);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_WIDTH, InpLineWidth);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"AB", OBJPROP_BACK, true);

   //--- BC leg
   ObjectCreate(0, g_prefix+"BC", OBJ_TREND, 0, tB, pB, tC, pC);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_COLOR, InpABColor);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"BC", OBJPROP_BACK, true);

   //--- CD projection leg
   ObjectCreate(0, g_prefix+"CD", OBJ_TREND, 0, tC, pC, tFuture, pD);
   ObjectSetInteger(0, g_prefix+"CD", OBJPROP_COLOR, InpCDColor);
   ObjectSetInteger(0, g_prefix+"CD", OBJPROP_WIDTH, InpLineWidth);
   ObjectSetInteger(0, g_prefix+"CD", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, g_prefix+"CD", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"CD", OBJPROP_BACK, true);

   //--- Target D horizontal line
   ObjectCreate(0, g_prefix+"TGT", OBJ_TREND, 0, tC, pD, tFuture, pD);
   ObjectSetInteger(0, g_prefix+"TGT", OBJPROP_COLOR, InpTargetColor);
   ObjectSetInteger(0, g_prefix+"TGT", OBJPROP_WIDTH, InpLineWidth);
   ObjectSetInteger(0, g_prefix+"TGT", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, g_prefix+"TGT", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"TGT", OBJPROP_BACK, true);

   //--- Labels
   string labels[] = {"A", "B", "C", "D"};
   double prices[] = {pA, pB, pC, pD};
   datetime times[] = {tA, tB, tC, tFuture};
   int lb = 0;
   for(lb = 0; lb < 4; lb++)
   {
      string nm = g_prefix + "L" + labels[lb];
      ObjectCreate(0, nm, OBJ_TEXT, 0, times[lb], prices[lb]);
      ObjectSetString(0, nm, OBJPROP_TEXT, " " + labels[lb]);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, lb < 3 ? InpABColor : InpCDColor);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 12);
      ObjectSetString(0, nm, OBJPROP_FONT, "Arial Bold");
   }

   //--- Info
   double abPts = MathAbs(moveAB) / _Point;
   string dir = moveAB > 0 ? "UP" : "DOWN";
   ObjectCreate(0, g_prefix+"INFO", OBJ_TEXT, 0, tFuture, pD);
   ObjectSetString(0, g_prefix+"INFO", OBJPROP_TEXT,
      "  D = " + DoubleToString(pD, _Digits) + " | AB=" + DoubleToString(abPts, 0) + " pts " + dir);
   ObjectSetInteger(0, g_prefix+"INFO", OBJPROP_COLOR, InpTargetColor);
   ObjectSetInteger(0, g_prefix+"INFO", OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, g_prefix+"INFO", OBJPROP_ANCHOR, ANCHOR_LEFT);

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
