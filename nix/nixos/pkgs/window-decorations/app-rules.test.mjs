import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../dist/settings/app-rules.js', import.meta.url), 'utf8')
    .replace(/^import .*;$/gm, '').replaceAll('export ', '');
const {parseRules, selectRule, applyRule} = vm.runInNewContext(`${source}\n({parseRules, selectRule, applyRule});`, {
    readShadowConfig: (_, focused, strength) => ({focused, strength}),
});

test('desktop IDs are case insensitive; unlisted applications bypass the effect', () => {
    const rules = parseRules(JSON.stringify({rules: [{match: ['Codex.desktop'], radius: 6}]}));
    assert.equal(selectRule(rules, ['codex'])?.radius, 6);
    assert.equal(selectRule(rules, ['kitty']), null);
});

test('per-app values inherit defaults independently; first disabled match blocks later rules', () => {
    const rules = parseRules(JSON.stringify({defaults: {radius: 10, shadow: false}, rules: [
        {match: ['codex'], enabled: false},
        {match: ['codex'], radius: 4},
        {match: ['kitty'], corners: false, shadow: true, shadowStrength: 70},
    ]}));
    assert.equal(selectRule(rules, ['codex']).enabled, false);
    const kitty = selectRule(rules, ['kitty']);
    assert.equal(kitty.radius, 10);
    const cfg = applyRule({}, kitty, {});
    assert.equal(cfg.cornerRadius, 0);
    assert.equal(cfg.customShadow, true);
    assert.equal(cfg.focusedShadow.strength, 70);
    assert.equal(cfg.keepRoundedFullscreen, false);
});

test('corners and shadow may be configured separately, with zero shadow allocating no shadow', () => {
    const [rule] = parseRules(JSON.stringify({rules: [{match: ['editor'], corners: true, radius: 5, shadowStrength: 0}]}));
    const cfg = applyRule({}, rule, {});
    assert.equal(cfg.cornerRadius, 5);
    assert.equal(cfg.customShadow, false);
    assert.equal(cfg.fillPadding, false);
});

test('reject invalid rules instead of silently broadening the affected applications', () => {
    for (const entry of [
        {match: []}, {match: [' ']}, {match: [42]}, {match: ['codex'], radius: -1},
        {match: ['codex'], radius: 1.5}, {match: ['codex'], smoothing: 2},
        {match: ['codex'], shadow: 'yes'}, {match: ['codex'], shadowStrength: 201},
        {match: ['codex'], raduis: 8},
    ]) assert.throws(() => parseRules(JSON.stringify({rules: [entry]})));
    assert.throws(() => parseRules('{'));
    assert.throws(() => parseRules(JSON.stringify({default: {}, rules: []})));
    assert.equal(parseRules(JSON.stringify({rules: []})).length, 0);
});
