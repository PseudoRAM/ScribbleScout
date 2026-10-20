#!/usr/bin/env python3
"""Summarize the frozen synthetic held-out run. No network or dependencies."""
import hashlib
import json
from pathlib import Path
from statistics import median

root = Path(__file__).resolve().parents[1] / 'docs/evaluations/pause-v1'
manifest = json.loads((root / 'manifest.json').read_text())
results = json.loads((root / 'heldout-results.json').read_text())
for name, digest in json.loads((root / 'inputs.sha256.json').read_text()).items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
samples = {s['id']: s for s in manifest['samples'] if s['split'] == 'heldout'}
rows = results['rows']
assert len(rows) == len(samples) == 12
assert {r['id'] for r in rows} == set(samples)
assert results['usage']['toolCalls'] == 0
for r in rows:
    assert r['expectedRoute'] == samples[r['id']]['expectedRoute']
    assert r['useful'] == samples[r['id']]['useful']
    if 'actualRoute' in r:
        assert r['routeCorrect'] == (r['actualRoute'] == r['expectedRoute'])
        # Frozen dfc4b8f coordinator suppresses recall and none; current builds may differ.
        assert r['finalPinProxy'] == (r['actualRoute'] not in ('none', 'recall'))

useful = [r for r in rows if r['useful']]
quiet = [r for r in rows if not r['useful']]
pins = [r for r in rows if r.get('finalPinProxy', False)]
actionable = [r for r in useful if r.get('finalPinProxy', False) and r.get('routeCorrect', False)]
metrics = {
    'scope': 'Synthetic single run; final pin and actionable usefulness are code-derived proxies, not observed user ratings',
    'n': len(rows),
    'errors': sum('error' in r for r in rows),
    'normalizedExactTranscripts': sum(r.get('transcript', '').split() == samples[r['id']]['text'].split() for r in rows),
    'correctRoutes': sum(r.get('routeCorrect', False) for r in rows),
    'finalPinProxyCount': len(pins),
    'unwantedFinalPinProxy': {'count': sum(r.get('finalPinProxy', False) for r in quiet), 'quietSamples': len(quiet)},
    'missedUsefulFinalPinProxy': {'count': len(useful) - len(actionable), 'usefulSamples': len(useful)},
    'correctActionablePinProxy': {'count': len(actionable), 'allFinalPins': len(pins)},
    'latencySeconds': {},
}
for field in ('recognitionSeconds', 'routingSeconds', 'pipelineSeconds', 'estimatedPauseToReviewSeconds'):
    values = [r[field] for r in rows if field in r]
    metrics['latencySeconds'][field] = {'n': len(values), 'median': median(values), 'max': max(values)}
print(json.dumps(metrics, indent=2))
