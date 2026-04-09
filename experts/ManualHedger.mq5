//+------------------------------------------------------------------+
//|                                                ManualHedger.mq5  |
//|           Двигает Buy Stop и Sell Stop за ценой каждые 5 сек      |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "2.00"
#property description "Trailing Buy Stop + Sell Stop orders"

#include <Trade\Trade.mqh>

input double InpLotSize    = 5.0;    // Лот
input int    InpOffset     = 200;    // Відступ від ціни (пунктів)
input int    InpSL         = 70;     // Stop Loss (пунктів)
input int    InpTP         = 0;      // Take Profit (пунктів, 0 = без)
input ulong  InpMagic      = 303030; // Magic number

CTrade trade;
ulong  g_buyTicket  = 0;
ulong  g_sellTicket = 0;

//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   uint fill = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fill & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(DetectFilling());
   EventSetTimer(5);
   Print("ManualHedger: started, offset=", InpOffset, " SL=", InpSL, " lot=", InpLotSize);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = _Point;
   int digits = _Digits;

   double buyPrice  = NormalizeDouble(ask + InpOffset * point, digits);
   double sellPrice = NormalizeDouble(bid - InpOffset * point, digits);

   double buySL  = InpSL > 0 ? NormalizeDouble(buyPrice - InpSL * point, digits) : 0;
   double sellSL = InpSL > 0 ? NormalizeDouble(sellPrice + InpSL * point, digits) : 0;
   double buyTP  = InpTP > 0 ? NormalizeDouble(buyPrice + InpTP * point, digits) : 0;
   double sellTP = InpTP > 0 ? NormalizeDouble(sellPrice - InpTP * point, digits) : 0;

   bool buyExists  = (g_buyTicket > 0 && OrderSelect(g_buyTicket) && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP);
   bool sellExists = (g_sellTicket > 0 && OrderSelect(g_sellTicket) && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP);

   // if one triggered (disappeared), delete the other and reset both
   if(!buyExists && g_buyTicket > 0)
   {
      if(sellExists) trade.OrderDelete(g_sellTicket);
      g_buyTicket = 0;
      g_sellTicket = 0;
   }
   if(!sellExists && g_sellTicket > 0)
   {
      if(g_buyTicket > 0 && OrderSelect(g_buyTicket)) trade.OrderDelete(g_buyTicket);
      g_buyTicket = 0;
      g_sellTicket = 0;
   }

   // place or move Buy Stop
   if(g_buyTicket > 0 && OrderSelect(g_buyTicket))
      trade.OrderModify(g_buyTicket, buyPrice, buySL, buyTP, 0, 0);
   else
   {
      if(trade.BuyStop(InpLotSize, buyPrice, _Symbol, buySL, buyTP, 0, 0, "Hedger BuyStop"))
         g_buyTicket = trade.ResultOrder();
   }

   // place or move Sell Stop
   if(g_sellTicket > 0 && OrderSelect(g_sellTicket))
      trade.OrderModify(g_sellTicket, sellPrice, sellSL, sellTP, 0, 0);
   else
   {
      if(trade.SellStop(InpLotSize, sellPrice, _Symbol, sellSL, sellTP, 0, 0, "Hedger SellStop"))
         g_sellTicket = trade.ResultOrder();
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
}
//+------------------------------------------------------------------+
