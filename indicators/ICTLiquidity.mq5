//+------------------------------------------------------------------+
//|                                                ICTLiquidity.mq5   |
//|           SMC Target Liquidity (X / SFP / MSS)                    |
//|           Переведено з PineScript v35                              |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "1.00"
#property description "SMC Target Liquidity"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- enums
enum ENUM_TXT_SIZE
{
   TXT_TINY   = 0,  // Tiny
   TXT_SMALL  = 1,  // Small
   TXT_NORMAL = 2,  // Normal
   TXT_LARGE  = 3,  // Large
   TXT_HUGE   = 4   // Huge
};

enum ENUM_LN_STYLE
{
   LN_SOLID  = 0,   // Solid
   LN_DASHED = 1,   // Dashed
   LN_DOTTED = 2    // Dotted
};

//--- inputs: main
input int             InpPivotPeriod    = 10;            // Pivot Period
input int             InpMaxActiveLines = 5;             // Max Active Lines (per side)
input int             InpMaxBars        = 500;           // Max bars to analyze

//--- inputs: sessions
input int             InpActiveWidth    = 2;             // Active Line Width
input string          InpAsiaSession    = "20:00-00:00"; // Asian Session
input color           InpAsiaColor      = clrYellow;     // Asian Color
input string          InpLondonSession  = "02:00-05:00"; // London Session
input color           InpLondonColor    = clrTeal;       // London Color
input string          InpNYAMSession    = "08:30-11:00"; // NY AM Session
input color           InpNYAMColor      = clrOrange;     // NY AM Color
input string          InpNYPMSession    = "13:30-16:00"; // NY PM Session
input color           InpNYPMColor      = clrFuchsia;    // NY PM Color
input color           InpOtherColor     = clrGray;       // Outside Session Color

//--- inputs: display
input ENUM_TXT_SIZE   InpTextSize       = TXT_LARGE;     // Text Size
input double          InpLabelOffset    = 30;            // Text Distance (Ticks)
input bool            InpFlipText       = false;         // Flip Text Position
input bool            InpShowPrice      = true;          // Show Price Labels
input int             InpLineExtension  = 15;            // Line Extension (bars)

//--- inputs: X (Sweep)
input bool            InpShowX          = true;          // Show X
input color           InpXLineColor     = clrGray;       // X Line Color
input color           InpXTextColor     = clrBlack;      // X Text Color
input ENUM_LN_STYLE   InpXStyle         = LN_DOTTED;     // X Line Style

//--- inputs: SFP (Fakeout)
input bool            InpShowSFP        = true;          // Show SFP
input color           InpSFPLineColor   = clrRed;        // SFP Line Color
input color           InpSFPTextColor   = clrBlack;      // SFP Text Color
input ENUM_LN_STYLE   InpSFPStyle       = LN_DASHED;     // SFP Line Style

//--- inputs: MSS (Breakout)
input bool            InpShowMSS        = true;          // Show MSS
input color           InpMSSLineColor   = clrBlack;      // MSS Line Color
input color           InpMSSTextColor   = clrBlack;      // MSS Text Color
input ENUM_LN_STYLE   InpMSSStyle       = LN_SOLID;      // MSS Line Style

//--- structures
struct SLevel
{
   double   price;
   datetime startTime;
   color    clr;
   int      id;
};

struct SSession
{
   int  startMin;
   int  endMin;
   bool valid;
};

//--- globals
SLevel   g_buyLevels[];
SLevel   g_sellLevels[];
int      g_nextId    = 0;
int      g_nextEvtId = 0;
string   g_prefix    = "ICT_";
SSession g_asia, g_london, g_nyam, g_nypm;

//+------------------------------------------------------------------+
string LnName(int id)  { return(g_prefix + "L" + IntegerToString(id)); }
string PlName(int id)  { return(g_prefix + "P" + IntegerToString(id)); }
string EvName()        { g_nextEvtId++; return(g_prefix + "E" + IntegerToString(g_nextEvtId)); }

