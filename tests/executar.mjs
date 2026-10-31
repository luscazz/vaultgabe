// Roda todos os testes do banco.
//   npm test           -> PostgreSQL em memoria (nao precisa de internet)
//   npm run test:neon  -> branch development do Neon, incluindo os testes da
//                         API; no fim ela e recarregada com os dados de
//                         demonstracao (01 a 04).
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const noNeon = process.argv.includes('--neon');
if (noNeon) process.env.TESTE_NEON = '1';

// A API precisa de um banco PostgreSQL de verdade: so roda no modo Neon.
const SUITES = ['bloqueios.mjs', 'operacoes.mjs', 'consultas.mjs', 'ampliacao.mjs', ...(noNeon ? ['api.mjs'] : [])];
let falhou = false;

console.log(noNeon ? 'Banco: Neon (branch development)' : 'Banco: PostgreSQL em memoria');

for (const suite of SUITES) {
  console.log(`\n=== ${suite} ===`);
  const r = spawnSync(process.execPath, [fileURLToPath(new URL(suite, import.meta.url))], {
    stdio: 'inherit',
    env: process.env,
  });
  if (r.status !== 0) falhou = true;
}

if (noNeon) {
  // Os testes fazem compras e anuncios; recarrega a development limpa.
  const { abrir } = await import('./banco.mjs');
  const db = await abrir();
  for (const arquivo of ['01_tabelas.sql', '02_regras.sql', '03_dados.sql', '04_dados_ampliados.sql']) {
    await db.exec(fs.readFileSync(new URL(`../database/${arquivo}`, import.meta.url), 'utf8'));
  }
  await db.close();
  console.log('\nBranch development recarregada com os dados de demonstracao.');
}

console.log(falhou ? '\nHA TESTES FALHANDO' : '\nTODOS OS TESTES PASSARAM');
process.exitCode = falhou ? 1 : 0;
