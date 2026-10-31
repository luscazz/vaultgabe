// Testes de BLOQUEIO: operacoes que as regras do banco devem recusar (e as
// que devem aceitar). Cada tentativa roda numa transacao desfeita.
import { fileURLToPath } from 'node:url';
import { abrir } from './banco.mjs';
import fs from 'node:fs';
import path from 'node:path';

const dir = fileURLToPath(new URL("../database/", import.meta.url));
const db = await abrir();
for (const f of ['01_tabelas.sql', '02_regras.sql', '03_dados.sql']) {
  await db.exec(fs.readFileSync(path.join(dir, f), 'utf8'));
}

const id = (ins) => `(SELECT id FROM item_instancia WHERE numero_inspecao='${ins}')`;
const user = (n) => `(SELECT id FROM usuario WHERE steam_id='STEAM_765611980000000${String(n).padStart(2, '0')}')`;
const novoAnuncio = (ins, u, status = 'ativo') =>
  `INSERT INTO anuncio (item_instancia_id, criador_id, data_publicacao, preco, data_expiracao, status_anuncio)
   VALUES (${id(ins)}, ${user(u)}, now(), 100, now() + interval '7 days', '${status}')`;

const casos = [
  ['BLOQUEAR: anunciar item de outro usuario', novoAnuncio('INS-EQ-0013', 1), false],
  ['BLOQUEAR: anunciar item bloqueado (EQ-0009)', novoAnuncio('INS-EQ-0009', 8), false],
  ['BLOQUEAR: anunciar item consumido (caixa aberta CN-0011)', novoAnuncio('INS-CN-0011', 1), false],
  ['BLOQUEAR: 2o anuncio aberto do mesmo item (EQ-0004 ja ativo)', novoAnuncio('INS-EQ-0004', 4), false],
  ['BLOQUEAR: anunciar adesivo aplicado (CO-0014)', novoAnuncio('INS-CO-0014', 9), false],
  ['BLOQUEAR: aplicar cosmetico de outro dono (CO-0010 de Bruno na AK EQ-0011 da Ana)',
    `INSERT INTO aplicacao_cosmetico VALUES (${id('INS-CO-0010')}, ${id('INS-EQ-0011')}, 1, 1, 0, 0)`, false],
  // Fora o anuncio, a abertura seria valida: a recusa tem de vir dele.
  ['BLOQUEAR: abrir capsula anunciada (CN-0005, com venda pendente)',
    `INSERT INTO abertura_recipiente (usuario_id, recipiente_id, chave_id, item_resultado_id, data_abertura)
     VALUES (${user(2)}, ${id('INS-CN-0005')}, NULL, ${id('INS-CO-0010')}, now())`, false, /anuncio aberto/],
  ['PERMITIR: anunciar item proprio e livre (EQ-0013 do Diego)', novoAnuncio('INS-EQ-0013', 4), true],
  ['PERMITIR: aplicar cosmetico proprio (CO-0011 do Bruno na AK EQ-0002 do Bruno)',
    `INSERT INTO aplicacao_cosmetico VALUES (${id('INS-CO-0011')}, ${id('INS-EQ-0002')}, 1, 1, 0, 0)`, true],
];

let falhas = 0;
// motivo (opcional): trecho que a mensagem de recusa precisa ter.
for (const [nome, sql, deveFuncionar, motivo] of casos) {
  let ok, msg = '';
  try {
    await db.transaction(async (tx) => { await tx.exec(sql); throw new Error('__rollback__'); });
  } catch (e) { msg = e.message; }
  const funcionou = msg === '__rollback__';
  ok = funcionou === deveFuncionar && (funcionou || !motivo || motivo.test(msg));
  if (!ok) falhas++;
  console.log(`${ok ? 'OK  ' : 'FALHOU'} ${nome}${funcionou ? '' : '  -> ' + msg}`);
}

// Vender a AK EQ-0002 (com chaveiro aplicado) e conferir se o chaveiro acompanha
await db.exec(`UPDATE item_instancia SET proprietario_id = ${user(9)} WHERE id = ${id('INS-EQ-0002')}`);
const r = await db.query(`SELECT u.apelido FROM item_instancia i JOIN usuario u ON u.id = i.proprietario_id WHERE i.id = ${id('INS-CO-0019')}`);
const acompanhou = r.rows[0].apelido === 'isizinha';
if (!acompanhou) falhas++;
console.log(`${acompanhou ? 'OK  ' : 'FALHOU'} cosmetico aplicado acompanha a arma ao mudar de dono (dono do CO-0019 agora: ${r.rows[0].apelido})`);

console.log(falhas ? `\n${falhas} teste(s) falharam` : '\nTodos os testes passaram');
await db.close?.();
process.exitCode = falhas ? 1 : 0;
