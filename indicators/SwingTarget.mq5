//+------------------------------------------------------------------+
//|                                                  SwingTarget.mq5  |
//|           Проекція цілі свінгу на основі середнього розміру       |
//|           + Fibonacci Extensions + Measured Move                   |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "1.00"
#property description "Swing Target Projection"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- inputs
input int    InpSwingPeriod   = 10;          // Swing Period (bars left/right)
input int    InpSwingHistory  = 6;           // Swing history count (for average)
input bool   InpShowAvgTarget = true;        // Show Average Swing target
input bool   InpShowFibo      = true;        // Show Fibonacci targets
input bool   InpShowMeasured  = true;        // Show Measured Move (AB=CD)
input color  InpAvgColor      = clrGold;     // Average target color
input color  InpFiboColor     = clrDodgerBlue; // Fibonacci color
input color  InpMeasuredColor = clrLime;     // Measured Move color
input int    InpLineWidth     = 1;           // Line width
input int    InpMaxBars       = 500;         // Max bars to analyze

//--- structures
struct SSwing
{
   double   price;
   datetime time;
   int      barIdx;
   bool     isHigh;
};

//--- globals
SSwing   g_swings[];
string   g_prefix = "SWT_";
int      g_lastBars = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Swing Target");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
}

//+------------------------------------------------------------------+
bool IsSwingHigh(const double &h[], int idx, int prd)
{
   double val = h[idx];
   int a = 0;
   for(a = 1; a <= prd; a++)
   {
      if(h[idx - a] >= val) return(false);
      if(h[idx + a] >= val) return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
bool IsSwingLow(const double &l[], int idx, int prd)
{
   double val = l[idx];
   int a = 0;
   for(a = 1; a <= prd; a++)
   {
      if(l[idx - a] <= val) return(false);
      if(l[idx + a] <= val) return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void DrawLabel(string name, double price, string text, color clr)
{
   datetime futureTime = iTime(_Symbol, _Period, 0) + PeriodSeconds() * 5;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, futureTime, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, futureTime);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void DrawTrendLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
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
   int prd = InpSwingPeriod;
   int minBar = 2 * prd;
   if(rates_total <= minBar + 1)
      return(0);

   if(rates_total == g_lastBars)
      return(rates_total);
   g_lastBars = rates_total;

   ObjectsDeleteAll(0, g_prefix);
   ArrayResize(g_swings, 0);

   int startBar = MathMax(prd, rates_total - InpMaxBars);
   int endBar = rates_total - 1 - prd;

   //--- Find all swings
   int i = 0;
   for(i = startBar; i <= endBar; i++)
   {
      if(i < prd) continue;

      if(IsSwingHigh(high, i, prd))
      {
         int sz = ArraySize(g_swings);
         ArrayResize(g_swings, sz + 1);
         g_swings[sz].price  = high[i];
         g_swings[sz].time   = time[i];
         g_swings[sz].barIdx = i;
         g_swings[sz].isHigh = true;
      }

      if(IsSwingLow(low, i, prd))
      {
         int sz = ArraySize(g_swings);
         ArrayResize(g_swings, sz + 1);
         g_swings[sz].price  = low[i];
         g_swings[sz].time   = time[i];
         g_swings[sz].barIdx = i;
         g_swings[sz].isHigh = false;
      }
   }

   int totalSwings = ArraySize(g_swings);
   if(totalSwings < 3)
      return(rates_total);

   //--- Draw swing zigzag lines
   for(i = 1; i < totalSwings; i++)
   {
      string zName = g_prefix + "Z" + IntegerToString(i);
      color zClr = g_swings[i].isHigh ? clrGray : clrGray;
      DrawTrendLine(zName,
                    g_swings[i-1].time, g_swings[i-1].price,
                    g_swings[i].time, g_swings[i].price,
                    clrDarkGray, 1, STYLE_DOT);
   }

   //--- Calculate average swing sizes (separate for up and down)
   double avgUp = 0, avgDn = 0;
   int cntUp = 0, cntDn = 0;
   int maxHist = MathMin(InpSwingHistory * 2, totalSwings - 1);

   for(i = totalSwings - 1; i >= MathMax(0, totalSwings - 1 - maxHist); i--)
   {
      if(i < 1) break;
      double swing = g_swings[i].price - g_swings[i-1].price;
      if(swing > 0 && cntUp < InpSwingHistory)
      {
         avgUp += swing;
         cntUp++;
      }
      else if(swing < 0 && cntDn < InpSwingHistory)
      {
         avgDn += MathAbs(swing);
         cntDn++;
      }
      if(cntUp >= InpSwingHistory && cntDn >= InpSwingHistory) break;
   }

   if(cntUp > 0) avgUp /= cntUp;
   if(cntDn > 0) avgDn /= cntDn;

   //--- Last swing point = projection origin
   SSwing lastSw = g_swings[totalSwings - 1];
   SSwing prevSw = g_swings[totalSwings - 2];

   //--- Determine current direction (from last swing)
   double curPrice = close[rates_total - 1];
   bool projDown = lastSw.isHigh;
   bool projUp   = !lastSw.isHigh;

   //=== 1. AVERAGE SWING TARGET ===
   if(InpShowAvgTarget)
   {
      if(projDown && avgDn > 0)
      {
         double target = lastSw.price - avgDn;
         DrawHLine(g_prefix + "AVG", target, InpAvgColor, InpLineWidth, STYLE_DASH);
         DrawLabel(g_prefix + "AVG_L", target,
                   "  AVG Target " + DoubleToString(target, _Digits) +
                   " (" + DoubleToString(avgDn / _Point, 0) + " pts)",
                   InpAvgColor);
      }
      else if(projUp && avgUp > 0)
      {
         double target = lastSw.price + avgUp;
         DrawHLine(g_prefix + "AVG", target, InpAvgColor, InpLineWidth, STYLE_DASH);
         DrawLabel(g_prefix + "AVG_L", target,
                   "  AVG Target " + DoubleToString(target, _Digits) +
                   " (" + DoubleToString(avgUp / _Point, 0) + " pts)",
                   InpAvgColor);
      }
   }

   //=== 2. FIBONACCI EXTENSIONS (from prev swing) ===
   if(InpShowFibo && totalSwings >= 3)
   {
      SSwing pointA = g_swings[totalSwings - 3];
      SSwing pointB = g_swings[totalSwings - 2];
      SSwing pointC = g_swings[totalSwings - 1];

      double swingAB = MathAbs(pointB.price - pointA.price);

      double fiboLevels[];
      string fiboNames[];
      ArrayResize(fiboLevels, 4);
      ArrayResize(fiboNames, 4);
      fiboLevels[0] = 0.618;  fiboNames[0] = "61.8%";
      fiboLevels[1] = 1.0;    fiboNames[1] = "100%";
      fiboLevels[2] = 1.272;  fiboNames[2] = "127.2%";
      fiboLevels[3] = 1.618;  fiboNames[3] = "161.8%";

      int f = 0;
      for(f = 0; f < 4; f++)
      {
         double target = 0;
         if(projDown)
            target = pointC.price - swingAB * fiboLevels[f];
         else
            target = pointC.price + swingAB * fiboLevels[f];

         string fName = g_prefix + "FIB" + IntegerToString(f);
         DrawHLine(fName, target, InpFiboColor, InpLineWidth, STYLE_DOT);
         DrawLabel(fName + "_L", target,
                   "  Fibo " + fiboNames[f] + " " + DoubleToString(target, _Digits),
                   InpFiboColor);
      }
   }

   //=== 3. MEASURED MOVE (AB=CD) ===
   if(InpShowMeasured && totalSwings >= 3)
   {
      SSwing pointA = g_swings[totalSwings - 3];
      SSwing pointB = g_swings[totalSwings - 2];
      SSwing pointC = g_swings[totalSwings - 1];

      double moveAB = pointB.price - pointA.price;
      double targetD = pointC.price + moveAB;

      DrawHLine(g_prefix + "ABCD", targetD, InpMeasuredColor, InpLineWidth + 1, STYLE_DASH);
      DrawLabel(g_prefix + "ABCD_L", targetD,
                "  AB=CD " + DoubleToString(targetD, _Digits) +
                " (" + DoubleToString(MathAbs(moveAB) / _Point, 0) + " pts)",
                InpMeasuredColor);

      //--- Draw A-B-C-D structure
      DrawTrendLine(g_prefix + "AB", pointA.time, pointA.price,
                    pointB.time, pointB.price, InpMeasuredColor, 1, STYLE_DASH);
      DrawTrendLine(g_prefix + "CD", pointC.time, pointC.price,
                    time[rates_total - 1], targetD, InpMeasuredColor, 1, STYLE_DASH);
   }

   //--- Info label
   string infoText = "";
   if(projDown)
      infoText = "Projection: DOWN from " + DoubleToString(lastSw.price, _Digits);
   else
      infoText = "Projection: UP from " + DoubleToString(lastSw.price, _Digits);

   if(cntUp > 0 || cntDn > 0)
   {
      infoText += "  |  Avg swing UP: " + DoubleToString(avgUp / _Point, 0) +
                  " pts  DN: " + DoubleToString(avgDn / _Point, 0) + " pts";
   }

   ObjectCreate(0, g_prefix + "INFO", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_prefix + "INFO", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_prefix + "INFO", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, g_prefix + "INFO", OBJPROP_YDISTANCE, 30);
   ObjectSetString(0, g_prefix + "INFO", OBJPROP_TEXT, infoText);
   ObjectSetInteger(0, g_prefix + "INFO", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_prefix + "INFO", OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, g_prefix + "INFO", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_prefix + "INFO", OBJPROP_SELECTABLE, false);

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
