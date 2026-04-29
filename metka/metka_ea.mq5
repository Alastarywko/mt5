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
input int    InpSL            = 7000;   // Stop Loss (пунктів)
input bool   InpDirectBuy     = true;   // Прямий BUY (фолс = відкривати SELL на BUY сигнал)
input bool   InpDirectSell    = true;   // Прямий SELL (фолс = відкривати BUY на SELL сигнал)

input ulong  InpMagic         = 202612; // Magic number
input bool   InpTradeBuy      = true;   // Торгувати BUY сигнали
input bool   InpTradeSell     = true;   // Торгувати SELL сигнали
input bool   InpTradeStrongBuy  = true;  // Торгувати сильні BUY
input bool   InpTradeStrongSell = true;   // Торгувати сильні SELL


//═══════════════════════════════════════════════════════════════
// КОНТР-ОРДЕР
//═══════════════════════════════════════════════════════════════
input bool   InpCounter       = false;  // Контр-ордер: вкл/викл
input double InpCounterLot    = 1.0;    // Контр-ордер: лот
input int    InpCounterTP     = 100;    // Контр-ордер: Take Profit (пунктів)
input int    InpCounterSL     = 1450;   // Контр-ордер: Stop Loss (пунктів)
input int    InpCounterDelay  = 0;      // Контр-ордер: відступ проти позиції (пунктів, 0=одразу)

//═══════════════════════════════════════════════════════════════
// ВІДКЛАДЕНИЙ ОРДЕР
//═══════════════════════════════════════════════════════════════
bool   InpPending       = false;  // Відкладений ордер: вкл/викл
int    InpPendingOffset = 30;     // Відкладений: відступ (пунктів)

//═══════════════════════════════════════════════════════════════
// ТРЕЙЛІНГ СТОП
//═══════════════════════════════════════════════════════════════
input bool   InpTrailing      = false;  // Трейлінг стоп: вкл/викл
input int    InpTrailActivate = 100;    // Трейлінг: активація (пунктів прибутку)
input int    InpTrailStep     = 10;     // Трейлінг: розмір (пунктів)

//═══════════════════════════════════════════════════════════════
// МАРТИНГЕЙЛ
//═══════════════════════════════════════════════════════════════
input bool   InpMartingale    = false;  // Мартингейл: вкл/викл
input double InpMartingaleMax = 0;      // Мартингейл: макс лот (0 = без обмежень)

