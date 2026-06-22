'use strict';
// SM-2 spaced-repetition scheduler — pure and dependency-free (Anki-style).
//
// A card carries: ease (≥1.3, starts 2.5), interval (days), reps (consecutive
// correct), lapses (times failed), due (YYYY-MM-DD). Grades map to SM-2 quality:
//   again = lapse (reset)   hard = 3   good = 4   easy = 5

const Q = { again: 1, hard: 3, good: 4, easy: 5 };

function addDays(dateStr, n) {
  const d = new Date(dateStr + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// Apply one review. Returns a new card object (does not mutate the input).
function review(card, grade, today) {
  const q = Q[grade];
  if (q == null) throw new Error('bad grade: ' + grade);

  let ease = card.ease || 2.5;
  let interval = card.interval || 0;
  let reps = card.reps || 0;
  let lapses = card.lapses || 0;

  if (q < 3) {
    reps = 0;
    lapses += 1;
    interval = 1;
    ease = Math.max(1.3, ease - 0.2);
  } else {
    if (reps === 0) interval = 1;
    else if (reps === 1) interval = grade === 'easy' ? 4 : 6;
    else interval = Math.max(1, Math.round(interval * ease * (grade === 'hard' ? 0.8 : 1)));
    reps += 1;
    ease = Math.max(1.3, ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)));
  }
  ease = Math.round(ease * 1000) / 1000;

  return { ...card, ease, interval, reps, lapses, due: addDays(today, interval), lastReviewed: today };
}

module.exports = { review, addDays, Q };
