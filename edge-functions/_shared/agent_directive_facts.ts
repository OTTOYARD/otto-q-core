/**
 * Whether a directive's facts are the brief's (edge function v34, db/checks/0493, FINDINGS G545).
 *
 * WHY. v32 counts whether a directive NAMES the subject its brief gave it; nothing read whether what it says about the
 * subject is true. Read 2026-11-14 over 30 hours at the twin depot (759 directives, 236 consults, 12 runs), against the
 * brief each consult was sent: the primary model's directives named a cut car's post correctly 201 times in 201, its
 * minutes since the cut 138 in 138 and its cut SoC 69 in 69. The first fallback model's: a wrong post once in 12,
 * minutes wrong 4 times in 9 (by up to 61 minutes, copied from its last answer), and "check charging again on
 * NASH-DCFC-STALL-14 within 6 min" about a car the brief had waiting in line with no post.
 *
 * WHAT IT CHECKS. Only a directive that names a car whose charge a fault cut (subjects.charges_cut_by_fault.cars), and
 * only in the words after that car's name, up to the next car the brief names:
 *   post      every post named there is the post the fault cut the charge on or the post the car charges on again;
 *   line_pos  "pos N" is the car's place in the kernel's line, and is not said of a car that is charging again;
 *   min_ago   "N min ago" is the brief's minutes since the cut, within 3;
 *   cut_soc   "cut at N%" is the SoC the brief says the charge was cut at.
 * It checks what is said against the brief the model was sent. It does not check the brief, and a fact it cannot find
 * in the text is not checked. Pure, so `node --test tests/*.test.mjs` drives it.
 */
import { namesSubject, type WakeBrief } from "./agent_wake_brief.ts";

export type FactMiss = {
  car: string;
  field: "post" | "line_pos" | "min_ago" | "cut_soc";
  said: string;
  brief: string;
};

export type FactCheck = {
  /** The cut cars the directive names. */
  cars: number;
  /** The facts found in the text and compared. */
  checked: number;
  wrong: FactMiss[];
};

const MIN_AGO_TOLERANCE = 3;

function rows(v: unknown): Record<string, unknown>[] {
  return Array.isArray(v) ? v.filter((r): r is Record<string, unknown> => r != null && typeof r === "object") : [];
}

/** Every string the brief holds under one of these keys, at any depth. */
function strings(node: unknown, keys: Set<string>, out: Set<string> = new Set()): Set<string> {
  if (Array.isArray(node)) { for (const x of node) strings(x, keys, out); return out; }
  if (node && typeof node === "object") {
    for (const [k, v] of Object.entries(node as Record<string, unknown>)) {
      if (keys.has(k) && typeof v === "string" && v.trim() !== "") out.add(v);
      else strings(v, keys, out);
    }
  }
  return out;
}

function escapeRe(s: string): string {
  return s.replace(/[^a-zA-Z0-9]/g, (ch) => `\\${ch}`);
}

/** Where a whole name begins in a text (any letter case, not inside a longer name), or -1. */
function indexOfName(text: string, name: string): number {
  const m = new RegExp(`(^|[^a-z0-9-])${escapeRe(name.toLowerCase())}(?=[^a-z0-9-]|$)`).exec(text.toLowerCase());
  return m ? m.index + m[1].length : -1;
}

/**
 * A pattern for anything shaped like one of the brief's posts: a known post's name with its last number replaced by
 * any number. So a post the brief does not hold at all ("NASH-DCFC-STALL-14" of a car with no post) is still read.
 */
function postPattern(posts: Set<string>): RegExp | null {
  const stems = new Set<string>();
  for (const p of posts) {
    const m = /^(.*?)(\d+)$/.exec(p);
    if (m && m[1] !== "") stems.add(escapeRe(m[1].toLowerCase()));
  }
  if (stems.size === 0) return null;
  return new RegExp(`(?:^|[^a-z0-9-])((?:${[...stems].join("|")})\\d+)(?![a-z0-9-])`, "g");
}

function sameNumber(a: string, b: string): boolean {
  const ma = /^(.*?)(\d+)$/.exec(a.toLowerCase()), mb = /^(.*?)(\d+)$/.exec(b.toLowerCase());
  return !!ma && !!mb && ma[1] === mb[1] && Number(ma[2]) === Number(mb[2]);
}

