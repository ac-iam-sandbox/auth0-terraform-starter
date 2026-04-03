#!/usr/bin/env node

import { readFileSync, existsSync } from 'fs';
import { resolve, join } from 'path';

const rootDir = resolve(import.meta.dirname, '..');

function validateValue(value, schema, path = '') {
  const errors = [];

  if (schema.type) {
    const actualType = Array.isArray(value) ? 'array' : typeof value;
    if (actualType === 'number' && schema.type === 'integer' && !Number.isInteger(value)) {
      errors.push(`${path}: expected integer, got float`);
    } else if (schema.type !== actualType && !(schema.type === 'number' && actualType === 'number')) {
      errors.push(`${path}: expected ${schema.type}, got ${actualType}`);
    }
  }

  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${path}: value "${value}" not in allowed values [${schema.enum.join(', ')}]`);
  }

  if (schema.minLength && typeof value === 'string' && value.length < schema.minLength) {
    errors.push(`${path}: string too short (min ${schema.minLength})`);
  }

  if (schema.minimum !== undefined && typeof value === 'number' && value < schema.minimum) {
    errors.push(`${path}: value ${value} below minimum ${schema.minimum}`);
  }

  if (schema.pattern && typeof value === 'string' && !new RegExp(schema.pattern).test(value)) {
    errors.push(`${path}: value "${value}" does not match pattern ${schema.pattern}`);
  }

  if (schema.required && typeof value === 'object' && !Array.isArray(value)) {
    for (const req of schema.required) {
      if (!(req in value)) errors.push(`${path}: missing required field "${req}"`);
    }
  }

  if (schema.properties && typeof value === 'object' && !Array.isArray(value)) {
    for (const [key, propSchema] of Object.entries(schema.properties)) {
      if (key in value) errors.push(...validateValue(value[key], propSchema, `${path}.${key}`));
    }
  }

  if (schema.additionalProperties && typeof value === 'object' && !Array.isArray(value)) {
    for (const [key, val] of Object.entries(value)) {
      if (!schema.properties || !(key in schema.properties)) {
        errors.push(...validateValue(val, schema.additionalProperties, `${path}.${key}`));
      }
    }
  }

  if (schema.items && Array.isArray(value)) {
    value.forEach((item, i) => errors.push(...validateValue(item, schema.items, `${path}[${i}]`)));
  }

  return errors;
}

const configs = [
  { file: 'actions.json', schema: 'actions.schema.json' },
  { file: 'applications.json', schema: 'applications.schema.json' },
  { file: 'action-modules.json', schema: 'action-modules.schema.json' },
  { file: 'journeys/flows.json', schema: 'flows.schema.json' },
  { file: 'journeys/forms.json', schema: 'forms.schema.json' },
  { file: 'journeys/vaults.json', schema: 'journey-vault-manifest.schema.json' },
];

const args = process.argv.slice(2);
const envFilter = args.includes('--env') ? args[args.indexOf('--env') + 1] : null;
const fileFilter = args.includes('--file') ? args[args.indexOf('--file') + 1] : null;
const envs = envFilter ? [envFilter] : ['dev', 'qa', 'val', 'prod'];
let totalErrors = 0;

for (const env of envs) {
  for (const cfg of configs) {
    if (fileFilter && cfg.file !== fileFilter) continue;

    const filePath = join(rootDir, 'environments', env, cfg.file);
    const schemaPath = join(rootDir, 'schemas', cfg.schema);

    if (!existsSync(filePath)) continue;
    if (!existsSync(schemaPath)) {
      console.warn(`WARN: Schema not found: ${cfg.schema}`);
      continue;
    }

    let data, schema;
    try {
      data = JSON.parse(readFileSync(filePath, 'utf-8'));
    } catch (e) {
      console.error(`FAIL: ${env}/${cfg.file} — invalid JSON: ${e.message}`);
      totalErrors++;
      continue;
    }

    try {
      schema = JSON.parse(readFileSync(schemaPath, 'utf-8'));
    } catch (e) {
      console.error(`FAIL: Schema ${cfg.schema} — invalid JSON: ${e.message}`);
      totalErrors++;
      continue;
    }

    const errors = validateValue(data, schema, `${env}/${cfg.file}`);
    if (errors.length > 0) {
      console.error(`FAIL: ${env}/${cfg.file}`);
      errors.forEach(e => console.error(`  ${e}`));
      totalErrors += errors.length;
    } else {
      console.log(`  OK: ${env}/${cfg.file}`);
    }
  }
}

if (totalErrors > 0) {
  console.error(`\nSchema validation FAILED (${totalErrors} error(s)).`);
  process.exit(1);
} else {
  console.log('\nAll schemas validated.');
}
