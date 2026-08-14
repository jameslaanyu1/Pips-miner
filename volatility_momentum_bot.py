"""
Volatility + Momentum 1-Minute Trading Bot

This bot implements a directional trading strategy based on volatility and momentum indicators.
It enters positions based on direction bias and trails stop orders 50 pips behind.
When the stop order is triggered, it closes the current position, opens an opposite position,
and creates a new stop order 50 pips behind the new position.
"""

import ccxt
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import time
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class VolatilityMomentumBot:
    """1-minute trading bot using volatility and momentum indicators"""
    
    def __init__(self, exchange_id='binance', symbol='BTC/USDT', timeframe='1m', api_key='', api_secret=''):
        """
        Initialize the bot
        
        Args:
            exchange_id: CCXT exchange ID
            symbol: Trading pair symbol
            timeframe: Candle timeframe
            api_key: Exchange API key
            api_secret: Exchange API secret
        """
        self.exchange = getattr(ccxt, exchange_id)({
            'apiKey': api_key,
            'secret': api_secret,
            'enableRateLimit': True
        })
        self.symbol = symbol
        self.timeframe = timeframe
        self.position = None  # 'long', 'short', or None
        self.entry_price = None
        self.stop_order_id = None
        self.stop_price = None
        self.pip_value = self.calculate_pip_value()
        self.last_candle_time = None
        self.trade_count = 0
        
    def calculate_pip_value(self):
        """Calculate the value of 1 pip (0.0001) for the trading pair"""
        return 0.0001
    
    def fetch_ohlcv(self, limit=50):
        """
        Fetch OHLCV data from exchange
        
        Args:
            limit: Number of candles to fetch
            
        Returns:
            pandas DataFrame with OHLCV data
        """
        try:
            ohlcv = self.exchange.fetch_ohlcv(self.symbol, self.timeframe, limit=limit)
            df = pd.DataFrame(
                ohlcv,
                columns=['timestamp', 'open', 'high', 'low', 'close', 'volume']
            )
            df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
            return df
        except Exception as e:
            logger.error(f"Error fetching OHLCV data: {e}")
            return None
    
    def calculate_volatility(self, df, period=14):
        """
        Calculate volatility using ATR (Average True Range)
        
        Args:
            df: DataFrame with OHLCV data
            period: Period for ATR calculation
            
        Returns:
            Current ATR value
        """
        df['tr'] = np.maximum(
            df['high'] - df['low'],
            np.maximum(
                abs(df['high'] - df['close'].shift(1)),
                abs(df['low'] - df['close'].shift(1))
            )
        )
        df['atr'] = df['tr'].rolling(window=period).mean()
        return df['atr'].iloc[-1]
    
    def calculate_momentum(self, df, period=14):
        """
        Calculate momentum using RSI (Relative Strength Index)
        
        Args:
            df: DataFrame with OHLCV data
            period: Period for RSI calculation
            
        Returns:
            Current RSI value (0-100)
        """
        delta = df['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
        
        rs = gain / loss
        rsi = 100 - (100 / (1 + rs))
        return rsi.iloc[-1]
    
    def calculate_direction_bias(self, df, volatility, momentum):
        """
        Determine direction bias based on volatility and momentum
        
        Args:
            df: DataFrame with OHLCV data
            volatility: ATR value
            momentum: RSI value
            
        Returns:
            'long', 'short', or None
        """
        current_price = df['close'].iloc[-1]
        previous_price = df['close'].iloc[-2]
        
        # Price trend
        price_momentum = 'up' if current_price > previous_price else 'down'
        
        # RSI-based momentum confirmation
        # RSI > 50: Bullish, RSI < 50: Bearish
        momentum_direction = 'bullish' if momentum > 50 else 'bearish'
        
        # High volatility + bullish momentum = Long bias
        if price_momentum == 'up' and momentum_direction == 'bullish' and volatility > 0:
            logger.info(f"📈 Bullish bias detected - Price UP, RSI: {momentum:.2f}, ATR: {volatility:.6f}")
            return 'long'
        
        # High volatility + bearish momentum = Short bias
        elif price_momentum == 'down' and momentum_direction == 'bearish' and volatility > 0:
            logger.info(f"📉 Bearish bias detected - Price DOWN, RSI: {momentum:.2f}, ATR: {volatility:.6f}")
            return 'short'
        
        return None
    
    def enter_position(self, direction, current_price):
        """
        Enter a trading position
        
        Args:
            direction: 'long' or 'short'
            current_price: Current market price
        """
        try:
            amount = 0.01  # Trade amount (adjust based on your risk)
            
            if direction == 'long':
                # Buy order
                order = self.exchange.create_market_buy_order(self.symbol, amount)
                self.position = 'long'
                self.entry_price = current_price
                logger.info(f"✅ LONG position entered at {current_price}")
            
            elif direction == 'short':
                # Sell order
                order = self.exchange.create_market_sell_order(self.symbol, amount)
                self.position = 'short'
                self.entry_price = current_price
                logger.info(f"✅ SHORT position entered at {current_price}")
            
            # Create trailing stop order
            self.create_trailing_stop(direction, current_price)
            
        except Exception as e:
            logger.error(f"Error entering position: {e}")
    
    def create_trailing_stop(self, position_direction, entry_price):
        """
        Create a trailing stop order 50 pips behind entry
        
        Args:
            position_direction: 'long' or 'short'
            entry_price: Entry price of the position
        """
        try:
            stop_distance = 50 * self.pip_value
            
            if position_direction == 'long':
                # For long position, stop is below entry (sell stop)
                self.stop_price = entry_price - stop_distance
                order = self.exchange.create_order(
                    self.symbol,
                    'limit',
                    'sell',
                    0.01,
                    self.stop_price
                )
                self.stop_order_id = order['id']
                logger.info(f"🛑 Long position - Stop order created at {self.stop_price}")
            
            elif position_direction == 'short':
                # For short position, stop is above entry (buy stop)
                self.stop_price = entry_price + stop_distance
                order = self.exchange.create_order(
                    self.symbol,
                    'limit',
                    'buy',
                    0.01,
                    self.stop_price
                )
                self.stop_order_id = order['id']
                logger.info(f"🛑 Short position - Stop order created at {self.stop_price}")
        
        except Exception as e:
            logger.error(f"Error creating trailing stop: {e}")
    
    def check_stop_triggered(self, current_price):
        """
        Check if the stop order has been triggered
        
        Args:
            current_price: Current market price
            
        Returns:
            True if stop is triggered, False otherwise
        """
        if self.stop_price is None:
            return False
        
        if self.position == 'long':
            # Stop triggered if price falls to or below stop price
            return current_price <= self.stop_price
        
        elif self.position == 'short':
            # Stop triggered if price rises to or above stop price
            return current_price >= self.stop_price
        
        return False
    
    def close_position(self):
        """Close the current position"""
        try:
            amount = 0.01
            
            if self.position == 'long':
                # Sell to close long
                self.exchange.create_market_sell_order(self.symbol, amount)
                logger.info(f"❌ LONG position closed at market")
            
            elif self.position == 'short':
                # Buy to close short
                self.exchange.create_market_buy_order(self.symbol, amount)
                logger.info(f"❌ SHORT position closed at market")
            
            self.position = None
            self.entry_price = None
            
            # Cancel any pending stop order
            if self.stop_order_id:
                try:
                    self.exchange.cancel_order(self.stop_order_id, self.symbol)
                except:
                    pass
            
            self.stop_order_id = None
            self.stop_price = None
        
        except Exception as e:
            logger.error(f"Error closing position: {e}")
    
    def handle_stop_triggered(self, trigger_price):
        """
        Handle stop order trigger:
        1. Close current position
        2. Open opposite position at trigger price
        3. Create new stop order 50 pips behind new position
        
        Args:
            trigger_price: Price at which stop was triggered
        """
        logger.info(f"⚡ Stop order triggered at {trigger_price}")
        
        # Determine opposite direction
        opposite_direction = 'short' if self.position == 'long' else 'long'
        
        # Close the current position
        self.close_position()
        
        # Open opposite position at the trigger price
        self.enter_position(opposite_direction, trigger_price)
        
        self.trade_count += 1
        logger.info(f"🔄 Opposite position opened | Total trades: {self.trade_count}")
    
    def run(self):
        """Main bot loop"""
        logger.info(f"Starting Volatility + Momentum Bot on {self.symbol}")
        logger.info(f"Timeframe: {self.timeframe}, Strategy: Volatility + Momentum with Opposite Position Swap")
        logger.info("=" * 80)
        
        try:
            while True:
                try:
                    # Fetch OHLCV data
                    df = self.fetch_ohlcv(limit=50)
                    if df is None or len(df) < 20:
                        time.sleep(5)
                        continue
                    
                    current_time = df['timestamp'].iloc[-1]
                    current_price = df['close'].iloc[-1]
                    
                    # Only process on new candle
                    if self.last_candle_time and current_time == self.last_candle_time:
                        time.sleep(1)
                        continue
                    
                    self.last_candle_time = current_time
                    
                    # Calculate indicators
                    volatility = self.calculate_volatility(df)
                    momentum = self.calculate_momentum(df)
                    
                    logger.info(f"⏰ {current_time} | 💰 {current_price:.2f} | "
                              f"📊 ATR: {volatility:.6f} | 📈 RSI: {momentum:.2f} | "
                              f"📍 Position: {self.position if self.position else 'NONE'}")
                    
                    # Check if stop order was triggered
                    if self.position and self.check_stop_triggered(current_price):
                        self.handle_stop_triggered(current_price)
                    
                    # Only enter new position if no open position
                    if not self.position:
                        direction = self.calculate_direction_bias(df, volatility, momentum)
                        
                        if direction:
                            self.enter_position(direction, current_price)
                    
                    # Wait before next iteration
                    time.sleep(1)
                
                except Exception as e:
                    logger.error(f"Error in main loop: {e}")
                    time.sleep(5)
        
        except KeyboardInterrupt:
            logger.info("\n🛑 Bot stopped by user")
            if self.position:
                self.close_position()
            logger.info(f"Total trades executed: {self.trade_count}")


def main():
    """Entry point for the bot"""
    # Configure your exchange credentials
    # Set these from environment variables or config file for security
    api_key = ''  # Add your API key
    api_secret = ''  # Add your API secret
    
    bot = VolatilityMomentumBot(
        exchange_id='binance',
        symbol='BTC/USDT',
        timeframe='1m',
        api_key=api_key,
        api_secret=api_secret
    )
    
    # Run the bot
    bot.run()


if __name__ == '__main__':
    main()
