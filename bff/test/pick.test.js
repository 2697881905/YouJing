import test from 'node:test';
import assert from 'node:assert/strict';
import { candidateIdsOf, guardPick, validatePickRequest } from '../src/services/pickGuard.js';

function bodyOf() {
  return {
    city: '杨凌',
    days: 1,
    pace: 'standard',
    interests: '文化/休闲',
    candidates: [
      {
        id: 's1', name: '教稼园', tag: '经典', brief: '农业始祖后稷教民稼穑之地',
        district: '杨陵区', popularity: 70, suggestedDuration: 60, requiresBooking: false
      },
      {
        id: 's2', name: '农高会会址', tag: '经典', brief: '农业高新科技成果博览会会址',
        district: '杨陵区', popularity: 80, suggestedDuration: 90, requiresBooking: true
      }
    ]
  };
}

test('accepts a valid pick request', () => {
  assert.equal(validatePickRequest(bodyOf()), '');
  assert.deepEqual(candidateIdsOf(bodyOf()), ['s1', 's2']);
});

test('rejects empty candidates and duplicate ids', () => {
  const empty = bodyOf();
  empty.candidates = [];
  assert.notEqual(validatePickRequest(empty), '');
  const dup = bodyOf();
  dup.candidates.push({ ...dup.candidates[0] });
  assert.notEqual(validatePickRequest(dup), '');
});

test('guard requires every candidate exactly once', () => {
  const ids = ['s1', 's2'];
  assert.throws(() => guardPick({ ranked: [{ id: 's1', reason: '顺路' }] }, ids));
  assert.throws(() => guardPick({ ranked: [{ id: 's1', reason: '' }, { id: 's1', reason: '' }] }, ids));
  assert.throws(() => guardPick({ ranked: [{ id: 's1', reason: '' }, { id: 'sx', reason: '' }] }, ids));
});

test('guard trims reasons and note, rejects overlong reason', () => {
  const out = guardPick({
    ranked: [{ id: 's2', reason: ' 会址适合先看 ' }, { id: 's1', reason: ' 园子小而安静 ' }],
    note: ' 一天先看会址再看教稼园 '
  }, ['s1', 's2']);
  assert.equal(out.ranked[0].reason, '会址适合先看');
  assert.equal(out.note, '一天先看会址再看教稼园');
  assert.throws(() => guardPick({
    ranked: [{ id: 's1', reason: 'x'.repeat(81) }, { id: 's2', reason: '' }]
  }, ['s1', 's2']));
});
