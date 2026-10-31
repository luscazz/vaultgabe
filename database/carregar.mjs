// Monta o banco do zero (01 a 04) numa branch do Neon e confere com o 05.
//   npm run banco:dev                      -> branch development (DATABASE_URL)
//   npm run banco:producao -- --confirmo   -> branch production (DATABASE_URL_PRODUCAO)
// ATENCAO: apaga e recria TODAS as tabelas da branch escolhida. Na
// producao, compras, anuncios e avaliacoes feitos no site sao perdidos;
// por isso ela so roda com --confirmo. A development le tambem
// DATABASE_URL_PRODUCAO, so para recusar rodar na producao.
import fs from 'node:fs';
import pg from 'pg';

const SCRIPTS = ['01_tabelas.sql', '02_regras.sql', '03_dados.sql', '04_dados_ampliados.sql'];
const alvo = process.argv[2];
const variavel = { development: 'DATABASE_URL', production: 'DATABASE_URL_PRODUCAO' }[alvo];

if (!variavel) {
  console.error('Use: node database/carregar.mjs development | production --confirmo');
  process.exit(1);
}
if (alvo === 'production' && !process.argv.includes('--confirmo')) {
  console.error('Isto apaga e recria o banco de PRODUCAO. Para continuar: npm run banco:producao -- --confirmo');
  process.exit(1);
}
if (!process.env[variavel]) {
  console.error(`${variavel} nao esta definida no .env.`);
  process.exit(1);
}
if (alvo === 'development') {
  const producao = process.env.DATABASE_URL_PRODUCAO;
  // O Neon tem dois enderecos por branch: o direto e o com "-pooler".
  const endpoint = (u) => new URL(u).hostname.replace('-pooler.', '.');
  if (!producao || endpoint(process.env.DATABASE_URL) === endpoint(producao)) {
    console.error('DATABASE_URL precisa ser a branch development, e DATABASE_URL_PRODUCAO precisa estar no .env para a conferencia.');
    process.exit(1);
  }
}

// Igual a src/banco.js: "sslmode=require" do Neon vira "verify-full" explicito.
const url = new URL(process.env[variavel]);
if (url.searchParams.get('sslmode') === 'require') url.searchParams.set('sslmode', 'verify-full');
const cliente = new pg.Client({ connectionString: url.toString() });
await cliente.connect();

try {
  for (const arquivo of SCRIPTS) {
    process.stdout.write(`${arquivo}... `);
    await cliente.query(fs.readFileSync(new URL(arquivo, import.meta.url), 'utf8'));
    console.log('ok');
  }

  const resultados = await cliente.query(fs.readFileSync(new URL('05_verificacao.sql', import.meta.url), 'utf8'));
  const contagens = resultados[0].rows.filter((r) => r.situacao !== 'OK');
  const regras = resultados[1].rows.filter((r) => r.resultado !== 'OK');
  const { rows: [resumo] } = await cliente.query(`
    SELECT (SELECT COUNT(*) FROM item_catalogo)                             AS modelos,
           (SELECT COUNT(*) FROM item_instancia)                            AS itens,
           (SELECT COUNT(*) FROM venda WHERE status_venda = 'concluida')    AS vendas,
           (SELECT COUNT(*) FROM anuncio WHERE status_anuncio = 'ativo')    AS anuncios_ativos,
           current_setting('TimeZone')                                      AS fuso`);
  console.log(`\n05_verificacao: ${contagens.length || regras.length ? 'PROBLEMAS' : 'tudo OK'} (${resultados[1].rows.length} regras)`);
  for (const r of [...contagens, ...regras]) console.log('  ', JSON.stringify(r));
  console.log(`Banco ${alvo}: ${resumo.modelos} modelos, ${resumo.itens} itens, ${resumo.vendas} vendas concluidas, ${resumo.anuncios_ativos} anuncios ativos, fuso ${resumo.fuso}.`);
  process.exitCode = contagens.length || regras.length ? 1 : 0;
} finally {
  await cliente.end();
}
