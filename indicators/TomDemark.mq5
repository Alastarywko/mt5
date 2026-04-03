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
input bool   InpAlertPrep    = true;     // Alert on Preparation Complete
input bool   InpAlertLead    = true;     // Alert on Lead-Up Complete

string g_pfx = "TD2_";

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Sequencer");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_pfx);
}

//+------------------------------------------------------------------+
void DrawLabel(string id, datetime t, double price, string text,
               color clr, int fontSize, bool isBelow)
{
   if(ObjectFind(0, id) >= 0) return;
   ObjectCreate(0, id, OBJ_TEXT, 0, t, price);
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

   static int bullPrep = 0, bearPrep = 0;
   static int bullLead = 0, bearLead = 0;
   static bool bullLeadActive = false, bearLeadActive = false;
   static int bullPrepLvlIdx = 0, bearPrepLvlIdx = 0;
   static int bullLeadLvlIdx = 0, bearLeadLvlIdx = 0;
   static datetime bullPrepLvlStart = 0, bearPrepLvlStart = 0;
   static double   bullPrepLvlPrice = 0, bearPrepLvlPrice = 0;
   static datetime bullLeadLvlStart = 0, bearLeadLvlStart = 0;
   static double   bullLeadLvlPrice = 0, bearLeadLvlPrice = 0;

   int start;
   if(prev_calculated == 0)
   {
      ObjectsDeleteAll(0, g_pfx);
      bullPrep = 0; bearPrep = 0;
      bullLead = 0; bearLead = 0;
      bullLeadActive = false; bearLeadActive = false;
      bullPrepLvlIdx = 0; bearPrepLvlIdx = 0;
      bullLeadLvlIdx = 0; bearLeadLvlIdx = 0;
      start = minBars;
   }
   else
      start = MathMax(prev_calculated - 1, minBars);

   for(int i = start; i < rates_total; i++)
   {
      bool completeBullPrep = false;
      bool completeBearPrep = false;

      //=== PREPARATION PHASE ===

      // Bullish Preparation: close < close[N bars ago]
      if(InpBullPrep && close[i] < close[i - InpPrepCompare])
      {
         bullPrep++;
         if(bullPrep > InpPrepLen) bullPrep = InpPrepLen + 1;

         if(bullPrep <= InpPrepLen)
         {
            bool isKey = (bullPrep == InpPrepLen);
            DrawLabel(g_pfx + "BP" + IntegerToString(i), time[i], low[i],
                      IntegerToString(bullPrep), InpBullPrepClr,
                      isKey ? InpPrepFontSize + 3 : InpPrepFontSize, true);

            if(bullPrep == InpPrepLen)
            {
               completeBullPrep = true;
               if(InpAlertPrep && i >= rates_total - 2)
                  Alert("Sequencer: Bullish Prep ", InpPrepLen, " | ", _Symbol, " ", EnumToString(_Period));
            }
         }
      }
      else if(bullPrep > 0 && !(close[i] < close[i - InpPrepCompare]))
      {
         // delete incomplete preparation labels
         for(int d = 1; d <= bullPrep && d <= InpPrepLen; d++)
         {
            int idx = i - bullPrep + d;
            if(idx >= 0) ObjectDelete(0, g_pfx + "BP" + IntegerToString(idx));
         }
         bullPrep = 0;
      }

      // Bearish Preparation: close > close[N bars ago]
      if(InpBearPrep && close[i] > close[i - InpPrepCompare])
      {
         bearPrep++;
         if(bearPrep > InpPrepLen) bearPrep = InpPrepLen + 1;

         if(bearPrep <= InpPrepLen)
         {
            bool isKey = (bearPrep == InpPrepLen);
            DrawLabel(g_pfx + "SP" + IntegerToString(i), time[i], high[i],
                      IntegerToString(bearPrep), InpBearPrepClr,
                      isKey ? InpPrepFontSize + 3 : InpPrepFontSize, false);

            if(bearPrep == InpPrepLen)
            {
               completeBearPrep = true;
               if(InpAlertPrep && i >= rates_total - 2)
                  Alert("Sequencer: Bearish Prep ", InpPrepLen, " | ", _Symbol, " ", EnumToString(_Period));
            }
         }
      }
      else if(bearPrep > 0 && !(close[i] > close[i - InpPrepCompare]))
      {
         for(int d = 1; d <= bearPrep && d <= InpPrepLen; d++)
         {
            int idx = i - bearPrep + d;
            if(idx >= 0) ObjectDelete(0, g_pfx + "SP" + IntegerToString(idx));
         }
         bearPrep = 0;
      }

      // Reset opposite on new count
      if(bullPrep == 1) bearPrep = 0;
      if(bearPrep == 1) bullPrep = 0;

      //=== PREPARATION LEVELS ===
      if(InpShowPrepLvl)
      {
         if(completeBullPrep)
         {
            bullPrepLvlStart = time[i];
            bullPrepLvlPrice = low[i];
            bullPrepLvlIdx++;
         }
         if(bullPrepLvlStart > 0)
            DrawLevel(g_pfx + "BPL" + IntegerToString(bullPrepLvlIdx), bullPrepLvlStart, time[i], bullPrepLvlPrice, InpBullPrepClr);

         if(completeBearPrep)
         {
            bearPrepLvlStart = time[i];
            bearPrepLvlPrice = high[i];
            bearPrepLvlIdx++;
         }
         if(bearPrepLvlStart > 0)
            DrawLevel(g_pfx + "SPL" + IntegerToString(bearPrepLvlIdx), bearPrepLvlStart, time[i], bearPrepLvlPrice, InpBearPrepClr);
      }

      //=== LEAD-UP PHASE ===

      // Start lead-up on preparation completion
      if(completeBullPrep && InpBullLead)
      {
         bullLeadActive = true;
         bullLead = 0;
      }
      if(completeBearPrep && InpBearLead)
      {
         bearLeadActive = true;
         bearLead = 0;
      }

      // Cancellation: opposite preparation completes
      if(InpCancellation)
      {
         if(completeBearPrep && bullLeadActive)
         {
            bullLeadActive = false;
            bullLead = 0;
         }
         if(completeBullPrep && bearLeadActive)
         {
            bearLeadActive = false;
            bearLead = 0;
         }
      }

      // Bullish Lead-Up: close <= low[N bars ago]
      if(bullLeadActive && i >= InpLeadCompare)
      {
         if(close[i] <= low[i - InpLeadCompare])
         {
            bullLead++;
            if(bullLead <= InpLeadLen)
            {
               bool isComplete = (bullLead == InpLeadLen);
               int fs = isComplete ? InpLeadFontSize + 5 : InpLeadFontSize;
               DrawLabel(g_pfx + "BL" + IntegerToString(i), time[i], low[i],
                         IntegerToString(bullLead), InpBullLeadClr, fs, true);

               if(isComplete)
               {
                  bullLeadActive = false;
                  bullLead = 0;
                  if(InpAlertLead && i >= rates_total - 2)
                     Alert("Sequencer: Bullish Lead-Up ", InpLeadLen, " | ", _Symbol, " ", EnumToString(_Period));

                  if(InpShowLeadLvl)
                  {
                     bullLeadLvlStart = time[i];
                     bullLeadLvlPrice = low[i];
                     bullLeadLvlIdx++;
                  }
               }
            }
         }
      }

      // Bearish Lead-Up: close >= high[N bars ago]
      if(bearLeadActive && i >= InpLeadCompare)
      {
         if(close[i] >= high[i - InpLeadCompare])
         {
            bearLead++;
            if(bearLead <= InpLeadLen)
            {
               bool isComplete = (bearLead == InpLeadLen);
               int fs = isComplete ? InpLeadFontSize + 5 : InpLeadFontSize;
               DrawLabel(g_pfx + "SL" + IntegerToString(i), time[i], high[i],
                         IntegerToString(bearLead), InpBearLeadClr, fs, false);

               if(isComplete)
               {
                  bearLeadActive = false;
                  bearLead = 0;
                  if(InpAlertLead && i >= rates_total - 2)
                     Alert("Sequencer: Bearish Lead-Up ", InpLeadLen, " | ", _Symbol, " ", EnumToString(_Period));

                  if(InpShowLeadLvl)
                  {
                     bearLeadLvlStart = time[i];
                     bearLeadLvlPrice = high[i];
                     bearLeadLvlIdx++;
                  }
               }
            }
         }
      }

      //=== LEAD-UP LEVELS ===
      if(InpShowLeadLvl)
      {
         if(bullLeadLvlStart > 0)
            DrawLevel(g_pfx + "BLL" + IntegerToString(bullLeadLvlIdx), bullLeadLvlStart, time[i], bullLeadLvlPrice, InpBullLeadClr);
         if(bearLeadLvlStart > 0)
            DrawLevel(g_pfx + "SLL" + IntegerToString(bearLeadLvlIdx), bearLeadLvlStart, time[i], bearLeadLvlPrice, InpBearLeadClr);
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