//+------------------------------------------------------------------+
ENUM_LINE_STYLE ToStyle(ENUM_LN_STYLE s)
{
   if(s == LN_DASHED) return(STYLE_DASH);
   if(s == LN_DOTTED) return(STYLE_DOT);
   return(STYLE_SOLID);
}

//+------------------------------------------------------------------+
int GetFontSize()
{
   if(InpTextSize == TXT_TINY)   return(7);
   if(InpTextSize == TXT_SMALL)  return(8);
   if(InpTextSize == TXT_NORMAL) return(10);
   if(InpTextSize == TXT_LARGE)  return(12);
   if(InpTextSize == TXT_HUGE)   return(14);
   return(10);
}

//+------------------------------------------------------------------+
bool ParseSession(string sess, SSession &out)
{
   out.valid = false;
   string halves[];
   if(StringSplit(sess, '-', halves) != 2)
      return(false);
   string sParts[];
   string eParts[];
   if(StringSplit(halves[0], ':', sParts) != 2)
      return(false);
   if(StringSplit(halves[1], ':', eParts) != 2)
      return(false);
   out.startMin = (int)StringToInteger(sParts[0]) * 60 + (int)StringToInteger(sParts[1]);
   out.endMin   = (int)StringToInteger(eParts[0]) * 60 + (int)StringToInteger(eParts[1]);
   out.valid = true;
   return(true);
}

//+------------------------------------------------------------------+
bool IsInSession(datetime t, const SSession &ses)
{
   if(!ses.valid) return(false);
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int m = dt.hour * 60 + dt.min;
   if(ses.startMin < ses.endMin)
      return(m >= ses.startMin && m < ses.endMin);
   else
      return(m >= ses.startMin || m < ses.endMin);
}

//+------------------------------------------------------------------+
color GetSessionColor(datetime t)
{
   if(IsInSession(t, g_nypm))   return(InpNYPMColor);
   if(IsInSession(t, g_nyam))   return(InpNYAMColor);
   if(IsInSession(t, g_london)) return(InpLondonColor);
   if(IsInSession(t, g_asia))   return(InpAsiaColor);
   return(InpOtherColor);
}

//+------------------------------------------------------------------+
bool IsPivotHigh(const double &h[], int idx, int prd)
{
   double val = h[idx];
   int a, b;
   for(a = 1; a <= prd; a++)
      if(h[idx - a] >= val) return(false);
   for(b = 1; b <= prd; b++)
      if(h[idx + b] >= val) return(false);
   return(true);
}

//+------------------------------------------------------------------+
bool IsPivotLow(const double &l[], int idx, int prd)
{
   double val = l[idx];
   int a, b;
   for(a = 1; a <= prd; a++)
      if(l[idx - a] <= val) return(false);
   for(b = 1; b <= prd; b++)
      if(l[idx + b] <= val) return(false);
   return(true);
}

