import os
import asyncio
from datetime import datetime, timezone
from metaapi_cloud_sdk import MetaApi

SYMBOL = "XAUUSD"
TIMEFRAME = "1m"
RECONNECT_DELAY = 5
TICK_TIMEOUT = 15


def minute_key(dt):
    return dt.replace(second=0, microsecond=0)


def update_candle(candle, tick):
    price = (tick["bid"] + tick["ask"]) / 2

    if candle is None:
        t = minute_key(tick["time"])

        return {
            "time": t,
            "open": price,
            "high": price,
            "low": price,
            "close": price,
            "volume": 1
        }

    candle["high"] = max(candle["high"], price)
    candle["low"] = min(candle["low"], price)
    candle["close"] = price
    candle["volume"] += 1

    return candle


def print_candle(c):
    print(
        f"{c['time']} "
        f"O:{c['open']:.2f} "
        f"H:{c['high']:.2f} "
        f"L:{c['low']:.2f} "
        f"C:{c['close']:.2f} "
        f"V:{c['volume']}"
    )


async def connect_account(api):
    account = await api.metatrader_account_api.get_account(
        os.environ["METAAPI_ACCOUNT_ID"]
    )

    connection = account.get_rpc_connection()

    print("\nConnecting to MetaAPI...")
    await connection.connect()

    print("Waiting for synchronization...")
    await connection.wait_synchronized()

    print("CONNECTED + SYNCHRONIZED")

    return connection


async def collect():
    api = MetaApi(os.environ["METAAPI_TOKEN"])

    completed = []
    current = None

    try:
        while True:
            connection = None

            try:
                connection = await connect_account(api)

                print("\n=== XAUUSD TICK → M1 ENGINE ===")
                print("Building M1 candles locally from live ticks.\n")

                while True:
                    tick = await asyncio.wait_for(
                        connection.get_tick(
                            SYMBOL,
                            keep_subscription=True
                        ),
                        timeout=TICK_TIMEOUT
                    )

                    tick_time = tick["time"]
                    key = minute_key(tick_time)

                    if current is None:
                        current = update_candle(None, tick)
                        continue

                    current_key = current["time"]

                    if key == current_key:
                        current = update_candle(current, tick)

                    elif key > current_key:
                        print_candle(current)

                        completed.append(current)

                        if len(completed) > 100:
                            completed.pop(0)

                        print(
                            f"Completed M1 candles: "
                            f"{len(completed)}"
                        )

                        current = update_candle(None, tick)

                    else:
                        # Ignore an out-of-order tick.
                        continue

            except asyncio.TimeoutError:
                print(
                    "\n[RECONNECT] Tick stream timed out."
                )

            except Exception as e:
                print(
                    f"\n[RECONNECT] "
                    f"{type(e).__name__}: {str(e)[:300]}"
                )

            finally:
                if connection:
                    try:
                        await connection.close()
                    except Exception:
                        pass

            print(
                f"Waiting {RECONNECT_DELAY}s "
                f"before reconnecting..."
            )

            await asyncio.sleep(RECONNECT_DELAY)

    finally:
        try:
            api.close()
        except Exception:
            pass


asyncio.run(collect())

