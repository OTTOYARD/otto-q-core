/**
 * The orchestrator agent's charge order (edge function v23, db/migrations/0614; v25, 0620; v26, 0621; v28, 0642).
 *
 * WHY. On run 81787ef9 the agent wrote no dial and kept one solver objective for the whole run, and its 74 answered
 * passes changed nothing the depot did (FINDINGS G315). The decision it is best placed to improve is the one the kernel
 * makes with a fixed formula: who in the charge line takes the next free charger, and on which kind. The kernel ranks
 * by wait over charge still owed and gives a fast charger to any car under 45%; it cannot weigh a car's due time
 * against the minutes each kind of charger would take, or see that the line holds three top-offs and one car that
 * owes 52 kWh.
 *
 * WHAT. When the board carries `charge_queue` (agent_charge_order = 1 on the run, OTTO-Q's seat), the prompt gains a
 * section that says how to read the line and asks for `charge_order`: up to CHARGE_ORDER_MAX_CARS cars from it in the
 * order they should take the next free chargers, each with a kind. normalizeChargeOrder maps the names the model uses
 * to vehicle ids from the same board, and the edge function hands the result to ottoq_agent_charge_order_record. The
 * kernel disposes: immediate dispatch first, any car waiting agent_charge_order_pin_wait_min or longer next, then the
 * cars the agent named for a kind free now, then the cars it did not name, then (0617) the cars it named for the other
 * kind; no charger idles for the order, and every car charges to its full target (CLAUDE.md rule 9) on whichever
 * charger it takes. Since 0618 the door checks the order against the kernel's own before taking it (status 'refused',
 * the reason in last_order.projection on the next board): on run 0bbdcc07 the order taken whole cost uptime,
 * departures and on-time readiness against the same seed without it (db/checks/0415). Since 0620 (v25) the check rolls
 * the line forward over the expected future and sampled ones, the agent's order for its life and the kernel's after,
 * with the cars coming home and the learned charge clock, and takes the order only when it wins the expected future
 * and win_frac of all; the board says how tight the line is (contention), who is coming home (arriving) and the bar
 * (check), and the prompt asks for an order only when the line is tight or congested. Since 0621 (v26) the kernel
 * replays each checked order 90 sim-minutes later with what actually happened and keeps the result; the board carries it
 * as track_record (this run and the depot's last days, by outcome; each kind of move with how often it won and lost in
 * hindsight; what most often made the check wrong), and the prompt asks the agent to make the moves that won and stop
 * making the ones that lost.
 *
 * Pure functions only, so `node --test tests/*.test.mjs` imports this file directly.
 */

export const CHARGE_ORDER_MAX_CARS = 12;

export type ChargeKind = "dcfc" | "l2" | "either";

