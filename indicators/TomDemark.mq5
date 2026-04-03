//+------------------------------------------------------------------+
//|                                                  TomDemark2.mq5  |
//|           Sequencer (LuxAlgo port to MQL5)                       |
//|           Preparation Phase (1-9) + Lead-Up Phase (1-13)         |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "1.00"
#property description "Sequencer - TD Sequential (Preparation + Lead-Up)"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//═══════════════════════════════════════════════════════════════
// PREPARATION PHASE
//═══════════════════════════════════════════════════════════════
input int    InpPrepLen      = 9;        // Preparation Phase Length
input int    InpPrepCompare  = 4;        // Preparation Comparison Period
input bool   InpBullPrep     = true;     // Bullish Preparation
input bool   InpBearPrep     = true;     // Bearish Preparation
input color  InpBullPrepClr  = clrGreen; // Bullish Preparation Color
input color  InpBearPrepClr  = clrRed;   // Bearish Preparation Color
input int    InpPrepFontSize = 9;        // Preparation Font Size
input int    InpDisplayHours = 72;      // Display period (hours, 0 = all)

//═══════════════════════════════════════════════════════════════
// LEAD-UP PHASE
//═══════════════════════════════════════════════════════════════
input int    InpLeadLen      = 13;       // Lead-Up Phase Length
input int    InpLeadCompare  = 2;        // Lead-Up Comparison Period
input bool   InpBullLead     = true;     // Bullish Lead-Up
input bool   InpBearLead     = true;     // Bearish Lead-Up
input bool   InpCancellation = true;     // Apply Cancellation
input color  InpBullLeadClr  = clrDodgerBlue; // Bullish Lead-Up Color
input color  InpBearLeadClr  = clrOrangeRed;  // Bearish Lead-Up Color
input int    InpLeadFontSize = 9;        // Lead-Up Font Size

//═══════════════════════════════════════════════════════════════
// LEVELS
//═══════════════════════════════════════════════════════════════
input bool   InpShowPrepLvl  = false;    // Show Preparation Levels
input bool   InpShowLeadLvl  = false;    // Show Lead-Up Levels

//═══════════════════════════════════════════════════════════════
// ALERTS
//═══════════════════════════════════════════════════════════════
input bool   InpAlertPrep    = false;    // Alert on Preparation Complete (9)
input bool   InpAlertLead    = false;    // Alert on Lead-Up Complete (13)
input bool   InpPreAlert     = true;     // Pre-alert 10s before 9/13
input int    InpPreAlertSec  = 10;       // Pre-alert seconds before bar close

string g_pfx = "TD2_";
datetime g_preAlertBar = 0;
int g_bullPrep = 0, g_bearPrep = 0;
int g_bullLead = 0, g_bearLead = 0;
bool g_bullLeadActive = false, g_bearLeadActive = false;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Sequencer");
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, g_pfx);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpPreAlert) return;

   datetime barStart = iTime(_Symbol, _Period, 0);
   int barSec = PeriodSeconds(_Period);
   if(barSec <= 0) return;
   datetime barEnd = barStart + barSec;
   datetime now = TimeCurrent();
   int remain = (int)(barEnd - now);

   if(remain > InpPreAlertSec || remain < 0) return;
   if(barStart == g_preAlertBar) return;

   int bars = iBars(_Symbol, _Period);
   if(bars < InpPrepCompare + 2) return;

   double c0 = iClose(_Symbol, _Period, 0);
   double cN = iClose(_Symbol, _Period, InpPrepCompare);
   double lo2 = iLow(_Symbol, _Period, InpLeadCompare);
   double hi2 = iHigh(_Symbol, _Period, InpLeadCompare);

   bool prepBuy9  = (g_bullPrep == InpPrepLen - 1 && c0 < cN);
   bool prepSell9 = (g_bearPrep == InpPrepLen - 1 && c0 > cN);
   bool leadBuy13  = (g_bullLeadActive && g_bullLead == InpLeadLen - 1 && c0 <= lo2);
   bool leadSell13 = (g_bearLeadActive && g_bearLead == InpLeadLen - 1 && c0 >= hi2);

   string msg = "";
   if(prepBuy9)   msg = "PRE: Bullish 9 forming";
   if(prepSell9)  msg = "PRE: Bearish 9 forming";
   if(leadBuy13)  msg = "PRE: Bullish 13 forming";
   if(leadSell13) msg = "PRE: Bearish 13 forming";

   if(msg != "")
   {
      Alert(StringFormat("Sequencer %s | %s %s | %ds", msg, _Symbol, EnumToString(_Period), remain));
      g_preAlertBar = barStart;
   }
}

