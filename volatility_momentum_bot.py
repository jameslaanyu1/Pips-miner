import os
import asyncio
from metaapi_cloud_sdk import MetaApi

SYMBOL = "XAUUSD"
LOT_SIZE = float(os.getenv("LOT_SIZE", "0.01"))
TRAIL_PIPS = float(os.getenv("TRAIL_PIPS", "30"))
def fmt_indicator(v):
    return f'{v:.2f}' if v is not None else 'N/A'

POLL_SECONDS = float(os.getenv("POLL_SECONDS", "1.0"))
VELOCITY_WINDOW = float(os.getenv("VELOCITY_WINDOW", "1.0"))
BASELINE_WINDOW = float(os.getenv("BASELINE_WINDOW", "10.0"))
EXPANSION_MULTIPLIER = float(os.getenv("EXPANSION_MULTIPLIER", "1.20"))
MIN_EXPANSION_MOVE = float(os.getenv("MIN_EXPANSION_MOVE", "0.03"))
COOLDOWN_SECONDS = float(os.getenv("COOLDOWN_SECONDS", "1.0"))
EXECUTE_ORDERS = os.getenv("EXECUTE_ORDERS", "true").lower() == "true"


def mid(tick):
    return (tick["bid"] + tick["ask"]) / 2


def minute(tick):
    return tick["time"].replace(second=0, microsecond=0)