/** A directive's facts about the cut cars it names, against the brief the model was sent. */
export function checkDirectiveFacts(brief: WakeBrief | null, text: unknown): FactCheck {
  const out: FactCheck = { cars: 0, checked: 0, wrong: [] };
  if (!brief || typeof text !== "string" || text === "") return out;
  const s = (brief.subjects ?? {}) as Record<string, any>;
  const cut = rows(s.charges_cut_by_fault?.cars).filter((c) => typeof c.car === "string" && c.car !== "");
  if (cut.length === 0) return out;
  const everyCar = strings(brief.subjects, new Set(["car"]));
  const posts = strings(brief.subjects, new Set(["post", "charging_again_on"]));
  const postRe = postPattern(posts);
  const lower = text.toLowerCase();

  // one car can be in the list twice (two charges cut): its facts are any of its rows'
  const byCar = new Map<string, Record<string, unknown>[]>();
  for (const c of cut) byCar.set(c.car as string, [...(byCar.get(c.car as string) ?? []), c]);

  for (const [car, mine] of byCar) {
    if (!namesSubject(text, car)) continue;
    out.cars++;
    const from = indexOfName(text, car) + car.length;
    let to = text.length;
    for (const other of everyCar) {
      if (other === car) continue;
      const at = indexOfName(text.slice(from), other);
      if (at >= 0) to = Math.min(to, from + at);
    }
    const clause = lower.slice(from, to);

    if (postRe) {
      const allowed = mine.flatMap((c) => [c.post, c.charging_again_on]).filter((p): p is string => typeof p === "string");
      for (const m of clause.matchAll(postRe)) {
        out.checked++;
        if (!allowed.some((p) => sameNumber(p, m[1]))) {
          out.wrong.push({ car, field: "post", said: m[1].toUpperCase(), brief: allowed.join(" / ") || "no post" });
        }
      }
    }

    const pos = /\bpos(?:ition)?\.?\s*#?\s*(\d+)/.exec(clause);
    if (pos) {
      out.checked++;
      const places = mine.map((c) => c.waiting_in_line_pos).filter((p): p is number => typeof p === "number");
      if (!places.includes(Number(pos[1]))) {
        out.wrong.push({ car, field: "line_pos", said: pos[1], brief: places.length ? places.join(" / ") : "not in line" });
      }
    }

    const ago = /(\d+)\s*min(?:ute)?s?\s+ago/.exec(clause);
    if (ago) {
      const mins = mine.map((c) => c.min_ago).filter((p): p is number => typeof p === "number");
      if (mins.length) {
        out.checked++;
        if (!mins.some((m) => Math.abs(m - Number(ago[1])) <= MIN_AGO_TOLERANCE)) {
          out.wrong.push({ car, field: "min_ago", said: ago[1], brief: mins.join(" / ") });
        }
      }
    }

    const soc = /\bcut\s+(?:by a fault\s+)?at\s+(\d+)\s*%/.exec(clause);
    if (soc) {
      const socs = mine.map((c) => c.cut_at_soc).filter((p): p is number => typeof p === "number");
      if (socs.length) {
        out.checked++;
        if (!socs.includes(Number(soc[1]))) {
          out.wrong.push({ car, field: "cut_soc", said: soc[1], brief: socs.join(" / ") });
        }
      }
    }
  }
  return out;
}

export type FactsTally = {
  /** Directives that named a cut car. */
  directives: number;
  facts_checked: number;
  facts_wrong: number;
  /** Directives not applied because a fallback model wrote them and they contradict the brief. */
  refused: number;
  misses: (FactMiss & { refused?: true })[];
};

export function newFactsTally(): FactsTally {
  return { directives: 0, facts_checked: 0, facts_wrong: 0, refused: 0, misses: [] };
}

/** Add one directive's check to the pass's tally. Keeps the first 12 misses. */
export function tallyFacts(t: FactsTally, c: FactCheck, refused: boolean): void {
  if (c.cars === 0) return;
  t.directives++;
  t.facts_checked += c.checked;
  t.facts_wrong += c.wrong.length;
  if (refused) t.refused++;
  for (const w of c.wrong) if (t.misses.length < 12) t.misses.push(refused ? { ...w, refused: true } : w);
}

/** The reason kept on a refused directive: what it said against what the brief holds. */
export function factsReason(c: FactCheck): string {
  return "contradicts the brief: " + c.wrong.slice(0, 4)
    .map((w) => `${w.car} ${w.field} said ${w.said}, the brief has ${w.brief}`).join("; ");
}
