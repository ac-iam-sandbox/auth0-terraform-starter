#!/usr/bin/env node

/**
 * verify-manifests.mjs — Verify integrity of promotion manifests
 *
 * Checks that every entry in each environment's manifest.json has a
 * matching SHA256 for the actual .js file on disk. Fails if someone
 * manually edited a .js file without going through the promote CLI.
 *
 * Usage:
 *   node scripts/verify-manifests.mjs           # check all envs
 *   node scripts/verify-manifests.mjs --env dev  # check one env
 */

import { readFileSync, existsSync, readdirSync } from 'fs';
import { resolve, join } from 'path';
import { createHash } from 'crypto';

function sha256(filePath) {
  const content = readFileSync(filePath);
  return createHash('sha256').update(content).digest('hex');
}

const rootDir = resolve(import.meta.dirname, '..');
const args = process.argv.slice(2);
const envFilter = args.includes('--env') ? args[args.indexOf('--env') + 1] : null;
const envs = envFilter ? [envFilter] : ['dev', 'qa', 'val', 'prod'];

let hasErrors = false;

for (const env of envs) {
  for (const type of ['actions', 'action-modules']) {
    const dir = join(rootDir, 'environments', env, type);
    const manifestPath = join(dir, 'manifest.json');

    if (!existsSync(manifestPath)) continue;

    let manifest;
    try {
      manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'));
    } catch {
      console.error(`FAIL: ${env}/${type}/manifest.json is not valid JSON`);
      hasErrors = true;
      continue;
    }

    for (const [name, entry] of Object.entries(manifest)) {
      const filePath = join(dir, entry.compiled_file);

      if (!existsSync(filePath)) {
        console.error(`FAIL: ${env}/${type}/${entry.compiled_file} — file missing (listed in manifest)`);
        hasErrors = true;
        continue;
      }

      const actualSha = sha256(filePath);
      if (actualSha !== entry.sha256) {
        console.error(
          `FAIL: ${env}/${type}/${entry.compiled_file} — SHA mismatch\n` +
          `       manifest: ${entry.sha256.substring(0, 16)}…\n` +
          `       actual:   ${actualSha.substring(0, 16)}…\n` +
          `       Use 'npm run promote' to update properly.`
        );
        hasErrors = true;
      } else {
        console.log(`  OK: ${env}/${type}/${entry.compiled_file} (${actualSha.substring(0, 12)}…)`);
      }
    }

    // Also check for .js files that exist but aren't in the manifest
    if (existsSync(dir)) {
      const jsFiles = readdirSync(dir).filter(f => f.endsWith('.js'));
      for (const file of jsFiles) {
        const logicalName = file.replace('.js', '');
        if (!manifest[logicalName]) {
          console.warn(`WARN: ${env}/${type}/${file} — not tracked in manifest (promoted manually?)`);
        }
      }
    }
  }
}

if (hasErrors) {
  console.error('\nManifest verification FAILED. Run npm run promote to fix.');
  process.exit(1);
} else {
  console.log('\nAll manifests verified.');
}
