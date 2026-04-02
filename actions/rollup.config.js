import typescript from '@rollup/plugin-typescript';
import { readdirSync, existsSync } from 'fs';
import { basename } from 'path';

function discoverEntries(subdir) {
  const dir = `src/${subdir}`;
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter(f => f.endsWith('.ts') && !f.includes('.test.') && !f.includes('.spec.'))
    .map(f => ({
      input: `${dir}/${f}`,
      outputDir: `dist/${subdir}`,
      outputName: basename(f, '.ts'),
    }));
}

const entries = [
  ...discoverEntries('actions'),
  ...discoverEntries('modules'),
];

export default entries.map(({ input, outputDir, outputName }) => ({
  input,
  output: {
    strict: false,
    format: 'cjs',
    dir: outputDir,
    entryFileNames: `${outputName}.js`,
    sourcemap: false,
  },
  external: [],
  plugins: [
    typescript({
      tsconfig: './tsconfig.json',
      outDir: outputDir,
      declaration: false,
      sourceMap: false,
    }),
  ],
}));