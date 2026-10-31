// Abre o banco usado pelos testes.
//   npm test          -> PostgreSQL em memoria (PGlite): rapido, sem internet,
//                        nao toca em nenhum banco real.
//   npm run test:neon -> branch development do Neon (DATABASE_URL do .env).
// ATENCAO: os testes apagam e recriam o banco de destino. Por isso exigem
// DATABASE_URL_PRODUCAO no .env e se recusam a rodar se DATABASE_URL
// apontar para a producao.
import { PGlite } from '@electric-sql/pglite';
import pg from 'pg';

export async function abrir() {
  if (process.env.TESTE_NEON !== '1') return new PGlite();

  const url = process.env.DATABASE_URL;
  const producao = process.env.DATABASE_URL_PRODUCAO;
  if (!url) throw new Error('DATABASE_URL nao esta definida no .env.');
  if (!producao) throw new Error('Defina DATABASE_URL_PRODUCAO no .env: os testes precisam dela para recusar a producao.');
  // O Neon tem dois enderecos por branch: o direto e o com "-pooler".
  const endpoint = (u) => new URL(u).hostname.replace('-pooler.', '.');
  if (endpoint(url) === endpoint(producao)) {
    throw new Error('DATABASE_URL aponta para a PRODUCAO. Os testes so rodam na branch development.');
  }

  // Igual a src/banco.js: "sslmode=require" do Neon vira "verify-full" explicito.
  const endereco = new URL(url);
  if (endereco.searchParams.get('sslmode') === 'require') endereco.searchParams.set('sslmode', 'verify-full');
  const client = new pg.Client({ connectionString: endereco.toString() });
  await client.connect();
  const exec = async (sql) => {
    const r = await client.query(sql);
    return Array.isArray(r) ? r : [r];
  };

  return {
    query: (sql, params) => client.query(sql, params),
    exec,
    transaction: async (fn) => {
      await client.query('BEGIN');
      try {
        const resultado = await fn({ exec, query: (s, p) => client.query(s, p) });
        await client.query('COMMIT');
        return resultado;
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    },
    close: () => client.end(),
  };
}
