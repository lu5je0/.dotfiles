import type Gio from 'gi://Gio';
import type {ExtensionConfig} from './config.js';
import {readShadowConfig} from './config.js';

export interface AppOptions {
    enabled: boolean;
    corners: boolean;
    radius: number;
    smoothing: number;
    shadow: boolean;
    shadowStrength: number;
    maximized: boolean;
    fullscreen: boolean;
}

export interface AppRule extends AppOptions {
    match: string[];
}

const DEFAULTS: AppOptions = {
    enabled: true, corners: true, radius: 8, smoothing: 0.25,
    shadow: true, shadowStrength: 100, maximized: false, fullscreen: false,
};
const BOOLEANS = ['enabled', 'corners', 'shadow', 'maximized', 'fullscreen'] as const;
const NUMBERS = {radius: [0, 50], smoothing: [0, 1], shadowStrength: [0, 200]} as const;

function object(value: unknown, path: string): Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value))
        throw new Error(`${path} must be an object`);
    return value as Record<string, unknown>;
}

function options(value: unknown, path: string): Partial<AppOptions> {
    const input = object(value, path);
    for (const key of Object.keys(input)) {
        if (!(BOOLEANS as readonly string[]).includes(key) && !(key in NUMBERS))
            throw new Error(`${path}.${key} is unknown`);
    }
    for (const key of BOOLEANS) {
        if (key in input && typeof input[key] !== 'boolean')
            throw new Error(`${path}.${key} must be a boolean`);
    }
    for (const [key, [min, max]] of Object.entries(NUMBERS)) {
        if (!(key in input)) continue;
        const n = input[key];
        if (typeof n !== 'number' || !Number.isFinite(n) || n < min || n > max ||
            (key !== 'smoothing' && !Number.isInteger(n)))
            throw new Error(`${path}.${key} must be ${key === 'smoothing' ? 'a number' : 'an integer'} in ${min}..${max}`);
    }
    return input as Partial<AppOptions>;
}

export function normalizeId(id: string): string {
    return id.trim().replace(/\.desktop$/i, '').toLowerCase();
}

/** Validate the whole document before replacing the last valid rules. */
export function parseRules(text: string): AppRule[] {
    const input = object(JSON.parse(text), 'config');
    for (const key of Object.keys(input))
        if (key !== 'defaults' && key !== 'rules') throw new Error(`config.${key} is unknown`);
    const defaults = {...DEFAULTS, ...options(input.defaults ?? {}, 'defaults')};
    if (!Array.isArray(input.rules)) throw new Error('rules must be an array');
    return input.rules.map((value, i) => {
        const entry = object(value, `rules[${i}]`);
        const {match, ...overrides} = entry;
        if (!Array.isArray(match) || !match.length ||
            match.some(id => typeof id !== 'string' || !normalizeId(id)))
            throw new Error(`rules[${i}].match must be a nonempty array of app identifiers`);
        return {...defaults, ...options(overrides, `rules[${i}]`), match: match.map(normalizeId)};
    });
}

/** First matching rule wins, including a disabled rule. Unmatched apps bypass rendering. */
export function selectRule(rules: AppRule[], identifiers: string[]): AppRule | null {
    const ids = new Set(identifiers.map(normalizeId));
    return rules.find(rule => rule.match.some(id => ids.has(id))) ?? null;
}

export function applyRule(base: ExtensionConfig, rule: AppRule, settings: Gio.Settings): ExtensionConfig {
    return {
        ...base,
        cornerRadius: rule.corners ? rule.radius : 0,
        smoothing: rule.smoothing,
        customShadow: rule.shadow && rule.shadowStrength > 0,
        focusedShadow: readShadowConfig(settings, true, rule.shadowStrength),
        unfocusedShadow: readShadowConfig(settings, false, rule.shadowStrength),
        keepRoundedMaximized: rule.maximized,
        keepRoundedFullscreen: rule.fullscreen,
        keepShadowMaximized: rule.maximized || rule.fullscreen,
        fillPadding: false,
        padding: {top: 0, bottom: 0, left: 0, right: 0},
        borderWidth: 0,
        blacklist: [], whitelistMode: false,
        skipLibadwaitaApp: false, skipLibhandyApp: false,
    };
}
