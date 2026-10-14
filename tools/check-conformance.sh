#!/bin/sh
# Read-only checks of required docs, selected live references, scans, and indexes.
set -eu
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import json,re,subprocess,sys
root=Path(sys.argv[1]).resolve();fail=False
required='README.md HANDOFF.md SCOPE.md RULES.md AGENTS.md STATE.json TARGETS.md FINDINGS.md STATUS.md'.split()
optional='FOCUS.md PLAN.md'.split()
for program in sorted((root/'programs').iterdir()):
    if not program.is_dir():continue
    # A stray/scratch directory that is not a program skeleton must not turn this check
    # permanently red -- a check nobody can pass stops being read. A real program always
    # carries README.md or STATE.json (the template ships both), so skip anything with
    # neither, and SAY SO rather than skipping in silence.
    if not ((program/'README.md').is_file() or (program/'STATE.json').is_file()):
        print(f'SKIP: {program.name}/ is not a program skeleton (no README.md, no STATE.json)');continue
    for name in required:
        if not (program/name).is_file():print(f'MISSING: {program.name}/{name}');fail=True
    docs=[program/name for name in required+optional if name.endswith('.md') and (program/name).is_file()]
    docs += [p for p in (program/'recon/reports').glob('*.md')]
    docs += [program/'recon/inventory'/name for name in ('discovery-gate.md','identity-rendered-evidence.md','writeoffs.md') if (program/'recon/inventory'/name).is_file()]
    for doc in docs:
        text=doc.read_text()
        refs=re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)',text)
        inline=re.findall(r'`((?:recon|scripts|data)/[A-Za-z0-9_./-]+\.(?:md|txt|json|sh|py|env|tsv))`',text)
        refs += inline
        for ref in refs:
            if ref.startswith(('http:','https:','/','#')) or any(x in ref for x in ('<','>','*','{')):continue
            rel=ref.split('#',1)[0]
            base=program if ref in inline else doc.parent
            if rel and not (base/rel).exists():
                # Dated tick-* scripts were moved to recon/archive/scripts/; earlier
                # records name them at their former location (see HANDOFF.md).
                archived = program / 'recon/archive/scripts' / Path(rel).name
                if rel.startswith('scripts/') and archived.exists():
                    continue
                print(f'DEAD REF: {doc.relative_to(root)}: {ref}'); fail = True
    # STATE.json carries a PATH LIST (`recon.artifacts`): one entry per artefact the program produced,
    # repo-relative, sometimes grouped as a sub-list for one round. A path list is a CITATION and gets
    # the same treatment as a citation inside a document -- it must resolve. Nothing read that field
    # before (measured 2026-10-10): the reference scan above reads `.md` documents only, and the
    # citation-integrity producer's corpus is the documents by design, so 2 of one program's 259 entries
    # were spelled without their `artifacts/` prefix and NO instrument ever looked at them.
    state_path = program / 'STATE.json'
    if state_path.is_file():
        try:
            state = json.loads(state_path.read_text())
        except Exception as exc:
            print(f'INVALID: {program.name}/STATE.json is not valid JSON: {exc}'); fail = True
            state = None
        if isinstance(state, dict):
            arts = (state.get('recon') or {}).get('artifacts')
            flat, lane_only = [], 0
            if isinstance(arts, list):
                for entry in arts:
                    if isinstance(entry, str):
                        flat.append(entry)
                    elif isinstance(entry, list):
                        flat.extend(x for x in entry if isinstance(x, str))
            elif arts is not None:
                print(f'TYPE: {program.name} recon.artifacts is not a list'); fail = True
            for entry in flat:
                if entry.startswith('/'):
                    lane_only += 1          # an absolute path resolves on the LANE host, not here
                    continue
                if not (program / entry).exists() and not (root / entry).exists():
                    print(f'DEAD REF: {program.name}/STATE.json recon.artifacts: {entry}')
                    fail = True
            print(f'STATE refs: {program.name}/ recon.artifacts {len(flat)} entries, {lane_only} lane-only')
    # A program that ships a producer for its STATUS.md header counters gets it checked here.
    # Program-agnostic by construction: the hook names no program, it runs whichever ones opt in.
    hook = program / 'scripts' / 'status-header.py'
    if hook.is_file():
        r = subprocess.run(['python3', str(hook), '--check', '--program', str(program)])
        if r.returncode:
            print(f'DRIFT: {program.name}/STATUS.md header counters (scripts/status-header.py --check)')
            fail = True
    # A program that ships a TEST for its rule-8 producer gets it run here, and the hook names
    # no program: it runs whichever ones opt in by shipping the pinned basename. The verdict is
    # the EXIT CODE, never a printed line -- the suite prints per-check PASS/FAIL and
    # `sys.exit(1 if fails else 0)`, so a producer test that went red on main can no longer sit
    # unseen while this gate prints CONFORMANT (measured 2026-10-10: the suite's 7 red checks
    # were on main, and `OPEN (named, not wired)` was the only record of it). The suite writes
    # only to the program's gitignored `tmp/` scratch and deletes it, so the check stays
    # read-only over the tracked tree.
    # Pinned to the tests whose verdict is a check that can go red HERE, deliberately not globbed.
    # MEASURED 2026-10-10T1105Z, one-variable mutant A/B on a copy of the tree under scratch: all
    # three `scripts/*-test.py` carry a non-zero exit path -- `compress-state-test.py`
    # (`sys.exit(1 if fails else 0)`), `select-never-measured-test.py`
    # (`return 0 if not FAILS else 1` -> `raise SystemExit(main())`) and
    # `audit-family-literal-set-test.py` (`raise SystemExit(1)` on FAILURES) -- so the earlier
    # reading that only the first one had a contract was an artefact of a `grep -n sys.exit`
    # pattern, not a property of the files. Two of the three read the runtime lane `/opt/data/<lane>`,
    # which lives outside the repository; their `LANE` is now env-overridable (`LANE_DIR`) and, with no
    # lane present, each PRINTS a `SKIP:` line and exits 0 -- so they can be wired here without turning
    # this gate RED on a fresh clone, which is what blocked them (measured 2026-10-10T1111Z: lane absent
    # -> `SKIP:` rc=0, lane present -> the real verdict, one-line mutant -> rc=1). Only
    # `audit-blank-payload-class.py` has no exit path at all (it is a census instrument: no `sys.exit`,
    # `assert` or `raise`), so it stays unwired.
    suite = program / 'scripts' / 'compress-state-test.py'
    if suite.is_file():
        r = subprocess.run(['python3', str(suite), str(program / 'STATE.json')])
        if r.returncode:
            print(f'RED: {program.name}/ rule-8 producer test (scripts/compress-state-test.py, rc={r.returncode})')
            fail = True
    # The other two producers of the same family are wired here now that they can run off-lane. Each
    # reads the engagement lane (outside the repository) at a path its `LANE_DIR` env var overrides,
    # and with no lane present prints `SKIP:` and exits 0 -- never read a bare rc=0 as "the corpus was
    # checked": read the `SKIP:` line. Measured 2026-10-10T1111Z on a copy of this tree: with no lane
    # both SKIP rc=0, with the lane both return their real verdict, and a one-line mutant in either
    # makes THIS gate print VIOLATIONS FOUND rc=1 (the pair it was written to catch: the law that prices
    # the queue ran nowhere the gate could see).
    # `delta-asset-census-test.py` joined this set 2026-10-10T1220Z for the same reason: a verdict FIELD the
    # next delta tick reads (`assets_match_recorded`) was derived with an extractor anchored on the `src=`/
    # `href=` ATTRIBUTE, so it reported a js/css ROTATION on a body whose literal set had not rotated -- the
    # record's own reopen signal for that axis. The test reads the producer's compiled pattern out of the
    # producer source (never re-typed), asserts every recorded literal is found by it, and pins the defect
    # signature (the attribute-anchored form finds 3 of 8). Lane absent -> `SKIP:` rc=0, so a fresh clone
    # stays CONFORMANT; a producer whose pattern is narrowed back -> rc=1 through this gate.
    # `isolate-document-delta-test.py` joined 2026-10-10T1430Z: it settles a SIZE delta between two
    # retained documents, and the record carried one such delta ("+26 B not isolated") across two rounds
    # while the cheapest wrong explanation (i18n key order) sat in the record as a plausible cause -- a
    # permutation cannot change a byte count. The test needs NO lane (synthetic documents under tempfile),
    # so it runs on a fresh clone and its verdict is real there too; its M1/M2 mutants pin the two
    # load-bearing parts (the canonicalisation, and the completeness gate that refuses a partial
    # attribution).
    # `store-stamp-index-test.py` joined 2026-10-10T1446Z: the previous round recorded that the
    # document-shipped i18n store is GLOBAL and proposed a per-stamp store diff as a delta source.
    # Both halves are claims with opposite consequences -- a shared blob makes a diff of any two
    # documents describe the estate; a per-document store makes it valid only SAME-DOCUMENT across
    # stamps. The test needs NO lane (synthetic bodies under tempfile) and pins the projector's
    # identity/canonicalisation/stamp-key/latest-date behaviour, so the verdict is real on a clone.
    # `state-canonical-format-test.py` joined 2026-10-10T1500Z: a tick rewrote STATE.json, compared the
    # size of its in-memory STRING (207 971) against the committed file (208 080 B) and recorded the
    # 109-byte gap as an unidentified SECOND WRITER of the shared document -- an open item handed to the
    # next tick. The gap is the UTF-8 width of the 55 non-ASCII characters already in the document
    # (54 x U+2026 = +2 each, 1 x U+00EA = +1): 54*2 + 1*1 = 109. `len(str)` counts characters, a file
    # counts bytes. The check the record now ships settles that class mechanically (the live document must
    # be byte-identical to its canonical serialisation) and its test pins the two REAL drift classes the
    # record carries -- a writer left on `ensure_ascii=True` (+166 B here, 20261010T041649Z) and a writer
    # that drops the trailing newline (20261010T141237Z) -- with the mutant that PARSES EQUAL to the
    # canonical document, so parsed equality is proved insufficient. Needs NO lane.
    # `shell-inline-route-census-test.py` joined 2026-10-10T1550Z: a tick re-keyed the retained
    # SHELL corpus by the URL each dump actually REQUESTED (the harvesting path could not pair the
    # corpus's own repeated captures) and added the same-shell cross-stamp pairing the store corpus
    # already carried. The test needs NO lane (synthetic shells under tempfile): T1 pairs two
    # differently-labelled dumps of one path and reads the literal the later build added (mutant M1
    # keys on the harvesting name and pairs nothing), T2 partitions one path on two hosts and pairs
    # INSIDE each subgroup (never across - mutant M2 pairs `ads.` against `seller.`), T3 requires the
    # identity accounting to be total and the literal digest reproducible, T4 requires the clone-safe
    # SKIP, T5 requires a one-stamp subgroup to yield no pair and a host-less member to be reported
    # unassignable. M3 RUNS the mutation (the source is loaded twice, once with the partition
    # disabled) and requires the mutant to be caught while the real producer stays clean. It also
    # FAILS if the producer stops resolving the URL through the record's own instrument.
    # T6 + M4 joined 2026-10-10T1609Z: the same host-scoped set is then back-partitioned by DOCUMENT
    # SHAPE (inline block count + byte magnitude), because a pair could otherwise compare two shapes of
    # one path and publish their byte delta as a rebuild. T6 requires a two-shape path to yield NO pair
    # and both single-stamp shape subgroups to be REPORTED as `shape_unpaired`, while a one-shape sibling
    # still pairs; M4 RUNS the mutation (the shape key collapsed to a constant) and requires the mutant's
    # pair to carry `shape_comparable` false and to trip I10, with the real producer clean on the same
    # rows. The cells build their `shape` through the loaded producer's own `shape_signature`.
    # The INTERVAL axis joined the same two test files on 2026-10-10T1657Z: both corpus producers
    # compared a subgroup only at its FIRST and LAST stamp, so a subgroup holding three stamps had
    # its middle stamp folded into ONE widened window (store T12 + M7 -> invariant I4d; census
    # T7 + M5 -> invariant I13). A widened window answers the question "did this change between the
    # first and last capture" while the record asked "in which interval did it land", and the two
    # get confused precisely because both are expressed as a pair of stamps. Each cell asserts the
    # FULL consecutive interval set of a three-stamp subgroup, and each mutant collapses the loop
    # to the first interval and must exit non-zero naming its invariant while the real producer
    # stays clean on the same rows. Needs NO lane (synthetic documents under tempfile).
    # `same-stamp-spread-test.py` joined 2026-10-10T1743Z: the census publishes `inline_sha_changed`
    # and `inline_byte_delta` as a rebuild signal, and the retained corpus holds captures of ONE page
    # at ONE stamp that DISAGREE in their inline bytes (measured: four captures of
    # one application page at `20261010` carry four inline digests while their
    # key-sorted i18n store digest is ONE). The cells build synthetic bodies under tempfile (no lane):
    # T1 a 400-unit same-stamp band makes a +50 delta `within_same_stamp_spread`, T2 a store whose keys
    # moved order keeps ONE store digest and TWO inline digests with a 0-byte band so its +874 delta
    # `exceeds_same_stamp_spread`, T3 a once-per-stamp page is `band_unmeasured` (never a claimed zero
    # band), T4 the interval classification is total. M1 RUNS the mutation (the same-stamp grouping
    # collapsed to per-member) and requires the mutant to lose the band and disagree with the producer
    # on the same bytes.
    for name in ('select-never-measured-test.py', 'audit-family-literal-set-test.py',
                 'delta-asset-census-test.py', 'audit-open-question-ledger-test.py',
                 'audit-pricing-pair-set-test.py', 'isolate-document-delta-test.py',
                 'store-stamp-index-test.py', 'state-canonical-format-test.py',
                 'shell-inline-route-census-test.py', 'same-stamp-spread-test.py'):
        t = program / 'scripts' / name
        if not t.is_file():
            continue
        r = subprocess.run(['python3', str(t)])
        if r.returncode:
            print(f'RED: {program.name}/ producer test scripts/{name} rc={r.returncode}')
            fail = True
    # `mode_ambiguous` is published by TWO producers (`store-stamp-index.py`,
    # `shell-inline-route-census.py`) and their formulas differ on ONE cell: two captures of one
    # stamp INSIDE one request context. The audit drives both producers' own pair constructors on a
    # four-case grid, classifies every pair of each producer's latest artifact against that grid, and
    # censuses every tracked file that READS the flag. `--strict` is ON since 20261010T1944Z: the
    # divergence was UNIFIED (the store producer's flag now matches the shell census's documented
    # reading - the flag says the record cannot name a context for every member, and the
    # separation fact keeps its own name on each side), so a re-divergence is a violation again
    # and must red the gate instead of being carried as a note.
    audit = program / 'scripts' / 'audit-mode-ambiguous-definition.py'
    if audit.is_file():
        r = subprocess.run(['python3', str(audit), '--out', '/dev/null', '--strict'],
                           capture_output=True, text=True)
        if r.returncode:
            print(f'RED: {program.name}/ consumer-definition audit scripts/'
                  f'audit-mode-ambiguous-definition.py rc={r.returncode}')
            fail = True
        else:
            for line in r.stdout.splitlines():
                if line.startswith('CROSS-PRODUCER DIVERGENCES') and 'none' not in line:
                    print(f'NOTE: {program.name}/ {line}')
    # Cross-artefact invariant: consumers of one corpus must exclude the loop's own output by the
    # SAME set of shapes, or one of them counts the loop's output as evidence. Names no script and
    # no program: it reads whichever ones declare `*ARTEFACT = re.compile(...)` constants, compares
    # the SHAPE per constant name (a consumer that edits its exclusion alone is caught), and
    # requires the SET of constant names to be identical across the consumers (a consumer that adds
    # a rule alone is caught too). Measured 2026-10-10 -- the same producer shape was declared under
    # a different constant name in each consumer, so per-name comparison alone went blind; the set
    # check is what makes the two names have to agree.
    per_name = {}
    artefact_sets = {}
    for s in sorted((program / 'scripts').glob('*.py')):
        text = s.read_text(errors='replace')
        names = re.findall(r'^([A-Z][A-Z0-9_]*ARTEFACT)\s*=\s*re\.compile\(', text, re.M)
        if names:
            artefact_sets[s.name] = set(names)
        for m in re.finditer(r'^([A-Z][A-Z0-9_]*ARTEFACT)\s*=\s*re\.compile\(', text, re.M):
            i = m.end()
            depth, j = 1, i
            while j < len(text) and depth:
                if text[j] == '(':
                    depth += 1
                elif text[j] == ')':
                    depth -= 1
                j += 1
            norm = re.sub(r'\s+', '', text[i:j - 1])
            per_name.setdefault(m.group(1), {}).setdefault(norm, []).append(s.name)
    if len(artefact_sets) > 1:
        union = set().union(*artefact_sets.values())
        for fn, ns in sorted(artefact_sets.items()):
            if ns != union:
                print(f'DRIFT: {program.name}/ {fn} declares exclusion constants {sorted(ns)} '
                      f'but its sibling consumer(s) declare {sorted(union)}')
                fail = True
    for name, variants in sorted(per_name.items()):
        if len(variants) > 1:
            print(f'DRIFT: {program.name}/ {name} shape disagrees between consumers: '
                  + ' vs '.join(f'{c!r} ({", ".join(n)})' for c, n in variants.items()))
            fail = True
for cmd in (["sh",str(root/'tools/scan-secrets.sh'),str(root)], ["sh",str(root/'tools/build-rounds.sh'),'--check',str(root)]):
    if subprocess.run(cmd).returncode:fail=True
print('Checks cover required docs, selected live references, supported secret patterns, generated indexes, and any per-program producer test that ships an exit-code contract.')
print('VIOLATIONS FOUND' if fail else 'CONFORMANT')
sys.exit(1 if fail else 0)
PY
