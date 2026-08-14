import os
import asyncio
import json
import time
from datetime import datetime, timezone
from metaapi_cloud_sdk import MetaApi

TOKEN = os.environ["METAAPI_TOKEN"]
ACCOUNT_ID = os.environ["METAAPI_ACCOUNT_ID"]

SYMBOL = os.getenv("SYMBOL", "XAUUSD")
EXECUTE_ORDERS = os.getenv("EXECUTE_ORDERS", "false").lower() == "true"

TRAIL_PIPS = float(os.getenv("TRAIL_PIPS", "100"))
POINT = float(os.getenv("POINT", "0.01"))
TRAIL_DISTANCE = TRAIL_PIPS * POINT

POLL_SECONDS = float(os.getenv("POLL_SECONDS", "1"))
TRADE_DELAY_SECONDS = float(os.getenv("TRADE_DELAY_SECONDS", "1"))
MAX_TRADE_ACTIONS_PER_CYCLE = int(os.getenv("MAX_TRADE_ACTIONS_PER_CYCLE", "1"))
CREATE_CONFIRM_TIMEOUT = float(os.getenv("CREATE_CONFIRM_TIMEOUT", "10"))
STATE_FILE = os.getenv("REVERSAL_STATE_FILE", ".reversal_manager_state.json")

COMMENT_PREFIX = "PIPS_REVERSAL_PARENT:"
MAGIC = 26081401


def now():
    return datetime.now(timezone.utc).isoformat()


def load_state():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            state = json.load(f)
        return {
            "pending": dict(state.get("pending", {})),
            "processed": list(state.get("processed", [])),
        }
    except Exception:
        return {"pending": {}, "processed": []}


def save_state(state):
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, STATE_FILE)


def parent_id_from_comment(comment):
    if not comment or COMMENT_PREFIX not in comment:
        return None

    return comment.split(COMMENT_PREFIX, 1)[1].split()[0]


def is_reversal_order(order):
    comment = order.get("comment", "")
    magic = order.get("magic")

    if COMMENT_PREFIX in comment:
        return True

    try:
        return int(magic) == MAGIC
    except Exception:
        return False


def order_parent_id(order):
    return parent_id_from_comment(order.get("comment", ""))


def pending_type_for(position):
    direction = position.get("type", "")

    if direction == "POSITION_TYPE_SELL":
        return "ORDER_TYPE_BUY_STOP"

    if direction == "POSITION_TYPE_BUY":
        return "ORDER_TYPE_SELL_STOP"

    return None


def desired_stop(position, price):
    """
    ALWAYS calculate the stop from CURRENT market price.

    SELL:
        BUY STOP = current ASK + 100 pips

    BUY:
        SELL STOP = current BID - 100 pips
    """

    direction = position.get("type", "")

    if direction == "POSITION_TYPE_SELL":
        return price["ask"] + TRAIL_DISTANCE

    if direction == "POSITION_TYPE_BUY":
        return price["bid"] - TRAIL_DISTANCE

    return None


def should_trail(direction, old_stop, target_stop):
    """
    Ratchet only.

    SELL parent:
        price falling -> BUY STOP moves DOWN.
        price rising  -> BUY STOP stays where it is.

    BUY parent:
        price rising  -> SELL STOP moves UP.
        price falling -> SELL STOP stays where it is.
    """

    if old_stop is None:
        return True

    if direction == "POSITION_TYPE_SELL":
        return target_stop < old_stop - (POINT / 2)

    if direction == "POSITION_TYPE_BUY":
        return target_stop > old_stop + (POINT / 2)

    return False


async def get_price(connection):
    price = await connection.get_symbol_price(SYMBOL)

    return {
        "bid": float(price["bid"]),
        "ask": float(price["ask"]),
    }


