# Highlighting a bash call's command, and its heredocs (t128)

The owner (2026-11-23): "set some research/implementation task to try to syntax highlight heredoc in calls rendering in blocks
if possible". What is known, measured or read, and what is not.

## How often, and what for

All plain session logs on the development Mac, read 2026-11-23:

| Measure | Value |
|---|---|
| `bash` calls | 66,579 |
| with a heredoc | 18,275 (27 %), 23,985 heredocs |
| reader | `python3` 14,033 (59 %), `cat` 8,830 (37 %), the rest under 1 % each (`git`, `ssh`, `osascript`) |
| delimiter | quoted (`<<'EOF'`) 23,376 (97 %), bare 609; `<<-` twice |
| what `cat` writes | `.swift` 5,018, no extension 1,764, `.md` 867, `.py` 669, `.sh` 410, `.json` 138 |
| body length | 16 lines at the median, 65 at p90, 724 at most |

A quarter of the commands the person reads are mostly a program in another language, shown today as plain brightened text.

## What ask and AemiLexers do today

- A command block's command rows are only brightened (`ScreenComposer+CommandBlock.brightened`); nothing is highlighted.
- AemiLexers has a `.shell` language (keywords, `$word` and `${…}` as attributes, strings, comments) through `CodeScanner`, and
  scans a text a line at a time from a `LexState` of **32 bits**, so a line can be scanned again without the ones before it.
- It knows no heredoc: a body is read as shell, so Python's `#` comments are shell comments and its quotes shell strings.

## The shell's rules, probed on bash 3.2 (macOS's `/bin/bash`)

`cat <<EOF` expands `$HOME`; `<<"EOF"` and `<<'EOF'` do not; `<<-EOF` strips leading tabs, the closing word included; two
heredocs on one line (`cat <<A; cat <<B`) take their bodies in order; the rest of the line goes on (`<<EOF | tr`, `<<'END' > f`);
a heredoc inside `$(…)` works the same. A body ends at a line equal to the word (after tabs with `<<-`), else at the text's end.

## Design questions, with a first answer each

1. **Remembering the word in 32 bits.** It cannot be held. Two ways: (a) a hash of the word in the state, a closing line found by
   hashing each line (a collision ends the body early, in colour only); (b) the lexer keeps a side table of words, and the state
   holds an index. (a) keeps `LineLexer` stateless and needs no change to its contract. **First answer: (a)**, 24 bits of hash
   and 8 of mode, tested on collisions.
2. **The body's language.** From the reader: `python3`, `python`, `node`, `ruby`, `swift`, `sh`/`bash`/`zsh`, `osascript`
   (AppleScript, none in AemiLexers: plain). From the target when the reader is `cat`/`tee`: the extension of `> file` or
   `tee file`. From a shebang on the body's first line. Else plain. In ask: the choice reads the command, not the lexer.
3. **A body in another language spans lines.** Its own state must go on across them: the outer state says "in a heredoc of
   language L, word hash H" and the inner lexer's state must fit too. With 32 bits that is too little for both. **First answer:**
   lex the body as a text of its own (the lines from the opening to the closing word), which ask has whole once the call is
   complete; during streaming, re-lex the body's last lines only (bodies are 16 lines at the median).
4. **Where it belongs.** Finding heredocs and their bodies is generic (any shell highlighter wants it): AemiLexers, as a
   `Language.shell` refinement or a `HeredocScanner`. Guessing the body's language from the reader and the target is ask's.
5. **Cost.** A command is re-shown on every streamed delta; highlighting must stay within the 4 ms input budget at 724 lines.
   To measure: AemiLexers' shell scan per line, and the body scans, on the largest command in the logs.
6. **What stays.** The full-brightness rule for a command (it is what the person approves) must survive: colours from the
   highlighter at full brightness, not dimmed.

## Not known yet

- Whether AemiLexers' maintainers (the same owner) want heredocs in the shell language or beside it.
- The cost of highlighting on the largest commands (question 5): not measured.
- Whether highlighting the shell part itself (keywords, variables, strings) helps reading or only adds colour: the owner's call
  once seen.

## Plan

1. AemiLexers: heredoc recognition in the shell scanner (state per question 1), bodies reported as ranges with their word and
   whether quoted; tests from the probed rules above.
2. ask: the body's language (question 2); the command rows highlighted, bodies by their language; full brightness kept.
3. Measure (question 5) and a PTY probe of a streamed `python3 - <<'EOF'` call.
