.pragma library

// Shared fuzzy match + scoring helpers for the Emoji/Nerd Font/Kaomoji
// picker. Kept generic (works over any array of plain objects) so the
// three tabs — with different underlying datasets — can all reuse the
// exact same matching/ranking behaviour instead of each re-implementing
// it slightly differently.

function isSubsequence(sub, str) {
    let i = 0;
    let j = 0;
    while (i < sub.length && j < str.length) {
        if (sub[i] === str[j]) i++;
        j++;
    }
    return i === sub.length;
}

// Normalizes a query for hex/codepoint lookups: strips a leading
// "U+"/"0x"/"\u" and lowercases, so "U+1F600", "0x1f600" and "1f600"
// all resolve to the same needle when compared against stored hex.
function normalizeHexQuery(q) {
    return q.replace(/^u\+|^0x|^\\u/i, "").toLowerCase();
}

// fields: array of { get: function(item) -> string, weight: number }
// Higher weight fields contribute more to matchQuality on exact/prefix
// hits, mirroring the clipboard widget's own scoring tiers.
function scoreItem(item, query, fields) {
    let best = 0;
    for (let f = 0; f < fields.length; f++) {
        let raw = fields[f].get(item);
        if (!raw) continue;
        let hay = (Array.isArray(raw) ? raw.join(" ") : raw).toLowerCase();
        let w = fields[f].weight || 1;
        let q = query;

        if (hay === q) {
            best = Math.max(best, 100000 * w);
        } else if (hay.startsWith(q)) {
            best = Math.max(best, 50000 * w);
        } else {
            // token-prefix match: any whitespace/dash/underscore separated
            // token in the haystack starting with the query counts almost
            // as well as a full prefix match ("account" matching
            // "cod-account" or "grinning face" matching "face").
            let tokens = hay.split(/[\s\-_]+/);
            let tokenHit = false;
            for (let t = 0; t < tokens.length; t++) {
                if (tokens[t].length > 0 && tokens[t].startsWith(q)) {
                    tokenHit = true;
                    break;
                }
            }
            if (tokenHit) {
                best = Math.max(best, 30000 * w);
            } else if (hay.includes(q)) {
                best = Math.max(best, 10000 * w);
            } else if (q.length >= 2 && isSubsequence(q, hay)) {
                best = Math.max(best, 1000 * w);
            }
        }
    }
    return best;
}

// Decayed frecency score, same half-life shape used by the app
// launcher's own ranking (app_rank.py): score halves every
// `halfLifeDays`. `entry` is { c: count, t: lastUsedMs }.
function decayedScore(entry, halfLifeDays, nowMs) {
    if (!entry) return 0;
    let ageDays = Math.max(0, (nowMs - (entry.t || 0)) / 86400000);
    return (entry.c || 0) * Math.pow(0.5, ageDays / halfLifeDays);
}

// Generic filter+sort. `dataset` is the full array, `keyOf` extracts the
// history-store key for an item, `historyStore` maps key -> {c,t}.
// Returns a new array, sorted by (matchQuality desc, historyScore desc,
// original order) when there's a query, or left in original dataset
// order when the query is empty (category filtering already applied by
// the caller before this runs).
function filterAndSort(dataset, query, fields, keyOf, historyStore, halfLifeDays) {
    let q = (query || "").trim().toLowerCase();
    if (q.length === 0) return dataset;

    let now = Date.now();
    let out = [];
    for (let i = 0; i < dataset.length; i++) {
        let item = dataset[i];
        let quality = scoreItem(item, q, fields);
        if (quality > 0) {
            let hScore = historyStore ? decayedScore(historyStore[keyOf(item)], halfLifeDays, now) : 0;
            out.push({ item: item, quality: quality, hScore: hScore, idx: i });
        }
    }

    out.sort(function(a, b) {
        if (a.quality !== b.quality) return b.quality - a.quality;
        if (a.hScore !== b.hScore) return b.hScore - a.hScore;
        return a.idx - b.idx;
    });

    let result = new Array(out.length);
    for (let i = 0; i < out.length; i++) result[i] = out[i].item;
    return result;
}

// Builds the "frequently used" shelf: top N keys by decayed score,
// resolved back to their dataset items via `lookup` (a plain object
// mapping key -> item), skipping any key no longer present in the
// dataset (e.g. after a data update).
function topUsed(historyStore, lookup, limit, halfLifeDays) {
    if (!historyStore) return [];
    let now = Date.now();
    let keys = Object.keys(historyStore);
    let scored = [];
    for (let i = 0; i < keys.length; i++) {
        let k = keys[i];
        if (!lookup[k]) continue;
        let s = decayedScore(historyStore[k], halfLifeDays, now);
        if (s > 0.01) scored.push({ key: k, score: s });
    }
    scored.sort(function(a, b) { return b.score - a.score; });
    if (scored.length > limit) scored = scored.slice(0, limit);
    let out = [];
    for (let i = 0; i < scored.length; i++) out.push(lookup[scored[i].key]);
    return out;
}
