//+------------------------------------------------------------------+
//|                                                       setka.mq5 |
//|   Сітка: ордер кожні N сек. Закриття сесії: сумарний профіт ≥ формула |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "1.04"
#property description "Інтервал (сек), лот, max ордерів, опційне авто-close сесії за прибутком"

#include <Trade\Trade.mqh>

enum ENUM_SETKA_DIR
{
   SETKA_BUY  = 0,  // BUY
   SETKA_SELL = 1   // SELL
};

input double          InpInitialLot      = 1.0;   // Початковий лот
input ENUM_SETKA_DIR  InpDirection       = SETKA_BUY;  // Напрямок
input int             InpMaxOrders       = 0;    // Макс. ордерів (0 = без обмеження)
input int             InpOpenIntervalSec = 60;   // Інтервал відкриття (секунд)
input double          InpProfitLotK      = 0.1;  // Поріг: множник до суми лотів (перший)
input double          InpProfitCloseK     = 2.0;  // Поріг: додатковий множник (другий)
input bool            InpAutoClose        = false; // Автозакриття сесії за прибутком (умова вище)
input ulong           InpMagic            = 202620;     // Magic number

CTrade trade;
ulong  g_session_tickets[];

//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   uint fill = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fill & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
bool SetkaDirectionOk(const long pos_type)
{
   if(InpDirection == SETKA_BUY && pos_type == POSITION_TYPE_BUY)  return true;
   if(InpDirection == SETKA_SELL && pos_type == POSITION_TYPE_SELL) return true;
   return false;
}

//+------------------------------------------------------------------+
void CollectSetkaTickets(ulong &tickets[])
{
   ArrayResize(tickets, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(!SetkaDirectionOk(type)) continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = PositionGetTicket(i);
   }
}

//+------------------------------------------------------------------+
bool ULongArrayContains(const ulong &arr[], const ulong v)
{
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == v) return true;
   return false;
}

//+------------------------------------------------------------------+
void RegisterNewSessionTickets(const ulong &before[], const ulong &after[])
{
   for(int i = 0; i < ArraySize(after); i++)
   {
      if(ULongArrayContains(before, after[i])) continue;
      if(ULongArrayContains(g_session_tickets, after[i])) continue;
      int n = ArraySize(g_session_tickets);
      ArrayResize(g_session_tickets, n + 1);
      g_session_tickets[n] = after[i];
   }
}

//+------------------------------------------------------------------+
void PruneSessionTickets()
{
   for(int i = ArraySize(g_session_tickets) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(g_session_tickets[i]))
      {
         int last = ArraySize(g_session_tickets) - 1;
         g_session_tickets[i] = g_session_tickets[last];
         ArrayResize(g_session_tickets, last);
      }
   }
}

//+------------------------------------------------------------------+
void CloseAllSessionPositions()
{
   for(int i = ArraySize(g_session_tickets) - 1; i >= 0; i--)
   {
      ulong t = g_session_tickets[i];
      if(!PositionSelectByTicket(t)) continue;
      if(!trade.PositionClose(t))
         PrintFormat("setka: PositionClose fail ticket=%s %d %s", IntegerToString((long)t),
                     trade.ResultRetcode(), trade.ResultComment());
   }
   ArrayResize(g_session_tickets, 0);
   Print("setka: усі позиції сесії закрито (ціль по прибутку)");
}

//+------------------------------------------------------------------+
void CheckSessionProfitAndClose()
{
   if(!InpAutoClose)
      return;

   PruneSessionTickets();
   int n = ArraySize(g_session_tickets);
   if(n == 0) return;

   double sum_lots   = 0;
   double sum_profit = 0;

   for(int i = 0; i < n; i++)
   {
      ulong t = g_session_tickets[i];
      if(!PositionSelectByTicket(t)) continue;
      sum_lots   += PositionGetDouble(POSITION_VOLUME);
      sum_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   if(sum_lots <= 0) return;

   double target = sum_lots * InpProfitLotK * InpProfitCloseK;
   if(sum_profit >= target)
   {
      PrintFormat("setka: close session: profit=%.2f ≥ target=%.2f (lots sum=%.2f, k1=%.4f k2=%.4f)",
                  sum_profit, target, sum_lots, InpProfitLotK, InpProfitCloseK);
      CloseAllSessionPositions();
   }
}

//+------------------------------------------------------------------+
int CountPositionsForSetka()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(SetkaDirectionOk(type)) c++;
   }
   return c;
}

//+------------------------------------------------------------------+
double LotForNextOrder()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   int    n    = CountPositionsForSetka();

   double vol = InpInitialLot + (double)n * step;
   vol = MathMax(vol, vmin);
   vol = MathMin(vol, vmax);
   vol = MathFloor(vol / step) * step;
   if(vol < vmin) vol = vmin;
   return NormalizeDouble(vol, 2);
}

//+------------------------------------------------------------------+
void OpenSetkaOrder()
{
   int openCount = CountPositionsForSetka();
   if(InpMaxOrders > 0 && openCount >= InpMaxOrders)
      return;

   ulong before[];
   CollectSetkaTickets(before);

   double vol = LotForNextOrder();
   double sl  = 0.0;
   double tp  = 0.0;

   bool ok = false;
   if(InpDirection == SETKA_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      ok = trade.Buy(vol, _Symbol, ask, sl, tp, "setka");
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ok = trade.Sell(vol, _Symbol, bid, sl, tp, "setka");
   }

   if(!ok)
      PrintFormat("setka: FAIL %d %s lot=%.2f", trade.ResultRetcode(), trade.ResultComment(), vol);
   else
   {
      ulong after[];
      CollectSetkaTickets(after);
      RegisterNewSessionTickets(before, after);
      PrintFormat("setka: OK lot=%.2f (#%d) dir=%s сесія=%d",
                  vol, CountPositionsForSetka(),
                  InpDirection == SETKA_BUY ? "BUY" : "SELL",
                  ArraySize(g_session_tickets));
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(DetectFilling());

   ArrayResize(g_session_tickets, 0);

   int sec = InpOpenIntervalSec < 1 ? 1 : InpOpenIntervalSec;
   if(!EventSetTimer(sec))
   {
      Print("setka: EventSetTimer failed");
      return INIT_FAILED;
   }
   Print("setka: таймер ", sec, " с, lot0=", InpInitialLot,
         ", dir=", (InpDirection == SETKA_BUY ? "BUY" : "SELL"),
         ", max=", (InpMaxOrders > 0 ? IntegerToString(InpMaxOrders) : "∞"),
         ", автозакриття=", (InpAutoClose ? "увімкн." : "вимкн."),
         (InpAutoClose ? ", close if profit ≥ sum(lots)×" + DoubleToString(InpProfitLotK, 4) + "×" + DoubleToString(InpProfitCloseK, 4) : ""));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   CheckSessionProfitAndClose();
   OpenSetkaOrder();
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckSessionProfitAndClose();
}

//+------------------------------------------------------------------+
