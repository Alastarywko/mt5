//+------------------------------------------------------------------+
//|                                                     metka_ea.mq5 |
//|           Советник: торгует по сигналам индикатора metka           |
//|           Берёт индикатор с графика, 1 позиция на сигнал          |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "3.00"
#property description "EA торгует по стрелкам индикатора Metka (с графіка)"

#include <Trade\Trade.mqh>

//═══════════════════════════════════════════════════════════════
// ОСНОВНІ ПАРАМЕТРИ
//═══════════════════════════════════════════════════════════════
input double InpLotSize       = 1.0;    // Лот
input int    InpTP            = 100;    // Take Profit (пунктів)
input int    InpSL            = 1450;   // Stop Loss (пунктів)
input ulong  InpMagic         = 202612; // Magic number
input bool   InpTradeStrongBuy  = false;  // Торгувати сильні BUY
input bool   InpTradeStrongSell = true;   // Торгувати сильні SELL

//═══════════════════════════════════════════════════════════════
// КОНТР-ОРДЕР
//═══════════════════════════════════════════════════════════════
input bool   InpCounter       = false;  // Контр-ордер: вкл/викл
input double InpCounterLot    = 1.0;    // Контр-ордер: лот
input int    InpCounterTP     = 100;    // Контр-ордер: Take Profit (пунктів)
input int    InpCounterSL     = 1450;   // Контр-ордер: Stop Loss (пунктів)

//═══════════════════════════════════════════════════════════════
// ВІДКЛАДЕНИЙ ОРДЕР
//═══════════════════════════════════════════════════════════════
input bool   InpPending       = false;  // Відкладений ордер: вкл/викл
input int    InpPendingOffset = 30;     // Відкладений: відступ (пунктів)

//═══════════════════════════════════════════════════════════════
// ТРЕЙЛІНГ СТОП
//═══════════════════════════════════════════════════════════════
input bool   InpTrailing      = false;  // Трейлінг стоп: вкл/викл
input int    InpTrailActivate = 100;    // Трейлінг: активація (пунктів прибутку)
input int    InpTrailStep     = 10;     // Трейлінг: розмір (пунктів)

CTrade   trade;
int      hIndicator;
datetime lastSignalTime;

//+------------------------------------------------------------------+
int FindChartIndicator()
{
   int total = ChartIndicatorsTotal(0, 0);
   for(int i = 0; i < total; i++)
   {
      string name = ChartIndicatorName(0, 0, i);
      if(StringFind(name, "Metka") >= 0)
         return ChartIndicatorGet(0, 0, name);
   }
   return INVALID_HANDLE;
}

//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   uint fill = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fill & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

