"""
Volatility + Momentum Trading Bot with MetaAPI Integration
Connects to HFM Demo Account via MetaAPI
"""

import asyncio
import logging
import json
from datetime import datetime, timedelta
from typing import Optional
import pandas as pd
import numpy as np
from metaapi_cloud_sdk import MetaApi
import os
from dotenv import load_dotenv

load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MetaAPITradingBot:
    """Volatility + Momentum trading bot using MetaAPI"""
    
    def __init__(self, account_id: str, api_token: str, symbol: str = 'EURUSD'):
        """
        Initialize MetaAPI bot
        
        Args:
            account_id: MetaAPI account ID
            api_token: MetaAPI token
            symbol: Trading symbol (default EURUSD)
        """
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
        """Initialize MetaAPI connection"""
        try:
            api = MetaApi(self.api_token)
            self.account = await api.metatrader_account_api.get_account(self.account_id)
            
            # Wait for account to be ready
            if self.account.state != 'DEPLOYED':
                logger.info(f"Deploying account {self.account_id}...")
                await self.account.deploy()
            
            await self.account.wait_deployed()
            
            # Connect to trading account
            self.connection = self.account.get_rpc_connection()
            await self.connection.connect()
            await self.connection.wait_synchronized()
            
            logger.info(f"✅ Connected to MetaAPI account: {self.account_id}")
            logger.info(f"Trading symbol: {self.symbol}")
            
        except Exception as e:
            logger.error(f"Error initializing MetaAPI: {e}")
            raise
    
    async def get_candles(self, timeframe: str = 'M1', limit: int = 50) -> Optional[list]:
        """Fetch candle data from MetaAPI"""
        try:
            candles = await self.connection.get_candles(
                symbol=self.symbol,
                timeframe=timeframe,
                limit=limit
            )
            return candles
        except Exception as e:
            logger.error(f"Error fetching candles: {e}")
            return None
    
    async def get_account_balance(self) -> dict:
        """Get account balance and equity"""
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
        """Calculate ATR volatility"""
        try:
            closes = [c['close'] for c in candles[-period:]]
            highs = [c['high'] for c in candles[-period:]]
            lows = [c['low'] for c in candles[-period:]]
            
            tr_list = []
            for i in range(1, len(closes)):
                tr = max(
                    highs[i] - lows[i],
                    abs(highs[i] - closes[i-1]),
                    abs(lows[i] - closes[i-1])
                )
                tr_list.append(tr)
            
            atr = sum(tr_list) / len(tr_list) if tr_list else 0
            return atr
        except Exception as e:
            logger.error(f"Error calculating volatility: {e}")
            return 0
    
    def calculate_momentum(self, candles: list, period: int = 14) -> float:
        """Calculate RSI momentum"""
        try:
            closes = [c['close'] for c in candles[-period-1:]]
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
        except Exception as e:
            logger.error(f"Error calculating momentum: {e}")
            return 50
    
    def determine_direction(self, candles: list, volatility: float, momentum: float) -> Optional[str]:
        """Determine trading direction based on indicators"""
        current_close = candles[-1]['close']
        previous_close = candles[-2]['close']
        
        price_trend = 'up' if current_close > previous_close else 'down'
        momentum_bias = 'bullish' if momentum > 50 else 'bearish'
        
        if price_trend == 'up' and momentum_bias == 'bullish' and volatility > 0:
            logger.info(f"📈 LONG Signal - Price UP, RSI: {momentum:.2f}, ATR: {volatility:.6f}")
            return 'BUY'
        elif price_trend == 'down' and momentum_bias == 'bearish' and volatility > 0:
            logger.info(f"📉 SHORT Signal - Price DOWN, RSI: {momentum:.2f}, ATR: {volatility:.6f}")
            return 'SELL'
        
        return None
    
    async def open_position(self, direction: str, volume: float = 0.01):
        """Open a new trading position"""
        try:
            candles = await self.get_candles()
            if not candles:
                return False
            
            current_price = candles[-1]['close']
            
            # Calculate stop loss 50 pips away
            if direction == 'BUY':
                stop_price = current_price - (50 * self.pip_value)
            else:
                stop_price = current_price + (50 * self.pip_value)
            
            # Place order
            order = await self.connection.create_market_order(
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
            
            logger.info(f"✅ {direction} position opened at {current_price:.5f}")
            logger.info(f"🛑 Stop Loss at {stop_price:.5f}")
            
            return True
        except Exception as e:
            logger.error(f"Error opening position: {e}")
            return False
    
    async def close_position(self):
        """Close current position"""
        try:
            positions = await self.connection.get_positions()
            
            for position in positions:
                if position['symbol'] == self.symbol:
                    await self.connection.close_position_partial(
                        positionId=position['id'],
                        volume=position['volume']
                    )
                    logger.info(f"❌ Position closed")
                    self.position = None
                    self.entry_price = None
                    return True
            
            return False
        except Exception as e:
            logger.error(f"Error closing position: {e}")
            return False
    
    async def check_positions(self):
        """Check if any positions are open"""
        try:
            positions = await self.connection.get_positions()
            return [p for p in positions if p['symbol'] == self.symbol]
        except Exception as e:
            logger.error(f"Error checking positions: {e}")
            return []
    
    async def run(self, interval: int = 60):
        """Main bot loop"""
        logger.info(f"🤖 Starting Volatility + Momentum Bot")
        logger.info(f"⏱️  Checking every {interval} seconds")
        
        await self.initialize()
        
        try:
            while True:
                try:
                    # Fetch candles
                    candles = await self.get_candles(timeframe='M1', limit=50)
                    if not candles or len(candles) < 30:
                        await asyncio.sleep(interval)
                        continue
                    
                    # Calculate indicators
                    volatility = self.calculate_volatility(candles)
                    momentum = self.calculate_momentum(candles)
                    current_price = candles[-1]['close']
                    
                    # Get account info
                    account_info = await self.get_account_balance()
                    
                    logger.info(f"\n⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
                    logger.info(f"💰 Price: {current_price:.5f} | ATR: {volatility:.6f} | RSI: {momentum:.2f}")
                    logger.info(f"💵 Balance: {account_info['balance']:.2f} | Equity: {account_info['equity']:.2f}")
                    
                    # Check open positions
                    positions = await self.check_positions()
                    
                    if positions:
                        # Position is open, check for stop trigger
                        position = positions[0]
                        
                        if (position['type'] == 'POSITION_TYPE_BUY' and current_price <= self.stop_price) or \
                           (position['type'] == 'POSITION_TYPE_SELL' and current_price >= self.stop_price):
                            
                            logger.info(f"⚡ Stop triggered at {current_price:.5f}")
                            
                            # Close and open opposite
                            await self.close_position()
                            await asyncio.sleep(2)
                            
                            opposite_direction = 'SELL' if position['type'] == 'POSITION_TYPE_BUY' else 'BUY'
                            await self.open_position(opposite_direction)
                            self.trade_count += 1
                    else:
                        # No position open, check for entry signal
                        direction = self.determine_direction(candles, volatility, momentum)
                        
                        if direction:
                            await self.open_position(direction)
                    
                    await asyncio.sleep(interval)
                
                except Exception as e:
                    logger.error(f"Error in bot loop: {e}")
                    await asyncio.sleep(interval)
        
        except KeyboardInterrupt:
            logger.info("\n🛑 Bot stopped by user")
            if self.position:
                await self.close_position()
            logger.info(f"Total trades: {self.trade_count}")
        finally:
            await self.connection.close()


async def main():
    """Main entry point"""
    # Get credentials from environment variables
    account_id = os.getenv('METAAPI_ACCOUNT_ID')
    api_token = os.getenv('METAAPI_TOKEN')
    
    if not account_id or not api_token:
        logger.error("Please set METAAPI_ACCOUNT_ID and METAAPI_TOKEN environment variables")
        return
    
    bot = MetaAPITradingBot(
        account_id=account_id,
        api_token=api_token,
        symbol='EURUSD'
    )
    
    await bot.run(interval=60)


if __name__ == '__main__':
    asyncio.run(main())
