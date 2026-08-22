"""
Volatility + Trading Bot with MetaAPI Integration
Connects to HFM Demo Account via MetaAPI
"""

import asyncio
import logging
from datetime import datetime
from typing import Optional
from metaapi_cloud_sdk import MetaApi
import os
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MetaAPITradingBot:
    """Volatility trading bot using MetaAPI, without RSI/momentum filtering."""

    def __init__(self, account_id: str, api_token: str, symbol: str = 'EURUSD'):
        self.account_id = account_id
        self.api_token = api_token
        self.symbol = symbol
        self.account = None
        self.connection = None
        self.position = None
        self.entry_price = None
        self.stop_price = None
        self.trade_count = 0
        self.pip_value = 0.0001

    async def initialize(self):
        try:
            api = MetaApi(self.api_token)
            self.account = await api.metatrader_account_api.get_account(self.account_id)
            if self.account.state != 'DEPLOYED':
                logger.info(f"Deploying account {self.account_id}...")
                await self.account.deploy()
            await self.account.wait_deployed()
            self.connection = self.account.get_rpc_connection()
            await self.connection.connect()
            await self.connection.wait_synchronized()
            logger.info(f"Connected to MetaAPI account: {self.account_id}")
            logger.info(f"Trading symbol: {self.symbol}")
        except Exception as e:
            logger.error(f"Error initializing MetaAPI: {e}")
            raise

    async def get_candles(self, timeframe: str = 'M1', limit: int = 50) -> Optional[list]:
        try:
            return await self.connection.get_candles(
                symbol=self.symbol, timeframe=timeframe, limit=limit
            )
        except Exception as e:
            logger.error(f"Error fetching candles: {e}")
            return None

    async def get_account_balance(self) -> dict:
        try:
            account_info = await self.connection.get_account_information()
            return {
                'balance': account_info['balance'],
                'equity': account_info['equity'],
                'free_margin': account_info['freemargin'],
                'margin_level': account_info['marginlevel']
            }
        except Exception as e:
            logger.error(f"Error fetching account balance: {e}")
            return None

    def calculate_volatility(self, candles: list, period: int = 14) -> float:
        """Calculate ATR volatility."""
        try:
            closes = [c['close'] for c in candles[-period:]]
            highs = [c['high'] for c in candles[-period:]]
            lows = [c['low'] for c in candles[-period:]]
            tr_list = []
            for i in range(1, len(closes)):
                tr_list.append(max(
                    highs[i] - lows[i],
                    abs(highs[i] - closes[i - 1]),
                    abs(lows[i] - closes[i - 1])
                ))
            return sum(tr_list) / len(tr_list) if tr_list else 0
        except Exception as e:
            logger.error(f"Error calculating volatility: {e}")
            return 0

    def determine_direction(self, candles: list, volatility: float) -> Optional[str]:
        """Determine direction from price trend and volatility only."""
        if len(candles) < 2 or volatility <= 0:
            return None

        current_close = candles[-1]['close']
        previous_close = candles[-2]['close']

        if current_close > previous_close:
            logger.info(f"LONG Signal - Price UP, ATR: {volatility:.6f}")
            return 'BUY'
        if current_close < previous_close:
            logger.info(f"SHORT Signal - Price DOWN, ATR: {volatility:.6f}")
            return 'SELL'
        return None

    async def open_position(self, direction: str, volume: float = 0.01):
        try:
            candles = await self.get_candles()
            if not candles:
                return False
            current_price = candles[-1]['close']
            stop_price = (
                current_price - (50 * self.pip_value)
                if direction == 'BUY'
                else current_price + (50 * self.pip_value)
            )
            await self.connection.create_market_order(
                symbol=self.symbol,
                orderType=direction,
                volume=volume,
                stopLoss=stop_price,
                priceTakeProfit=None,
                comment="Vol-Mom Bot"
            )
            self.position = direction
            self.entry_price = current_price
            self.stop_price = stop_price
            logger.info(f"{direction} position opened at {current_price:.5f}")
            logger.info(f"Stop Loss at {stop_price:.5f}")
            return True
        except Exception as e:
            logger.error(f"Error opening position: {e}")
            return False

    async def close_position(self):
        try:
            positions = await self.connection.get_positions()
            for position in positions:
                if position['symbol'] == self.symbol:
                    await self.connection.close_position_partial(
                        positionId=position['id'], volume=position['volume']
                    )
                    logger.info("Position closed")
                    self.position = None
                    self.entry_price = None
                    return True
            return False
        except Exception as e:
            logger.error(f"Error closing position: {e}")
            return False

    async def check_positions(self):
        try:
            positions = await self.connection.get_positions()
            return [p for p in positions if p['symbol'] == self.symbol]
        except Exception as e:
            logger.error(f"Error checking positions: {e}")
            return []

    async def run(self, interval: int = 60):
        logger.info("Starting Volatility Bot")
        logger.info(f"Checking every {interval} seconds")
        await self.initialize()
        try:
            while True:
                try:
                    candles = await self.get_candles(timeframe='M1', limit=50)
                    if not candles or len(candles) < 30:
                        await asyncio.sleep(interval)
                        continue

                    volatility = self.calculate_volatility(candles)
                    current_price = candles[-1]['close']
                    account_info = await self.get_account_balance()

                    logger.info(datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
                    logger.info(f"Price: {current_price:.5f} | ATR: {volatility:.6f}")
                    logger.info(
                        f"Balance: {account_info['balance']:.2f} | "
                        f"Equity: {account_info['equity']:.2f}"
                    )

                    positions = await self.check_positions()
                    if positions:
                        position = positions[0]
                        if (
                            position['type'] == 'POSITION_TYPE_BUY' and current_price <= self.stop_price
                        ) or (
                            position['type'] == 'POSITION_TYPE_SELL' and current_price >= self.stop_price
                        ):
                            logger.info(f"Stop triggered at {current_price:.5f}")
                            await self.close_position()
                            await asyncio.sleep(2)
                            opposite_direction = (
                                'SELL' if position['type'] == 'POSITION_TYPE_BUY' else 'BUY'
                            )
                            await self.open_position(opposite_direction)
                            self.trade_count += 1
                    else:
                        direction = self.determine_direction(candles, volatility)
                        if direction:
                            await self.open_position(direction)

                    await asyncio.sleep(interval)
                except Exception as e:
                    logger.error(f"Error in bot loop: {e}")
                    await asyncio.sleep(interval)
        except KeyboardInterrupt:
            logger.info("Bot stopped by user")
            if self.position:
                await self.close_position()
            logger.info(f"Total trades: {self.trade_count}")
        finally:
            await self.connection.close()


async def main():
    account_id = os.getenv('METAAPI_ACCOUNT_ID')
    api_token = os.getenv('METAAPI_TOKEN')
    if not account_id or not api_token:
        logger.error("Please set METAAPI_ACCOUNT_ID and METAAPI_TOKEN environment variables")
        return
    bot = MetaAPITradingBot(account_id=account_id, api_token=api_token, symbol='EURUSD')
    await bot.run(interval=60)


if __name__ == '__main__':
    asyncio.run(main())
