import os
import asyncio
import math
from metaapi_cloud_sdk import MetaApi

SYMBOL = "XAUUSD"
LOT_SIZE = float(os.getenv("LOT_SIZE", "0.01"))
TRAIL_PIPS = float(os.getenv("TRAIL_PIPS", "100"))
def fmt_indicator(v):
    return f'{v:.2f}' if v is not None else 'N/A'

POLL_SECONDS = float(os.getenv("POLL_SECONDS", "1.0"))
VELOCITY_WINDOW = float(os.getenv("VELOCITY_WINDOW", "1.0"))
BASELINE_WINDOW = float(os.getenv("BASELINE_WINDOW", "10.0"))
EXPANSION_MULTIPLIER = float(os.getenv("EXPANSION_MULTIPLIER", "1.20"))
MIN_EXPANSION_MOVE = float(os.getenv("MIN_EXPANSION_MOVE", "0.03"))
COOLDOWN_SECONDS = float(os.getenv("COOLDOWN_SECONDS", "1.0"))
EXECUTE_ORDERS = os.getenv("EXECUTE_ORDERS", "true").lower() == "true"
LEVERAGE = float(os.getenv("LEVERAGE", "400"))
RISK_PERCENT = min(float(os.getenv("RISK_PERCENT", "5")), 5.0)
MIN_LOT = float(os.getenv("MIN_LOT", "0.01"))
MAX_LOT = float(os.getenv("MAX_LOT", "60"))
RECONNECT_DELAY = float(os.getenv("RECONNECT_DELAY", "5"))


def mid(tick):
    return (tick["bid"] + tick["ask"]) / 2


def minute(tick):
    return tick["time"].replace(second=0, microsecond=0)


def normalize_volume(raw, minimum, maximum, step):
    minimum = max(float(minimum or 0.01), MIN_LOT)
    maximum = min(float(maximum or MAX_LOT), MAX_LOT)
    step = float(step or 0.01)

    raw = max(minimum, min(float(raw), maximum))
    steps = math.floor((raw - minimum + 1e-12) / step)
    return round(max(minimum, min(minimum + steps * step, maximum)), 8)


