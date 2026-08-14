"""
MetaAPI Bridge for Testing
Handles real-time synchronization with MetaAPI and HFM accounts
"""

import asyncio
import logging
import json
from datetime import datetime, timedelta
from typing import Optional, Dict, List
from metaapi_cloud_sdk import MetaApi
import os
from dotenv import load_dotenv
from dataclasses import dataclass, asdict
from enum import Enum

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class OrderType(Enum):
    """Order types"""
    BUY = 'BUY'
    SELL = 'SELL'
    BUY_LIMIT = 'BUY_LIMIT'
    SELL_LIMIT = 'SELL_LIMIT'
    BUY_STOP = 'BUY_STOP'
    SELL_STOP = 'SELL_STOP'


class PositionStatus(Enum):
    """Position status"""
    OPEN = 'OPEN'
    CLOSED = 'CLOSED'
    PENDING = 'PENDING'


@dataclass
class TradeOrder:
    """Trade order data structure"""
    order_id: str
    symbol: str
    order_type: str
    volume: float
    open_price: float
    open_time: datetime
    close_price: Optional[float] = None
    close_time: Optional[datetime] = None
    profit_loss: float = 0.0
    stop_loss: float = 0.0
    take_profit: Optional[float] = None
    status: str = 'OPEN'
    comment: str = ''

    def to_dict(self):
        data = asdict(self)
        data['open_time'] = self.open_time.isoformat()
        if self.close_time:
            data['close_time'] = self.close_time.isoformat()
        return data


@dataclass
class AccountInfo:
    """Account information structure"""
    account_id: str
    account_type: str  # 'DEMO' or 'LIVE'
    balance: float
    equity: float
    free_margin: float
    margin_used: float
    margin_level: float
    currency: str
    leverage: int
    connected: bool
    synchronized: bool
    broker: str = 'HFM'
    server: str = ''

    def to_dict(self):
        return asdict(self)


@dataclass
class Quote:
    """Price quote data structure"""
    symbol: str
    bid: float
    ask: float
    mid: float
    timestamp: datetime
    atr_14: float = 0.0
    rsi_14: float = 0.0

    def to_dict(self):
        return {
            'symbol': self.symbol,
            'bid': self.bid,
            'ask': self.ask,
            'mid': self.mid,
            'timestamp': self.timestamp.isoformat(),
            'atr_14': self.atr_14,
            'rsi_14': self.rsi_14,
        }


