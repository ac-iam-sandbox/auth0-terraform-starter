#!/usr/bin/env node

/**
 * promote.mjs — Promote compiled actions/modules to target environments
 *
 * Usage:
 *   npm run promote -- --env dev --action post-login-action
 *   npm run promote -- --env qa --action post-login-action --action enforce-mfa
 *   npm run promote -- --env prod --all
 *   npm run promote -- --env dev --module shared-utils
 *   npm run promote -- --env qa --module shared-utils --action post-login-action
 *   npm run promote -- --env dev --all --dry-run
 *
 * Source layout (single build):
 *   actions/dist/actions/*.js   ← compiled Auth0 Actions
 *   actions/dist/modules/*.js   ← compiled Auth0 Action Modules
 *
 * Target layout (per environment):
 *   environments/{env}/actions/*.js          + manifest.json
 *   environments/{env}/action-modules/*.js   + manifest.json
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, copyFileSync } from 'fs';
import { resolve, basename, join } from 'path';
import { createHash } from 'crypto';
import { execSync } from 'child_process';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sha256(filePath) {
  const content = readFileSync(filePath);
  return createHash('sha256').update(content).digest('hex');
}

function getGitSha() {
  try {
    return execSync('git rev-parse HEAD', { encoding: 'utf-8' }).trim();
  } catch {
    return 'unknown';
  }
}

function getGitUser() {
  try {
    return execSync('git config user.name', { encoding: 'utf-8' }).trim();
  } catch {
    return process.env.USER || 'unknown';
  }
}

function getGitDirty() {
  try {
    const status = execSync('git status --porcelain', { encoding: 'utf-8' }).trim();
    return status.length > 0;
  } catch {
    return false;
  }
}

function loadManifest(manifestPath) {
  if (existsSync(manifestPath)) {
    try {
      return JSON.parse(readFileSync(manifestPath, 'utf-8'));
    } catch {
      return {};
    }
  }
  return {};
}

function saveManifest(manifestPath, manifest) {
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', 'utf-8');
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = {
    env: null,
    actions: [],
    modules: [],
    all: false,
    dryRun: false,
    skipBuild: false,
  };

  let i = 0;
  while (i < argv.length) {
    switch (argv[i]) {
      case '--env':
        args.env = argv[++i];
        break;
      case '--action':
        args.actions.push(argv[++i]);
        break;
      case '--module':
        args.modules.push(argv[++i]);
        break;
      case '--all':
        args.all = true;
        break;
      case '--dry-run':
        args.dryRun = true;
        break;
      case '--skip-build':
        args.skipBuild = true;
        break;
      default:
        break;
    }
    i++;
  }

  return args;
}

// ---------------------------------------------------------------------------
// Promote logic
// ---------------------------------------------------------------------------

function promoteFiles(distDir, targetDir, selectedFiles, manifestPath, sourceSubdir, dryRun, gitSha, gitUser) {
  if (!existsSync(distDir)) {
    // No compiled files for this type — skip silently if --all, error if explicit
    if (selectedFiles.length === 0) return [];
    console.error(`  ERROR: ${distDir} does not exist. Run 'cd actions && npm run build' first.`);
    process.exit(1);
  }

  const availableFiles = readdirSync(distDir).filter(f => f.endsWith('.js'));

  if (availableFiles.length === 0) {
    if (selectedFiles.length === 0) return [];
    console.error(`  ERROR: No compiled .js files in ${distDir}`);
    process.exit(1);
  }

  // Determine which files to promote
  let filesToPromote;
  if (selectedFiles.length === 0) {
    filesToPromote = availableFiles;
  } else {
    filesToPromote = [];
    for (const name of selectedFiles) {
      const fileName = name.endsWith('.js') ? name : `${name}.js`;
      if (!availableFiles.includes(fileName)) {
        console.error(`  ERROR: ${fileName} not found in ${distDir}`);
        console.error(`  Available: ${availableFiles.join(', ')}`);
        process.exit(1);
      }
      filesToPromote.push(fileName);
    }
  }

  mkdirSync(targetDir, { recursive: true });

  const manifest = loadManifest(manifestPath);
  const now = new Date().toISOString();
  const changes = [];

  for (const fileName of filesToPromote) {
    const srcPath = join(distDir, fileName);
    const destPath = join(targetDir, fileName);
    const newSha = sha256(srcPath);
    const logicalName = basename(fileName, '.js');

    const existingEntry = manifest[logicalName];
    if (existingEntry && existingEntry.sha256 === newSha) {
      console.log(`  ○ ${fileName} — unchanged (sha: ${newSha.substring(0, 12)}…)`);
      continue;
    }

    if (dryRun) {
      console.log(`  ● ${fileName} — would promote (sha: ${newSha.substring(0, 12)}…)`);
    } else {
      copyFileSync(srcPath, destPath);
      manifest[logicalName] = {
        source_file: `${sourceSubdir}/${logicalName}.ts`,
        compiled_file: fileName,
        sha256: newSha,
        git_sha: gitSha,
        promoted_at: now,
        promoted_by: gitUser,
      };
      console.log(`  ● ${fileName} — promoted (sha: ${newSha.substring(0, 12)}…)`);
    }
    changes.push(fileName);
  }

  if (!dryRun && changes.length > 0) {
    saveManifest(manifestPath, manifest);
    console.log(`  ✓ manifest.json updated (${changes.length} file(s))`);
  }

  return changes;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const rootDir = resolve(import.meta.dirname, '..');
  const args = parseArgs(process.argv.slice(2));

  if (!args.env) {
    console.error('Usage: npm run promote -- --env <environment> [--action <n>...] [--module <n>...] [--all] [--dry-run]');
    console.error('');
    console.error('Examples:');
    console.error('  npm run promote -- --env dev --action post-login-action');
    console.error('  npm run promote -- --env qa --action post-login-action --action enforce-mfa');
    console.error('  npm run promote -- --env prod --all');
    console.error('  npm run promote -- --env dev --module shared-utils');
    console.error('  npm run promote -- --env dev --all --dry-run');
    process.exit(1);
  }

  const validEnvs = ['dev', 'qa', 'val', 'prod'];
  if (!validEnvs.includes(args.env)) {
    console.error(`ERROR: Invalid environment '${args.env}'. Must be one of: ${validEnvs.join(', ')}`);
    process.exit(1);
  }

  if (args.actions.length === 0 && args.modules.length === 0 && !args.all) {
    console.error('ERROR: Specify --action <name>, --module <name>, or --all');
    process.exit(1);
  }

  const gitSha = getGitSha();
  const gitUser = getGitUser();
  const isDirty = getGitDirty();

  console.log('');
  console.log(`╔══════════════════════════════════════════════════╗`);
  console.log(`║  Auth0 Promote → ${args.env.toUpperCase().padEnd(32)}║`);
  console.log(`╚══════════════════════════════════════════════════╝`);
  console.log(`  Git SHA:  ${gitSha.substring(0, 12)}${isDirty ? ' (dirty)' : ''}`);
  console.log(`  User:     ${gitUser}`);
  console.log(`  Dry run:  ${args.dryRun ? 'yes' : 'no'}`);
  console.log('');

  if (isDirty && !args.dryRun) {
    console.warn('  ⚠ Working tree has uncommitted changes.');
    console.warn('  ⚠ The git_sha in manifest may not match the compiled code.');
    console.warn('  ⚠ Consider committing source changes first.');
    console.warn('');
  }

  const envDir = join(rootDir, 'environments', args.env);
  if (!existsSync(envDir)) {
    console.error(`ERROR: Environment directory not found: ${envDir}`);
    process.exit(1);
  }

  // Build if dist doesn't exist
  if (!args.skipBuild) {
    const actionsDistDir = join(rootDir, 'actions', 'dist');
    if (!existsSync(actionsDistDir)) {
      console.log('  Building actions & modules...');
      try {
        execSync('npm run build', { cwd: join(rootDir, 'actions'), stdio: 'pipe' });
        console.log('  ✓ Build successful');
        console.log('');
      } catch (err) {
        console.error('  ERROR: Build failed');
        console.error(err.stderr?.toString() || err.message);
        process.exit(1);
      }
    }
  }

  let totalChanges = 0;

  // Promote actions
  if (args.all || args.actions.length > 0) {
    console.log('  Actions:');
    const changes = promoteFiles(
      join(rootDir, 'actions', 'dist', 'actions'),
      join(envDir, 'actions'),
      args.all ? [] : args.actions,
      join(envDir, 'actions', 'manifest.json'),
      'actions',
      args.dryRun, gitSha, gitUser
    );
    totalChanges += changes.length;
    if (changes.length === 0 && (args.all || args.actions.length > 0)) {
      console.log('  (no changes)');
    }
    console.log('');
  }

  // Promote modules
  if (args.all || args.modules.length > 0) {
    const modulesDistDir = join(rootDir, 'actions', 'dist', 'modules');
    if (existsSync(modulesDistDir) && readdirSync(modulesDistDir).filter(f => f.endsWith('.js')).length > 0) {
      console.log('  Action Modules:');
      const changes = promoteFiles(
        modulesDistDir,
        join(envDir, 'action-modules'),
        args.all ? [] : args.modules,
        join(envDir, 'action-modules', 'manifest.json'),
        'modules',
        args.dryRun, gitSha, gitUser
      );
      totalChanges += changes.length;
      if (changes.length === 0) {
        console.log('  (no changes)');
      }
      console.log('');
    } else if (args.modules.length > 0) {
      console.error('  ERROR: No compiled action modules found in actions/dist/modules/');
      console.error('  Make sure you have .ts files in actions/src/modules/ and run: cd actions && npm run build');
      process.exit(1);
    }
  }

  // Summary
  if (args.dryRun) {
    console.log(`  ${totalChanges} file(s) would be promoted. Re-run without --dry-run to apply.`);
  } else if (totalChanges > 0) {
    console.log(`  ✓ ${totalChanges} file(s) promoted to ${args.env}.`);
    console.log('');
    console.log('  Next steps:');
    console.log(`    git add environments/${args.env}/actions/ environments/${args.env}/action-modules/`);
    console.log(`    git commit -m "promote: ${args.env} — ${totalChanges} file(s) from ${gitSha.substring(0, 8)}"`);
  } else {
    console.log('  No changes detected — all files already match dist/.');
  }
  console.log('');
}

main();