/** What the edge function sends to ottoq_agent_charge_order_record, plus the references it could not resolve. */
export type NormalizedChargeOrder = {
  cars: { vehicle_id: string; kind: ChargeKind; why: string }[];
  why: string;
  unmatched: string[];   // names the model used that are not on the board; sent on so the door records the drop
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The board's charge line, or null when the run does not take a charge order. */
export function chargeQueueOf(board: unknown): { cars: { vehicle_id: string; name: string }[] } | null {
  const q = (board as any)?.charge_queue;
  if (!q || typeof q !== "object" || !Array.isArray(q.cars)) return null;
  return q;
}

/** dcfc | l2 | either, from whatever the model wrote. */
export function normalizeKind(kind: unknown): ChargeKind {
  const k = String(kind ?? "").trim().toLowerCase().replace(/[\s_-]+/g, "");
  if (["dcfc", "dc", "fast", "dcfast", "fastcharger", "dcfastcharger"].includes(k)) return "dcfc";
  if (["l2", "level2", "ac", "slow", "l2charger"].includes(k)) return "l2";
  return "either";
}

/**
 * The model's charge_order, made safe to send. Accepts {cars:[...]} or a bare array; each car may be named by `car`,
 * `name` or `vehicle_id`. A name on the board becomes its vehicle id; a uuid passes through (the door checks it against
 * the whole line, not only the 24 cars shown); anything else is sent on as written so the door records it as dropped,
 * with its reason, in the agent's own ledger. Duplicates after the first are left out here. Null when the board carries
 * no charge line or the answer carries no order.
 */
export function normalizeChargeOrder(raw: unknown, board: unknown): NormalizedChargeOrder | null {
  const q = chargeQueueOf(board);
  if (!q || raw == null || typeof raw !== "object") return null;
  const list: unknown[] | null = Array.isArray(raw) ? raw : Array.isArray((raw as any).cars) ? (raw as any).cars : null;
  if (!list) return null;
  const byKey = new Map<string, string>();
  for (const c of q.cars) {
    if (typeof c?.vehicle_id !== "string") continue;
    byKey.set(c.vehicle_id.toLowerCase(), c.vehicle_id);
    if (typeof c.name === "string" && c.name.trim() !== "") byKey.set(c.name.trim().toLowerCase(), c.vehicle_id);
  }
  const cars: NormalizedChargeOrder["cars"] = [];
  const unmatched: string[] = [];
  const seen = new Set<string>();
  for (const e of list.slice(0, 40)) {
    if (cars.length >= CHARGE_ORDER_MAX_CARS) break;
    const o = (e && typeof e === "object") ? e as Record<string, unknown> : {};
    const ref = String((typeof e === "string" ? e : o.car ?? o.name ?? o.vehicle_id ?? o.id) ?? "").trim();
    if (ref === "") continue;
    const id = byKey.get(ref.toLowerCase()) ?? (UUID.test(ref) ? ref.toLowerCase() : null);
    if (id == null) unmatched.push(ref.slice(0, 60));
    const vehicleId = id ?? ref.slice(0, 60);
    if (seen.has(vehicleId)) continue;
    seen.add(vehicleId);
    cars.push({ vehicle_id: vehicleId, kind: normalizeKind(o.kind), why: String(o.why ?? "").trim().slice(0, 200) });
  }
  const why = Array.isArray(raw) ? "" : String((raw as any).why ?? "").trim().slice(0, 400);
  return { cars, why, unmatched };
}

/**
 * The prompt section, appended only when the board carries `charge_queue`. Every number it names is a field on the
 * board, and every rule it states is one the kernel enforces whatever the agent sends -- so a model that ignores the
 * section loses its say, never a vehicle's charge.
 */
export const CHARGE_ORDER_PROMPT = `
THE CHARGE LINE — this board carries "charge_queue", so the depot takes your charge order this pass if it passes the kernel's check.
charge_queue.cars are the cars waiting for a charger, the head 24 in the kernel's own order (kernel_pos). For each: soc and target (the car's full target, 100 unless its owner set less), kwh_owed, min_on_dcfc and min_on_l2 (minutes to target on this depot's fastest charger of that kind, on the depot's learned charge clock: what charges here really take), wait_min against contract_wait_limit_min (over_limit_min = minutes already past the contract), urgency and due_in_min (minutes until it must be ready; 0 or less means it is already late), other_work (in_place runs while it charges; bay needs a bay of its own), rule_kind (the kind the kernel would give it), dcfc_ok and l2_ok (whether it can plug into that kind here). charge_queue.kernel_order is how the kernel orders its own line after immediate dispatch: any car waiting floor_min or longer first, the longest wait first; then the highest (minutes waited + minutes of charge) / minutes of charge when by is charge_minutes (by battery points owed when it is points). charge_queue.chargers: free and down by kind, kw by kind, freeing_soonest (chargers in use and the minutes until their car is full), and held (the chargers the depot's calendar holds for a named car within the next hour, soonest first: kind, stall, car, from_min, until_min). While a hold covers the moment, the kernel gives that charger to no other car, whatever your order says. Each car's held names the charger held for it, if any (kind, stall, from_min, until_min): the kernel seats it there when its window opens. Each car's plan, each arriving car's plan_start_min and plan_kind, and charge_queue.kernel_plan are what the kernel's own order does from now in the check's expected future: when each car starts (start_min) and on which kind, when it is ready (ready_min), and late_min when it misses its due time; kernel_plan counts the cars it makes late (late, late_min), the cars under 45% it puts on an L2 (low_on_l2) and the cars it cannot seat within the horizon (unseated). This is the plan your order is checked against. charge_queue.contention: waiting against free_now and freeing_15_min, arriving_60_min, and pressure (none = every car waiting can plug in now; tight = within 15 minutes; congested = not). charge_queue.arriving: the cars coming home, soonest first, with eta_min and soc (returning = driving home now; forecast = the depot expects it to be called home for its reserve). charge_queue.check: the bar your order must clear (futures, win_frac), the learned charge clock (charge_time_factors) and the return model the check uses. last_order.projection is the kernel's check on your last order: take, reason, wins of futures, need, expected_by (what decided the expected future: on_time, lateness, contract_wait or flow), and the expected future's two sides (kernel, agent: on_time = cars ready by their due time, late_sum = minutes late summed, flow_sum = minutes in the depot summed over every car, the cars coming home included). usage says what your orders did: seats_by_rank, orders_refused and refused_by_reason, moved_ahead, kind_followed of kind_named, seats_pinned.
track_record is how your orders did in what actually happened: 90 sim-minutes after each order the kernel replays it with the real arrivals, the real charge times, the cars it never saw coming and the chargers that faulted, against its own order from the same moment. this_run and depot (its last depot_days days) count your taken orders that won, tied or lost, and your refused orders that would have won. moves says, for each kind of move your orders made, how many orders made it and how many of them beat the kernel's own order in what actually happened (won), tied or lost it, taken or not: due_rescue_fast (a car late in the kernel's order made ready by its due time on a fast charger), due_rescue (the same, on an L2), low_battery_on_l2 (a car under 45% put on an L2 ahead of the kernel's order), top_off_ahead (a car at 80% or more seated ahead of it), late_car_first (a car already past its due time moved up), kind_swap (the same car, the other kind), reorder_only (only who goes first). check_wrong_by names what most often made the check's own forecast wrong.

YOUR JOB: add "charge_order" to the JSON — up to 12 cars from charge_queue.cars, in the order they should take the next free chargers, each with the kind of charger it should take. THE KERNEL CHECKS IT FIRST: it rolls the whole line forward from now twice — your order for its ttl and then its own, against its own order throughout — with the cars coming home joining the line when they arrive and every charge timed by the learned clock, in the expected future and in sampled futures (charge times and arrivals jittered by how much they really vary). It takes your order only when it beats its own in the expected future AND in at least win_frac of all the futures (10 of 12). Better means, in this order: more cars ready by their due time; then fewer minutes late; then fewer minutes waited past each car's contract queue wait (contract_wait_limit_min), summed; then fewer minutes in the depot summed over every car. Otherwise it keeps its own order and says why in last_order.projection. When it takes your order: immediate-dispatch cars go first and any car waiting pin_wait_min or longer goes next, whatever you send; then the cars you named for a kind of charger that is free now, in your order; then the cars you did not name, in the kernel's order; and last the cars you named for a kind that is not free, which wait for that kind. No charger is left idle for your order: a car still takes the other kind when no other car waits for it. Every car charges to its full target on whichever charger it takes. Your order decides who goes next and on which kind of charger — never how much charge a car gets, and never whether it charges.

WHEN TO ORDER: when contention.pressure is tight or congested and kernel_plan shows something to fix: a car it makes late, a low battery it puts on an L2. When it is none, every car waiting plugs in now whatever you send: leave out charge_order (the check would answer same_as_kernel). Your order matters most when the line is congested.

HOW TO ORDER THE LINE (this is what the check rewards):
1. A car that will miss its due time unless it takes the next fast charger to free: name it dcfc, earliest due first. This is where your order gains most: the kernel's own order does not read due times.
2. A car already past its due time (due_in_min 0 or less): name the kind that gets it ready soonest, from min_on_dcfc, min_on_l2 and freeing_soonest.
3. Then the shortest charge first, on the kind each car would take: every minute a car waits or charges is a minute off the road. The kernel's own order already leans this way (kernel_order.by), so an order that only does the same changes nothing.
4. Mind the cars coming home (arriving): a low battery put on an L2 holds it for hours, and the cars that arrive behind it wait. The check counts them, and so should you.
5. The check counts each car's minutes past contract_wait_limit_min right after lateness, so an order wins when it keeps more cars inside their owners' queue wait. The kernel already serves a car waiting kernel_order.floor_min or longer first: moving one up gains nothing.
6. Never name a kind a car cannot plug into (dcfc_ok / l2_ok false). Use "either" when the kind does not matter.
7. Read chargers.held before you count a charger as yours: a charger held for another car is not free to the cars you name while its hold lasts, and a car with a charger held for it is already placed. Name it only if it should charge before its window opens.
8. Read last_order.projection before you order again. same_as_kernel means your order changed nothing: do not resend it. worse_in_expected_future, no_better_in_expected_future or not_enough_futures_won mean it lost: compare the two sides and change what made yours worse; never send the same order again.
9. Leave out charge_order, or send an empty list, when the kernel's order is already right. Your last order stands for ttl_ticks ticks, then the kernel's order resumes.
10. Learn from track_record.moves, this depot's own hindsight: make the moves that won in what actually happened; stop making a move that has lost more often than it won over 3 or more orders, and say so in why. A move the check refused that won in hindsight is still worth making when the board shows the same situation.
Never hold a car back, never end a charge early, never lower a target: the line is ordered, not shortened.

Add to the JSON object exactly: "charge_order":{"cars":[{"car":"<name exactly as in charge_queue.cars>","kind":"dcfc|l2|either","why":"<8 words or fewer>"}],"why":"<one sentence citing board numbers>"}`;

/** The system prompt for this board: the base, plus the charge-line section when the board carries one. */
export function withChargeOrder(system: string, board: unknown): string {
  return chargeQueueOf(board) ? `${system}\n${CHARGE_ORDER_PROMPT}` : system;
}

/** What the decision row records about the order: the order sent, and the kernel's receipt. */
export function chargeOrderAccepted(receipt: unknown): boolean {
  const r = receipt as any;
  return r?.ok === true && (r.status === "accepted" || r.status === "partial");
}
