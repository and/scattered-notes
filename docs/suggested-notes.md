# Suggested notes: notes that mean the same thing in different words

This document explains the Suggested list in the Links column: what it does, how it works, what was tried, what the numbers were, and what could make it better. It is a living document. Each time we find a way to improve the feature, or learn something about how well it works, add it to the [Change log](#change-log) and update the sections above it.

## What it does

When a note is open and the Links column is showing, the column can list notes that are about the same thing as the open note, even when they share few or no words. A note about "call the dentist" might be matched with one about "teeth appointment". The list is headed **Suggested**, each row says "Similar meaning", and a line under the list says it is only a guess.

It is a guess, so it never changes a note and never writes a link. If a suggestion is right, you can write the link yourself with `[[Title]]`.

The feature is **off by default**. Turn it on in Settings → Suggestions → "Suggest notes by meaning". It is only on the Mac for now.

## Where it fits among the other link features

The Links column has four lists, from most certain to least:

| List | What it means | How sure it is |
|---|---|---|
| Links to | This note mentions another note's title, or has a `[[Title]]` | Exact, by whole-word match |
| Linked from | Another note mentions this note's title | Exact |
| Related | Shares a `#tag` or `@person`, or many uncommon words | Rule-based, repeatable |
| Suggested | Close in meaning | A guess from a language model |

A note listed in a higher list is left out of the lists below it, so nothing is shown twice.

## How it works, step by step

1. **A word model.** macOS ships with a table of English words. Each word is a list of 512 numbers, and words used in similar ways have similar lists, so "dentist" and "teeth" are close. This is called a word embedding. The app uses Apple's `NLEmbedding.wordEmbedding(for: .english)`, which works offline and sends nothing anywhere.
2. **Choose the words.** For each note, the app reads its title and the first 800 characters of its text, with date markers removed. It keeps words of three letters or more, and drops numbers and a list of words that say little, such as "the", "would", "today" and the placeholder "untitled note".
3. **Weight the words.** Each word is scaled by how much it says. A word used in only a few notes counts more than a word used in many. The scale is `ln(1 + notes / notes using the word)`, the usual inverse document frequency. Words in the title count double, because a note is mostly about what it is called.
4. **Add them up.** A note's vector is its words' vectors added together, each times its weight. A note with fewer than two known words gets no vector: one word says too little, and one-word notes such as "test" would otherwise match each other perfectly.
5. **Take off the common part.** Every word vector in the model has a large part that points the same way, so any two notes look alike. After scaling every note's vector to length 1, the app takes the average of all of them off each one, then scales again to length 1. What is left is what sets a note apart from the rest of your notes.
6. **Compare.** Two notes' similarity is the dot product of their vectors, which for length-1 vectors is the cosine of the angle between them: 1 means the same direction, 0 means unrelated.
7. **Add small bonuses.** Each shared `#tag` or `@person` adds 0.05, up to two of them. Being in the same project adds 0.02. These count because two notes that look alike and also share a mark are far more likely to be related.
8. **Cut off and rank.** A note is suggested when its score is at least 0.5. The best five are shown, best first. Equal scores are ordered newest note first, then by id, so the list never reshuffles.

The vectors are worked out in the background, off the main thread, whenever the notes change. Because step 3 and step 5 depend on all the notes, all the vectors are worked out again when any one note changes. For a few hundred notes this is instant. See [Limits](#limits) for larger collections.

## Why this design, and what was tried first

**Apple's sentence model was tried first and gave wrong answers.** `NLEmbedding.sentenceEmbedding` turns a whole sentence into one vector, which sounds ideal. In a test of ten pairs on 5 November 2026, it scored "call the dentist tomorrow" against "file the tax return" (0.40) higher than against "teeth appointment on friday" (0.29). It got related pairs right only when they shared words.

**Averaging word vectors worked better.** The same ten pairs, with word vectors averaged and common words dropped:

| Pair | Score |
|---|---|
| dentist / teeth appointment | 0.60 |
| dentist / tax return | 0.36 |
| "things that help me focus" / "staying consistent with habits" | 0.52 |
| "things that help me focus" / "buy oat milk" | 0.30 |
| iphone app slow to load / slow startup on mobile | 0.57 |
| iphone app slow to load / garden plants watering | 0.33 |
| meeting notes with neil about the deck / discussion with neil on slides | 0.57 |
| meeting notes with neil about the deck / recipe for pasta | 0.30 |

Every related pair scored 0.52 or more, and every unrelated pair 0.36 or less.

**Weighting the words made scores too high.** The first version with inverse document frequency scored almost every pair of the author's real notes at 0.8 to 0.9, including pairs that had nothing in common, such as "features" and "Bugs". The common part of the vectors (step 5) was dominating. Taking the average off fixed it: on the same 81 notes, only 14 pairs among each note's top three suggestions passed 0.5, and the ones checked by hand were sensible ("why sometimes when i close the quick note…" with "why do i see the full SN window after…", "can we add sync?" with "how difficult is to create a reliable sync").

**Why not a bigger model.** A larger sentence-level or multilingual model could do better, but it means shipping a model file, a larger app, slower start-up, and results that differ between devices. Windows and Android have no built-in model of this kind, so a note would show different suggestions on different devices. The rule-based Related list stays the same everywhere, which is why it is the one that will be ported.

## Where the code is

| What | File |
|---|---|
| The maths: vectors, weights, centring, scoring, ranking | `Sources/Models/SuggestedNotes.swift` (`SuggestedIndex`, `SuggestedNote`, `WordVectors`) |
| Apple's word model, background work, caching of the latest index | `Sources/Storage/SuggestionEngine.swift` |
| The setting | `AppSettings.suggestNotes` in `Sources/Storage/AppSettings.swift`, switched in `Sources/Views/Settings/SettingsView.swift` |
| The list on screen | `Sources/Views/Editor/NoteLinksPanel.swift` |
| Tests | `Tests/ScatteredNotesTests/SuggestedNotesTests.swift` |

The maths is separate from Apple's model, behind a small `WordVectors` interface, so the tests can use a made-up three-dimensional model where the answers are known. One test also runs Apple's real model on the Mac it is running on.

## Limits

- **English only.** The model is English. A note in another language will have few known words and get no vector.
- **It reads the start of a note.** Only the title and the first 800 characters count.
- **Short notes are noisy, one-word notes are skipped.** A note with only two or three known words has a vector that rests on very little.
- **Names and abbreviations are invisible.** Words the model does not know, such as "sn", "scl" or a person's name, are ignored. Shared `@person` marks help with names, but nothing helps with abbreviations yet.
- **Everything is worked out again when one note changes.** For 2,000 notes of about 100 words each this is roughly a second of background work. A collection much larger than that would need the weights kept up to date note by note.
- **The threshold was set by eye.** 0.5 comes from looking at one person's 81 notes. It has not been measured against a set of notes marked right and wrong.
- **Mac only for now.** The code is shared with the iPhone app and compiles there, but the iPhone has no Links column. Windows and Android have no model.

## Ideas that could make it better

These are not done. When one is tried, move it to the change log with the result.

1. **Choose the cut-off from data.** Mark 50 or so pairs from real notes as "related" or "not", then pick the threshold that best separates them. Today it is a guess.
2. **A "not related" button** on each suggestion, remembered per pair, so a wrong suggestion goes away for good. It does not improve the model but it improves what you see, and the marks could later tune the threshold.
3. **Read more of each note.** Read the whole note, or weight lines near the top more, instead of the first 800 characters.
4. **Use the words people actually write.** Add an exact-word boost for rare words that two notes share, so abbreviations the model does not know still count.
5. **Multi-word titles.** Treat a title as one phrase as well as separate words.
6. **Keep the weights up to date note by note** instead of recomputing everything, if collections grow large.
7. **A better model**, if the cost in size and cross-device differences becomes acceptable. See above.

## Change log

- **5 November 2026: first version.** Averaged word vectors from Apple's English model, cut-off 0.5 on cosine similarity, top five, opt-in setting. Replaced a first attempt with Apple's sentence model after it ranked an unrelated pair above a related one.
- **5 November 2026: weighting, centring and bonuses.**
  - Words scaled by inverse document frequency and title words doubled.
  - The average of all notes' vectors taken off each vector. Without this, unrelated notes scored 0.8 to 0.9. With it, the cut-off of 0.5 gave 14 pairs on 81 real notes, mostly sensible.
  - Bonus of 0.05 per shared tag or person (up to two) and 0.02 for the same project.
  - Notes with fewer than two known words left out, since one-word notes such as "test" matched each other perfectly. The words "untitled", "note" and "notes" are ignored.
