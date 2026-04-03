#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync, cpSync, rmSync } from 'fs';
import { resolve, join, dirname } from 'path';

const rootDir = resolve(import.meta.dirname, '..');
const validEnvs = ['dev', 'qa', 'val', 'prod'];

function parseArgs(argv) {
  const args = { from: null, to: null, forms: [], flows: [], vaults: [], dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--from': args.from = argv[++i]; break;
      case '--to': args.to = argv[++i]; break;
      case '--form': args.forms.push(argv[++i]); break;
      case '--flow': args.flows.push(argv[++i]); break;
      case '--vault': args.vaults.push(argv[++i]); break;
      case '--dry-run': args.dryRun = true; break;
    }
  }
  return args;
}
const loadJson = (p) => JSON.parse(readFileSync(p, 'utf-8'));
const saveJson = (p, v) => writeFileSync(p, JSON.stringify(v, null, 2) + '
');
const ensureDir = (p) => mkdirSync(p, { recursive: true });
const copyFileEnsured = (src, dest) => { ensureDir(dirname(dest)); copyFileSync(src, dest); };

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.from || !args.to) throw new Error('Usage: npm run promote:journeys -- --from dev --to qa --form progressive_profiling');
  if (!validEnvs.includes(args.from) || !validEnvs.includes(args.to)) throw new Error('Invalid env');
  if (args.forms.length === 0 && args.flows.length === 0 && args.vaults.length === 0) throw new Error('Specify at least one --form, --flow, or --vault');

  const fromDir = join(rootDir, 'environments', args.from);
  const toDir = join(rootDir, 'environments', args.to);
  const fromForms = loadJson(join(fromDir, 'forms.json'));
  const fromFlows = loadJson(join(fromDir, 'flows.json'));
  const fromVaults = loadJson(join(fromDir, 'vault-connections.json'));
  const toForms = loadJson(join(toDir, 'forms.json'));
  const toFlows = loadJson(join(toDir, 'flows.json'));
  const toVaults = loadJson(join(toDir, 'vault-connections.json'));

  const selectedForms = new Set(args.forms);
  const selectedFlows = new Set(args.flows);
  const selectedVaults = new Set(args.vaults);

  for (const formName of selectedForms) {
    const form = fromForms[formName];
    if (!form) throw new Error(`Form not found in ${args.from}: ${formName}`);
    for (const logicalFlow of Object.values(form.token_replacements || {})) selectedFlows.add(logicalFlow);
  }
  for (const flowName of Array.from(selectedFlows)) {
    const flow = fromFlows[flowName];
    if (!flow) throw new Error(`Flow not found in ${args.from}: ${flowName}`);
    for (const logicalVault of Object.values(flow.token_replacements || {})) selectedVaults.add(logicalVault);
  }
  for (const vaultName of selectedVaults) {
    if (!fromVaults[vaultName]) throw new Error(`Vault not found in ${args.from}: ${vaultName}`);
  }

  console.log(`Promoting journeys from ${args.from} -> ${args.to}`);
  for (const vaultName of selectedVaults) {
    toVaults[vaultName] = fromVaults[vaultName];
    console.log(`  vault: ${vaultName}`);
  }
  for (const flowName of selectedFlows) {
    toFlows[flowName] = fromFlows[flowName];
    console.log(`  flow:  ${flowName}`);
    if (!args.dryRun) copyFileEnsured(join(fromDir, fromFlows[flowName].file), join(toDir, fromFlows[flowName].file));
  }
  for (const formName of selectedForms) {
    toForms[formName] = fromForms[formName];
    console.log(`  form:  ${formName}`);
    if (!args.dryRun) copyFileEnsured(join(fromDir, fromForms[formName].file), join(toDir, fromForms[formName].file));
    const i18nSrc = join(fromDir, 'i18n', 'forms', formName);
    const i18nDest = join(toDir, 'i18n', 'forms', formName);
    if (existsSync(i18nSrc)) {
      console.log(`  i18n:  forms/${formName}`);
      if (!args.dryRun) {
        rmSync(i18nDest, { recursive: true, force: true });
        ensureDir(dirname(i18nDest));
        cpSync(i18nSrc, i18nDest, { recursive: true });
      }
    }
  }
  if (!args.dryRun) {
    saveJson(join(toDir, 'forms.json'), toForms);
    saveJson(join(toDir, 'flows.json'), toFlows);
    saveJson(join(toDir, 'vault-connections.json'), toVaults);
  }
  console.log(args.dryRun ? 'Dry run complete.' : 'Promotion complete.');
}

main();
