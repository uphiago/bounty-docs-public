# Research methodology

Lessons from the campaigns recorded here. Apply them within each program's policy
and describe the evidence that supports a decision.

## Choose work from a queue

Recon should identify a testable surface and a reason to investigate it. A host
count measures inventory coverage. Track which sources were used, which names were
new, and what the next request could establish.

Repeated sweeps with no new names justify a longer interval for those sources.
They do not establish that every host, endpoint, or vulnerability class has been
examined. Stop a scheduled tick when no permitted, useful step is available.

## Use passive sources and record their coverage

Certificate Transparency supplemented passive enumeration in the first campaign:
CT yielded 11,048 names versus 5,779 from subfinder. These are source outputs from
that campaign, not a universal productivity ranking. Deduplicate and apply scope
before probing; certificate names may be historical or outside the program.

Queries to third-party CT services do not contact the target. Availability, rate
limits, and source completeness still constrain the result.

## Separate authorization, eligibility, and campaign restrictions

An asset can be eligible for submission without being eligible for a bounty.
Check both fields, asset-specific instructions, and program policy. A wildcard's
coverage, including the apex, depends on that policy. Treat URL assets as exact
listed assets unless the program explicitly authorizes broader testing.

A campaign may choose stricter limits, such as holding test environments or
restricting requests to read operations. Label those decisions as campaign policy.
Do not turn one program's rules into requirements for every program.

## Make identity configuration explicit

Configure the research header and runtime identity before sending requests. Keep
credentials outside version control and label captures before storing them.
Check that scanners and report examples use the same identity requirements.
Public attribution may appear in historical evidence; do not claim the repository
contains no researcher identity when it does.

## Check summaries against captures

Confirm timestamps, job status, request counts, and response content against the
available artifacts. A file can contain a summary, stale data, or an incomplete
capture. State where the original responses are retained and what is missing from
a checkout. Mark an unverified runtime state as unverified.

Consistency audits compare recorded fields. They cannot certify impact, a complete
scope interpretation, or runtime execution merely because matching files exist.
Generated reports should include a source hash so edits cannot leave a same-count
shortlist silently stale.

## Keep conclusions within the test

Record the host, endpoint, method, identity, control, result, and date. A failed
hypothesis is useful evidence for those conditions.

- A login redirect shows an anonymous access boundary on the tested route.
- A pre-login ReturnUrl test does not decide behavior after authentication.
- An edge denial can leave origin behavior untested.
- Several negative hosts can justify deprioritizing a technique without proving
  that the technique is absent from the estate.
- A CNAME or a technology fingerprint is a lead; claimability or exposure needs
  separate evidence specific to the service.

Use "not observed in the tested sample", "requires an identity", or "deprioritized"
when those descriptions fit. Revisit a negative only when its premise changes.

## Assess the operation, including GET requests

Method names describe expected HTTP semantics. Implementations can have side
effects; GET alone does not guarantee a read operation. The
[RFC 9110 safe-method discussion](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.1)
explicitly addresses actions selected through a URI.

A published cache-clear link suggests an action but does not prove anonymous
execution. Record it without invoking it when the campaign prohibits state changes.
Use method discovery cautiously; an invalid body does not make DELETE harmless.
A previous DELETE probe unlinked a test account because the server ignored its body.

CORS response headers require an authenticated data-read demonstration before
claiming cross-origin disclosure. Standard OIDC discovery metadata is intended to
be available to clients; its presence is not an authentication bypass. See the
[OpenID Connect discovery specification](https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderConfig).

## Preserve evidence without duplicating the narrative

Keep detailed evidence in a dossier or round artifact. Candidate entries summarize
the observation and limitation; journal entries explain decisions and link to the
record. Preserve old statements in the archive and add dated corrections.
Use explicit fields for target, severity, status, and disposition so tools do not
infer them from incidental words or hostnames in prose.

Never run an unrestricted recursive edit over a working tree that may contain
untracked credentials. Select tracked files or explicit paths. Secret scanning has
limited coverage: record known history exposure and do not claim a clean scan
proves the absence of all secrets or personal data.

