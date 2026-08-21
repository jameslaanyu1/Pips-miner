import math
import threading
import time
import uuid


class MockTrading:
    def __init__(self):
        self.lock = threading.RLock()
        self.accounts = {}

    def connect(self, login, server, platform):
        account_id = f"mock-{login}-{uuid.uuid4().hex[:10]}"
        self.accounts[account_id] = {
            "login": login,
            "server": server,
            "platform": platform,
            "balance": 10000.0,
            "positions": [],
            "orders": [],
        }
        return account_id

    def account(self, account_id):
        if account_id not in self.accounts:
            parts = account_id.split("-")
            self.accounts[account_id] = {
                "login": parts[1] if len(parts) > 1 else "demo",
                "server": "MOCK-Demo",
                "platform": "mt5",
                "balance": 10000.0,
                "positions": [],
                "orders": [],
            }
        return self.accounts[account_id]

    def price(self, symbol):
        symbol = symbol.upper()

        override = getattr(self, "_trigger_price_override", {})
        if symbol in override:
            return override[symbol]
        bases = {
            "EURUSD": 1.17000,
            "GBPUSD": 1.34500,
            "USDJPY": 148.500,
            "XAUUSD": 3340.00,
            "BTCUSD": 118000.0,
        }
        base = bases.get(symbol, 1.0)
        wave = math.sin(time.time() / 17) * 0.00045

        if symbol == "USDJPY":
            wave *= 100
        elif symbol == "XAUUSD":
            wave *= 1000
        elif symbol == "BTCUSD":
            wave *= 100000

        bid = round(base + wave, 5 if base < 10 else 2)
        spread = 0.00010 if base < 10 else 0.01
        return bid, round(bid + spread, 5 if base < 10 else 2)

    @staticmethod
    def contract_size(symbol):
        return 100 if symbol.upper() in ("XAUUSD", "BTCUSD") else 100000

    def information(self, account_id):
        a = self.account(account_id)
        floating = 0.0

        for p in a["positions"]:
            bid, ask = self.price(p["symbol"])
            current = bid if p["type"] == "POSITION_TYPE_BUY" else ask
            direction = 1 if p["type"] == "POSITION_TYPE_BUY" else -1
            floating += (
                (current - p["openPrice"])
                * direction
                * p["volume"]
                * self.contract_size(p["symbol"])
            )

        equity = a["balance"] + floating

        return {
            "broker": a["server"],
            "currency": "USD",
            "balance": round(a["balance"], 2),
            "equity": round(equity, 2),
            "margin": 0,
            "freeMargin": round(equity, 2),
            "marginLevel": None,
            "leverage": 100,
            "login": a["login"],
            "server": a["server"],
            "tradeAllowed": True,
            "type": "MOCK",
        }

    def positions(self, account_id):
        self.process_pending_orders(account_id)
        a = self.account(account_id)
        result = []

        for p in a["positions"]:
            bid, ask = self.price(p["symbol"])
            current = bid if p["type"] == "POSITION_TYPE_BUY" else ask
            direction = 1 if p["type"] == "POSITION_TYPE_BUY" else -1

            item = dict(p)
            item["currentPrice"] = current
            item["profit"] = round(
                (current - p["openPrice"])
                * direction
                * p["volume"]
                * self.contract_size(p["symbol"]),
                2,
            )
            result.append(item)

        return result

    def orders(self, account_id):
        self.process_pending_orders(account_id)
        return list(self.account(account_id)["orders"])

    def trade(self, account_id, body):
        a = self.account(account_id)
        action = str(
            body.get("actionType", body.get("action", ""))
        ).upper()

        symbol = str(body.get("symbol", "EURUSD")).upper()
        volume = float(body.get("volume", 0.01))

        if volume <= 0:
            raise ValueError("Trade volume must be greater than zero.")

        # Immediate market BUY / SELL.
        if action in (
            "BUY",
            "ORDER_TYPE_BUY",
            "SELL",
            "ORDER_TYPE_SELL",
        ):
            bid, ask = self.price(symbol)
            buy = action in ("BUY", "ORDER_TYPE_BUY")
            position_id = f"mock-pos-{uuid.uuid4().hex[:10]}"

            a["positions"].append({
                "id": position_id,
                "positionId": position_id,
                "symbol": symbol,
                "type": (
                    "POSITION_TYPE_BUY"
                    if buy
                    else "POSITION_TYPE_SELL"
                ),
                "volume": volume,
                "openPrice": ask if buy else bid,
                "openTime": int(time.time() * 1000),
                "stopLoss": body.get("stopLoss"),
                "takeProfit": body.get("takeProfit"),
                "comment": body.get(
                    "comment",
                    "Pips-Miner mock",
                ),
                "magic": body.get("magic", 26081501),
            })

            return {
                "stringCode": "TRADE_RETCODE_DONE",
                "numericCode": 10009,
                "orderId": f"mock-order-{uuid.uuid4().hex[:10]}",
                "positionId": position_id,
                "message": "Mock trade executed.",
            }

        # Pending BUY STOP / SELL STOP.
        if action in (
            "ORDER_TYPE_BUY_STOP",
            "ORDER_TYPE_SELL_STOP",
        ):
            open_price = body.get("openPrice")

            if open_price is None:
                raise ValueError(
                    "Pending stop order requires openPrice."
                )

            open_price = float(open_price)

            bid, ask = self.price(symbol)

            if action == "ORDER_TYPE_BUY_STOP" and open_price <= ask:
                raise ValueError(
                    "BUY STOP price must be above the current ask."
                )

            if action == "ORDER_TYPE_SELL_STOP" and open_price >= bid:
                raise ValueError(
                    "SELL STOP price must be below the current bid."
                )

            order_id = f"mock-order-{uuid.uuid4().hex[:10]}"

            a["orders"].append({
                "id": order_id,
                "orderId": order_id,
                "symbol": symbol,
                "type": action,
                "volume": volume,
                "openPrice": open_price,
                "currentPrice": bid if "SELL" in action else ask,
                "time": int(time.time() * 1000),
                "comment": body.get(
                    "comment",
                    "Pips-Miner mock stop",
                ),
                "magic": body.get("magic", 26081501),
            })

            return {
                "stringCode": "TRADE_RETCODE_DONE",
                "numericCode": 10009,
                "orderId": order_id,
                "message": "Mock stop order placed.",
            }

        # Modify pending order.
        if action == "ORDER_MODIFY":
            order_id = str(body.get("orderId", ""))
            if not order_id:
                raise ValueError(
                    "ORDER_MODIFY requires orderId."
                )

            new_price = body.get("openPrice")
            if new_price is None:
                raise ValueError(
                    "ORDER_MODIFY requires openPrice."
                )

            for order in a["orders"]:
                if order["id"] == order_id:
                    order["openPrice"] = float(new_price)
                    return {
                        "stringCode": "TRADE_RETCODE_DONE",
                        "numericCode": 10009,
                        "orderId": order_id,
                        "message": "Mock order modified.",
                    }

            raise ValueError("Mock order not found.")

        # Cancel pending order.
        if action == "ORDER_CANCEL":
            order_id = str(body.get("orderId", ""))
            before = len(a["orders"])

            a["orders"] = [
                order
                for order in a["orders"]
                if order["id"] != order_id
            ]

            if len(a["orders"]) == before:
                raise ValueError("Mock order not found.")

            return {
                "stringCode": "TRADE_RETCODE_DONE",
                "numericCode": 10009,
                "orderId": order_id,
                "message": "Mock order cancelled.",
            }

        # Close an existing position.
        if action in (
            "POSITION_CLOSE_ID",
            "CLOSE_POSITION",
        ):
            position_id = str(body.get("positionId", ""))

            before = len(a["positions"])

            a["positions"] = [
                position
                for position in a["positions"]
                if position["id"] != position_id
            ]

            if len(a["positions"]) == before:
                raise ValueError(
                    "Mock position not found."
                )

            return {
                "stringCode": "TRADE_RETCODE_DONE",
                "numericCode": 10009,
                "positionId": position_id,
                "message": "Mock position closed.",
            }

        raise ValueError(
            f"Unsupported mock trade action: "
            f"{action or 'missing'}"
        )

    def pip_distance(self, symbol):
        symbol = symbol.upper()

        # Standard FX:
        # 5-digit EURUSD -> 1 pip = 0.00010
        # 3-digit USDJPY -> 1 pip = 0.010
        if symbol.endswith("JPY"):
            return 0.01

        # Gold/crypto use a practical mock distance rather than FX pip math.
        if symbol == "XAUUSD":
            return 0.10

        if symbol == "BTCUSD":
            return 10.0

        return 0.00010

    def reversal_distance(self, symbol):
        # Pips-Miner strategy distance: 100 pips.
        return self.pip_distance(symbol) * 100

    def process_pending_orders(self, account_id):
        """
        Simulate broker-side pending-stop triggering.

        When price crosses a BUY STOP:
          - remove the pending order
          - open a BUY position
          - close any opposite managed position
          - place a new SELL STOP 100 pips below the new BUY

        When price crosses a SELL STOP:
          - remove the pending order
          - open a SELL position
          - close any opposite managed position
          - place a new BUY STOP 100 pips above the new SELL
        """
        with self.lock:
            a = self.account(account_id)

            triggered = []

            bid_ask_cache = {}

            for order in list(a["orders"]):
                symbol = order["symbol"]

                if symbol not in bid_ask_cache:
                    bid_ask_cache[symbol] = self.price(symbol)

                bid, ask = bid_ask_cache[symbol]

                order_type = order["type"]
                trigger = False
                buy = False

                if order_type == "ORDER_TYPE_BUY_STOP":
                    trigger = ask >= float(order["openPrice"])
                    buy = True

                elif order_type == "ORDER_TYPE_SELL_STOP":
                    trigger = bid <= float(order["openPrice"])
                    buy = False

                if trigger:
                    triggered.append(
                        (order, buy, bid, ask)
                    )

            results = []

            for order, buy, bid, ask in triggered:
                if order not in a["orders"]:
                    continue

                # Remove the pending order first.
                a["orders"].remove(order)

                symbol = order["symbol"]
                volume = float(order["volume"])
                magic = order.get("magic", 26081501)

                # Close opposite Pips-Miner positions.
                opposite_type = (
                    "POSITION_TYPE_SELL"
                    if buy
                    else "POSITION_TYPE_BUY"
                )

                closed_positions = []

                remaining = []

                for position in a["positions"]:
                    if (
                        position["symbol"] == symbol
                        and position["magic"] == magic
                        and position["type"] == opposite_type
                    ):
                        closed_positions.append(position["id"])
                    else:
                        remaining.append(position)

                a["positions"] = remaining

                position_id = (
                    f"mock-pos-{uuid.uuid4().hex[:10]}"
                )

                open_price = ask if buy else bid

                position = {
                    "id": position_id,
                    "positionId": position_id,
                    "symbol": symbol,
                    "type": (
                        "POSITION_TYPE_BUY"
                        if buy
                        else "POSITION_TYPE_SELL"
                    ),
                    "volume": volume,
                    "openPrice": open_price,
                    "openTime": int(time.time() * 1000),
                    "stopLoss": None,
                    "takeProfit": None,
                    "comment": "Pips-Miner reversal",
                    "magic": magic,
                }

                a["positions"].append(position)

                # Place the next opposite stop exactly 100 pips away.
                distance = self.reversal_distance(symbol)

                if buy:
                    next_type = "ORDER_TYPE_SELL_STOP"
                    next_price = round(
                        open_price - distance,
                        5 if open_price < 10 else 2,
                    )
                else:
                    next_type = "ORDER_TYPE_BUY_STOP"
                    next_price = round(
                        open_price + distance,
                        5 if open_price < 10 else 2,
                    )

                next_order_id = (
                    f"mock-order-{uuid.uuid4().hex[:10]}"
                )

                next_order = {
                    "id": next_order_id,
                    "orderId": next_order_id,
                    "symbol": symbol,
                    "type": next_type,
                    "volume": volume,
                    "openPrice": next_price,
                    "currentPrice": (
                        bid if next_type == "ORDER_TYPE_SELL_STOP"
                        else ask
                    ),
                    "time": int(time.time() * 1000),
                    "comment": "Pips-Miner 100-pip reversal",
                    "magic": magic,
                }

                a["orders"].append(next_order)

                results.append({
                    "triggeredOrderId": order["id"],
                    "newPositionId": position_id,
                    "newOrderId": next_order_id,
                    "newOrderType": next_type,
                    "newOrderPrice": next_price,
                    "closedPositions": closed_positions,
                })

            return results

    def specification(self, symbol):
        symbol = symbol.upper()
        return {
            "symbol": symbol,
            "digits": 5,
            "point": 0.00001,
            "contractSize": self.contract_size(symbol),
            "minVolume": 0.01,
            "maxVolume": 100.0,
            "volumeStep": 0.01,
        }

    def candles(self, symbol, timeframe):
        bid, _ = self.price(symbol)
        now = int(time.time())

        step = {
            "M1": 60,
            "1m": 60,
            "M5": 300,
            "5m": 300,
            "M15": 900,
            "15m": 900,
            "H1": 3600,
            "1h": 3600,
        }.get(timeframe, 60)

        result = []

        for i in range(100):
            t = now - (100 - i) * step
            wave = math.sin(t / 173) * 0.0015
            close = bid + wave
            opening = close - math.sin(t / 97) * 0.00035

            result.append({
                "time": t,
                "open": round(opening, 5),
                "high": round(max(opening, close) + 0.00025, 5),
                "low": round(min(opening, close) - 0.00025, 5),
                "close": round(close, 5),
                "tickVolume": 100 + abs(int(math.sin(t / 31) * 80)),
            })

        return result


MOCK_TRADING = MockTrading()