async def create_reversal(connection, position, stop_price, state):
    parent_id = str(position["id"])
    volume = float(position["volume"])
    order_type = pending_type_for(position)

    comment = f"{COMMENT_PREFIX}{parent_id}"

    print(
        f">>> CREATE REVERSAL "
        f"parent={parent_id} "
        f"type={order_type} "
        f"volume={volume} "
        f"stop={stop_price:.2f}"
    )

    if not EXECUTE_ORDERS:
        print(
            f">>> DRY RUN: WOULD CREATE "
            f"{order_type} "
            f"parent={parent_id} "
            f"volume={volume} "
            f"price={stop_price:.2f}"
        )
        return None

    options = {
        "comment": comment,
        "magic": MAGIC,
    }

    if order_type == "ORDER_TYPE_BUY_STOP":
        result = await connection.create_stop_buy_order(
            SYMBOL,
            volume,
            stop_price,
            None,
            None,
            options,
        )
    else:
        result = await connection.create_stop_sell_order(
            SYMBOL,
            volume,
            stop_price,
            None,
            None,
            options,
        )

    order_id = None

    if isinstance(result, dict):
        order_id = result.get("orderId") or result.get("id")
    else:
        order_id = (
            getattr(result, "orderId", None)
            or getattr(result, "id", None)
        )

    # IMPORTANT:
    # Keep the submission pending until broker state confirms it.
    # This prevents duplicate creation while MetaApi is synchronizing.
    state["pending"][parent_id] = {
        "created_at": time.time(),
        "order_id": str(order_id) if order_id else None,
    }
    save_state(state)

    print(
        f">>> OPPOSITE STOP SUBMITTED "
        f"parent={parent_id} "
        f"order={order_id}"
    )

    return result


async def modify_reversal(connection, order, new_price):
    order_id = order["id"]
    parent_id = order_parent_id(order)

    old_price = float(
        order.get("openPrice")
        or order.get("currentPrice")
        or 0
    )

    if abs(new_price - old_price) < POINT / 2:
        return False

    print(
        f">>> TRAIL REVERSAL "
        f"parent={parent_id} "
        f"order={order_id} "
        f"{old_price:.2f} -> {new_price:.2f}"
    )

    if not EXECUTE_ORDERS:
        print(
            f">>> DRY RUN: WOULD MODIFY "
            f"order={order_id} "
            f"price={new_price:.2f}"
        )
        return True

    await connection.modify_order(
        order_id,
        {
            "openPrice": new_price,
        },
    )

    return True


async def cancel_reversal(connection, order):
    order_id = order["id"]
    parent_id = order_parent_id(order)

    print(
        f">>> CANCEL ORPHAN/DUPLICATE "
        f"parent={parent_id} "
        f"order={order_id}"
    )

    if not EXECUTE_ORDERS:
        print(
            f">>> DRY RUN: WOULD CANCEL "
            f"order={order_id}"
        )
        return

    await connection.cancel_order(order_id)


async def process_triggered_stops(
    connection,
    reversal_orders,
    positions_by_id,
    state,
):
    """
    A filled opposite stop becomes the new running position.

    Therefore:
      1. detect the filled reversal order;
      2. close its OLD parent position;
      3. remove the old parent/stop relationship;
      4. next reconciliation cycle sees the NEW position;
      5. the NEW position receives its own opposite stop.
    """

    live_order_ids = {
        str(order["id"])
        for order in reversal_orders
    }

    actions = 0

    for parent_id, info in list(
        state["pending"].items()
    ):

        order_id = info.get("order_id")

        if not order_id:
            continue

        if str(order_id) in live_order_ids:
            continue

        try:
            history = await connection.get_history_orders_by_ticket(
                str(order_id)
            )
        except Exception as exc:
            print(
                f">>> HISTORY CHECK ERROR "
                f"order={order_id}: "
                f"{type(exc).__name__}: {exc}"
            )
            continue

        if not history:

            # Broker has not confirmed the order yet.
            # Keep it pending for the confirmation window.
            if (
                time.time()
                - float(info.get("created_at", 0))
                > CREATE_CONFIRM_TIMEOUT
            ):
                state["pending"].pop(parent_id, None)
                save_state(state)

            continue

        filled = [
            h
            for h in history
            if h.get("state") == "ORDER_STATE_FILLED"
        ]

        if not filled:

            # Cancelled/rejected/expired.
            state["pending"].pop(parent_id, None)
            save_state(state)
            continue

        filled_order = filled[-1]

        new_position_id = str(
            filled_order.get("positionId") or ""
        )

        print(
            f">>> OPPOSITE STOP TRIGGERED "
            f"parent={parent_id} "
            f"order={order_id} "
            f"new_position={new_position_id or 'unknown'}"
        )

        # The opposite stop is now the NEW running position.
        # Close ONLY the OLD parent.
        if (
            parent_id in positions_by_id
            and parent_id != new_position_id
        ):

            if EXECUTE_ORDERS:

                print(
                    f">>> CLOSE OLD PARENT "
                    f"position={parent_id}"
                )

                await connection.close_position(
                    position_id=parent_id
                )

                actions += 1

                await asyncio.sleep(
                    TRADE_DELAY_SECONDS
                )

            else:

                print(
                    f">>> DRY RUN: WOULD CLOSE "
                    f"OLD PARENT position={parent_id}"
                )

        state["pending"].pop(parent_id, None)

        state["processed"].append(
            str(order_id)
        )

        state["processed"] = (
            state["processed"][-500:]
        )

        save_state(state)

        if actions >= MAX_TRADE_ACTIONS_PER_CYCLE:
            break

    return actions


