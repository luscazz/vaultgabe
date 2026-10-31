// Testes das OPERACOES da aplicacao: compra, cancelamento, ciclo de vida do
// anuncio, expiracao e avaliacao. No fim confere 05_verificacao.sql.
import { fileURLToPath } from 'node:url';
import { abrir } from './banco.mjs';
import fs from 'node:fs';
import path from 'node:path';

const dir = fileURLToPath(new URL("../database/", import.meta.url));
const db = await abrir();
for (const f of ['01_tabelas.sql', '02_regras.sql', '03_dados.sql']) {
  await db.exec(fs.readFileSync(path.join(dir, f), 'utf8'));
}

let falhas = 0;
const ok = (cond, nome, extra = '') => {
  if (!cond) falhas++;
  console.log(`${cond ? 'OK    ' : 'FALHOU'} ${nome}${extra ? '  -> ' + extra : ''}`);
};
const um = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const deveFalhar = async (nome, sql, params = []) => {
  try {
    await db.query(sql, params);
    ok(false, nome, 'foi aceito, mas deveria ser bloqueado');
  } catch (e) {
    ok(true, nome, e.message);
  }
};
const user = async (apelido) => (await um('SELECT id FROM usuario WHERE apelido = $1', [apelido])).id;
const anuncioAtivo = async (ins) => (await um(
  `SELECT a.id FROM anuncio a JOIN item_instancia i ON i.id = a.item_instancia_id
    WHERE i.numero_inspecao = $1 AND a.status_anuncio = 'ativo'`, [ins])).id;
const dono = async (ins) => (await um(
  `SELECT u.apelido FROM item_instancia i JOIN usuario u ON u.id = i.proprietario_id
    WHERE i.numero_inspecao = $1`, [ins])).apelido;
const dvValido = (chave) => {
  let soma = 0, peso = 2;
  for (let i = 42; i >= 0; i--) { soma += Number(chave[i]) * peso; peso = peso === 9 ? 2 : peso + 1; }
  const r = soma % 11;
  return Number(chave[43]) === (r < 2 ? 0 : 11 - r);
};

const isizinha = await user('isizinha'), dfontes = await user('dfontes'), lari = await user('lari'), viniciuslabubu = await user('viniciuslabubu');

console.log('--- COMPRA');
const awp = await anuncioAtivo('INS-EQ-0004');
const compra = await um('SELECT * FROM fn_comprar_anuncio($1, $2, $3)', [awp, isizinha, 'pix']);
ok(/^VND-\d{4}-0013$/.test(compra.protocolo), 'compra gera o proximo protocolo', compra.protocolo);
ok(/^\d{44}$/.test(compra.chave_nota_fiscal) && dvValido(compra.chave_nota_fiscal), 'chave da nota fiscal com 44 digitos e DV valido', compra.chave_nota_fiscal);
const venda = await um(`SELECT v.status_venda, p.status_pagamento, p.metodo_pagamento, n.valor_total, a.status_anuncio
  FROM venda v JOIN pagamento p ON p.venda_id = v.id JOIN nota_fiscal n ON n.venda_id = v.id
  JOIN anuncio a ON a.id = v.anuncio_id WHERE v.id = $1`, [compra.venda_id]);
ok(venda.status_venda === 'concluida' && venda.status_pagamento === 'aprovado' && venda.status_anuncio === 'vendido' && Number(venda.valor_total) === 1100,
  'venda concluida + pagamento aprovado + nota fiscal + anuncio vendido', JSON.stringify(venda));
ok(await dono('INS-EQ-0004') === 'isizinha', 'item passa para a compradora');

await deveFalhar('comprar o mesmo anuncio de novo', 'SELECT * FROM fn_comprar_anuncio($1, $2, $3)', [awp, dfontes, 'pix']);
await deveFalhar('comprar o proprio item', 'SELECT * FROM fn_comprar_anuncio($1, $2, $3)', [await anuncioAtivo('INS-EQ-0006'), lari, 'pix']);
const protoDepois = (await um(`SELECT MAX(protocolo_venda) AS p FROM venda`)).p;
ok(/^VND-\d{4}-0013$/.test(protoDepois), 'compra recusada nao deixa venda pela metade', protoDepois);

console.log('--- REVENDA COM ADESIVO');
const m4 = await anuncioAtivo('INS-EQ-0006');
const revenda = await um('SELECT * FROM fn_comprar_anuncio($1, $2, $3)', [m4, dfontes, 'cartao_credito']);
ok(await dono('INS-EQ-0006') === 'dfontes' && await dono('INS-CO-0018') === 'dfontes', 'M4A4 revendida e o adesivo aplicado vai junto', revenda.protocolo);
ok(/^VND-\d{4}-0014$/.test(revenda.protocolo), 'compra recusada antes nao pula numero de protocolo', revenda.protocolo);

console.log('--- CANCELAMENTO E CICLO DE VIDA');
await deveFalhar('cancelar anuncio com venda pendente (Capsula Ambush)',
  `UPDATE anuncio SET status_anuncio = 'cancelado' WHERE id = $1`, [await anuncioAtivo('INS-CN-0005')]);
const p90 = await anuncioAtivo('INS-EQ-0007');
await db.query(`UPDATE anuncio SET status_anuncio = 'cancelado' WHERE id = $1`, [p90]);
ok((await um('SELECT status_anuncio FROM anuncio WHERE id = $1', [p90])).status_anuncio === 'cancelado', 'cancelar anuncio ativo sem venda');
await deveFalhar('reabrir anuncio cancelado', `UPDATE anuncio SET status_anuncio = 'ativo' WHERE id = $1`, [p90]);
await deveFalhar('marcar como vendido sem venda', `UPDATE anuncio SET status_anuncio = 'vendido' WHERE id = $1`, [await anuncioAtivo('INS-EQ-0010')]);
await deveFalhar('expirar anuncio que ainda nao venceu', `UPDATE anuncio SET status_anuncio = 'expirado' WHERE id = $1`, [await anuncioAtivo('INS-EQ-0010')]);
await db.query(`UPDATE anuncio SET preco = 1800 WHERE id = $1`, [await anuncioAtivo('INS-EQ-0010')]);
ok(true, 'alterar o preco de um anuncio ativo continua permitido');