class MetaAPIBridge:
    """Bridge for MetaAPI integration with HFM accounts"""

    def __init__(self, api_token: str):
        """
        Initialize MetaAPI Bridge
        
        Args:
            api_token: MetaAPI token
        """
        self.api_token = api_token
        self.api = MetaApi(api_token)
        self.accounts: Dict[str, 'MetaAPIAccount'] = {}
        self.active_account: Optional['MetaAPIAccount'] = None
        self.quotes: Dict[str, Quote] = {}
        self.trades: Dict[str, TradeOrder] = {}

    async def get_or_create_account(self, account_id: str) -> 'MetaAPIAccount':
        """
        Get or create account connection
        
        Args:
            account_id: MetaAPI account ID
            
        Returns:
            MetaAPIAccount instance
        """
        if account_id in self.accounts:
            logger.info(f"Using existing account connection: {account_id}")
            return self.accounts[account_id]

        logger.info(f"Creating new account connection: {account_id}")
        account = MetaAPIAccount(self.api, account_id)
        await account.initialize()
        self.accounts[account_id] = account
        return account

    async def set_active_account(self, account_id: str) -> bool:
        """
        Set active trading account
        
        Args:
            account_id: MetaAPI account ID
            
        Returns:
            True if successful
        """
        try:
            account = await self.get_or_create_account(account_id)
            self.active_account = account
            logger.info(f"✅ Active account set to: {account_id}")
            return True
        except Exception as e:
            logger.error(f"Error setting active account: {e}")
            return False

    async def get_account_info(self) -> Optional[AccountInfo]:
        """
        Get active account information
        
        Returns:
            AccountInfo object
        """
        if not self.active_account:
            return None
        return await self.active_account.get_account_info()

    async def get_quote(self, symbol: str) -> Optional[Quote]:
        """
        Get current price quote for symbol
        
        Args:
            symbol: Trading symbol (e.g., 'EURUSD')
            
        Returns:
            Quote object
        """
        if not self.active_account:
            return None
        return await self.active_account.get_quote(symbol)

    async def get_candles(self, symbol: str, timeframe: str = 'M1', limit: int = 50) -> List[dict]:
        """
        Get candle data for symbol
        
        Args:
            symbol: Trading symbol
            timeframe: Timeframe (M1, M5, M15, H1, etc.)
            limit: Number of candles
            
        Returns:
            List of candle dictionaries
        """
        if not self.active_account:
            return []
        return await self.active_account.get_candles(symbol, timeframe, limit)

    async def open_position(self, symbol: str, order_type: str, volume: float, 
                           stop_loss: Optional[float] = None,
                           take_profit: Optional[float] = None,
                           comment: str = '') -> Optional[TradeOrder]:
        """
        Open a trading position
        
        Args:
            symbol: Trading symbol
            order_type: BUY or SELL
            volume: Lot volume
            stop_loss: Stop loss price
            take_profit: Take profit price
            comment: Order comment
            
        Returns:
            TradeOrder object
        """
        if not self.active_account:
            return None
        return await self.active_account.open_position(
            symbol, order_type, volume, stop_loss, take_profit, comment
        )

    async def close_position(self, ticket: str, volume: Optional[float] = None) -> bool:
        """
        Close a trading position
        
        Args:
            ticket: Position ticket/ID
            volume: Volume to close (None = close all)
            
        Returns:
            True if successful
        """
        if not self.active_account:
            return False
        return await self.active_account.close_position(ticket, volume)

    async def get_open_positions(self, symbol: Optional[str] = None) -> List[TradeOrder]:
        """
        Get open positions
        
        Args:
            symbol: Filter by symbol (optional)
            
        Returns:
            List of TradeOrder objects
        """
        if not self.active_account:
            return []
        return await self.active_account.get_open_positions(symbol)

    async def modify_position(self, ticket: str, stop_loss: Optional[float] = None,
                             take_profit: Optional[float] = None) -> bool:
        """
        Modify position stop loss or take profit
        
        Args:
            ticket: Position ticket/ID
            stop_loss: New stop loss price
            take_profit: New take profit price
            
        Returns:
            True if successful
        """
        if not self.active_account:
            return False
        return await self.active_account.modify_position(ticket, stop_loss, take_profit)

    async def get_trade_history(self, limit: int = 50) -> List[TradeOrder]:
        """
        Get closed trades history
        
        Args:
            limit: Number of trades to retrieve
            
        Returns:
            List of TradeOrder objects
        """
        if not self.active_account:
            return []
        return await self.active_account.get_trade_history(limit)

    async def close(self):
        """
        Close all account connections
        """
        for account in self.accounts.values():
            await account.close()
        logger.info("MetaAPI Bridge closed")