CTrade   trade;
int      hIndicator;
datetime lastSignalTime;
int      g_counterDir    = 0;    // pending counter: 1=buy, -1=sell
double   g_counterEntry  = 0;    // entry price of main position
bool     g_counterPlaced = false;
double   g_currentLot    = 1.0;  // поточний лот (змінюється мартингейлом)

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
   // no existing arrow: return time of last closed bar (NOT TimeCurrent),
   // so a fresh arrow forming on the next bar close is NOT skipped due to
   // attach happening mid-bar.
   datetime t1 = iTime(_Symbol, _Period, 1);
   if(t1 > 0) return t1;
   return 0;
}

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(DetectFilling());

   hIndicator = FindChartIndicator();

   if(hIndicator == INVALID_HANDLE)
      Print("metka_ea: індикатор Metka не знайдено, чекаємо...");
   else
      Print("metka_ea: індикатор знайдено, SL=", InpSL, " TP=", InpTP,
            " pending=", InpPending, " trailing=", InpTrailing);
   datetime savedTime = (datetime)GlobalVariableGet("MetkaEA_LastSigTime");
   datetime foundTime = FindLastExistingSignalTime();
   lastSignalTime = MathMax(savedTime, foundTime);
   Print("metka_ea: skip existing signals before ", lastSignalTime,
         " (saved=", savedTime, " found=", foundTime, ")");

   // Мартингейл: відновлюємо поточний лот після перезапуску
   if(InpMartingale && GlobalVariableCheck("MetkaEA_MartLot"))
   {
      g_currentLot = GlobalVariableGet("MetkaEA_MartLot");
      if(g_currentLot < InpLotSize) g_currentLot = InpLotSize;
      PrintFormat("metka_ea: Martingale RESTORED lot=%.2f", g_currentLot);
   }
   else
      g_currentLot = InpLotSize;

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

   if(hIndicator == INVALID_HANDLE)
   {
      hIndicator = FindChartIndicator();
      if(hIndicator != INVALID_HANDLE)
         Print("metka_ea: індикатор знайдено");
      return;
   }

   // delayed counter order
   if(InpCounter && InpCounterDelay > 0 && g_counterDir != 0 && !g_counterPlaced)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double dist = 0;
      if(g_counterDir == -1) // counter sell after buy → check if price dropped
         dist = g_counterEntry - bid;
      else                   // counter buy after sell → check if price rose
         dist = ask - g_counterEntry;

      if(dist >= InpCounterDelay * _Point)
      {
         if(g_counterDir == -1) OpenCounterSell();
         else                   OpenCounterBuy();
         g_counterPlaced = true;
         g_counterDir = 0;
      }
   }

   if(!GlobalVariableCheck("MetkaSignal_Time"))
      return;

   datetime sigTime = (datetime)GlobalVariableGet("MetkaSignal_Time");
   int      sigDir  = (int)GlobalVariableGet("MetkaSignal_Dir");

   if(sigTime == 0)
      return;
   if(sigTime <= lastSignalTime)
      return;

   // sigDir: 1=buy, 2=strong buy, -1=sell, -2=strong sell
   bool isBuy       = (sigDir == 1);
   bool isStrongBuy = (sigDir == 2);
   bool isSell       = (sigDir == -1);
   bool isStrongSell = (sigDir == -2);

   // RACE GUARD: if Time looks new but Dir is 0/invalid, indicator is mid-write.
   // Do NOT update lastSignalTime; just wait for next tick when both are coherent.
   if(sigDir == 0 || (!isBuy && !isStrongBuy && !isSell && !isStrongSell))
   {
      PrintFormat("metka_ea: race detected sigTime=%s dir=%d - waiting next tick",
                  TimeToString(sigTime), sigDir);
      return;
   }

   // determine if signal passes strong filter
   bool sigIsBuy  = isBuy || (isStrongBuy  && InpTradeStrongBuy);
   bool sigIsSell = isSell || (isStrongSell && InpTradeStrongSell);

   if(!sigIsBuy && !sigIsSell)
   {
      PrintFormat("metka_ea: SKIP (strong filter) sigTime=%s dir=%d StrongBuy=%d StrongSell=%d",
                  TimeToString(sigTime), sigDir, InpTradeStrongBuy, InpTradeStrongSell);
      lastSignalTime = sigTime;
      GlobalVariableSet("MetkaEA_LastSigTime", (double)lastSignalTime);
      return;
   }

   // determine actual trade direction
   // InpDirectBuy=false → on BUY signal open SELL; InpDirectSell=false → on SELL signal open BUY
   bool doOpenBuy  = false;
   bool doOpenSell = false;

   if(sigIsBuy)
   {
      if(InpDirectBuy)  doOpenBuy  = InpTradeBuy;
      else              doOpenSell = InpTradeSell;
   }
   if(sigIsSell)
   {
      if(InpDirectSell) doOpenSell = InpTradeSell;
      else              doOpenBuy  = InpTradeBuy;
   }

   if(!doOpenBuy && !doOpenSell)
   {
      PrintFormat("metka_ea: SKIP (trade flags) sigTime=%s dir=%d TradeBuy=%d TradeSell=%d DirectBuy=%d DirectSell=%d",
                  TimeToString(sigTime), sigDir,
                  InpTradeBuy, InpTradeSell, InpDirectBuy, InpDirectSell);
      lastSignalTime = sigTime;
      GlobalVariableSet("MetkaEA_LastSigTime", (double)lastSignalTime);
      return;
   }

   lastSignalTime = sigTime;
   GlobalVariableSet("MetkaEA_LastSigTime", (double)lastSignalTime);

   PrintFormat("metka_ea: SIGNAL sigTime=%s dir=%d openBuy=%d openSell=%d",
               TimeToString(sigTime), sigDir, doOpenBuy, doOpenSell);

   DeletePendingOrders();

   if(doOpenBuy)
   {
      OpenBuy();
      if(InpCounter)
      {
         if(InpCounterDelay == 0)
            OpenCounterSell();
         else
         {
            g_counterDir = -1;
            g_counterEntry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            g_counterPlaced = false;
         }
      }
   }
   if(doOpenSell)
   {
      OpenSell();
      if(InpCounter)
      {
         if(InpCounterDelay == 0)
            OpenCounterBuy();
         else
         {
            g_counterDir = 1;
            g_counterEntry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            g_counterPlaced = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lot = InpMartingale ? g_currentLot : InpLotSize;

   if(InpPending)
   {
      double price = NormalizeDouble(ask - InpPendingOffset * _Point, _Digits);
      double sl = InpSL > 0 ? NormalizeDouble(price - InpSL * _Point, _Digits) : 0;
      double tp = InpTP > 0 ? NormalizeDouble(price + InpTP * _Point, _Digits) : 0;

      if(!trade.BuyLimit(lot, price, _Symbol, sl, tp, 0, 0, "Metka BUY Limit"))
         PrintFormat("BUY LIMIT FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
      else
         PrintFormat("metka_ea: BUY LIMIT @ %.2f SL=%.2f TP=%.2f lot=%.2f", price, sl, tp, lot);
   }
   else
   {
      double sl = InpSL > 0 ? NormalizeDouble(ask - InpSL * _Point, _Digits) : 0;
      double tp = InpTP > 0 ? NormalizeDouble(ask + InpTP * _Point, _Digits) : 0;

      if(!trade.Buy(lot, _Symbol, ask, sl, tp, "Metka BUY"))
         PrintFormat("BUY FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
      else
         PrintFormat("metka_ea: BUY @ %.2f SL=%.2f TP=%.2f lot=%.2f", ask, sl, tp, lot);
   }
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lot = InpMartingale ? g_currentLot : InpLotSize;

   if(InpPending)
   {
      double price = NormalizeDouble(bid + InpPendingOffset * _Point, _Digits);
      double sl = InpSL > 0 ? NormalizeDouble(price + InpSL * _Point, _Digits) : 0;
      double tp = InpTP > 0 ? NormalizeDouble(price - InpTP * _Point, _Digits) : 0;

      if(!trade.SellLimit(lot, price, _Symbol, sl, tp, 0, 0, "Metka SELL Limit"))
         PrintFormat("SELL LIMIT FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
      else
         PrintFormat("metka_ea: SELL LIMIT @ %.2f SL=%.2f TP=%.2f lot=%.2f", price, sl, tp, lot);
   }
   else
   {
      double sl = InpSL > 0 ? NormalizeDouble(bid + InpSL * _Point, _Digits) : 0;
      double tp = InpTP > 0 ? NormalizeDouble(bid - InpTP * _Point, _Digits) : 0;

      if(!trade.Sell(lot, _Symbol, bid, sl, tp, "Metka SELL"))
         PrintFormat("SELL FAIL: %d %s", trade.ResultRetcode(), trade.ResultComment());
      else
         PrintFormat("metka_ea: SELL @ %.2f SL=%.2f TP=%.2f lot=%.2f", bid, sl, tp, lot);
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
// МАРТИНГЕЙЛ: відстежуємо результат кожної закритої позиції
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(!InpMartingale) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC)  != (long)InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL)  != _Symbol) return;

   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(profit >= 0)
   {
      // TP спрацював або закрили в плюс → скидаємо на початковий лот
      g_currentLot = InpLotSize;
      GlobalVariableSet("MetkaEA_MartLot", g_currentLot);
      PrintFormat("metka_ea: Martingale RESET → lot=%.2f (profit=%.2f)", g_currentLot, profit);
   }
   else
   {
      // SL спрацював → подвоюємо лот
      double newLot = NormalizeDouble(g_currentLot * 2.0, 2);
      if(InpMartingaleMax > 0 && newLot > InpMartingaleMax)
      {
         newLot = InpMartingaleMax;
         PrintFormat("metka_ea: Martingale CAP reached → lot=%.2f (loss=%.2f)", newLot, profit);
      }
      else
         PrintFormat("metka_ea: Martingale DOUBLE → lot=%.2f (loss=%.2f)", newLot, profit);

      g_currentLot = newLot;
      GlobalVariableSet("MetkaEA_MartLot", g_currentLot);
   }
}
//+------------------------------------------------------------------+
