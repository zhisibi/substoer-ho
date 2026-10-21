#!/usr/bin/env python3
"""Static checks for ArkUI pitfalls that compile fine but break at runtime.

1. More than one .bindSheet / .bindContentCover / .bindPopup / .bindMenu on the SAME component: ArkUI keeps only
   the last binding of each kind, so the earlier sheets never open (the 1.2.x SFTP "new" / sort bug).
2. .bindMenu on an IconBtn (its inner onClick swallows the tap, the menu never opens).
3. $r('sys.symbol.X') names that the SDK does not define (they compile but render nothing / crash).
Exit 1 when anything is found."""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'entry/src/main/ets')
KINDS = ['bindSheet', 'bindContentCover', 'bindPopup', 'bindMenu', 'bindContextMenu']
bad = []


def indent(l):
    return len(l) - len(l.lstrip(' '))


for dp, _, fs in os.walk(ROOT):
    for f in fs:
        if not f.endswith('.ets'):
            continue
        p = os.path.join(dp, f)
        lines = open(p, encoding='utf-8').read().split('\n')
        seen = set()
        for i, l in enumerate(lines):
            m = re.match(r'\s*\.(' + '|'.join(KINDS) + r')\(', l)
            if not m or i in seen:
                continue
            ind = indent(l)
            # the modifier chain of one component: contiguous lines at this indent starting with '.', plus their
            # deeper continuation lines; stops at a line at this indent (or shallower) that is not a modifier
            j = i
            while j > 0:
                pl = lines[j - 1]
                if pl.strip() == '' or (indent(pl) <= ind and not pl.lstrip().startswith(('.', '}', ')'))):
                    break
                j -= 1
            k = i
            while k + 1 < len(lines):
                nl = lines[k + 1]
                if nl.strip() == '' or (indent(nl) <= ind and not nl.lstrip().startswith(('.', '}', ')'))):
                    break
                k += 1
            chain = [(n, lines[n]) for n in range(j, k + 1)]
            counts = {}
            for n, cl in chain:
                mm = re.match(r'\s*\.(' + '|'.join(KINDS) + r')\(', cl)
                if mm and indent(cl) == ind:
                    counts.setdefault(mm.group(1), []).append(n)
                    seen.add(n)
            for kind, ns in counts.items():
                if len(ns) > 1:
                    bad.append(f'{os.path.relpath(p, ROOT)}:{ns[0] + 1}: {len(ns)}x .{kind} on one component '
                               f'(lines {", ".join(str(n + 1) for n in ns)}); only the last one works')
            head = lines[j - 1] if j > 0 else ''
            if m.group(1) == 'bindMenu' and 'IconBtn(' in ''.join(x for _, x in chain[:1]) + head:
                bad.append(f'{os.path.relpath(p, ROOT)}:{i + 1}: .bindMenu on IconBtn (inner onClick eats the tap)')
import json
SDK_IDS = '/workspace/work/hmtools/command-line-tools/sdk/default/openharmony/toolchains/id_defined.json'
if os.path.exists(SDK_IDS):
    syms = {r['name'] for r in json.load(open(SDK_IDS))['record'] if r.get('type') == 'symbol'}
    for dp, _, fs in os.walk(ROOT):
        for f in fs:
            if f.endswith('.ets'):
                p = os.path.join(dp, f)
                for i, l in enumerate(open(p, encoding='utf-8')):
                    for m in re.finditer(r"sys\.symbol\.([A-Za-z0-9_]+)", l):
                        if m.group(1) not in syms:
                            bad.append(f'{os.path.relpath(p, ROOT)}:{i + 1}: unknown system symbol {m.group(1)}')
for b in bad:
    print(b)
print('check-arkui:', 'FAIL' if bad else 'ok')
sys.exit(1 if bad else 0)
