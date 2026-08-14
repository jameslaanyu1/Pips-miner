import os
import asyncio
from metaapi_cloud_sdk import MetaApi

SYMBOL = "XAUUSD"
LOT_SIZE = float(os.getenv("LOT_SIZE", "0.01"))
TRAIL_PIPS = float(os.getenv("TRAIL_PIPS", "50"))
def fmt_indicator(v):
    return f'{v:.2f}' if v is not None else 'N/A'

DEMO_ONLY = os.getenv("DEMO_ONLY", "true").lower() == "true"
POLL_SECONDS = float(os.getenv("POLL_SECONDS", "1.0"))


def mid(tick):
    return (tick["bid"] + tick["ask"]) / 2


def minute(tick):
    return tick["time"].replace(second=0, microsecond=0)


def rsi(closes, period=14):
    if len(closes) < period + 1:
        return None

    changes = [
        closes[i] - closes[i - 1]
        for i in range(1, len(closes))
    ]

    gains = [max(x, 0) for x in changes[-period:]]
    losses = [max(-x, 0) for x in changes[-period:]]

    avg_gain = sum(gains) / period
    avg_loss = sum(losses) / period

    if avg_loss == 0:
        return 100.0

    rs = avg_gain / avg_loss
    return 100 - (100 / (1 + rs))


async def main():

    if not DEMO_ONLY:
        raise RuntimeError(
            "DEMO_ONLY must remain true for this demo build."
        )

    token = os.environ["METAAPI_TOKEN"]
    account_id = os.environ["METAAPI_ACCOUNT_ID"]

    api = MetaApi(token)

    try:
        account = await api.metatrader_account_api.get_account(
            account_id
        )

        print("========================================")
        print(" PIP-LIFE XAUUSD M1 DEMO ENGINE")
        print("========================================")
        print("Account:", account.name)
        print("Server:", account.server)
        print("Region:", account.region)
        print("Connection:", account.connection_status)

        if account.connection_status != "CONNECTED":
            raise RuntimeError(
                "MetaApi account is not connected."
            )

        connection = account.get_rpc_connection()

        await connection.connect()
        await connection.wait_synchronized()

        specification = await connection.get_symbol_specification(
            SYMBOL
        )

        digits = specification.get("digits", 2)
        point = specification.get("point")

        if not point:
            point = 10 ** (-digits)

        trailing_distance = TRAIL_PIPS * point

        print("RPC: CONNECTED")
        print("Symbol:", SYMBOL)
        print("Lot:", LOT_SIZE)
        print("Trailing distance:", trailing_distance)
        print("")
        print("RULES:")
        print("NO FIXED STOP LOSS")
        print("NO FIXED TAKE PROFIT")
        print("OPPOSITE STOP = STOP LOSS + TAKE PROFIT")
        print("OPPOSITE STOP ALWAYS TRAILS")
        print("DEMO SAFETY MODE: NO ORDERS SENT")
        print("========================================")

        candles = []
        current = None

        while True:

            tick = await connection.get_tick(
                SYMBOL,
                keep_subscription=True
            )

            price = mid(tick)
            candle_time = minute(tick)

            if current is None:

                current = {
                    "time": candle_time,
                    "open": price,
                    "high": price,
                    "low": price,
                    "close": price
                }

                continue

            if candle_time == current["time"]:

                current["high"] = max(
                    current["high"],
                    price
                )

                current["low"] = min(
                    current["low"],
                    price
                )

                current["close"] = price

                continue

            if candle_time < current["time"]:
                continue

            candles.append(current)

            candles = candles[-60:]

            print(
                f"M1 {current['time']} "
                f"O:{current['open']:.2f} "
                f"H:{current['high']:.2f} "
                f"L:{current['low']:.2f} "
                f"C:{current['close']:.2f}"
            )

            current = {
                "time": candle_time,
                "open": price,
                "high": price,
                "low": price,
                "close": price
            }

            # IMMEDIATE MOMENTUM ENTRY
            # Do not wait for 16 candles.
            # The first directional close-to-close movement
            # establishes the immediate momentum direction.

            if len(candles) < 2:
                continue

            closes = [
                candle["close"]
                for candle in candles
            ]

            recent = candles[-min(14, len(candles)):]

            atr = sum(
                candle["high"] - candle["low"]
                for candle in recent
            ) / len(recent)

            momentum = rsi(closes)

            direction = None

            price_momentum = closes[-1] - closes[-2]

            if price_momentum > 0 and atr > 0:
                direction = "BUY"

            elif price_momentum < 0 and atr > 0:
                direction = "SELL"

            momentum_display = f"{momentum:.2f}" if momentum is not None else "N/A"

            print(
                f"SIGNAL "
                f"PRICE={price:.2f} "
                f"ATR={atr:.2f} "
                f"RSI={momentum_display} "
                f"BIAS={direction or 'NONE'}"
            )

            if direction:

                if direction == "BUY":

                    entry = tick["ask"]
                    opposite = "SELL STOP"
                    stop = entry - trailing_distance

                else:

                    entry = tick["bid"]
                    opposite = "BUY STOP"
                    stop = entry + trailing_distance

                print("")
                print(">>> DEMO TRADE SIGNAL <<<")
                print("Direction:", direction)
                print("Volume:", LOT_SIZE)
                print("Entry:", round(entry, digits))
                print(
                    "Opposite order:",
                    opposite
                )
                print(
                    "Trailing stop:",
                    round(stop, digits)
                )
                print(
                    "Role: EXIT + REVERSAL"
                )
                print("ORDER SENT: NO")
                print("")

            await asyncio.sleep(POLL_SECONDS)

    finally:

        try:
            await connection.close()
        except Exception:
            pass

        api.close()


if __name__ == "__main__":
    asyncio.run(main())