async def reconcile(connection, state):
    positions = await connection.get_positions()
    orders = await connection.get_orders()

    xau_positions = [
        p for p in positions
        if p.get("symbol") == SYMBOL
        and p.get("type") in (
            "POSITION_TYPE_BUY",
            "POSITION_TYPE_SELL",
        )
    ]

    reversal_orders = [
        o for o in orders
        if o.get("symbol") == SYMBOL
        and is_reversal_order(o)
    ]

    positions_by_id = {
        str(p["id"]): p
        for p in xau_positions
    }

    orders_by_parent = {}

    for order in reversal_orders:
        parent_id = order_parent_id(order)

        if parent_id:
            orders_by_parent.setdefault(
                parent_id,
                []
            ).append(order)

    price = await get_price(connection)

    print(
        f"[{now()}] "
        f"POSITIONS={len(xau_positions)} "
        f"REVERSAL_ORDERS={len(reversal_orders)} "
        f"BID={price['bid']:.2f} "
        f"ASK={price['ask']:.2f}"
    )

    # First process any opposite stop that has filled.
    # The filled order becomes the new running position.
    actions = await process_triggered_stops(
        connection,
        reversal_orders,
        positions_by_id,
        state,
    )

    if actions >= MAX_TRADE_ACTIONS_PER_CYCLE:
        return

    # Re-read broker state after a trigger/parent close.
    positions = await connection.get_positions()
    orders = await connection.get_orders()

    xau_positions = [
        p for p in positions
        if p.get("symbol") == SYMBOL
        and p.get("type") in (
            "POSITION_TYPE_BUY",
            "POSITION_TYPE_SELL",
        )
    ]

    reversal_orders = [
        o for o in orders
        if o.get("symbol") == SYMBOL
        and is_reversal_order(o)
    ]

    positions_by_id = {
        str(p["id"]): p
        for p in xau_positions
    }

    orders_by_parent = {}

    for order in reversal_orders:

        parent_id = order_parent_id(order)

        if parent_id:
            orders_by_parent.setdefault(
                parent_id,
                []
            ).append(order)

    # ---------------------------------------------------------
    # ORPHAN CLEANUP + DUPLICATE CLEANUP
    # ---------------------------------------------------------

    for parent_id, parent_orders in list(
        orders_by_parent.items()
    ):

        if parent_id not in positions_by_id:

            for order in parent_orders:

                if actions >= MAX_TRADE_ACTIONS_PER_CYCLE:
                    break

                await cancel_reversal(
                    connection,
                    order
                )

                actions += 1

                if EXECUTE_ORDERS:
                    await asyncio.sleep(
                        TRADE_DELAY_SECONDS
                    )

            continue

        if len(parent_orders) <= 1:
            continue

        position = positions_by_id[parent_id]
        direction = position.get("type")

        # Keep the most aggressively trailed order.
        if direction == "POSITION_TYPE_SELL":
            parent_orders.sort(
                key=lambda o: float(
                    o.get("openPrice") or 0
                )
            )
        else:
            parent_orders.sort(
                key=lambda o: float(
                    o.get("openPrice") or 0
                ),
                reverse=True
            )

        keep = parent_orders[0]

        for duplicate in parent_orders[1:]:

            if actions >= MAX_TRADE_ACTIONS_PER_CYCLE:
                break

            await cancel_reversal(
                connection,
                duplicate
            )

            actions += 1

            if EXECUTE_ORDERS:
                await asyncio.sleep(
                    TRADE_DELAY_SECONDS
                )

        orders_by_parent[parent_id] = [keep]

    # ---------------------------------------------------------
    # EXACTLY ONE STOP PER OPEN POSITION
    # ---------------------------------------------------------

    for parent_id, position in positions_by_id.items():

        if actions >= MAX_TRADE_ACTIONS_PER_CYCLE:
            break

        expected_type = pending_type_for(position)

        if not expected_type:
            continue

        parent_orders = orders_by_parent.get(
            parent_id,
            []
        )

        target = desired_stop(
            position,
            price
        )

        if target is None:
            continue

        # -----------------------------------------------------
        # NO EXISTING REVERSAL
        # -----------------------------------------------------

        if not parent_orders:

            pending = state["pending"].get(
                parent_id
            )

            if (
                pending
                and time.time()
                - float(
                    pending.get(
                        "created_at",
                        0
                    )
                )
                < CREATE_CONFIRM_TIMEOUT
            ):

                print(
                    f">>> WAIT BROKER CONFIRM "
                    f"parent={parent_id} "
                    f"order={pending.get('order_id')}"
                )

                continue

            await create_reversal(
                connection,
                position,
                target,
                state,
            )

            actions += 1

            if EXECUTE_ORDERS:
                await asyncio.sleep(
                    TRADE_DELAY_SECONDS
                )

            continue

        order = parent_orders[0]

        # Broker state is authoritative once the order is visible.
        state["pending"][parent_id] = {
            "created_at": state["pending"].get(
                parent_id,
                {}
            ).get(
                "created_at",
                time.time()
            ),
            "order_id": str(order["id"]),
        }
        save_state(state)

        # -----------------------------------------------------
        # WRONG ORDER TYPE
        # -----------------------------------------------------

        if order.get("type") != expected_type:

            print(
                f">>> WRONG REVERSAL TYPE "
                f"parent={parent_id} "
                f"existing={order.get('type')} "
                f"expected={expected_type}"
            )

            await cancel_reversal(
                connection,
                order
            )

            actions += 1

            if EXECUTE_ORDERS:
                await asyncio.sleep(
                    TRADE_DELAY_SECONDS
                )

            continue

        # -----------------------------------------------------
        # EXISTING ORDER: TRAIL IT
        # -----------------------------------------------------

        old_stop = float(
            order.get("openPrice")
            or order.get("currentPrice")
            or 0
        )

        if should_trail(
            position.get("type"),
            old_stop,
            target
        ):

            await modify_reversal(
                connection,
                order,
                target
            )

            actions += 1

            if EXECUTE_ORDERS:
                await asyncio.sleep(
                    TRADE_DELAY_SECONDS
                )

        else:

            print(
                f">>> HOLD REVERSAL "
                f"parent={parent_id} "
                f"stop={old_stop:.2f} "
                f"target={target:.2f}"
            )