class MetaAPIAccount:
    """Individual account connection handler"""

    def __init__(self, api: MetaApi, account_id: str):
        """
        Initialize account connection
        
        Args:
            api: MetaApi instance
            account_id: MetaAPI account ID
        """
        self.api = api
        self.account_id = account_id
        self.account = None
        self.connection = None
        self.account_info: Optional[AccountInfo] = None

    async def initialize(self):
        """
        Initialize and connect to account
        """
        try:
            # Get account from MetaAPI
            self.account = await self.api.metatrader_account_api.get_account(self.account_id)
            logger.info(f"📡 Retrieved account: {self.account_id}")

            # Deploy if needed
            if self.account.state != 'DEPLOYED':
                logger.info(f"🚀 Deploying account...")
                await self.account.deploy()
                await self.account.wait_deployed()
                logger.info(f"✅ Account deployed")

            # Get RPC connection
            self.connection = self.account.get_rpc_connection()
            await self.connection.connect()
            logger.info(f"🔗 Waiting for synchronization...")
            await self.connection.wait_synchronized()
            logger.info(f"✅ Account synchronized")

        except Exception as e:
            logger.error(f"Error initializing account: {e}")
            raise

    async def get_account_info(self) -> AccountInfo:
        """
        Get account information
        
        Returns:
            AccountInfo object
        """
        try:
            info = await self.connection.get_account_information()
            self.account_info = AccountInfo(
                account_id=self.account_id,
                account_type='LIVE' if info.get('isLive') else 'DEMO',
                balance=info.get('balance', 0),
                equity=info.get('equity', 0),
                free_margin=info.get('freemargin', 0),
                margin_used=info.get('margin', 0),
                margin_level=info.get('marginlevel', 0),
                currency=info.get('currency', 'USD'),
                leverage=int(info.get('leverage', 100)),
                connected=True,
                synchronized=True,
                server=self.account.server if self.account else '',
            )
            return self.account_info
        except Exception as e:
            logger.error(f"Error getting account info: {e}")
            return None

    async def get_quote(self, symbol: str) -> Optional[Quote]:
        """
        Get current price quote
        
        Args:
            symbol: Trading symbol
            
        Returns:
            Quote object
        """
        try:
            quote = await self.connection.get_symbol_price(symbol)
            return Quote(
                symbol=symbol,
                bid=quote['bid'],
                ask=quote['ask'],
                mid=(quote['bid'] + quote['ask']) / 2,
                timestamp=datetime.now(),
            )
        except Exception as e:
            logger.error(f"Error getting quote for {symbol}: {e}")
            return None

    async def get_candles(self, symbol: str, timeframe: str = 'M1', limit: int = 50) -> List[dict]:
        """
        Get candle data
        
        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            limit: Number of candles
            
        Returns:
            List of candle dictionaries
        """
        try:
            candles = await self.connection.get_candles(
                symbol=symbol,
                timeframe=timeframe,
                limit=limit
            )
            return candles if candles else []
        except Exception as e:
            logger.error(f"Error getting candles for {symbol}: {e}")
            return []

    async def open_position(self, symbol: str, order_type: str, volume: float,
                           stop_loss: Optional[float] = None,
                           take_profit: Optional[float] = None,
                           comment: str = 'Vol-Mom Bot') -> Optional[TradeOrder]:
        """
        Open a trading position
        
        Args:
            symbol: Trading symbol
            order_type: BUY or SELL
            volume: Lot volume
            stop_loss: Stop loss price
            take_profit: Take profit price
            comment: Order comment
            
        Returns:
            TradeOrder object
        """
        try:
            quote = await self.get_quote(symbol)
            if not quote:
                logger.error(f"Cannot get quote for {symbol}")
                return None

            order = await self.connection.create_market_order(
                symbol=symbol,
                orderType=order_type,
                volume=volume,
                stopLoss=stop_loss,
                takeProfitPrice=take_profit,
                comment=comment
            )

            trade = TradeOrder(
                order_id=order['id'],
                symbol=symbol,
                order_type=order_type,
                volume=volume,
                open_price=quote.mid,
                open_time=datetime.now(),
                stop_loss=stop_loss or 0.0,
                take_profit=take_profit,
                comment=comment,
                status='OPEN'
            )

            logger.info(f"✅ Position opened: {order_type} {volume} {symbol} @ {quote.mid:.5f}")
            return trade

        except Exception as e:
            logger.error(f"Error opening position: {e}")
            return None

    async def close_position(self, ticket: str, volume: Optional[float] = None) -> bool:
        """
        Close a trading position
        
        Args:
            ticket: Position ticket/ID
            volume: Volume to close (None = close all)
            
        Returns:
            True if successful
        """
        try:
            if volume:
                await self.connection.close_position_partial(ticket, volume)
            else:
                await self.connection.close_position_partially(ticket)

            logger.info(f"✅ Position {ticket} closed")
            return True
        except Exception as e:
            logger.error(f"Error closing position: {e}")
            return False

    async def modify_position(self, ticket: str, stop_loss: Optional[float] = None,
                             take_profit: Optional[float] = None) -> bool:
        """
        Modify position SL/TP
        
        Args:
            ticket: Position ticket/ID
            stop_loss: New stop loss price
            take_profit: New take profit price
            
        Returns:
            True if successful
        """
        try:
            await self.connection.modify_position(
                ticket,
                stopLoss=stop_loss,
                takeProfitPrice=take_profit
            )
            logger.info(f"✅ Position {ticket} modified")
            return True
        except Exception as e:
            logger.error(f"Error modifying position: {e}")
            return False

    async def get_open_positions(self, symbol: Optional[str] = None) -> List[TradeOrder]:
        """
        Get open positions
        
        Args:
            symbol: Filter by symbol (optional)
            
        Returns:
            List of TradeOrder objects
        """
        try:
            positions = await self.connection.get_positions()
            trades = []

            for pos in positions:
                if symbol and pos['symbol'] != symbol:
                    continue

                trade = TradeOrder(
                    order_id=pos['id'],
                    symbol=pos['symbol'],
                    order_type='BUY' if pos['type'] == 'POSITION_TYPE_BUY' else 'SELL',
                    volume=pos['volume'],
                    open_price=pos['openPrice'],
                    open_time=datetime.fromtimestamp(pos['openTime'] / 1000),
                    profit_loss=pos.get('profit', 0),
                    stop_loss=pos.get('stopLoss', 0),
                    take_profit=pos.get('takeProfit'),
                    status='OPEN'
                )
                trades.append(trade)

            return trades
        except Exception as e:
            logger.error(f"Error getting open positions: {e}")
            return []

    async def get_trade_history(self, limit: int = 50) -> List[TradeOrder]:
        """
        Get closed trades history
        
        Args:
            limit: Number of trades
            
        Returns:
            List of TradeOrder objects
        """
        try:
            deals = await self.connection.get_deals(limit=limit)
            trades = []

            for deal in deals:
                if deal['type'] != 'DEAL_TYPE_SELL' and deal['type'] != 'DEAL_TYPE_BUY':
                    continue

                trade = TradeOrder(
                    order_id=deal['id'],
                    symbol=deal['symbol'],
                    order_type='BUY' if deal['type'] == 'DEAL_TYPE_BUY' else 'SELL',
                    volume=deal['volume'],
                    open_price=deal['price'],
                    open_time=datetime.fromtimestamp(deal['time'] / 1000),
                    profit_loss=deal.get('profit', 0),
                    status='CLOSED'
                )
                trades.append(trade)

            return trades
        except Exception as e:
            logger.error(f"Error getting trade history: {e}")
            return []

    async def close(self):
        """
        Close account connection
        """
        if self.connection:
            await self.connection.close()
            logger.info(f"Account {self.account_id} connection closed")


