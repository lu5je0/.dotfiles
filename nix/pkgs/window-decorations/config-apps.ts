import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {parseRules} from '../settings/app-rules.js';

const [, contents] = Gio.File.new_for_path(ARGV[0]).load_contents(null);
const rules = parseRules(new TextDecoder().decode(contents));
const ids = [...new Set(rules.filter(rule => rule.enabled &&
    ((rule.corners && rule.radius > 0) || (rule.shadow && rule.shadowStrength > 0)))
    .flatMap(rule => rule.match))];
print(new GLib.Variant('as', ids).print(true));