async def main():

    token = os.environ["METAAPI_TOKEN"]
    account_id = os.environ["METAAPI_ACCOUNT_ID"]

    api = MetaApi(token)

    try:
        account = await api.metatrader_account_api.get_account(
            account_id
        )

        print("========================================")
        print(" PIPS-MINER XAUUSD M1 VELOCITY ENGINE")
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
        print("RSI: NOT USED")
        print("MOMENTUM: NOT USED")
        print("ENTRY: IMMEDIATE VELOCITY EXPANSION")
        print("ORDERS ENABLED:", EXECUTE_ORDERS)
        print("========================================")

        from collections import deque
        samples = deque(maxlen=240)

        position = None
        entry_price = None
        reversal_level = None
        last_signal_time = 0.0
        expansion_armed = True

        while True:

            tick = await connection.get_tick(
                SYMBOL,
                keep_subscription=True
            )

            now = asyncio.get_running_loop().time()
            price = mid(tick)

            samples.append((now, price))

            cutoff = now - BASELINE_WINDOW

            while samples and samples[0][0] < cutoff:
                samples.popleft()

            if len(samples) < 3:
                await asyncio.sleep(POLL_SECONDS)
                continue

            window_start = now - VELOCITY_WINDOW
            anchor = samples[0]

            for sample in samples:
                if sample[0] >= window_start:
                    anchor = sample
                    break

            elapsed = now - anchor[0]

            if elapsed <= 0:
                await asyncio.sleep(POLL_SECONDS)
                continue

            move = price - anchor[1]
            velocity = move / elapsed
            abs_velocity = abs(velocity)

            velocities = []

            previous_t, previous_p = samples[0]

            for t, p_now in list(samples)[1:]:

                dt = t - previous_t

                if dt > 0:

                    age = now - t

                    if VELOCITY_WINDOW < age <= BASELINE_WINDOW:
                        velocities.append(
                            abs((p_now - previous_p) / dt)
                        )

                previous_t = t
                previous_p = p_now

            baseline = (
                sum(velocities) / len(velocities)
                if velocities else 0.0
            )

            expansion = (
                baseline > 0
                and abs_velocity >= baseline * EXPANSION_MULTIPLIER
                and abs(move) >= MIN_EXPANSION_MOVE
            )

            direction = (
                "BUY"
                if velocity > 0
                else "SELL"
                if velocity < 0
                else None
            )

            print(
                f"VELOCITY "
                f"PRICE={price:.{digits}f} "
                f"MOVE={move:.{digits}f} "
                f"V={velocity:.{digits+2}f}/s "
                f"BASE={baseline:.{digits+2}f}/s "
                f"EXPANSION={'YES' if expansion else 'NO'}"
            )

            if position == "BUY":

                candidate = price - trailing_distance

                if reversal_level is None:
                    reversal_level = entry_price - trailing_distance

                reversal_level = max(
                    reversal_level,
                    candidate
                )

                if price <= reversal_level:

                    print(
                        f"REVERSAL BUY -> SELL "
                        f"@ {price:.{digits}f}"
                    )

                    try:

                        if EXECUTE_ORDERS:

                            positions = await connection.get_positions()

                            for pos in positions:
                                if pos.get("symbol") == SYMBOL:
                                    await connection.close_position(
                                        pos["id"]
                                    )

                            await connection.create_market_sell_order(
                                SYMBOL,
                                LOT_SIZE
                            )

                        position = "SELL"
                        entry_price = price
                        reversal_level = (
                            price + trailing_distance
                        )
                        expansion_armed = False

                    except Exception as e:
                        print(
                            "REVERSAL ERROR:",
                            type(e).__name__,
                            str(e)
                        )

            elif position == "SELL":

                candidate = price + trailing_distance

                if reversal_level is None:
                    reversal_level = entry_price + trailing_distance

                reversal_level = min(
                    reversal_level,
                    candidate
                )

                if price >= reversal_level:

                    print(
                        f"REVERSAL SELL -> BUY "
                        f"@ {price:.{digits}f}"
                    )

                    try:

                        if EXECUTE_ORDERS:

                            positions = await connection.get_positions()

                            for pos in positions:
                                if pos.get("symbol") == SYMBOL:
                                    await connection.close_position(
                                        pos["id"]
                                    )

                            await connection.create_market_buy_order(
                                SYMBOL,
                                LOT_SIZE
                            )

                        position = "BUY"
                        entry_price = price
                        reversal_level = (
                            price - trailing_distance
                        )
                        expansion_armed = False

                    except Exception as e:
                        print(
                            "REVERSAL ERROR:",
                            type(e).__name__,
                            str(e)
                        )

            if (
                not expansion
                and abs_velocity <
                max(
                    baseline *
                    (EXPANSION_MULTIPLIER * 0.75),
                    1e-12
                )
            ):
                expansion_armed = True

            if (
                position is None
                and expansion
                and direction
                and expansion_armed
                and now - last_signal_time >= COOLDOWN_SECONDS
            ):

                entry_price = (
                    float(tick["ask"])
                    if direction == "BUY"
                    else float(tick["bid"])
                )

                reversal_level = (
                    entry_price - trailing_distance
                    if direction == "BUY"
                    else entry_price + trailing_distance
                )

                print("")
                print(">>> VELOCITY EXPANSION ENTRY <<<")
                print("DIRECTION:", direction)
                print("ENTRY:", round(entry_price, digits))
                print("VELOCITY:", velocity)
                print("BASELINE:", baseline)
                print(
                    "REVERSAL LEVEL:",
                    round(reversal_level, digits)
                )

                try:

                    if EXECUTE_ORDERS:

                        if direction == "BUY":

                            result = (
                                await connection
                                .create_market_buy_order(
                                    SYMBOL,
                                    LOT_SIZE
                                )
                            )

                        else:

                            result = (
                                await connection
                                .create_market_sell_order(
                                    SYMBOL,
                                    LOT_SIZE
                                )
                            )

                        print("ORDER SENT: YES")
                        print("ORDER RESULT:", result)

                    else:

                        print(
                            "ORDER SENT: NO "
                            "(EXECUTE_ORDERS=false)"
                        )

                    position = direction
                    last_signal_time = now
                    expansion_armed = False

                except Exception as e:

                    print(
                        "ENTRY ORDER ERROR:",
                        type(e).__name__,
                        str(e)
                    )

                    position = None
                    entry_price = None
                    reversal_level = None

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
