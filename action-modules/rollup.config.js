import typescript from '@rollup/plugin-typescript';
import { readdirSync } from 'fs';
import { basename } from 'path';

// Auto-discover all .ts files in src/ (excluding tests)
const entryPoints = readdirSync('src')
  .filter(f => f.endsWith('.ts') && !f.includes('.test.') && !f.includes('.spec.'))
  .map(f => `src/${f}`);

export default entryPoints.map(input => ({
  input,
  output: {
    strict: false,
    format: 'cjs',
    dir: 'dist',
    entryFileNames: `${basename(input, '.ts')}.js`,
    sourcemap: false,
  },
  external: [],
  plugins: [
    typescript({
      module: 'esnext',
      tsconfig: './tsconfig.json',
    }),
  ],
}));
