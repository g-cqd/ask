---- MODULE CredentialRefresh ----
\* The refresh protocol of ClaudeAccess and CodexAccess (ADR-0036, ADR-0039, ADR-0073), hand-written from
\* Sources/AskAI/Claude/ClaudeAccess.swift and Sources/AskAI/Credentials/CredentialFile.swift.
\*
\* Processes are ask runs that find the stored credentials expired. The server rotates the refresh token:
\* a token is accepted once. A run holds the refresh lock across the request and takes the save lock only
\* for the compare-and-replace. The user may sign out and in again at any time.
\*
\* MaySaveFail models a save that cannot complete after the refresh succeeded: the save lock times out
\* (CredentialFileError.locked after 5 s), the disk is full, or the rename fails. ClaudeAccess.auth then
\* throws .storage and drops the refreshed credentials.
EXTENDS Naturals, FiniteSets

CONSTANTS Runs, MaxLogins, MaySaveFail

VARIABLES stored,   \* the refresh token of the record in the file, or 0 when signed out
          spent,    \* refresh tokens the server has already accepted
          next,     \* the next token the server will issue
          lock,     \* the refresh lock: "free" or the run that holds it
          pc, cur,  \* per run: where it is, and the record it loaded under the lock
          logins,   \* how many sign-ins the user has made
          fresh     \* per run: the token the server issued to it, or 0

vars == <<stored, spent, next, lock, pc, cur, logins, fresh>>

Init ==
    /\ stored = 1
    /\ spent = {}
    /\ next = 2
    /\ lock = "free"
    /\ pc = [r \in Runs |-> "start"]
    /\ cur = [r \in Runs |-> 0]
    /\ logins = 1
    /\ fresh = [r \in Runs |-> 0]

\* auth(): load; expired; take the refresh lock.
Lock(r) ==
    /\ pc[r] = "start"
    /\ stored # 0
    /\ lock = "free"
    /\ lock' = r
    /\ pc' = [pc EXCEPT ![r] = "locked"]
    /\ UNCHANGED <<stored, spent, next, cur, logins, fresh>>

\* guard let credentials = try load() else { throw .signedOut }
Reload(r) ==
    /\ pc[r] = "locked"
    /\ IF stored = 0
          THEN /\ pc' = [pc EXCEPT ![r] = "done"]
               /\ lock' = "free"
               /\ cur' = cur
          ELSE /\ pc' = [pc EXCEPT ![r] = "loaded"]
               /\ cur' = [cur EXCEPT ![r] = stored]
               /\ lock' = lock
    /\ UNCHANGED <<stored, spent, next, logins, fresh>>

\* client.refresh(credentials): the server accepts a token once.
Refresh(r) ==
    /\ pc[r] = "loaded"
    /\ IF cur[r] \in spent
          THEN /\ pc' = [pc EXCEPT ![r] = "refused"]      \* throw .refreshFailed
               /\ UNCHANGED <<spent, next, fresh>>
          ELSE /\ spent' = spent \cup {cur[r]}
               /\ fresh' = [fresh EXCEPT ![r] = next]
               /\ next' = next + 1
               /\ pc' = [pc EXCEPT ![r] = "refreshed"]
    /\ UNCHANGED <<stored, lock, cur, logins>>

\* file.saveClaude(refreshed, ifStill: credentials): one transaction under the save lock.
Save(r) ==
    /\ pc[r] = "refreshed"
    /\ IF stored = cur[r]
          THEN stored' = fresh[r]
          ELSE stored' = stored
    /\ pc' = [pc EXCEPT ![r] = "saved"]
    /\ UNCHANGED <<spent, next, lock, cur, logins, fresh>>

\* try file.saveClaude throws .storage(...): the refreshed credentials are dropped.
SaveFails(r) ==
    /\ MaySaveFail
    /\ pc[r] = "refreshed"
    /\ pc' = [pc EXCEPT ![r] = "storageError"]
    /\ UNCHANGED <<stored, spent, next, lock, cur, logins, fresh>>

\* defer { lock.release() }, on every way out.
Release(r) ==
    /\ pc[r] \in {"saved", "refused", "storageError"}
    /\ lock = r
    /\ lock' = "free"
    /\ pc' = [pc EXCEPT ![r] = "done"]
    /\ UNCHANGED <<stored, spent, next, cur, logins, fresh>>

\* The user: sign out, or sign in again (a new grant, a new refresh token).
Logout ==
    /\ stored # 0
    /\ stored' = 0
    /\ UNCHANGED <<spent, next, lock, pc, cur, logins, fresh>>

Login ==
    /\ logins < MaxLogins
    /\ stored' = next
    /\ next' = next + 1
    /\ logins' = logins + 1
    /\ UNCHANGED <<spent, lock, pc, cur, fresh>>

Next == \/ \E r \in Runs : Lock(r) \/ Reload(r) \/ Refresh(r) \/ Save(r) \/ SaveFails(r) \/ Release(r)
        \/ Logout \/ Login

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ lock \in Runs \cup {"free"}
    /\ pc \in [Runs -> {"start", "locked", "loaded", "refreshed", "saved", "refused", "storageError", "done"}]
    /\ stored \in 0..next
    /\ spent \subseteq 1..next

\* What the user sees once no run is between the server's answer and the save: a stored token the server
\* will refuse is a sign-out in all but name.
StoredTokenUsable == (\A r \in Runs : pc[r] # "refreshed") => (stored # 0 => stored \notin spent)

\* The refresh lock excludes: at most one run between taking it and releasing it.
OneRefresher == Cardinality({r \in Runs : pc[r] \in {"locked", "loaded", "refreshed", "saved", "refused", "storageError"}}) <= 1

\* A refresh never offers a token the server has already accepted.
NoDoubleSpend == \A r \in Runs : pc[r] # "refused"

\* A sign-out stands: nothing a run does brings the old record back.
SignOutStands == [][(stored = 0) => (stored' = 0 \/ stored' \notin spent)]_stored
====
