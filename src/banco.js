// Conexao com o PostgreSQL (Neon) e execucao das consultas pelo nome.
import pg from 'pg';
import { carregarConsultas } from './consultas.js';
import { ErroApi } from './erros.js';

// Como o driver devolve alguns tipos para a aplicacao:
//  - DATE e TIMESTAMP chegam como TEXTO ('2026-01-06 14:00:00'). Sem isso, o
//    driver os converte para o fuso do servidor e a data pode aparecer um dia
//    antes. O banco ja grava no horario de Sao Paulo (timezone do Neon).
//  - BIGINT (resultado de COUNT) chega como numero; os valores sao pequenos.
//  - NUMERIC (dinheiro) continua texto, para nao perder centavos.
pg.types.setTypeParser(pg.types.builtins.DATE, (valor) => valor);
pg.types.setTypeParser(pg.types.builtins.TIMESTAMP, (valor) => valor);
pg.types.setTypeParser(pg.types.builtins.INT8, (valor) => Number(valor));

const consultas = carregarConsultas();
let pool = null;

function enderecoDoBanco() {
  const texto = process.env.DATABASE_URL;
  if (!texto) {
    throw new ErroApi(503, 'Banco de dados não configurado: defina DATABASE_URL no .env.');
  }
  // Conexao criptografada com certificado conferido: "require" vira "verify-full".
  const url = new URL(texto);
  if (url.searchParams.get('sslmode') === 'require') url.searchParams.set('sslmode', 'verify-full');
  return url.toString();
}

function obterPool() {
  if (!pool) {
    pool = new pg.Pool({
      connectionString: enderecoDoBanco(),
      max: 5,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 15_000, // o Neon pode levar alguns segundos para "acordar"
    });
    // Uma conexao parada que cai nao pode derrubar o servidor.
    pool.on('error', (err) => console.error('Conexao com o banco perdida:', err.message));
  }
  return pool;
}

// Executa uma consulta de database/consultas pelo nome e devolve as linhas.
export async function consultar(nome, parametros = []) {
  const sql = consultas.get(nome);
  if (!sql) throw new Error(`Consulta inexistente: ${nome}`);
  const { rows } = await obterPool().query(sql, parametros);
  return rows;
}

// Encerra os anuncios que ja venceram (fn_expirar_anuncios) antes de listar
// ofertas. Roda no maximo uma vez por minuto, para nao repetir o UPDATE a
// cada pagina aberta.
let ultimaExpiracao = 0;

export async function expirarAnunciosVencidos() {
  if (Date.now() - ultimaExpiracao < 60_000) return;
  await consultar('expirar_anuncios');
  ultimaExpiracao = Date.now();
}

// Usada por /api/saude: confirma que o banco responde.
export async function verificarConexao() {
  const inicio = Date.now();
  const [banco] = await consultar('saude_banco');
  return { ...banco, latencia_ms: Date.now() - inicio };
}

export const totalConsultas = () => consultas.size;
