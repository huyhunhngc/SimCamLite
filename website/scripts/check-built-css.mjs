import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = new URL('../dist/_astro/', import.meta.url).pathname;
const css = readdirSync(dir)
  .filter((f) => f.endsWith('.css'))
  .map((f) => readFileSync(join(dir, f), 'utf8'))
  .join('\n');

const unprefixed = (css.match(/(?<![-\w])backdrop-filter:/g) ?? []).length;
const prefixed = (css.match(/-webkit-backdrop-filter:/g) ?? []).length;

if (unprefixed === 0 || prefixed === 0) {
  console.error(
    `Built CSS lost a backdrop-filter declaration (unprefixed: ${unprefixed}, -webkit-: ${prefixed}). ` +
      'The header blur would break in production; check build.cssMinify in astro.config.mjs.'
  );
  process.exit(1);
}
console.log(`Built CSS keeps backdrop-filter (unprefixed: ${unprefixed}, -webkit-: ${prefixed}).`);
