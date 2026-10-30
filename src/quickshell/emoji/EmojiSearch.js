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

function normalizeText(value) {
    let text = String(value || "").toLowerCase();
    if (text.normalize) text = text.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    return text.replace(/[\s\-_]+/g, " ").trim();
}

function scoreText(hay, query, weight) {
    if (hay === query) return 100000 * weight;
    if (hay.startsWith(query)) return 50000 * weight;

    // "some token starts with query". normalizeText collapses every run of
    // whitespace (and '-', '_') to a single space with no leading/trailing
    // space, so a token boundary is exactly the start of the string or a
    // space — no need to materialize the token array (a per-item, per-field
    // allocation that dominated scoring on the 11k-entry Nerd Font tab).
    // Queries containing a space can never prefix a single token, so they
    // fall through to the phrase tier as before.
    if (query.indexOf(" ") === -1 && hay.includes(" " + query)) return 30000 * weight;
    if (hay.includes(query)) return 10000 * weight;
    return query.length >= 2 && isSubsequence(query, hay) ? 1000 * weight : 0;
}

// fields: array of { get: function(item) -> string, weight: number }
// Higher weight fields contribute more to matchQuality on exact/prefix
// hits, mirroring the clipboard widget's own scoring tiers.
//
// Precomputes, for each item, the normalized haystack of every field. The
// datasets are immutable between keystrokes, so normalizing once here turns
// the per-keystroke cost from "normalize every field of every item" into a
// plain scan over already-normalized strings — the dominant cost for the
// 11k-entry Nerd Font tab. Keeps items, per-field weights and the haystack
// matrix aligned by index.
function buildFieldIndex(dataset, fields) {
    let weights = new Array(fields.length);
    for (let f = 0; f < fields.length; f++) weights[f] = fields[f].weight || 1;

    let hay = new Array(dataset.length);
    for (let i = 0; i < dataset.length; i++) {
        let item = dataset[i];
        let row = new Array(fields.length);
        for (let f = 0; f < fields.length; f++) {
            let raw = fields[f].get(item);
            row[f] = raw ? normalizeText(Array.isArray(raw) ? raw.join(" ") : raw) : "";
        }
        hay[i] = row;
    }
    return { items: dataset, weights: weights, hay: hay };
}

// scoreItem over a pre-normalized row: same tier/weight semantics, but no
// per-field { text, weight } allocation and no query re-normalization per
// item.
function scoreIndexedRow(row, weights, q, terms) {
    let phraseBest = 0;
    for (let f = 0; f < row.length; f++) {
        let h = row[f];
        if (!h) continue;
        let s = scoreText(h, q, weights[f]);
        if (s > phraseBest) phraseBest = s;
    }
    if (terms.length === 1) return phraseBest;

    let termScore = 0;
    for (let t = 0; t < terms.length; t++) {
        let best = 0;
        for (let f = 0; f < row.length; f++) {
            let h = row[f];
            if (!h) continue;
            let s = scoreText(h, terms[t], weights[f]);
            if (s > best) best = s;
        }
        if (best === 0) return 0;
        termScore += best;
    }
    return phraseBest + termScore;
}

// Decayed frecency score, same half-life shape used by the app
// launcher's own ranking (app_rank.py): score halves every
// `halfLifeDays`. `entry` is { c: count, t: lastUsedMs }.
function decayedScore(entry, halfLifeDays, nowMs) {
    if (!entry) return 0;
    let ageDays = Math.max(0, (nowMs - (entry.t || 0)) / 86400000);
    return (entry.c || 0) * Math.pow(0.5, ageDays / halfLifeDays);
}

// Filter+sort over a prebuilt field index (see buildFieldIndex). `keyOf`
// extracts the history-store key for an item, `historyStore` maps key ->
// {c,t}. Returns a new array, sorted by (matchQuality desc, historyScore
// desc, original order), or null when the query is empty (callers handle the
// unfiltered/featured ordering).
function filterAndSortIndexed(index, query, keyOf, historyStore, halfLifeDays) {
    let q = normalizeText(query);
    if (q.length === 0) return null;

    let terms = q.split(" ");
    let now = Date.now();
    let hay = index.hay;
    let weights = index.weights;
    let out = [];
    for (let i = 0; i < hay.length; i++) {
        let quality = scoreIndexedRow(hay[i], weights, q, terms);
        if (quality > 0) {
            let item = index.items[i];
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

// Finds the top N used keys by decayed score,
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

// Place frequent items first in All without repeating them in the main dataset.
function prioritizeUsed(dataset, recent, keyOf) {
    let available = new Set(dataset.map(keyOf));
    let seen = new Set();
    let items = [];
    for (let item of recent) {
        let key = keyOf(item);
        if (!available.has(key) || seen.has(key)) continue;
        seen.add(key);
        items.push(item);
    }
    let count = items.length;
    for (let item of dataset) {
        let key = keyOf(item);
        if (seen.has(key)) continue;
        seen.add(key);
        items.push(item);
    }
    return { items: items, count: count };
}