console.log('--- EXPIRACAO');
await db.query(`INSERT INTO anuncio (item_instancia_id, criador_id, data_publicacao, preco, data_expiracao, status_anuncio)
  VALUES ((SELECT id FROM item_instancia WHERE numero_inspecao = 'INS-EQ-0013'), $1, '2026-01-01', 900, '2026-01-08', 'ativo')`, [dfontes]);
const vencido = await anuncioAtivo('INS-EQ-0013');
await deveFalhar('comprar anuncio vencido', 'SELECT * FROM fn_comprar_anuncio($1, $2, $3)', [vencido, isizinha, 'pix']);
const qtd = (await um('SELECT fn_expirar_anuncios() AS n')).n;
const st = (await um('SELECT status_anuncio FROM anuncio WHERE id = $1', [vencido])).status_anuncio;
ok(qtd === 1 && st === 'expirado', 'fn_expirar_anuncios expira so o vencido', `expirados=${qtd}, status=${st}`);
const capsula = (await um(`SELECT a.status_anuncio FROM anuncio a JOIN item_instancia i ON i.id = a.item_instancia_id
  WHERE i.numero_inspecao = 'INS-CN-0005' AND a.data_publicacao = '2026-02-03 12:25:00'`)).status_anuncio;
ok(capsula === 'ativo', 'anuncio com venda pendente nao e expirado', capsula);

console.log('--- AVALIACAO');
const ticket = (await um('SELECT fn_avaliar_venda($1, $2, $3, $4) AS t', [compra.venda_id, isizinha, 5, 'Entrega rapida.'])).t;
const aval = await um(`SELECT x.avaliado_id, x.nota FROM avaliacao x WHERE ticket_avaliacao = $1`, [ticket]);
ok(/^TKT-\d{4}-0011$/.test(ticket) && aval.avaliado_id === dfontes && aval.nota === 5, 'compradora avalia o vendedor (ticket e avaliado corretos)', ticket);
await deveFalhar('avaliar a mesma venda duas vezes', 'SELECT fn_avaliar_venda($1, $2, $3, $4)', [compra.venda_id, isizinha, 4, 'De novo']);
await deveFalhar('terceiro avaliar a venda', 'SELECT fn_avaliar_venda($1, $2, $3, $4)', [compra.venda_id, viniciuslabubu, 1, 'Intruso']);
const pendente = (await um(`SELECT id FROM venda WHERE protocolo_venda = 'VND-2026-0011'`)).id;
await deveFalhar('avaliar venda pendente', 'SELECT fn_avaliar_venda($1, $2, $3, $4)', [pendente, await user('JV'), 3, '']);
await deveFalhar('nota fora de 1 a 5', 'SELECT fn_avaliar_venda($1, $2, $3, $4)', [compra.venda_id, dfontes, 7, '']);
const t2 = (await um('SELECT fn_avaliar_venda($1, $2, $3, $4) AS t', [compra.venda_id, dfontes, 4, '  '])).t;
const coment = (await um('SELECT comentario FROM avaliacao WHERE ticket_avaliacao = $1', [t2])).comentario;
ok(/^TKT-\d{4}-0012$/.test(t2) && coment === null, 'vendedor tambem avalia a compradora; comentario vazio vira NULL', t2);

console.log('--- NUMERACAO ACIMA DE 9999');
// Protocolo e ticket tem 4 digitos ate 9999; depois crescem, sem cortar.
await db.query(`SELECT setval('venda_protocolo_seq', 9999)`);
const deag = await um(`SELECT a.id, a.criador_id FROM anuncio a JOIN item_instancia i ON i.id = a.item_instancia_id
  WHERE i.numero_inspecao = 'INS-EQ-0010' AND a.status_anuncio = 'ativo'`);
const comprador = [isizinha, dfontes].find((u) => u !== deag.criador_id);
const grande = await um('SELECT * FROM fn_comprar_anuncio($1, $2, $3)', [deag.id, comprador, 'boleto']);
ok(/^VND-\d{4}-10000$/.test(grande.protocolo) && dvValido(grande.chave_nota_fiscal), 'protocolo 10000 sai inteiro, com nota valida', grande.protocolo);
await db.query(`SELECT setval('avaliacao_ticket_seq', 9999)`);
const ticketGrande = (await um('SELECT fn_avaliar_venda($1, $2, $3, $4) AS t', [grande.venda_id, comprador, 5, ''])).t;
ok(/^TKT-\d{4}-10000$/.test(ticketGrande), 'ticket 10000 sai inteiro', ticketGrande);

console.log('--- VERIFICACAO GERAL DEPOIS DE TUDO');
const res = await db.exec(fs.readFileSync(path.join(dir, '05_verificacao.sql'), 'utf8'));
const contagens = res[0].rows.filter(r => r.situacao !== 'OK');
const regras = res[1].rows.filter(r => r.resultado !== 'OK');
ok(contagens.length === 0 && regras.length === 0, `05_verificacao: ${res[1].rows.length} regras`, regras.length ? JSON.stringify(regras) : 'todas OK');

console.log(falhas ? `\n${falhas} teste(s) falharam` : '\nTodos os testes passaram');
await db.close?.();
process.exitCode = falhas ? 1 : 0;
