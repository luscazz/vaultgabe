// Leitura e validacao dos parametros que chegam do navegador (query string
// ou corpo JSON). Valor ausente ou vazio vira NULL, que nas consultas
// significa "filtro desligado". Valor invalido vira erro 400 com mensagem.
import { ErroApi } from './erros.js';

// Codigos de desgaste aceitos nos filtros (ver fn_desgaste em 02_regras.sql).
export const DESGASTES = ['FN', 'MW', 'FT', 'WW', 'BS'];

const invalido = (nome) => new ErroApi(400, `Parâmetro inválido: ${nome}.`);
const vazio = (valor) => valor === undefined || valor === null || valor === '';

// "?x=1&x=2" chega como lista; "?x=1,2" tambem e aceito.
function comoLista(valor) {
  if (vazio(valor)) return [];
  return (Array.isArray(valor) ? valor : String(valor).split(','))
    .map((v) => String(v).trim())
    .filter((v) => v !== '');
}

export function texto(valor, tamanhoMaximo = 100) {
  if (vazio(valor)) return null;
  const t = String(valor).trim().slice(0, tamanhoMaximo);
  return t === '' ? null : t;
}

export function inteiro(valor, nome) {
  if (vazio(valor)) return null;
  if (!/^\d{1,9}$/.test(String(valor))) throw invalido(nome);
  return Number(valor);
}

// Como inteiro(), mas o valor e obrigatorio (ex.: id no endereco).
export function inteiroObrigatorio(valor, nome) {
  const n = inteiro(valor, nome);
  if (n === null) throw new ErroApi(400, `Informe ${nome}.`);
  return n;
}

export function listaDeInteiros(valor, nome) {
  const lista = comoLista(valor);
  return lista.length ? lista.map((v) => inteiro(v, nome)) : null;
}

// Numero nao negativo; aceita virgula como separador decimal.
export function numero(valor, nome) {
  if (vazio(valor)) return null;
  const n = Number(String(valor).replace(',', '.'));
  if (!Number.isFinite(n) || n < 0) throw invalido(nome);
  return n;
}

// Data no formato AAAA-MM-DD (campo <input type="date">), e que exista no
// calendario (2026-02-30 e recusada; o ano 0000 nao existe no PostgreSQL).
export function data(valor, nome) {
  if (vazio(valor)) return null;
  const t = String(valor);
  const d = new Date(`${t}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(t) || t < '0001-01-01'
      || Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== t) {
    throw invalido(nome);
  }
  return t;
}

// Preco em reais: maior que zero, com no maximo 2 casas e ate R$ 1 milhao.
export function preco(valor) {
  if (vazio(valor)) throw new ErroApi(400, 'Informe o preço.');
  const n = Number(String(valor).replace(',', '.'));
  if (!Number.isFinite(n)) throw new ErroApi(400, 'O preço precisa ser um número.');
  if (n <= 0) throw new ErroApi(400, 'O preço precisa ser maior que zero.');
  if (n > 1_000_000) throw new ErroApi(400, 'O preço pode ser de no máximo R$ 1.000.000,00.');
  if (Math.round(n * 100) !== Number((n * 100).toFixed(6))) throw new ErroApi(400, 'Use no máximo 2 casas decimais no preço.');
  return Math.round(n * 100) / 100;
}

// Caixa marcada ("1", "true" ou "on") liga o filtro; o resto o deixa desligado.
export function marcado(valor) {
  return ['1', 'true', 'on'].includes(String(valor)) ? true : null;
}

export function umDe(valor, opcoes, nome, padrao = null) {
  if (vazio(valor)) return padrao;
  if (!opcoes.includes(String(valor))) throw invalido(nome);
  return String(valor);
}

export function listaDe(valor, opcoes, nome) {
  const lista = comoLista(valor);
  if (lista.some((v) => !opcoes.includes(v))) throw invalido(nome);
  return lista.length ? lista : null;
}
