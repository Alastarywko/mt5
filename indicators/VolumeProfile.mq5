//+------------------------------------------------------------------+
//|                                               VolumeProfile.mq5   |
//|           Професійний профіль об'єму v2                           |
//|           Трикутний розподіл + сесійні профілі + TPO + Delta      |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "2.00"
#property description "Professional Volume Profile (Session-based, TPO, Delta)"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- enums
enum ENUM_VP_MODE
{
   VP_LOOKBACK = 0,   // Fixed Lookback (bars)
   VP_DAILY    = 1,   // Daily Sessions
   VP_WEEKLY   = 2    // Weekly Sessions
};

enum ENUM_VP_DIST
{
   DIST_UNIFORM    = 0,  // Uniform (simple)
   DIST_TRIANGULAR = 1,  // Triangular (weighted to close)
   DIST_OHLC       = 2   // OHLC-weighted (most accurate)
};

//--- inputs
input ENUM_VP_MODE  InpMode        = VP_LOOKBACK;    // Profile Mode
input int           InpLookback    = 200;            // Lookback bars (for Fixed mode)
input int           InpBins        = 50;             // Number of price bins
input ENUM_VP_DIST  InpDistMethod  = DIST_OHLC;      // Volume Distribution Method
input bool          InpUseRealVol  = true;           // Use Real Volume (if available)
input double        InpVAPercent   = 70.0;           // Value Area % (default 70)
input color         InpHVNColor    = C'221,221,244'; // High Volume Node color
input color         InpLVNColor    = C'229,229,229'; // Low Volume Node color
input color         InpPOCColor    = clrGold;        // POC block color
input color         InpPOCLineClr  = clrDarkBlue;     // POC line color
input color         InpVAHColor    = clrMediumPurple; // VAH color
input color         InpVALColor    = clrMediumPurple; // VAL color
input color         InpBuyColor    = C'192,250,192'; // Buy Delta color
input color         InpSellColor   = C'250,192,192'; // Sell Delta color
input int           InpMaxWidth    = 30;             // Max histogram width (bars)
input double        InpHVNThresh   = 0.7;            // HVN threshold (0.0-1.0)
input bool          InpShowDelta   = true;           // Show Buy/Sell Delta
input bool          InpShowTPO     = true;           // Show TPO count
input bool          InpShowStats   = true;           // Show statistics panel

string g_prefix = "VP_";
int    g_lastBars = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Volume Profile Pro");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, g_prefix); }

//+------------------------------------------------------------------+
double GetBarVolume(const long &tick_vol[], const long &real_vol[], int idx)
{
   if(InpUseRealVol && real_vol[idx] > 0)
      return((double)real_vol[idx]);
   if(tick_vol[idx] > 0)
      return((double)tick_vol[idx]);
   return(1.0);
}

