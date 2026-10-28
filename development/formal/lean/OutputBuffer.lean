/-!
# `OutputBuffer` and `Compaction.clipped`, modelled

A stream is a list of bytes. `OutputBuffer(keeping: k)` keeps the first `k` bytes (`head`), the last `k` of the
rest (`tail`), and counts the bytes between (`omitted`). `kept` is `head ++ tail`. `Job.wait(for:)` searches `kept`
for a text.

Source: `Sources/AskTools/OutputBuffer.swift`. The ring buffer is modelled by what it holds, not how it rotates.
-/

namespace OutputBuffer

def head (k : Nat) (s : List Nat) : List Nat := s.take k
def tail (k : Nat) (s : List Nat) : List Nat := (s.drop k).drop ((s.drop k).length - k)
def kept (k : Nat) (s : List Nat) : List Nat := head k s ++ tail k s
def omitted (k : Nat) (s : List Nat) : Nat := s.length - 2 * k

/-- What the code promises: the kept bytes and the omitted count account for the whole stream. -/
theorem accounts (k : Nat) (s : List Nat) : (kept k s).length + omitted k s = s.length := by
  simp only [kept, head, tail, omitted, List.length_append, List.length_take, List.length_drop]
  omega

/-- Memory is bounded by `2k` however much the command prints. -/
theorem bounded (k : Nat) (s : List Nat) : (kept k s).length ≤ 2 * k := by
  simp only [kept, head, tail, List.length_append, List.length_take, List.length_drop]
  omega

/-- A stream no longer than `2k` is kept whole. -/
theorem whole (k : Nat) (s : List Nat) (h : s.length ≤ 2 * k) : kept k s = s := by
  simp only [kept, head, tail]
  have h1 : (s.drop k).length - k = 0 := by simp only [List.length_drop]; omega
  rw [h1]
  simp

/-- Searching `kept` is searching the stream only if `kept` is a run of it. It is not: here `[5,6]` is found in
the kept bytes of a stream that never contains it. This is the fault `Job.wait(for:)` has. -/
example : [5, 6] <:+: kept 2 [1, 5, 9, 9, 9, 9, 6, 2] ∧ ¬ [5, 6] <:+: [1, 5, 9, 9, 9, 9, 6, 2] := by
  decide

/-- The gap is exactly the omitted middle: whenever bytes were omitted, `kept` is the stream with them deleted,
so a text can straddle the join and appear in `kept` without appearing in the stream. -/
theorem join_is_not_adjacent : omitted 2 [1, 5, 9, 9, 9, 9, 6, 2] = 4 := by decide

/-! ## Cutting at bytes -/

/-- A two-byte character, `é` as UTF-8, is `[0xC3, 0xA9]`. Cutting the stream `ééé` after three bytes splits the
second one: the head ends in a lead byte with no continuation. -/
def e : List Nat := [0xC3, 0xA9]

example : (head 3 (e ++ e ++ e)) = [0xC3, 0xA9, 0xC3] := by decide

/-- `0xC3` alone is not valid UTF-8 (a lead byte must be followed by a continuation byte `0x80…0xBF`), so
`String(decoding:)` replaces it with U+FFFD. -/
def isLead (b : Nat) : Bool := 0xC0 ≤ b && b < 0xF8
def endsMidCharacter (bs : List Nat) : Bool :=
  match bs.reverse with
  | b :: _ => isLead b
  | [] => false

example : endsMidCharacter (head 3 (e ++ e ++ e)) = true := by decide

end OutputBuffer
