/**
 * The orchestrator agent's charge order (edge function v23, db/migrations/0614).
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
 * charger it takes.
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
THE CHARGE LINE — this board carries "charge_queue", so the depot takes your charge order this pass.
charge_queue.cars are the cars waiting for a charger, the head 24 in the kernel's own order (kernel_pos). For each: soc and target (the car's full target, 100 unless its owner set less), kwh_owed, min_on_dcfc and min_on_l2 (minutes to target on this depot's fastest charger of that kind), wait_min against contract_wait_limit_min (over_limit_min = minutes already past the contract), urgency and due_in_min (when it must be ready), other_work (in_place runs while it charges; bay needs a bay of its own), rule_kind (the kind the kernel would give it), dcfc_ok and l2_ok (whether it can plug into that kind here). charge_queue.chargers: free and down by kind, kw by kind, and freeing_soonest (chargers in use and the minutes until their car is full). last_order and usage say what your recent orders did: seats_by_rank (cars your order seated), moved_ahead (cars it moved ahead of the kernel's order), kind_followed of kind_named, seats_pinned (cars that waited pin_wait_min or longer and went ahead of your order).

YOUR JOB: add "charge_order" to the JSON — up to 12 cars from charge_queue.cars, in the order they should take the next free chargers, each with the kind of charger it should take. The kernel disposes: immediate-dispatch cars go first and any car waiting pin_wait_min or longer goes next, whatever you send; then the cars you named for a kind of charger that is free now, in your order; then the cars you did not name, in the kernel's order; and last the cars you named for a kind that is not free, which wait for that kind. No charger is left idle for your order: a car still takes the other kind when no other car waits for it. Every car charges to its full target on whichever charger it takes. Your order decides who goes next and on which kind of charger — never how much charge a car gets, and never whether it charges.

HOW TO ORDER THE LINE:
1. The contract first: cars with over_limit_min above 0, then those nearest contract_wait_limit_min.
2. Due times next: a car whose due_in_min is shorter than its min_on_l2 needs a fast charger — name it dcfc.
3. A fast charger is the scarce resource. Give it where it returns the most time: the highest min_on_l2 ÷ min_on_dcfc, which is a car with a lot of charge owed; a car near its target tapers on a fast charger and gains little over L2. Name l2 for a car whose due time its min_on_l2 still meets. A car you name dcfc waits for a fast charger while a free L2 goes to another car, so name dcfc where the time it saves is worth that wait (freeing_soonest says when one frees).
4. Among cars otherwise equal, the shortest charge first (the fewest minutes on the kind you name): it clears the line soonest and shortens everyone's wait.
5. Never name a kind a car cannot plug into (dcfc_ok / l2_ok false). Use "either" when the kind does not matter.
6. Read usage before you order again. If seats_by_rank stays at 0 while cars wait, or kind_followed is far below kind_named, your order is not landing: name only cars in charge_queue.cars and kinds that are free or freeing soon.
7. Leave out charge_order, or send an empty list, when the kernel's order is already right. Your last order stands for ttl_ticks ticks, then the kernel's order resumes.
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