async def main():
    state = load_state()

    api = MetaApi(TOKEN)

    account = await (
        api.metatrader_account_api
        .get_account(ACCOUNT_ID)
    )

    connection = account.get_rpc_connection()

    await connection.connect()
    await connection.wait_synchronized()

    print("========================================")
    print(" PIPS-MINER OPPOSITE STOP STATE MACHINE")
    print("========================================")
    print(f"SYMBOL={SYMBOL}")
    print(f"EXECUTE_ORDERS={EXECUTE_ORDERS}")
    print(f"TRAIL_PIPS={TRAIL_PIPS}")
    print(f"POINT={POINT}")
    print(f"TRAIL_DISTANCE={TRAIL_DISTANCE}")
    print("SELL -> BUY STOP = ASK + TRAIL")
    print("BUY  -> SELL STOP = BID - TRAIL")
    print("MODE=ONE OPPOSITE STOP PER POSITION")
    print("MODE=TRIGGER CLOSES OLD PARENT")
    print("MODE=TRIGGERED ORDER BECOMES NEW POSITION")
    print("MODE=NEW POSITION GETS NEW OPPOSITE STOP")
    print("MODE=BROKER STATE AUTHORITATIVE")
    print("MODE=ONE STOP PER PARENT")
    print("MODE=NO DUPLICATES")
    print("MODE=ORPHAN CLEANUP")
    print(
        f"MAX_ACTIONS={MAX_TRADE_ACTIONS_PER_CYCLE}"
    )
    print("========================================")

    try:

        while True:

            try:
                await reconcile(connection, state)

            except Exception as exc:

                print(
                    f">>> REVERSAL MANAGER ERROR: "
                    f"{type(exc).__name__}: {exc}"
                )

            await asyncio.sleep(
                POLL_SECONDS
            )

    finally:

        result = api.close()

        if result is not None:
            await result


if __name__ == "__main__":
    asyncio.run(main())
