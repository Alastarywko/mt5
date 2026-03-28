//+------------------------------------------------------------------+
//|                                              SwingStructure.mq5   |
//|           Найближчі структурні рівні (swing H/L як магніти)       |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "1.00"
#property description "Nearest Swing Structure Levels"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input int    InpSwingPeriod  = 10;         // Swing Period
input int    InpMaxLevels    = 8;          // Max levels to show
input color  InpResColor     = clrOrangeRed;  // Resistance color (above price)
input color  InpSupColor     = clrDodgerBlue; // Support color (below price)
input color  InpTestedColor  = clrGray;    // Tested level color
input int    InpLineWidth    = 1;          // Line width
input bool   InpShowDistance = true;       // Show distance in points
input int    InpMaxBars      = 500;        // Max bars

string g_prefix = "SST_";
int    g_lastBars = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Swing Structure");
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

   double curPrice = close[rates_total - 1];
   datetime tNow = time[rates_total - 1];
   datetime tFuture = tNow + PeriodSeconds() * 10;

   //--- Collect all swing points
   double lvlPrice[];
   datetime lvlTime[];
   bool lvlIsHigh[];
   bool lvlTested[];
   ArrayResize(lvlPrice, 0);
   ArrayResize(lvlTime, 0);
   ArrayResize(lvlIsHigh, 0);
   ArrayResize(lvlTested, 0);

   int startBar = MathMax(prd, rates_total - InpMaxBars);
   int endBar = rates_total - 1 - prd;
   int i = 0;

   for(i = startBar; i <= endBar; i++)
   {
      if(i < prd) continue;

      if(IsSwHigh(high, i, prd))
      {
         int sz = ArraySize(lvlPrice);
         ArrayResize(lvlPrice, sz+1);
         ArrayResize(lvlTime, sz+1);
         ArrayResize(lvlIsHigh, sz+1);
         ArrayResize(lvlTested, sz+1);
         lvlPrice[sz] = high[i];
         lvlTime[sz] = time[i];
         lvlIsHigh[sz] = true;
         lvlTested[sz] = false;
      }

      if(IsSwLow(low, i, prd))
      {
         int sz = ArraySize(lvlPrice);
         ArrayResize(lvlPrice, sz+1);
         ArrayResize(lvlTime, sz+1);
         ArrayResize(lvlIsHigh, sz+1);
         ArrayResize(lvlTested, sz+1);
         lvlPrice[sz] = low[i];
         lvlTime[sz] = time[i];
         lvlIsHigh[sz] = false;
         lvlTested[sz] = false;
      }
   }

   int totalLevels = ArraySize(lvlPrice);
   if(totalLevels == 0) return(rates_total);

   //--- Check which levels have been tested (price touched after creation)
   int k = 0;
   for(i = 0; i < totalLevels; i++)
   {
      for(k = i + 1; k < rates_total; k++)
      {
         if(time[k] <= lvlTime[i]) continue;
         if(k >= rates_total) break;
         if(high[k] >= lvlPrice[i] && low[k] <= lvlPrice[i])
         {
            lvlTested[i] = true;
            break;
         }
      }
   }

   //--- Sort by distance to current price, pick closest untested first
   double dist[];
   int idx[];
   ArrayResize(dist, totalLevels);
   ArrayResize(idx, totalLevels);
   for(i = 0; i < totalLevels; i++)
   {
      dist[i] = MathAbs(lvlPrice[i] - curPrice);
      idx[i] = i;
   }

   //--- Simple sort by distance
   int a = 0, b = 0;
   for(a = 0; a < totalLevels - 1; a++)
   {
      for(b = a + 1; b < totalLevels; b++)
      {
         if(dist[b] < dist[a])
         {
            double tmpD = dist[a]; dist[a] = dist[b]; dist[b] = tmpD;
            int tmpI = idx[a]; idx[a] = idx[b]; idx[b] = tmpI;
         }
      }
   }

   //--- Draw closest levels
   int drawn = 0;
   int aboveCount = 0, belowCount = 0;
   int maxPerSide = InpMaxLevels / 2;

   for(i = 0; i < totalLevels && drawn < InpMaxLevels; i++)
   {
      int li = idx[i];
      bool isAbove = lvlPrice[li] > curPrice;

      if(isAbove && aboveCount >= maxPerSide) continue;
      if(!isAbove && belowCount >= maxPerSide) continue;

      color clr = InpTestedColor;
      ENUM_LINE_STYLE style = STYLE_DOT;

      if(!lvlTested[li])
      {
         clr = isAbove ? InpResColor : InpSupColor;
         style = STYLE_SOLID;
      }

      string nm = g_prefix + "L" + IntegerToString(drawn);
      ObjectCreate(0, nm, OBJ_TREND, 0, lvlTime[li], lvlPrice[li], tFuture, lvlPrice[li]);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, lvlTested[li] ? 1 : InpLineWidth);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

      //--- Price label
      string label = "  " + DoubleToString(lvlPrice[li], _Digits);
      if(InpShowDistance)
      {
         double dPts = MathAbs(lvlPrice[li] - curPrice) / _Point;
         label += " (" + DoubleToString(dPts, 0) + " pts)";
      }
      if(lvlTested[li]) label += " [tested]";

      string nmL = g_prefix + "T" + IntegerToString(drawn);
      ObjectCreate(0, nmL, OBJ_TEXT, 0, tFuture, lvlPrice[li]);
      ObjectSetString(0, nmL, OBJPROP_TEXT, label);
      ObjectSetInteger(0, nmL, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nmL, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nmL, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, nmL, OBJPROP_SELECTABLE, false);

      if(isAbove) aboveCount++;
      else belowCount++;
      drawn++;
   }

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