//+------------------------------------------------------------------+
void DistributeVolume(double vol, double barOpen, double barHigh,
                      double barLow, double barClose,
                      double priceLow, double binSize, int numBins,
                      double &binVol[], double &binBuy[], double &binSell[])
{
   int bLow  = (int)MathFloor((barLow - priceLow) / binSize);
   int bHigh = (int)MathFloor((barHigh - priceLow) / binSize);
   if(bLow < 0) bLow = 0;
   if(bHigh >= numBins) bHigh = numBins - 1;
   if(bLow > bHigh) return;

   int totalBins = bHigh - bLow + 1;
   bool isBullish = barClose >= barOpen;

   if(InpDistMethod == DIST_UNIFORM)
   {
      double perBin = vol / totalBins;
      int b = 0;
      for(b = bLow; b <= bHigh; b++)
      {
         binVol[b] += perBin;
         if(isBullish) binBuy[b] += perBin;
         else          binSell[b] += perBin;
      }
   }
   else if(InpDistMethod == DIST_TRIANGULAR)
   {
      int bClose = (int)MathFloor((barClose - priceLow) / binSize);
      if(bClose < bLow) bClose = bLow;
      if(bClose > bHigh) bClose = bHigh;

      double weights[];
      ArrayResize(weights, totalBins);
      double sumW = 0;
      int b = 0;

      for(b = bLow; b <= bHigh; b++)
      {
         int dist = MathAbs(b - bClose);
         double w = 1.0 + (double)(totalBins - dist) / totalBins;
         weights[b - bLow] = w;
         sumW += w;
      }

      for(b = bLow; b <= bHigh; b++)
      {
         double portion = vol * weights[b - bLow] / sumW;
         binVol[b] += portion;
         if(isBullish) binBuy[b] += portion;
         else          binSell[b] += portion;
      }
   }
   else // DIST_OHLC
   {
      int bOpen  = (int)MathFloor((barOpen - priceLow) / binSize);
      int bClose = (int)MathFloor((barClose - priceLow) / binSize);
      if(bOpen < bLow) bOpen = bLow;
      if(bOpen > bHigh) bOpen = bHigh;
      if(bClose < bLow) bClose = bLow;
      if(bClose > bHigh) bClose = bHigh;

      double weights[];
      ArrayResize(weights, totalBins);
      double sumW = 0;
      int b = 0;

      for(b = bLow; b <= bHigh; b++)
      {
         double w = 1.0;
         if(b == bOpen)  w += 2.0;
         if(b == bClose) w += 3.0;
         if(b == bHigh)  w += 1.5;
         if(b == bLow)   w += 1.5;

         double midPrice = priceLow + (b + 0.5) * binSize;
         double distFromClose = MathAbs(midPrice - barClose);
         double maxDist = barHigh - barLow;
         if(maxDist > _Point)
            w += 2.0 * (1.0 - distFromClose / maxDist);

         weights[b - bLow] = w;
         sumW += w;
      }

      for(b = bLow; b <= bHigh; b++)
      {
         double portion = vol * weights[b - bLow] / sumW;
         binVol[b] += portion;
         if(isBullish) binBuy[b] += portion;
         else          binSell[b] += portion;
      }
   }
}