async def get_dynamic_lot(connection, specification, price, direction="BUY"):
    """
    HARD RISK POLICY

    1. Maximum trade risk = RISK_PERCENT of balance (normally 5%).
    2. Leverage 1:400 is NOT used to force position size.
    3. Actual MetaApi margin is checked before execution.
    4. New trade may use at most MARGIN_FREE_PERCENT of free margin.
    5. Volume is always rounded DOWN to broker volumeStep.
    6. If the minimum executable volume cannot pass the checks: NO TRADE.
    """

    info = connection.terminal_state.account_information or {}

    balance = float(
        info.get("balance") or info.get("equity") or 0.0
    )
    equity = float(info.get("equity") or balance)
    free_margin = float(info.get("freeMargin") or 0.0)

    if balance <= 0 or equity <= 0:
        raise ValueError("Invalid account balance/equity")

    if free_margin <= 0:
        raise ValueError("No free margin available")

    risk_budget = balance * (RISK_PERCENT / 100.0)

    pip_size = float(
        specification.get("pipSize")
        or specification.get("point")
        or 0.01
    )

    contract_size = float(
        specification.get("contractSize")
        or specification.get("tradeContractSize")
        or 100.0
    )

    # Current strategy risk boundary: 100 pips.
    risk_distance = float(TRAIL_PIPS) * pip_size

    # XAUUSD monetary risk per 1.00 lot.
    one_lot_loss = risk_distance * contract_size

    if one_lot_loss <= 0:
        raise ValueError("Unable to calculate XAUUSD risk")

    # Risk-based maximum. This is NEVER increased because of leverage.
    risk_lot = risk_budget / one_lot_loss

    minimum = float(
        specification.get("minVolume") or MIN_LOT
    )
    maximum = float(
        specification.get("maxVolume") or MAX_LOT
    )
    step = float(
        specification.get("volumeStep") or 0.01
    )

    maximum = min(maximum, MAX_LOT)

    # Broker/account margin safety reserve.
    allowed_margin = free_margin * (MARGIN_FREE_PERCENT / 100.0)

    def normalize_down(volume):
        if volume < minimum:
            return 0.0
        volume = min(volume, maximum)
        steps = int(volume / step + 1e-9)
        return round(steps * step, 8)

    async def margin_for(volume):
        order_type = (
            "ORDER_TYPE_BUY"
            if str(direction).upper() == "BUY"
            else "ORDER_TYPE_SELL"
        )

        result = await connection.calculate_margin(
            symbol=SYMBOL,
            order_type=order_type,
            volume=volume,
            open_price=float(price)
        )

        if isinstance(result, dict):
            return float(
                result.get("margin")
                or result.get("requiredMargin")
                or 0.0
            )

        return float(getattr(result, "margin", 0.0) or 0.0)

    # Never exceed the 5% risk budget.
    lot = normalize_down(risk_lot)

    if lot <= 0:
        raise ValueError(
            f"NO TRADE: minimum lot exceeds {RISK_PERCENT}% risk budget"
        )

    # Reduce lot until BOTH risk and actual margin pass.
    while lot >= minimum:
        final_loss = lot * one_lot_loss

        if final_loss > risk_budget + 1e-8:
            lot = normalize_down(lot - step)
            continue

        required_margin = await margin_for(lot)

        if required_margin > 0 and required_margin <= allowed_margin:
            print(
                f"RISK CHECK: balance={balance:.2f} "
                f"risk_limit={risk_budget:.2f} "
                f"lot={lot:.2f} "
                f"risk={final_loss:.2f} "
                f"margin={required_margin:.2f} "
                f"free_margin={free_margin:.2f}"
            )
            return lot, equity

        lot = normalize_down(lot - step)

    raise ValueError(
        "NO TRADE: no volume satisfies both the 5% risk limit "
        "and the available-margin safety limit"
    )
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

        connection = account.get_streaming_connection()

        await connection.connect()
        await connection.wait_synchronized()

        if not connection.terminal_state.connected_to_broker:
            raise RuntimeError("MetaTrader terminal is not connected to broker")

        await connection.subscribe_to_market_data(
            symbol=SYMBOL
        )

        terminal_state = connection.terminal_state

        specification = terminal_state.specification(
            symbol=SYMBOL
        )

        if not specification:
            raise RuntimeError(
                f"No symbol specification available for {SYMBOL}"
            )

        digits = specification.get("digits", 2)
        point = specification.get("point")

        if not point:
            point = 10 ** (-digits)

        trailing_distance = TRAIL_PIPS * point

        preview_quote = None

        for _ in range(40):
            preview_quote = connection.terminal_state.price(
                symbol=SYMBOL
            )

            if (
                preview_quote
                and preview_quote.get("bid") is not None
                and preview_quote.get("ask") is not None
            ):
                break

            await asyncio.sleep(0.25)

        if not preview_quote:
            raise TimeoutError(
                f"No streaming XAUUSD quote received"
            )

        preview_price = mid(preview_quote)
        preview_direction = "BUY"
        dynamic_lot, balance, equity, risk_budget, preview_loss = await get_dynamic_lot(
            connection,
            specification,
            preview_price,
            preview_direction
        )

        print("STREAMING: CONNECTED + SYNCHRONIZED")
        print("Symbol:", SYMBOL)
        print("Account balance:", round(balance, 2))
        print("Account equity:", round(equity, 2))
        print("Leverage:", f"1:{LEVERAGE:g}")
        print("Risk limit:", f"{RISK_PERCENT:g}% =", round(risk_budget, 2))
        print("Calculated lot:", dynamic_lot)
        print("100-pip calculated risk:", round(preview_loss, 2))
        print("Trailing distance:", trailing_distance)
        print("")
        print("RULES:")
        print("NO FIXED STOP LOSS")
        print("NO FIXED TAKE PROFIT")
        print("OPPOSITE STOP = STOP LOSS + TAKE PROFIT")
        print("OPPOSITE STOP ALWAYS TRAILS")
        print("RSI: NOT USED")
        print("MOMENTUM: NOT USED")
        print("ENTRY: FAST VELOCITY EXPANSION")
        print("DIRECTION: LATEST PRICE MOVEMENT")
        print("POSITION SIZE: ACCOUNT EQUITY")
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

            try:
                tick = connection.terminal_state.price(symbol=SYMBOL)

            except Exception as e:
                error_name = type(e).__name__
                error_text = str(e)

                if (
                    "Timeout" in error_name
                    or "timeout" in error_text.lower()
                    or "not connected" in error_text.lower()
                    or "socket" in error_text.lower()
                ):
                    print("")
                    print(">>> METAAPI CONNECTION LOST <<<")
                    print("ERROR:", error_name, error_text[:300])
                    print("RECONNECTING...")

                    try:
                        await connection.close()
                    except Exception:
                        pass

                    await asyncio.sleep(RECONNECT_DELAY)

                    try:
                        connection = account.get_streaming_connection()
                        await connection.connect()
                        await connection.wait_synchronized()

                        if not connection.terminal_state.connected_to_broker:
                            raise RuntimeError(
                                "MetaTrader terminal is not connected to broker"
                            )

                        await connection.subscribe_to_market_data(
                            symbol=SYMBOL
                        )

                        terminal_state = connection.terminal_state

                        specification = terminal_state.specification(
                            symbol=SYMBOL
                        )

                        print(">>> METAAPI STREAM RECONNECTED + SYNCHRONIZED <<<")
                        print(">>> XAUUSD QUOTES RESUBSCRIBED <<<")
                        print("XAUUSD ENGINE RESUMED")
                        continue

                    except Exception as reconnect_error:
                        print(
                            "RECONNECT FAILED:",
                            type(reconnect_error).__name__,
                            str(reconnect_error)[:300]
                        )
                        await asyncio.sleep(RECONNECT_DELAY)
                        continue

                raise

            now = asyncio.get_running_loop().time()
            price = mid(tick)
            current_price = price

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

            latest_delta = samples[-1][1] - samples[-2][1]
            direction_velocity = latest_delta if latest_delta != 0 else velocity

            direction = (
                "BUY"
                if direction_velocity > 0
                else "SELL"
                if direction_velocity < 0
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

                        lot, _, _, _, _ = await get_dynamic_lot(
                            connection,
                            specification,
                            price,
                            "SELL"
                        )

                        if EXECUTE_ORDERS:

                            positions = list(terminal_state.positions)

                            for pos in positions:
                                if pos.get("symbol") == SYMBOL:
                                    await connection.close_position(
                                        pos["id"]
                                    )

                            await connection.create_market_sell_order(
                                SYMBOL,
                                lot
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

                        lot, _, _, _, _ = await get_dynamic_lot(
                            connection,
                            specification,
                            price,
                            "BUY"
                        )

                        if EXECUTE_ORDERS:

                            positions = list(terminal_state.positions)

                            for pos in positions:
                                if pos.get("symbol") == SYMBOL:
                                    await connection.close_position(
                                        pos["id"]
                                    )

                            await connection.create_market_buy_order(
                                SYMBOL,
                                lot
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
                    baseline * 0.95,
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

                    lot, balance, equity, risk_budget, risk_loss = await get_dynamic_lot(
                        connection,
                        specification,
                        entry_price,
                        direction
                    )

                    print("ACCOUNT BALANCE:", round(balance, 2))
                    print("ACCOUNT EQUITY:", round(equity, 2))
                    print("LEVERAGE:", f"1:{LEVERAGE:g}")
                    print("POSITION SIZE:", lot)
                    print("RISK LIMIT:", round(risk_budget, 2))
                    print("CALCULATED 100-PIP LOSS:", round(risk_loss, 2))

                    if EXECUTE_ORDERS:

                        if direction == "BUY":

                            result = (
                                await connection
                                .create_market_buy_order(
                                    SYMBOL,
                                    lot
                                )
                            )

                        else:

                            result = (
                                await connection
                                .create_market_sell_order(
                                    SYMBOL,
                                    lot
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
