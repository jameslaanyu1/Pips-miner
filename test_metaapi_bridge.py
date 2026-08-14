"""
Testing script for MetaAPI Bridge Integration
Test all bot functionalities with real MetaAPI connection
Gold (XAUUSD) Trading Symbol
"""

import asyncio
import logging
from datetime import datetime
from metaapi_bridge import MetaAPIBridge, OrderType
import os
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class BotTester:
    """Test suite for trading bot with MetaAPI"""

    def __init__(self, api_token: str, account_id: str, symbol: str = 'XAUUSD'):
        self.bridge = MetaAPIBridge(api_token)
        self.account_id = account_id
        self.symbol = symbol
        self.test_results = []

    async def run_all_tests(self):
        """
        Run all test cases
        """
        logger.info("\n" + "="*80)
        logger.info("🧪 METAAPI BRIDGE TEST SUITE - XAUUSD (GOLD)")
        logger.info("="*80)

        try:
            # Test 1: Account Connection
            await self.test_account_connection()

            # Test 2: Account Information
            await self.test_account_info()

            # Test 3: Price Quotes
            await self.test_price_quotes()

            # Test 4: Candle Data
            await self.test_candle_data()

            # Test 5: Open Positions
            await self.test_open_positions()

            # Test 6: Trade History
            await self.test_trade_history()

            # Test 7: Indicator Calculation
            await self.test_indicators()

            # Test 8: Position Management (read-only)
            await self.test_position_info()

            # Summary
            await self.print_summary()

        except Exception as e:
            logger.error(f"Test suite failed: {e}")
        finally:
            await self.bridge.close()

    async def test_account_connection(self):
        """
        Test: Account Connection
        """
        logger.info("\n🔌 TEST 1: Account Connection")
        logger.info("-" * 80)

        try:
            success = await self.bridge.set_active_account(self.account_id)
            if success:
                logger.info(f"✅ PASS: Connected to account {self.account_id}")
                self.test_results.append(('Account Connection', 'PASS'))
            else:
                logger.error("❌ FAIL: Could not connect to account")
                self.test_results.append(('Account Connection', 'FAIL'))
        except Exception as e:
            logger.error(f"❌ FAIL: {e}")
            self.test_results.append(('Account Connection', 'FAIL'))

    async def test_account_info(self):
        """
        Test: Retrieve Account Information
        """
        logger.info("\n📊 TEST 2: Account Information")
        logger.info("-" * 80)

        try:
            info = await self.bridge.get_account_info()
            if info:
                logger.info(f"Account ID: {info.account_id}")
                logger.info(f"Account Type: {info.account_type}")
                logger.info(f"Broker: {info.broker}")
                logger.info(f"Balance: ${info.balance:,.2f}")
                logger.info(f"Equity: ${info.equity:,.2f}")
                logger.info(f"Free Margin: ${info.free_margin:,.2f}")
                logger.info(f"Margin Level: {info.margin_level:.2f}%")
                logger.info(f"Leverage: 1:{info.leverage}")
                logger.info(f"Currency: {info.currency}")
                logger.info(f"Connected: {info.connected}")
                logger.info(f"Synchronized: {info.synchronized}")
                logger.info("✅ PASS: Account info retrieved successfully")
                self.test_results.append(('Account Info', 'PASS'))
            else:
                logger.error("❌ FAIL: Could not retrieve account info")
                self.test_results.append(('Account Info', 'FAIL'))
        except Exception as e:
            logger.error(f"❌ FAIL: {e}")
            self.test_results.append(('Account Info', 'FAIL'))

    async def test_price_quotes(self):
        """
        Test: Get Price Quotes for XAUUSD and other symbols
        """
        logger.info("\n💱 TEST 3: Price Quotes")
        logger.info("-" * 80)

        try:
            symbols = ['XAUUSD', 'EURUSD', 'GBPUSD']
            success_count = 0

            for symbol in symbols:
                quote = await self.bridge.get_quote(symbol)
                if quote:
                    logger.info(f"{symbol}: Bid={quote.bid:.5f} Ask={quote.ask:.5f} Mid={quote.mid:.5f}")
                    success_count += 1

            if success_count == len(symbols):
                logger.info(f"✅ PASS: Retrieved quotes for {success_count}/{len(symbols)} symbols")
                self.test_results.append(('Price Quotes', 'PASS'))
            else:
                logger.error(f"⚠️  PARTIAL: Retrieved quotes for {success_count}/{len(symbols)} symbols")
                self.test_results.append(('Price Quotes', 'PARTIAL'))
        except Exception as e:
            logger.error(f"❌ FAIL: {e}")
            self.test_results.append(('Price Quotes', 'FAIL'))

    async def test_candle_data(self):
        """
        Test: Retrieve Candle Data for XAUUSD
        """
        logger.info("\n📈 TEST 4: Candle Data")
        logger.info("-" * 80)

        try:
            candles = await self.bridge.get_candles(self.symbol, 'M1', 10)
            if candles:
                logger.info(f"Retrieved {len(candles)} M1 candles for {self.symbol}")
                logger.info("Last 3 candles:")
                for i, candle in enumerate(candles[-3:]):
                    logger.info(
                        f"  {i+1}. O:{candle.get('open', 0):.5f} "
                        f"H:{candle.get('high', 0):.5f} L:{candle.get('low', 0):.5f} "
                        f"C:{candle.get('close', 0):.5f} V:{candle.get('volume', 0)}"
                    )
                logger.info("✅ PASS: Candle data retrieved successfully")
                self.test_results.append(('Candle Data', 'PASS'))
            else:
                logger.error("❌ FAIL: No candle data received")
                self.test_results.append(('Candle Data', 'FAIL'))
        except Exception as e:
            logger.error(f"❌ FAIL: {e}")
            self.test_results.append(('Candle Data', 'FAIL'))

    async def test_open_positions(self):
        """
        Test: Retrieve Open Positions
        """
        logger.info("\n📋 TEST 5: Open Positions")
        logger.info("-" * 80)

        try:
            positions = await self.bridge.get_open_positions()
            logger.info(f"Open positions: {len(positions)}")

            if positions:
                for pos in positions:
                    logger.info(
                        f"  {pos.order_type} {pos.volume} {pos.symbol} "
                        f"@ {pos.open_price:.5f} | P&L: ${pos.profit_loss:.2f}"
                    )
            else:
                logger.info("No open positions")

            logger.info("✅ PASS: Open positions retrieved")
            self.test_results.append(('Open Positions', 'PASS'))
        except Exception as e:
            logger.error(f"❌ FAIL: {e}")
            self.test_results.append(('Open Positions', 'FAIL'))

    async def test_trade_history(self):
        """
        Test: Retrieve Trade History
        """
        logger.info("\n📜 TEST 6: Trade History")
        logger.info("-" * 80)

        try:
            trades = await self.bridge.get_trade_history(limit=10)
            logger.info(f"Retrieved {len(trades)} recent trades")

            if trades:
                for i, trade in enumerate(trades[:5]):
                    logger.info(
                        f"  {i+1}. {trade.order_type} {trade.volume} {trade.symbol} "
                        f"@ {trade.open_price:.5f} | P&L: ${trade.profit_loss:.2f}"
                    )
            else:
                logger.info("No trade history available")

            logger.info("✅ PASS: Trade history retrieved")
            self.test_results.append(('Trade History', 'PASS'))
        except Exception as e:
            logger.error(f"❌ FAIL: {e}")
            self.test_results.append(('Trade History', 'FAIL'))

    async def test_indicators(self):
        """
        Test: Indicator Calculation for XAUUSD
        """
        logger.info("\n📊 TEST 7: Indicator Calculation")
        logger.info("-" * 80)

        try:
            candles = await self.bridge.get_candles(self.symbol, 'M1', 50)
            if not candles:
                logger.error("❌ FAIL: Cannot calculate indicators without candles")
                self.test_results.append(('Indicators', 'FAIL'))
                return

            # Calculate ATR
            atr = self._calculate_atr(candles, 14)
            logger.info(f"ATR (14) for {self.symbol}: {atr:.6f}")

            # Calculate RSI
            rsi = self._calculate_rsi(candles, 14)
            logger.info(f"RSI (14) for {self.symbol}: {rsi:.2f}")

            logger.info("✅ PASS: Indicators calculated successfully")
            self.test_results.append(('Indicators', 'PASS'))
        except Exception as e:
            logger.error(f"❌ FAIL: {e}")
            self.test_results.append(('Indicators', 'FAIL'))

    async def test_position_info(self):
        """
        Test: Position Information for XAUUSD
        """
        logger.info("\n📍 TEST 8: Position Information")
        logger.info("-" * 80)

        try:
            positions = await self.bridge.get_open_positions(self.symbol)
            logger.info(f"Positions for {self.symbol}: {len(positions)}")

            if positions:
                for pos in positions:
                    logger.info(f"  Direction: {pos.order_type}")
                    logger.info(f"  Volume: {pos.volume}")
                    logger.info(f"  Entry: {pos.open_price:.5f}")
                    logger.info(f"  Stop Loss: {pos.stop_loss:.5f}")
                    logger.info(f"  P&L: ${pos.profit_loss:.2f}")

            logger.info("✅ PASS: Position info retrieved")
            self.test_results.append(('Position Info', 'PASS'))
        except Exception as e:
            logger.error(f"❌ FAIL: {e}")
            self.test_results.append(('Position Info', 'FAIL'))

    def _calculate_atr(self, candles, period=14):
        """Calculate ATR"""
        if len(candles) < period:
            return 0.0

        tr_list = []
        for i in range(1, len(candles)):
            high = candles[i].get('high', 0)
            low = candles[i].get('low', 0)
            close = candles[i-1].get('close', 0)

            tr = max(
                high - low,
                abs(high - close),
                abs(low - close)
            )
            tr_list.append(tr)

        return sum(tr_list[-period:]) / period if tr_list else 0.0

    def _calculate_rsi(self, candles, period=14):
        """Calculate RSI"""
        if len(candles) < period + 1:
            return 50.0

        closes = [c.get('close', 0) for c in candles]
        deltas = [closes[i] - closes[i-1] for i in range(1, len(closes))]

        gains = [d for d in deltas if d > 0]
        losses = [-d for d in deltas if d < 0]

        avg_gain = sum(gains) / period if gains else 0
        avg_loss = sum(losses) / period if losses else 0

        if avg_loss == 0:
            return 100 if avg_gain > 0 else 50

        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))
        return rsi

    async def print_summary(self):
        """
        Print test summary
        """
        logger.info("\n" + "="*80)
        logger.info("📋 TEST SUMMARY - XAUUSD GOLD TRADING")
        logger.info("="*80)

        pass_count = sum(1 for _, result in self.test_results if result == 'PASS')
        total_count = len(self.test_results)

        for test_name, result in self.test_results:
            status = "✅" if result == 'PASS' else "⚠️ " if result == 'PARTIAL' else "❌"
            logger.info(f"{status} {test_name}: {result}")

        logger.info("\n" + "-"*80)
        logger.info(f"Overall: {pass_count}/{total_count} tests passed")
        logger.info("="*80 + "\n")


async def main():
    """
    Main entry point
    """
    api_token = os.getenv('METAAPI_TOKEN')
    account_id = os.getenv('METAAPI_ACCOUNT_ID')
    symbol = os.getenv('TRADING_SYMBOL', 'XAUUSD')

    if not api_token or not account_id:
        logger.error("\n❌ Please set the following environment variables:")
        logger.error("   - METAAPI_TOKEN: Your MetaAPI token")
        logger.error("   - METAAPI_ACCOUNT_ID: Your MetaAPI account ID")
        logger.error("\nExample .env file:")
        logger.error("   METAAPI_TOKEN=xxx")
        logger.error("   METAAPI_ACCOUNT_ID=xxx")
        logger.error("   TRADING_SYMBOL=XAUUSD")
        return

    tester = BotTester(api_token, account_id, symbol)
    await tester.run_all_tests()


if __name__ == '__main__':
    asyncio.run(main())