//+------------------------------------------------------------------+
void FindSessionRange(const datetime &time[], int rates_total,
                      int &outStart, int &outEnd)
{
   outEnd = rates_total - 1;

   if(InpMode == VP_LOOKBACK)
   {
      outStart = MathMax(0, rates_total - InpLookback);
      return;
   }

   MqlDateTime dt;
   TimeToStruct(time[outEnd], dt);

   if(InpMode == VP_DAILY)
   {
      int i = outEnd;
      for(i = outEnd - 1; i >= 0; i--)
      {
         MqlDateTime dt2;
         TimeToStruct(time[i], dt2);
         if(dt2.day != dt.day || dt2.mon != dt.mon || dt2.year != dt.year)
         {
            outStart = i + 1;
            return;
         }
      }
      outStart = 0;
   }
   else // VP_WEEKLY
   {
      int i = outEnd;
      for(i = outEnd - 1; i >= 0; i--)
      {
         MqlDateTime dt2;
         TimeToStruct(time[i], dt2);
         if(dt2.day_of_week < dt.day_of_week && dt2.day_of_week == 1)
         {
            outStart = i;
            return;
         }
         if(time[outEnd] - time[i] > 7 * 86400)
         {
            outStart = i;
            return;
         }
      }
      outStart = 0;
   }
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   if(rates_total < 50) return(0);
   if(rates_total == g_lastBars) return(rates_total);
   g_lastBars = rates_total;

   ObjectsDeleteAll(0, g_prefix);

   //--- Determine range
   int startBar = 0, endBar = 0;
   FindSessionRange(time, rates_total, startBar, endBar);
   if(endBar - startBar < 5) return(rates_total);

   //--- Find price range
   double priceHigh = high[startBar];
   double priceLow  = low[startBar];
   int i = 0;

   for(i = startBar + 1; i <= endBar; i++)
   {
      if(high[i] > priceHigh) priceHigh = high[i];
      if(low[i] < priceLow)   priceLow = low[i];
   }

   double range = priceHigh - priceLow;
   if(range < _Point * 10) return(rates_total);

   double binSize = range / InpBins;

   //--- Accumulate volume per bin
   double binVol[], binBuy[], binSell[];
   int binTPO[];
   ArrayResize(binVol, InpBins);
   ArrayResize(binBuy, InpBins);
   ArrayResize(binSell, InpBins);
   ArrayResize(binTPO, InpBins);
   ArrayInitialize(binVol, 0);
   ArrayInitialize(binBuy, 0);
   ArrayInitialize(binSell, 0);
   ArrayInitialize(binTPO, 0);

   double totalVolume = 0;

   for(i = startBar; i <= endBar; i++)
   {
      double vol = GetBarVolume(tick_volume, volume, i);
      totalVolume += vol;

      DistributeVolume(vol, open[i], high[i], low[i], close[i],
                       priceLow, binSize, InpBins,
                       binVol, binBuy, binSell);

      //--- TPO: count how many bars touched each bin
      int bLow  = (int)MathFloor((low[i] - priceLow) / binSize);
      int bHigh = (int)MathFloor((high[i] - priceLow) / binSize);
      if(bLow < 0) bLow = 0;
      if(bHigh >= InpBins) bHigh = InpBins - 1;
      int b = 0;
      for(b = bLow; b <= bHigh; b++)
         binTPO[b]++;
   }

   //--- Find POC (max volume bin)
   double maxVol = 0;
   int pocBin = 0;
   for(i = 0; i < InpBins; i++)
   {
      if(binVol[i] > maxVol)
      {
         maxVol = binVol[i];
         pocBin = i;
      }
   }
   if(maxVol < 1) return(rates_total);

   //--- Find TPO POC
   int maxTPO = 0;
   int tpoPocBin = 0;
   for(i = 0; i < InpBins; i++)
   {
      if(binTPO[i] > maxTPO)
      {
         maxTPO = binTPO[i];
         tpoPocBin = i;
      }
   }

   //--- Value Area calculation
   double vaTarget = totalVolume * InpVAPercent / 100.0;
   double vaVol = binVol[pocBin];
   int vaLow = pocBin, vaHigh = pocBin;

   while(vaVol < vaTarget)
   {
      double addLow = (vaLow > 0) ? binVol[vaLow - 1] : 0;
      double addHigh = (vaHigh < InpBins - 1) ? binVol[vaHigh + 1] : 0;

      if(vaLow <= 0 && vaHigh >= InpBins - 1) break;

      if(addLow >= addHigh && vaLow > 0)
      {
         vaLow--;
         vaVol += binVol[vaLow];
      }
      else if(vaHigh < InpBins - 1)
      {
         vaHigh++;
         vaVol += binVol[vaHigh];
      }
      else if(vaLow > 0)
      {
         vaLow--;
         vaVol += binVol[vaLow];
      }
      else
         break;
   }

   double vaLowPrice  = priceLow + vaLow * binSize;
   double vaHighPrice = priceLow + (vaHigh + 1) * binSize;
   double pocPrice    = priceLow + (pocBin + 0.5) * binSize;
   double tpoPocPrice = priceLow + (tpoPocBin + 0.5) * binSize;

   datetime tRight = time[endBar];
   datetime tLeft  = time[startBar];
   datetime tFuture = tRight + PeriodSeconds() * 12;

   //--- Draw histogram
   int b = 0;
   for(b = 0; b < InpBins; b++)
   {
      double ratio = binVol[b] / maxVol;
      int barWidth = (int)MathRound(ratio * InpMaxWidth);
      if(barWidth < 1) barWidth = 1;

      double yLow  = priceLow + b * binSize;
      double yHigh = yLow + binSize;

      datetime tBar = time[MathMax(0, endBar - barWidth)];

      bool isHVN = ratio >= InpHVNThresh;
      bool isPOC = (b == pocBin);
      bool inVA  = (b >= vaLow && b <= vaHigh);

      //--- Main volume bar (filled rectangles)
      color clr = InpLVNColor;
      if(isPOC) clr = InpPOCColor;
      else if(isHVN) clr = InpHVNColor;
      else if(inVA) clr = InpHVNColor;

      string nm = g_prefix + "B" + IntegerToString(b);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, tBar, yLow, tRight, yHigh);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_FILL, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

      //--- Delta overlay (buy/sell — right side, outside candles)
      if(InpShowDelta && binVol[b] > 0)
      {
         double buyRatio  = binBuy[b] / binVol[b];
         double sellRatio = binSell[b] / binVol[b];

         int deltaWidth = (int)MathMax(1, MathRound(ratio * InpMaxWidth * 0.4));
         datetime tDeltaStart = tRight + PeriodSeconds() * 3;
         datetime tDeltaEnd   = tRight + PeriodSeconds() * (deltaWidth + 3);
         double yMid = yLow + (yHigh - yLow) * sellRatio;

         if(sellRatio > 0.05)
         {
            string nmS = g_prefix + "DS" + IntegerToString(b);
            ObjectCreate(0, nmS, OBJ_RECTANGLE, 0, tDeltaStart, yLow, tDeltaEnd, yMid);
            ObjectSetInteger(0, nmS, OBJPROP_COLOR, InpSellColor);
            ObjectSetInteger(0, nmS, OBJPROP_FILL, true);
            ObjectSetInteger(0, nmS, OBJPROP_BACK, true);
            ObjectSetInteger(0, nmS, OBJPROP_SELECTABLE, false);
         }

         if(buyRatio > 0.05)
         {
            string nmB = g_prefix + "DB" + IntegerToString(b);
            ObjectCreate(0, nmB, OBJ_RECTANGLE, 0, tDeltaStart, yMid, tDeltaEnd, yHigh);
            ObjectSetInteger(0, nmB, OBJPROP_COLOR, InpBuyColor);
            ObjectSetInteger(0, nmB, OBJPROP_FILL, true);
            ObjectSetInteger(0, nmB, OBJPROP_BACK, true);
            ObjectSetInteger(0, nmB, OBJPROP_SELECTABLE, false);
         }
      }
   }

   //--- POC line
   ObjectCreate(0, g_prefix+"POC", OBJ_TREND, 0, tLeft, pocPrice, tFuture, pocPrice);
   ObjectSetInteger(0, g_prefix+"POC", OBJPROP_COLOR, InpPOCLineClr);
   ObjectSetInteger(0, g_prefix+"POC", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, g_prefix+"POC", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, g_prefix+"POC", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"POC", OBJPROP_BACK, false);
   ObjectSetInteger(0, g_prefix+"POC", OBJPROP_SELECTABLE, false);

   ObjectCreate(0, g_prefix+"POC_L", OBJ_TEXT, 0, tFuture, pocPrice);
   ObjectSetString(0, g_prefix+"POC_L", OBJPROP_TEXT,
      "  POC " + DoubleToString(pocPrice, _Digits));
   ObjectSetInteger(0, g_prefix+"POC_L", OBJPROP_COLOR, InpPOCLineClr);
   ObjectSetInteger(0, g_prefix+"POC_L", OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, g_prefix+"POC_L", OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, g_prefix+"POC_L", OBJPROP_ANCHOR, ANCHOR_LEFT);

   //--- TPO POC line (if different from volume POC)
   if(InpShowTPO && MathAbs(tpoPocPrice - pocPrice) > binSize * 0.5)
   {
      ObjectCreate(0, g_prefix+"TPOC", OBJ_TREND, 0, tLeft, tpoPocPrice, tFuture, tpoPocPrice);
      ObjectSetInteger(0, g_prefix+"TPOC", OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, g_prefix+"TPOC", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, g_prefix+"TPOC", OBJPROP_STYLE, STYLE_DASHDOT);
      ObjectSetInteger(0, g_prefix+"TPOC", OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, g_prefix+"TPOC", OBJPROP_BACK, false);

      ObjectCreate(0, g_prefix+"TPOC_L", OBJ_TEXT, 0, tFuture, tpoPocPrice);
      ObjectSetString(0, g_prefix+"TPOC_L", OBJPROP_TEXT,
         "  TPO-POC " + DoubleToString(tpoPocPrice, _Digits));
      ObjectSetInteger(0, g_prefix+"TPOC_L", OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, g_prefix+"TPOC_L", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, g_prefix+"TPOC_L", OBJPROP_ANCHOR, ANCHOR_LEFT);
   }

   //--- VAH line
   ObjectCreate(0, g_prefix+"VAH", OBJ_TREND, 0, tLeft, vaHighPrice, tFuture, vaHighPrice);
   ObjectSetInteger(0, g_prefix+"VAH", OBJPROP_COLOR, InpVAHColor);
   ObjectSetInteger(0, g_prefix+"VAH", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, g_prefix+"VAH", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, g_prefix+"VAH", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"VAH", OBJPROP_BACK, true);

   ObjectCreate(0, g_prefix+"VAH_L", OBJ_TEXT, 0, tFuture, vaHighPrice);
   ObjectSetString(0, g_prefix+"VAH_L", OBJPROP_TEXT,
      "  VAH " + DoubleToString(vaHighPrice, _Digits));
   ObjectSetInteger(0, g_prefix+"VAH_L", OBJPROP_COLOR, InpVAHColor);
   ObjectSetInteger(0, g_prefix+"VAH_L", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_prefix+"VAH_L", OBJPROP_ANCHOR, ANCHOR_LEFT);

   //--- VAL line
   ObjectCreate(0, g_prefix+"VAL", OBJ_TREND, 0, tLeft, vaLowPrice, tFuture, vaLowPrice);
   ObjectSetInteger(0, g_prefix+"VAL", OBJPROP_COLOR, InpVALColor);
   ObjectSetInteger(0, g_prefix+"VAL", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, g_prefix+"VAL", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, g_prefix+"VAL", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, g_prefix+"VAL", OBJPROP_BACK, true);

   ObjectCreate(0, g_prefix+"VAL_L", OBJ_TEXT, 0, tFuture, vaLowPrice);
   ObjectSetString(0, g_prefix+"VAL_L", OBJPROP_TEXT,
      "  VAL " + DoubleToString(vaLowPrice, _Digits));
   ObjectSetInteger(0, g_prefix+"VAL_L", OBJPROP_COLOR, InpVALColor);
   ObjectSetInteger(0, g_prefix+"VAL_L", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_prefix+"VAL_L", OBJPROP_ANCHOR, ANCHOR_LEFT);

   //--- Statistics panel
   if(InpShowStats)
   {
      double curPrice = close[rates_total - 1];
      string posVA = "INSIDE VA";
      if(curPrice > vaHighPrice) posVA = "ABOVE VA";
      else if(curPrice < vaLowPrice) posVA = "BELOW VA";

      double totalBuy = 0, totalSell = 0;
      for(b = 0; b < InpBins; b++)
      {
         totalBuy += binBuy[b];
         totalSell += binSell[b];
      }
      double deltaPercent = 0;
      if(totalBuy + totalSell > 0)
         deltaPercent = (totalBuy - totalSell) / (totalBuy + totalSell) * 100.0;

      int barsInProfile = endBar - startBar + 1;
      string modeStr = "Lookback";
      if(InpMode == VP_DAILY) modeStr = "Daily";
      if(InpMode == VP_WEEKLY) modeStr = "Weekly";

      string line1 = modeStr + " | " + IntegerToString(barsInProfile) + " bars | " + posVA;
      string line2 = "POC: " + DoubleToString(pocPrice, _Digits) +
                      " | VA: " + DoubleToString(vaLowPrice, _Digits) +
                      " - " + DoubleToString(vaHighPrice, _Digits);
      string line3 = "Delta: " + DoubleToString(deltaPercent, 1) + "% " +
                      (deltaPercent > 0 ? "(BUYERS)" : deltaPercent < 0 ? "(SELLERS)" : "(NEUTRAL)");

      int yOff = 30;
      int ln = 0;
      string lines[];
      ArrayResize(lines, 3);
      lines[0] = line1;
      lines[1] = line2;
      lines[2] = line3;

      for(ln = 0; ln < 3; ln++)
      {
         string sNm = g_prefix + "S" + IntegerToString(ln);
         ObjectCreate(0, sNm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, sNm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, sNm, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, sNm, OBJPROP_YDISTANCE, yOff + ln * 16);
         ObjectSetString(0, sNm, OBJPROP_TEXT, lines[ln]);
         ObjectSetInteger(0, sNm, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, sNm, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, sNm, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, sNm, OBJPROP_SELECTABLE, false);
      }
   }

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