## Document runtime constraints separately

Record configured schedules and observed executions separately. A recent scheduler
heartbeat does not establish that a job completed. Monitor execution failures and
silence, and scope automated recovery to diagnosed failures.

A script-stage lock can expire before an agent turn starts. A holder file with a
TTL reduces overlap but cannot guarantee exclusive execution after expiry or
priority override. Describe that limitation until the runtime owns the lock for the
full turn. Runtime-specific recovery procedures belong in the program's operating
notes rather than in the generic template.

## Rules this repository has paid for

The generic guidance above is field-neutral. These rules were each learned by paying for the mistake
once inside this repository, and they are what the surviving records are built on. They are campaign
lessons, not universal law — but a program that ignores them tends to re-learn them.

1. **Read the target's own output before sending a request.** Route tables in its JS chunks, its own
   error text, its own server-rendered pages and its own `robots.txt` produced the largest surface
   gains recorded here, at zero requests. Request volume is the slow path.
2. **Put a control in the same pass, and make it reach a backend.** An edge envelope (unmatched path,
   login redirect) can never detect a degraded estate, so it cannot control a route that does reach one.
3. **Compare bytes, never status codes or error codes.** One error code was measured in six distinct
   bodies across three statuses; the same 71 bytes arrived under two different statuses. Codes are not
   identities.
4. **A digest belongs to its pass context, not to its route** — session *and* locale. A cell captured
   with a session reads as the authenticated answer, and the same body differs by interface language
   when the locale differs.
5. **An ambiguous envelope proves nothing on its own.** Where an unmatched path and a matched but
   unauthenticated path answer identically, a claim needs an impossible sibling **inside the same
   family or prefix** that answers differently in the same pass.
6. **Published does not imply served.** A name a site declares may be served, bounced, or redirected;
   only the cell decides which. The inverse also holds — a host can serve a strictly allowlisted set of
   documents and bounce everything else.
7. **Never guess a parameter name or value.** The target names its own parameters, and a guessed key
   returns the binder's literal and proves nothing. A parameter that exists with no citable value stays
   blocked rather than being exercised with an invented one.
8. **Reachability is not impact.** A correct refusal is a *negative result*, and a `200` carrying a
   constant, a boolean, a UI string or the caller's own bootstrap carries no other principal's data.
9. **Compute derived lists; never type them.** A hand-typed list of "families we have not touched" was
   wrong in 11 of 12 entries. Every derived document in this repository names the producer that computes
   its numbers.
10. **Audit a derived closure at the literal, line-local.** A "the literal is already known" verdict
    built on prose proximity is adjacency, not evidence; the same test can also fail in both directions.
11. **Audit the producers themselves.** A queue filter that drops rows without a counter is a queue that
    lies; two separate shape filters in this repository hid real, registered routes until they were
    rewritten to print every bucket and to fail closed on unknown shapes.
12. **A record is state, not a transcript.** A state entry is one leading verdict clause plus the
    anchors it cites; the prose belongs in the round file. Archive the pre-compression document outside
    the tree, then assert that no entry, list length or anchor was lost.
13. **Write the blocked path down as a result.** When the missing input lives outside the authorized
    surface — a bundle on an out-of-scope host, a UI capture only the operator can make — record the
    exact input needed and stop. Documentation never widens scope, and a request to get the answer
    anyway is the failure mode this rule exists to prevent.
14. **Do not document a route from a path you constructed.** A constructed name that answers the
    unmatched envelope will read as "the route does not exist" forever; one such name hid a route the
    application publishes and answers as a success.

## Before submitting

- Reconfirm the asset and exclusions against current program policy.
- Include a reproducible request with the required headers and rate control.
- Separate observed impact from possible extensions.
- Include sanitized evidence and identify any missing original captures.
- Use permitted accounts and avoid destructive reproduction.
- Group occurrences only when the evidence supports a shared root cause.
- Have the operator review the report; acceptance, severity, and payout remain
  the program's decisions.
