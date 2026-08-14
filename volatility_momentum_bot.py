def trading_session_allowed(specification, now):
    sessions = specification.get("tradeSessions", {})
    day = now.strftime("%A").upper()
    session = sessions.get(day, [])

    if not session:
        return False

    start = session[0]["from"][:8]
    end = session[0]["to"][:8]

    start_time = datetime.strptime(start, "%H:%M:%S").time()
    end_time = datetime.strptime(end, "%H:%M:%S").time()

    current = now.time()

    start_seconds = (
        start_time.hour * 3600
        + start_time.minute * 60
        + start_time.second
        + 7200
    )

    end_seconds = (
        end_time.hour * 3600
        + end_time.minute * 60
        + end_time.second
        - 7200
    )

    current_seconds = (
        current.hour * 3600
        + current.minute * 60
        + current.second
    )

    return start_seconds <= current_seconds <= end_seconds
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
RISK_PERCENT = 1.0
MAX_TOTAL_RISK_PERCENT = 5.0
MAX_POSITIONS = 5
MARGIN_FREE_PERCENT = 50.0

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


async def get_dynamic_lot(
    connection,
    specification,
    price,
    direction="BUY",
    replacing_position=False
):
    """
    COMPOUNDING RISK POLICY

    Each NEW position:
        Maximum risk = 1% of CURRENT account balance.

    Portfolio:
        Maximum aggregate theoretical risk = 5% of CURRENT balance.

    Therefore:
        Up to 5 x 1% positions may be open when margin permits.

    Position size:
        Recalculated from current balance for every new entry.

    Leverage:
        Never used to increase risk or force lot size.

    Safety:
        Required MetaApi margin must be <= 50% of free margin.
        Failure of any risk/margin calculation = NO TRADE.
    """

    info = connection.terminal_state.account_information or {}

    balance = float(
        info.get("balance") or 0.0
    )
    equity = float(
        info.get("equity") or balance
    )
    free_margin = float(
        info.get("freeMargin") or 0.0
    )

    if balance <= 0 or equity <= 0:
        raise ValueError(
            "NO TRADE: invalid account balance/equity"
        )

    if free_margin <= 0:
        raise ValueError(
            "NO TRADE: no free margin"
        )

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

    risk_distance = float(TRAIL_PIPS) * pip_size

    one_lot_loss = risk_distance * contract_size

    if one_lot_loss <= 0:
        raise ValueError(
            "NO TRADE: invalid XAUUSD risk calculation"
        )

    # 1% risk for this new position.
    position_risk_budget = (
        balance * RISK_PERCENT / 100.0
    )

    # Maximum total theoretical risk across XAUUSD positions.
    total_risk_budget = (
        balance * MAX_TOTAL_RISK_PERCENT / 100.0
    )

    positions = [
        pos for pos in connection.terminal_state.positions
        if pos.get("symbol") == SYMBOL
    ]

    current_open_risk = 0.0

    for pos in positions:
        try:
            volume = float(pos.get("volume") or 0.0)
            current_open_risk += volume * one_lot_loss
        except Exception:
            continue

    # During a reversal the existing position is about to be closed,
    # so don't let it consume the new position's risk allowance.
    if replacing_position:
        current_open_risk = 0.0

    remaining_total_risk = (
        total_risk_budget - current_open_risk
    )

    if remaining_total_risk <= 0:
        raise ValueError(
            "NO TRADE: aggregate 5% account-risk limit reached"
        )

    risk_budget = min(
        position_risk_budget,
        remaining_total_risk
    )

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

    if step <= 0:
        raise ValueError(
            "NO TRADE: invalid broker volume step"
        )

    allowed_margin = (
        free_margin *
        (MARGIN_FREE_PERCENT / 100.0)
    )

    def normalize_down(volume):
        if volume < minimum:
            return 0.0

        volume = min(volume, maximum)

        steps = math.floor(
            volume / step + 1e-12
        )

        normalized = steps * step

        if normalized < minimum:
            return 0.0

        return round(
            min(normalized, maximum),
            8
        )

    async def margin_for(volume):
        order_type = (
            "ORDER_TYPE_BUY"
            if str(direction).upper() == "BUY"
            else "ORDER_TYPE_SELL"
        )

        try:
            result = await connection.calculate_margin(
                {
                    "symbol": SYMBOL,
                    "type": order_type,
                    "volume": volume,
                    "openPrice": float(price)
                }
            )
        except Exception as exc:
            raise ValueError(
                f"NO TRADE: MetaApi margin check failed: {exc}"
            )

        if isinstance(result, dict):
            margin = (
                result.get("margin")
                or result.get("requiredMargin")
            )
        else:
            margin = getattr(
                result,
                "margin",
                None
            )

        if margin is None:
            raise ValueError(
                "NO TRADE: MetaApi returned no margin value"
            )

        margin = float(margin)

        if margin <= 0:
            raise ValueError(
                "NO TRADE: invalid MetaApi margin"
            )

        return margin

    lot = normalize_down(
        risk_budget / one_lot_loss
    )

    if lot <= 0:
        raise ValueError(
            "NO TRADE: 1% risk is below broker minimum lot"
        )

    # Find the largest lot satisfying BOTH:
    #   1. 1% position-risk limit
    #   2. 50% free-margin safety limit
    #
    # Use binary search instead of reducing by 0.01 lots repeatedly.
    # This dramatically reduces MetaApi margin requests.

    low = minimum
    high = lot
    best_lot = 0.0
    best_margin = None

    while low <= high + step / 2:
        candidate = normalize_down(
            (low + high) / 2
        )

        if candidate < minimum:
            break

        projected_risk = (
            candidate * one_lot_loss
        )

        if projected_risk > risk_budget + 1e-8:
            high = normalize_down(
                candidate - step
            )
            continue

        required_margin = await margin_for(candidate)

        if required_margin <= allowed_margin:
            best_lot = candidate
            best_margin = required_margin
            low = normalize_down(
                candidate + step
            )
        else:
            print(
                f"RISK REDUCTION: lot={candidate:.2f} "
                f"margin={required_margin:.2f} "
                f"allowed={allowed_margin:.2f}"
            )
            high = normalize_down(
                candidate - step
            )

    if best_lot >= minimum:

        lot = best_lot
        required_margin = best_margin
        projected_risk = lot * one_lot_loss

        if required_margin <= allowed_margin:

            print("=== COMPOUNDING RISK CHECK PASSED ===")
            print(
                f"Balance: {balance:.2f}"
            )
            print(
                f"Equity: {equity:.2f}"
            )
            print(
                f"Position risk: {RISK_PERCENT:.2f}%"
            )
            print(
                f"Position risk budget: {position_risk_budget:.2f}"
            )
            print(
                f"Existing XAUUSD risk: {current_open_risk:.2f}"
            )
            print(
                f"Total risk ceiling: "
                f"{MAX_TOTAL_RISK_PERCENT:.2f}%"
            )
            print(
                f"Remaining risk: {remaining_total_risk:.2f}"
            )
            print(
                f"Approved lot: {lot:.2f}"
            )
            print(
                f"Projected position risk: "
                f"{projected_risk:.2f}"
            )
            print(
                f"Required margin: "
                f"{required_margin:.2f}"
            )
            print(
                f"Allowed margin: "
                f"{allowed_margin:.2f}"
            )
            print("========================================")

            return (
                lot,
                balance,
                equity,
                risk_budget,
                projected_risk
            )

        print(
            f"RISK REDUCTION: lot={lot:.2f} "
            f"margin={required_margin:.2f} "
            f"allowed={allowed_margin:.2f}"
        )

        lot = normalize_down(
            lot - step
        )

    raise ValueError(
        "NO TRADE: no lot satisfies the 1% position-risk "
        "and 50% free-margin limits"
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

        connection = account.get_streaming_connection()

        broker_ready = False
        last_connection_error = None

        for attempt in range(1, 7):
            try:
                print(f">>> STREAM STARTUP ATTEMPT {attempt}/6 <<<")
                await connection.connect()
                await connection.wait_synchronized()

                if connection.terminal_state.connected_to_broker:
                    broker_ready = True
                    print(">>> BROKER CONNECTED + SYNCHRONIZED <<<")
                    break

                print(">>> WAITING FOR BROKER CONNECTION <<<")

            except Exception as exc:
                last_connection_error = exc
                print(
                    f">>> STREAM STARTUP RETRY: "
                    f"{type(exc).__name__}: {exc} <<<"
                )

            await asyncio.sleep(10)

        if not broker_ready:
            raise RuntimeError(
                "MetaTrader broker connection did not become ready: "
                f"{last_connection_error}"
            )

        subscribed = False
        last_subscription_error = None

        for attempt in range(1, 7):
            try:
                print(
                    f">>> MARKET-DATA SUBSCRIPTION ATTEMPT "
                    f"{attempt}/6 <<<"
                )

                await connection.subscribe_to_market_data(
                    symbol=SYMBOL
                )

                subscribed = True
                print(">>> MARKET-DATA SUBSCRIBED <<<")
                break

            except Exception as exc:
                last_subscription_error = exc
                print(
                    f">>> SUBSCRIPTION RETRY: "
                    f"{type(exc).__name__}: {exc} <<<"
                )

                await asyncio.sleep(10)

        if not subscribed:
            raise RuntimeError(
                "XAUUSD market-data subscription failed after retries: "
                f"{last_subscription_error}"
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
        print("Risk per position:", f"{RISK_PERCENT:g}% =", round(risk_budget, 2))
        print("Maximum total open risk:", f"{MAX_TOTAL_RISK_PERCENT:g}%")
        print("Maximum positions:", MAX_POSITIONS)
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

            # =====================================================
            # EXIT MANAGEMENT IS OWNED BY broker_reversal_manager.py
            # =====================================================
            #
            # This velocity bot does NOT reverse positions itself.
            #
            # Entry remains:
            #     FAST VELOCITY EXPANSION
            #
            # Exit is handled externally by the broker state machine:
            #     BUY  -> SELL STOP = current BID - trailing distance
            #     SELL -> BUY STOP  = current ASK + trailing distance
            #
            # The opposite stop trails favorable price movement.
            # When triggered:
            #     1. old parent is closed;
            #     2. triggered position becomes the new running position;
            #     3. the new position receives its own opposite stop.
            #
            # =====================================================

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
    expansion
    and direction
    and expansion_armed
    and trading_session_allowed(specification, now)
                and now - last_signal_time >= COOLDOWN_SECONDS
                and len([
                    p for p in terminal_state.positions
                    if p.get("symbol") == SYMBOL
                ]) < MAX_POSITIONS
                and (
                    not [
                        p for p in terminal_state.positions
                        if p.get("symbol") == SYMBOL
                    ]
                    or all(
                        (
                            "BUY" in str(p.get("type", "")).upper()
                            if direction == "BUY"
                            else "SELL" in str(p.get("type", "")).upper()
                        )
                        for p in terminal_state.positions
                        if p.get("symbol") == SYMBOL
                    )
                )
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