# Testing functions
async def test_bridge():
    """
    Test MetaAPI Bridge functionality
    """
    api_token = os.getenv('METAAPI_TOKEN')
    demo_account_id = os.getenv('METAAPI_ACCOUNT_ID')

    if not api_token or not demo_account_id:
        logger.error("Please set METAAPI_TOKEN and METAAPI_ACCOUNT_ID environment variables")
        return

    bridge = MetaAPIBridge(api_token)

    try:
        # Set active account
        await bridge.set_active_account(demo_account_id)

        # Get account info
        logger.info("\n📊 Fetching Account Information...")
        account_info = await bridge.get_account_info()
        if account_info:
            logger.info(f"Account: {account_info.account_id}")
            logger.info(f"Type: {account_info.account_type}")
            logger.info(f"Balance: ${account_info.balance:.2f}")
            logger.info(f"Equity: ${account_info.equity:.2f}")
            logger.info(f"Free Margin: ${account_info.free_margin:.2f}")
            logger.info(f"Leverage: 1:{account_info.leverage}")

        # Get price quote
        logger.info("\n💱 Fetching Price Quote...")
        quote = await bridge.get_quote('EURUSD')
        if quote:
            logger.info(f"Symbol: {quote.symbol}")
            logger.info(f"Bid: {quote.bid:.5f}")
            logger.info(f"Ask: {quote.ask:.5f}")
            logger.info(f"Mid: {quote.mid:.5f}")

        # Get candles
        logger.info("\n📈 Fetching Candles...")
        candles = await bridge.get_candles('EURUSD', 'M1', 5)
        if candles:
            logger.info(f"Retrieved {len(candles)} candles")
            for i, candle in enumerate(candles[-3:]):
                logger.info(
                    f"  Candle {i}: O:{candle['open']:.5f} "
                    f"H:{candle['high']:.5f} L:{candle['low']:.5f} C:{candle['close']:.5f}"
                )

        # Get open positions
        logger.info("\n📋 Fetching Open Positions...")
        positions = await bridge.get_open_positions()
        logger.info(f"Open positions: {len(positions)}")
        for pos in positions:
            logger.info(
                f"  {pos.order_type} {pos.volume} {pos.symbol} @ "
                f"{pos.open_price:.5f} | P&L: ${pos.profit_loss:.2f}"
            )

    except Exception as e:
        logger.error(f"Test failed: {e}")
    finally:
        await bridge.close()


if __name__ == '__main__':
    asyncio.run(test_bridge())
