//+------------------------------------------------------------------+
//|                                                 ShotCatcher.mq5  |
//|           Двигает Buy Stop и Sell Stop за ценой                    |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "2.00"
#property description "Trailing Buy Stop + Sell Stop orders"

#include <Trade\Trade.mqh>

input double InpLotSize    = 5.0;    // Лот
input int    InpOffset     = 200;    // Відступ від ціни (пунктів)
input int    InpSL         = 70;     // Stop Loss (пунктів)
input int    InpTP         = 0;      // Take Profit (пунктів, 0 = без)
input bool   InpTracking   = true;   // Слідкування за ціною: вкл/викл
input int    InpInterval   = 3;      // Інтервал оновлення (секунд)
input bool   InpTrailing   = false;  // Трейлінг стоп: вкл/викл
input int    InpTrailAct   = 100;    // Трейлінг: активація (пунктів прибутку)
input int    InpTrailStep  = 5;      // Трейлінг: крок (пунктів)
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
   EventSetTimer(InpInterval);
   Print("ShotCatcher: started, offset=", InpOffset, " SL=", InpSL, " lot=", InpLotSize, " interval=", InpInterval, "s");
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

   // check for open positions
   bool hasBuyPos = false, hasSellPos = false;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      if(PositionGetSymbol(p) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)  hasBuyPos = true;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) hasSellPos = true;
   }

   bool buyExists  = (g_buyTicket > 0 && OrderSelect(g_buyTicket) && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP);
   bool sellExists = (g_sellTicket > 0 && OrderSelect(g_sellTicket) && OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP);

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

   // Buy Stop
   if(hasBuyPos)
   {
      if(buyExists) { trade.OrderDelete(g_buyTicket); g_buyTicket = 0; }
   }
   else if(g_buyTicket > 0 && OrderSelect(g_buyTicket))
   {
      if(InpTracking)
         trade.OrderModify(g_buyTicket, buyPrice, buySL, buyTP, 0, 0);
   }
   else if(!hasBuyPos)
   {
      if(trade.BuyStop(InpLotSize, buyPrice, _Symbol, buySL, buyTP, 0, 0, "Shot BuyStop"))
         g_buyTicket = trade.ResultOrder();
   }

   // Sell Stop
   if(hasSellPos)
   {
      if(sellExists) { trade.OrderDelete(g_sellTicket); g_sellTicket = 0; }
   }
   else if(g_sellTicket > 0 && OrderSelect(g_sellTicket))
   {
      if(InpTracking)
         trade.OrderModify(g_sellTicket, sellPrice, sellSL, sellTP, 0, 0);
   }
   else if(!hasSellPos)
   {
      if(trade.SellStop(InpLotSize, sellPrice, _Symbol, sellSL, sellTP, 0, 0, "Shot SellStop"))
         g_sellTicket = trade.ResultOrder();
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(InpTrailing)
      ManageTrailing();
}

//+------------------------------------------------------------------+
void ManageTrailing()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type   = PositionGetInteger(POSITION_TYPE);
      double openPr = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      ulong  ticket = PositionGetInteger(POSITION_TICKET);
      double actDist = InpTrailAct * _Point;
      double step    = InpTrailStep * _Point;

      if(type == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - openPr >= actDist)
         {
            double newSL = NormalizeDouble(bid - step, _Digits);
            if(newSL > curSL + _Point)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(openPr - ask >= actDist)
         {
            double newSL = NormalizeDouble(ask + step, _Digits);
            if(curSL < _Point || newSL < curSL - _Point)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
   }
}
//+------------------------------------------------------------------+