datetime FindLastExistingSignalTime()
{
   for(int s = 1; s < 500; s++)
   {
      double buy[], sell[], sbuy[], ssell[];
      if(CopyBuffer(hIndicator, 0, s, 1, buy)   <= 0) continue;
      if(CopyBuffer(hIndicator, 1, s, 1, sell)  <= 0) continue;
      if(CopyBuffer(hIndicator, 2, s, 1, sbuy)  <= 0) continue;
      if(CopyBuffer(hIndicator, 3, s, 1, ssell) <= 0) continue;

      if(buy[0] != EMPTY_VALUE || sell[0] != EMPTY_VALUE ||
         sbuy[0] != EMPTY_VALUE || ssell[0] != EMPTY_VALUE)
         return iTime(_Symbol, _Period, s);
   }
   return TimeCurrent();
}

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(DetectFilling());

   hIndicator = FindChartIndicator();

   if(hIndicator == INVALID_HANDLE)
   {
      Print("metka_ea: індикатор Metka не знайдено на графіку! Додайте metka на графік.");
      return(INIT_FAILED);
   }

   Print("metka_ea: індикатор знайдено, SL=", InpSL, " TP=", InpTP,
         " pending=", InpPending, " trailing=", InpTrailing);
   datetime savedTime = (datetime)GlobalVariableGet("MetkaEA_LastSigTime");
   datetime foundTime = FindLastExistingSignalTime();
   lastSignalTime = MathMax(savedTime, foundTime);
   Print("metka_ea: skip existing signals before ", lastSignalTime,
         " (saved=", savedTime, " found=", foundTime, ")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(InpTrailing)
      ManageTrailing();

   if(!GlobalVariableCheck("MetkaSignal_Time"))
      return;

   datetime sigTime = (datetime)GlobalVariableGet("MetkaSignal_Time");
   int      sigDir  = (int)GlobalVariableGet("MetkaSignal_Dir");

   if(sigTime <= lastSignalTime)
      return;

   // sigDir: 1=buy, 2=strong buy, -1=sell, -2=strong sell
   bool isBuy       = (sigDir == 1);
   bool isStrongBuy = (sigDir == 2);
   bool isSell       = (sigDir == -1);
   bool isStrongSell = (sigDir == -2);

   bool tradeBuy  = isBuy || (isStrongBuy && InpTradeStrongBuy);
   bool tradeSell = isSell || (isStrongSell && InpTradeStrongSell);

   if(!tradeBuy && !tradeSell)
   {
      lastSignalTime = sigTime;
      GlobalVariableSet("MetkaEA_LastSigTime", (double)lastSignalTime);
      return;
   }

   lastSignalTime = sigTime;
   GlobalVariableSet("MetkaEA_LastSigTime", (double)lastSignalTime);

   DeletePendingOrders();

   if(tradeBuy)
   {
      OpenBuy();
      if(InpCounter)
         OpenCounterSell();
   }
   else
   {
      OpenSell();
      if(InpCounter)
         OpenCounterBuy();
   }
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(InpPending)
   {
      double price = NormalizeDouble(ask - InpPendingOffset * _Point, _Digits);
      double sl = InpSL > 0 ? NormalizeDouble(price - InpSL * _Point, _Digits) : 0;
      double tp = InpTP > 0 ? NormalizeDouble(price + InpTP * _Point, _Digits) : 0;

      if(!trade.BuyLimit(InpLotSize, price, _Symbol, sl, tp, 0, 0, "Metka BUY Limit"))
         PrintFormat("BUY LIMIT FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
      else
         PrintFormat("metka_ea: BUY LIMIT @ %.2f SL=%.2f TP=%.2f", price, sl, tp);
   }
   else
   {
      double sl = InpSL > 0 ? NormalizeDouble(ask - InpSL * _Point, _Digits) : 0;
      double tp = InpTP > 0 ? NormalizeDouble(ask + InpTP * _Point, _Digits) : 0;

      if(!trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "Metka BUY"))
         PrintFormat("BUY FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
      else
         PrintFormat("metka_ea: BUY @ %.2f SL=%.2f TP=%.2f", ask, sl, tp);
   }
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(InpPending)
   {
      double price = NormalizeDouble(bid + InpPendingOffset * _Point, _Digits);
      double sl = InpSL > 0 ? NormalizeDouble(price + InpSL * _Point, _Digits) : 0;
      double tp = InpTP > 0 ? NormalizeDouble(price - InpTP * _Point, _Digits) : 0;

      if(!trade.SellLimit(InpLotSize, price, _Symbol, sl, tp, 0, 0, "Metka SELL Limit"))
         PrintFormat("SELL LIMIT FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
      else
         PrintFormat("metka_ea: SELL LIMIT @ %.2f SL=%.2f TP=%.2f", price, sl, tp);
   }
   else
   {
      double sl = InpSL > 0 ? NormalizeDouble(bid + InpSL * _Point, _Digits) : 0;
      double tp = InpTP > 0 ? NormalizeDouble(bid - InpTP * _Point, _Digits) : 0;

      if(!trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "Metka SELL"))
         PrintFormat("SELL FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
      else
         PrintFormat("metka_ea: SELL @ %.2f SL=%.2f TP=%.2f", bid, sl, tp);
   }
}

//+------------------------------------------------------------------+
void OpenCounterBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = InpCounterSL > 0 ? NormalizeDouble(ask - InpCounterSL * _Point, _Digits) : 0;
   double tp = InpCounterTP > 0 ? NormalizeDouble(ask + InpCounterTP * _Point, _Digits) : 0;

   if(!trade.Buy(InpCounterLot, _Symbol, ask, sl, tp, "Metka COUNTER BUY"))
      PrintFormat("COUNTER BUY FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
   else
      PrintFormat("metka_ea: COUNTER BUY @ %.2f SL=%.2f TP=%.2f", ask, sl, tp);
}

//+------------------------------------------------------------------+
void OpenCounterSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = InpCounterSL > 0 ? NormalizeDouble(bid + InpCounterSL * _Point, _Digits) : 0;
   double tp = InpCounterTP > 0 ? NormalizeDouble(bid - InpCounterTP * _Point, _Digits) : 0;

   if(!trade.Sell(InpCounterLot, _Symbol, bid, sl, tp, "Metka COUNTER SELL"))
      PrintFormat("COUNTER SELL FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
   else
      PrintFormat("metka_ea: COUNTER SELL @ %.2f SL=%.2f TP=%.2f", bid, sl, tp);
}

//+------------------------------------------------------------------+
void ManageTrailing()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type     = PositionGetInteger(POSITION_TYPE);
      double openPr   = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    = PositionGetDouble(POSITION_SL);
      double curTP    = PositionGetDouble(POSITION_TP);
      ulong  ticket   = PositionGetInteger(POSITION_TICKET);

      double activateDist = InpTrailActivate * _Point;
      double trailDist    = InpTrailStep * _Point;

      if(type == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = bid - openPr;

         if(profit >= activateDist)
         {
            double newSL = NormalizeDouble(bid - trailDist, _Digits);
            if(newSL > curSL + _Point)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit = openPr - ask;

         if(profit >= activateDist)
         {
            double newSL = NormalizeDouble(ask + trailDist, _Digits);
            if(curSL < _Point || newSL < curSL - _Point)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      trade.OrderDelete(ticket);
   }
}
//+------------------------------------------------------------------+