//+------------------------------------------------------------------+
void MakeLine(int id, datetime t1, datetime t2, double price, color clr, int width)
{
   string nm = LnName(id);
   ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void MakePriceLabel(int id, datetime t, double price, color clr)
{
   if(!InpShowPrice) return;
   string nm = PlName(id);
   ObjectCreate(0, nm, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, nm, OBJPROP_TEXT, " " + DoubleToString(price, _Digits));
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, nm, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void MakeEventLabel(datetime t, double price, string txt, color txtClr, bool isHigh)
{
   string nm = EvName();
   double offset = InpLabelOffset * _Point;
   double mult = 1.0;
   if(isHigh)
      mult = InpFlipText ? -1.0 : 1.0;
   else
      mult = InpFlipText ? 1.0 : -1.0;
   double yPos = price + offset * mult;

   ObjectCreate(0, nm, OBJ_TEXT, 0, t, yPos);
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, GetFontSize());
   ObjectSetString(0, nm, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void ResolveLine(int id, datetime endTime, color clr, ENUM_LINE_STYLE style)
{
   string nm = LnName(id);
   ObjectSetInteger(0, nm, OBJPROP_TIME, 1, endTime);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
   ObjectDelete(0, PlName(id));
}

//+------------------------------------------------------------------+
void AddBuyLevel(double price, datetime startTime, color clr, datetime endTime)
{
   int id = g_nextId;
   g_nextId++;

   SLevel lvl;
   lvl.price     = price;
   lvl.startTime = startTime;
   lvl.clr       = clr;
   lvl.id        = id;

   int sz = ArraySize(g_buyLevels);
   ArrayResize(g_buyLevels, sz + 1);
   g_buyLevels[sz] = lvl;

   MakeLine(id, startTime, endTime, price, clr, InpActiveWidth);
   MakePriceLabel(id, endTime, price, clr);

   while(ArraySize(g_buyLevels) > InpMaxActiveLines)
   {
      ObjectDelete(0, LnName(g_buyLevels[0].id));
      ObjectDelete(0, PlName(g_buyLevels[0].id));
      ArrayRemove(g_buyLevels, 0, 1);
   }
}

//+------------------------------------------------------------------+
void AddSellLevel(double price, datetime startTime, color clr, datetime endTime)
{
   int id = g_nextId;
   g_nextId++;

   SLevel lvl;
   lvl.price     = price;
   lvl.startTime = startTime;
   lvl.clr       = clr;
   lvl.id        = id;

   int sz = ArraySize(g_sellLevels);
   ArrayResize(g_sellLevels, sz + 1);
   g_sellLevels[sz] = lvl;

   MakeLine(id, startTime, endTime, price, clr, InpActiveWidth);
   MakePriceLabel(id, endTime, price, clr);

   while(ArraySize(g_sellLevels) > InpMaxActiveLines)
   {
      ObjectDelete(0, LnName(g_sellLevels[0].id));
      ObjectDelete(0, PlName(g_sellLevels[0].id));
      ArrayRemove(g_sellLevels, 0, 1);
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!ParseSession(InpAsiaSession,   g_asia))   { Print("ICT: bad Asia session");   return(INIT_FAILED); }
   if(!ParseSession(InpLondonSession, g_london)) { Print("ICT: bad London session"); return(INIT_FAILED); }
   if(!ParseSession(InpNYAMSession,   g_nyam))   { Print("ICT: bad NY AM session");  return(INIT_FAILED); }
   if(!ParseSession(InpNYPMSession,   g_nypm))   { Print("ICT: bad NY PM session");  return(INIT_FAILED); }

   IndicatorSetString(INDICATOR_SHORTNAME, "ICT Liquidity");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
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
   int prd = InpPivotPeriod;
   int minBar = 2 * prd;
   if(rates_total <= minBar + 1)
      return(0);

   int barLimit = rates_total - 2;
   int start = 0;

   if(prev_calculated == 0)
   {
      ObjectsDeleteAll(0, g_prefix);
      ArrayResize(g_buyLevels, 0);
      ArrayResize(g_sellLevels, 0);
      g_nextId    = 0;
      g_nextEvtId = 0;
      start = MathMax(minBar, rates_total - InpMaxBars);
   }
   else
   {
      start = MathMax(prev_calculated - 1, minBar);
   }

   datetime futureTime = time[rates_total - 1] + InpLineExtension * PeriodSeconds();
   int i = 0;
   int j = 0;
   int k = 0;

   for(i = start; i <= barLimit; i++)
   {
      int pivotIdx = i - prd;
      if(pivotIdx < prd)
         continue;

      //--- Pivot Low -> Buy Level (support)
      if(IsPivotLow(low, pivotIdx, prd))
      {
         double pl = low[pivotIdx];
         bool broken = false;
         for(k = pivotIdx + 1; k <= i; k++)
         {
            if(low[k] < pl) { broken = true; break; }
         }
         if(!broken)
            AddBuyLevel(pl, time[pivotIdx], GetSessionColor(time[pivotIdx]), futureTime);
      }

      //--- Pivot High -> Sell Level (resistance)
      if(IsPivotHigh(high, pivotIdx, prd))
      {
         double ph = high[pivotIdx];
         bool broken = false;
         for(k = pivotIdx + 1; k <= i; k++)
         {
            if(high[k] > ph) { broken = true; break; }
         }
         if(!broken)
            AddSellLevel(ph, time[pivotIdx], GetSessionColor(time[pivotIdx]), futureTime);
      }

      //--- Check Buy Level interactions ---
      for(j = ArraySize(g_buyLevels) - 1; j >= 0; j--)
      {
         double lvl = g_buyLevels[j].price;
         long tMid = ((long)g_buyLevels[j].startTime + (long)time[i]) / 2;
         datetime midTime = (datetime)tMid;

         if(close[i] > lvl && close[i - 1] < lvl)
         {
            ResolveLine(g_buyLevels[j].id, time[i], InpSFPLineColor, ToStyle(InpSFPStyle));
            if(InpShowSFP)
               MakeEventLabel(midTime, lvl, "SFP", InpSFPTextColor, false);
            ArrayRemove(g_buyLevels, j, 1);
         }
         else if(close[i] < lvl && close[i - 1] < lvl && close[i] < close[i - 1])
         {
            ResolveLine(g_buyLevels[j].id, time[i], InpMSSLineColor, ToStyle(InpMSSStyle));
            if(InpShowMSS)
               MakeEventLabel(midTime, lvl, "MSS", InpMSSTextColor, false);
            ArrayRemove(g_buyLevels, j, 1);
         }
         else if(low[i] <= lvl && close[i] > lvl)
         {
            ResolveLine(g_buyLevels[j].id, time[i], InpXLineColor, ToStyle(InpXStyle));
            if(InpShowX)
               MakeEventLabel(midTime, lvl, "X", InpXTextColor, false);
            ArrayRemove(g_buyLevels, j, 1);
         }
      }

      //--- Check Sell Level interactions ---
      for(j = ArraySize(g_sellLevels) - 1; j >= 0; j--)
      {
         double lvl = g_sellLevels[j].price;
         long tMid = ((long)g_sellLevels[j].startTime + (long)time[i]) / 2;
         datetime midTime = (datetime)tMid;

         if(close[i] < lvl && close[i - 1] > lvl)
         {
            ResolveLine(g_sellLevels[j].id, time[i], InpSFPLineColor, ToStyle(InpSFPStyle));
            if(InpShowSFP)
               MakeEventLabel(midTime, lvl, "SFP", InpSFPTextColor, true);
            ArrayRemove(g_sellLevels, j, 1);
         }
         else if(close[i] > lvl && close[i - 1] > lvl && close[i] > close[i - 1])
         {
            ResolveLine(g_sellLevels[j].id, time[i], InpMSSLineColor, ToStyle(InpMSSStyle));
            if(InpShowMSS)
               MakeEventLabel(midTime, lvl, "MSS", InpMSSTextColor, true);
            ArrayRemove(g_sellLevels, j, 1);
         }
         else if(high[i] >= lvl && close[i] < lvl)
         {
            ResolveLine(g_sellLevels[j].id, time[i], InpXLineColor, ToStyle(InpXStyle));
            if(InpShowX)
               MakeEventLabel(midTime, lvl, "X", InpXTextColor, true);
            ArrayRemove(g_sellLevels, j, 1);
         }
      }
   }

   //--- Update extensions for active lines ---
   int bCnt = ArraySize(g_buyLevels);
   for(j = 0; j < bCnt; j++)
   {
      ObjectSetInteger(0, LnName(g_buyLevels[j].id), OBJPROP_TIME, 1, futureTime);
      if(ObjectFind(0, PlName(g_buyLevels[j].id)) >= 0)
         ObjectSetInteger(0, PlName(g_buyLevels[j].id), OBJPROP_TIME, 0, futureTime);
   }

   int sCnt = ArraySize(g_sellLevels);
   for(j = 0; j < sCnt; j++)
   {
      ObjectSetInteger(0, LnName(g_sellLevels[j].id), OBJPROP_TIME, 1, futureTime);
      if(ObjectFind(0, PlName(g_sellLevels[j].id)) >= 0)
         ObjectSetInteger(0, PlName(g_sellLevels[j].id), OBJPROP_TIME, 0, futureTime);
   }

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