//+------------------------------------------------------------------+
void DrawLabel(string id, datetime t, double price, string text,
               color clr, int fontSize, bool isBelow, int layer = 0)
{
   if(ObjectFind(0, id) >= 0) return;
   double shift = _Point * 40 * layer;
   double y = isBelow ? price - shift : price + shift;
   ObjectCreate(0, id, OBJ_TEXT, 0, t, y);
   ObjectSetString(0, id, OBJPROP_TEXT, text);
   ObjectSetString(0, id, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, id, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, id, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, id, OBJPROP_ANCHOR, isBelow ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void DrawLevel(string id, datetime t1, datetime t2, double price, color clr)
{
   if(ObjectFind(0, id) >= 0)
   {
      ObjectSetInteger(0, id, OBJPROP_TIME, 1, t2);
      return;
   }
   ObjectCreate(0, id, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, id, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, id, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, id, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, id, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, id, OBJPROP_BACK, true);
   ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   int minBars = MathMax(InpPrepCompare, InpLeadCompare) + 2;
   if(rates_total < minBars + 10) return(0);

   static int g_bullPrepLvlIdx = 0, g_bearPrepLvlIdx = 0;
   static int g_bullLeadLvlIdx = 0, g_bearLeadLvlIdx = 0;
   static datetime g_bullPrepLvlStart = 0, g_bearPrepLvlStart = 0;
   static double   g_bullPrepLvlPrice = 0, g_bearPrepLvlPrice = 0;
   static datetime g_bullLeadLvlStart = 0, g_bearLeadLvlStart = 0;
   static double   g_bullLeadLvlPrice = 0, g_bearLeadLvlPrice = 0;

   int start;
   if(prev_calculated == 0)
   {
      ObjectsDeleteAll(0, g_pfx);
      g_bullPrep = 0; g_bearPrep = 0;
      g_bullLead = 0; g_bearLead = 0;
      g_bullLeadActive = false; g_bearLeadActive = false;
      g_bullPrepLvlIdx = 0; g_bearPrepLvlIdx = 0;
      g_bullLeadLvlIdx = 0; g_bearLeadLvlIdx = 0;
      start = minBars;
   }
   else
      start = MathMax(prev_calculated - 1, minBars);

   datetime cutoff = 0;
   if(InpDisplayHours > 0 && rates_total > 0)
      cutoff = time[rates_total - 1] - InpDisplayHours * 3600;

   for(int i = start; i < rates_total; i++)
   {
      int belowCount = 0, aboveCount = 0;
      bool completeBullPrep = false;
      bool completeBearPrep = false;
      bool canDraw = (InpDisplayHours == 0 || time[i] >= cutoff);

      //=== PREPARATION PHASE ===

      // Bullish Preparation: close < close[N bars ago]
      if(InpBullPrep && close[i] < close[i - InpPrepCompare])
      {
         g_bullPrep++;
         if(g_bullPrep > InpPrepLen) g_bullPrep = InpPrepLen + 1;

         if(g_bullPrep <= InpPrepLen && g_bullPrep >= 6 && canDraw)
         {
            bool isKey = (g_bullPrep == InpPrepLen);
            DrawLabel(g_pfx + "BP" + IntegerToString(i), time[i], low[i],
                      IntegerToString(g_bullPrep), InpBullPrepClr,
                      isKey ? InpPrepFontSize + 3 : InpPrepFontSize, true, belowCount);
            belowCount++;

            if(g_bullPrep == InpPrepLen)
            {
               completeBullPrep = true;
               if(InpAlertPrep && i >= rates_total - 2)
                  Alert("Sequencer: Bullish Prep ", InpPrepLen, " | ", _Symbol, " ", EnumToString(_Period));
            }
         }
      }
      else if(g_bullPrep > 0 && !(close[i] < close[i - InpPrepCompare]))
      {
         // delete incomplete preparation labels
         for(int d = 1; d <= g_bullPrep && d <= InpPrepLen; d++)
         {
            int idx = i - g_bullPrep + d;
            if(idx >= 0) ObjectDelete(0, g_pfx + "BP" + IntegerToString(idx));
         }
         g_bullPrep = 0;
      }

      // Bearish Preparation: close > close[N bars ago]
      if(InpBearPrep && close[i] > close[i - InpPrepCompare])
      {
         g_bearPrep++;
         if(g_bearPrep > InpPrepLen) g_bearPrep = InpPrepLen + 1;

         if(g_bearPrep <= InpPrepLen && g_bearPrep >= 6 && canDraw)
         {
            bool isKey = (g_bearPrep == InpPrepLen);
            DrawLabel(g_pfx + "SP" + IntegerToString(i), time[i], high[i],
                      IntegerToString(g_bearPrep), InpBearPrepClr,
                      isKey ? InpPrepFontSize + 3 : InpPrepFontSize, false, aboveCount);
            aboveCount++;

            if(g_bearPrep == InpPrepLen)
            {
               completeBearPrep = true;
               if(InpAlertPrep && i >= rates_total - 2)
                  Alert("Sequencer: Bearish Prep ", InpPrepLen, " | ", _Symbol, " ", EnumToString(_Period));
            }
         }
      }
      else if(g_bearPrep > 0 && !(close[i] > close[i - InpPrepCompare]))
      {
         for(int d = 1; d <= g_bearPrep && d <= InpPrepLen; d++)
         {
            int idx = i - g_bearPrep + d;
            if(idx >= 0) ObjectDelete(0, g_pfx + "SP" + IntegerToString(idx));
         }
         g_bearPrep = 0;
      }

      // Reset opposite on new count
      if(g_bullPrep == 1) g_bearPrep = 0;
      if(g_bearPrep == 1) g_bullPrep = 0;

      //=== PREPARATION LEVELS ===
      if(InpShowPrepLvl)
      {
         if(completeBullPrep)
         {
            g_bullPrepLvlStart = time[i];
            g_bullPrepLvlPrice = low[i];
            g_bullPrepLvlIdx++;
         }
         if(g_bullPrepLvlStart > 0)
            DrawLevel(g_pfx + "BPL" + IntegerToString(g_bullPrepLvlIdx), g_bullPrepLvlStart, time[i], g_bullPrepLvlPrice, InpBullPrepClr);

         if(completeBearPrep)
         {
            g_bearPrepLvlStart = time[i];
            g_bearPrepLvlPrice = high[i];
            g_bearPrepLvlIdx++;
         }
         if(g_bearPrepLvlStart > 0)
            DrawLevel(g_pfx + "SPL" + IntegerToString(g_bearPrepLvlIdx), g_bearPrepLvlStart, time[i], g_bearPrepLvlPrice, InpBearPrepClr);
      }

      //=== LEAD-UP PHASE ===

      // Start lead-up on preparation completion
      if(completeBullPrep && InpBullLead)
      {
         g_bullLeadActive = true;
         g_bullLead = 0;
      }
      if(completeBearPrep && InpBearLead)
      {
         g_bearLeadActive = true;
         g_bearLead = 0;
      }

      // Cancellation: opposite preparation completes
      if(InpCancellation)
      {
         if(completeBearPrep && g_bullLeadActive)
         {
            g_bullLeadActive = false;
            g_bullLead = 0;
         }
         if(completeBullPrep && g_bearLeadActive)
         {
            g_bearLeadActive = false;
            g_bearLead = 0;
         }
      }

      // Bullish Lead-Up: close <= low[N bars ago]
      if(g_bullLeadActive && i >= InpLeadCompare)
      {
         if(close[i] <= low[i - InpLeadCompare])
         {
            g_bullLead++;
            if(g_bullLead <= InpLeadLen && g_bullLead >= 6 && canDraw)
            {
               bool isComplete = (g_bullLead == InpLeadLen);
               int fs = isComplete ? InpLeadFontSize + 5 : InpLeadFontSize;
               DrawLabel(g_pfx + "BL" + IntegerToString(i), time[i], low[i],
                         IntegerToString(g_bullLead), InpBullLeadClr, fs, true, belowCount);
               belowCount++;

               if(isComplete)
               {
                  g_bullLeadActive = false;
                  g_bullLead = 0;
                  if(InpAlertLead && i >= rates_total - 2)
                     Alert("Sequencer: Bullish Lead-Up ", InpLeadLen, " | ", _Symbol, " ", EnumToString(_Period));

                  if(InpShowLeadLvl)
                  {
                     g_bullLeadLvlStart = time[i];
                     g_bullLeadLvlPrice = low[i];
                     g_bullLeadLvlIdx++;
                  }
               }
            }
         }
      }

      // Bearish Lead-Up: close >= high[N bars ago]
      if(g_bearLeadActive && i >= InpLeadCompare)
      {
         if(close[i] >= high[i - InpLeadCompare])
         {
            g_bearLead++;
            if(g_bearLead <= InpLeadLen && g_bearLead >= 6 && canDraw)
            {
               bool isComplete = (g_bearLead == InpLeadLen);
               int fs = isComplete ? InpLeadFontSize + 5 : InpLeadFontSize;
               DrawLabel(g_pfx + "SL" + IntegerToString(i), time[i], high[i],
                         IntegerToString(g_bearLead), InpBearLeadClr, fs, false, aboveCount);
               aboveCount++;

               if(isComplete)
               {
                  g_bearLeadActive = false;
                  g_bearLead = 0;
                  if(InpAlertLead && i >= rates_total - 2)
                     Alert("Sequencer: Bearish Lead-Up ", InpLeadLen, " | ", _Symbol, " ", EnumToString(_Period));

                  if(InpShowLeadLvl)
                  {
                     g_bearLeadLvlStart = time[i];
                     g_bearLeadLvlPrice = high[i];
                     g_bearLeadLvlIdx++;
                  }
               }
            }
         }
      }

      //=== LEAD-UP LEVELS ===
      if(InpShowLeadLvl)
      {
         if(g_bullLeadLvlStart > 0)
            DrawLevel(g_pfx + "BLL" + IntegerToString(g_bullLeadLvlIdx), g_bullLeadLvlStart, time[i], g_bullLeadLvlPrice, InpBullLeadClr);
         if(g_bearLeadLvlStart > 0)
            DrawLevel(g_pfx + "SLL" + IntegerToString(g_bearLeadLvlIdx), g_bearLeadLvlStart, time[i], g_bearLeadLvlPrice, InpBearLeadClr);
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
