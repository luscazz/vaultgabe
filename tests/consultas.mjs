// Testes das CONSULTAS de database/consultas: executa cada uma com parametros
// reais e confere o resultado com valores conhecidos dos dados.
import { fileURLToPath } from 'node:url';
import { abrir } from './banco.mjs';
import fs from 'node:fs';
import path from 'node:path';

const dir = fileURLToPath(new URL("../database/", import.meta.url));
const db = await abrir();
for (const f of ['01_tabelas.sql', '02_regras.sql', '03_dados.sql']) {
  await db.exec(fs.readFileSync(path.join(dir, f), 'utf8'));
}

// Carrega as consultas pelo nome (mesmo formato usado pelo backend).
const consultas = {};
const pasta = path.join(dir, 'consultas');
for (const arq of fs.readdirSync(pasta).filter(f => f.endsWith('.sql'))) {
  const partes = fs.readFileSync(path.join(pasta, arq), 'utf8').split(/^-- name: /m).slice(1);
  for (const p of partes) {
    const nome = p.slice(0, p.indexOf('\n')).trim();
    if (consultas[nome]) throw new Error(`consulta duplicada: ${nome}`);
    consultas[nome] = { sql: p.slice(p.indexOf('\n') + 1), arq };
  }
}
const usadas = new Set();
const q = async (nome, params = []) => {
  if (!consultas[nome]) throw new Error(`consulta inexistente: ${nome}`);
  usadas.add(nome);
  return (await db.query(consultas[nome].sql, params)).rows;
};

let falhas = 0;
const ok = (cond, nome, extra = '') => {
  if (!cond) falhas++;
  console.log(`${cond ? 'OK    ' : 'FALHOU'} ${nome}${extra !== '' ? '  -> ' + extra : ''}`);
};
const num = (v) => (v === null || v === undefined ? null : Number(v));
const id = async (sql, p = []) => Object.values((await db.query(sql, p)).rows[0])[0];
const user = (apelido) => id('SELECT id FROM usuario WHERE apelido = $1', [apelido]);
const modelo = (nome) => id('SELECT id FROM item_catalogo WHERE nome_item = $1', [nome]);
const item = (ins) => id('SELECT id FROM item_instancia WHERE numero_inspecao = $1', [ins]);
const N = null;
const filtros = (o = {}) => [o.busca ?? N, o.categorias ?? N, o.raridades ?? N, o.colecao ?? N, o.min ?? N, o.max ?? N,
  o.aVenda ?? N, o.desgastes ?? N, o.st ?? N, o.sv ?? N, o.adesivos ?? N, o.ordenar ?? N];

const isizinha = await user('isizinha'), lari = await user('lari'), ana = await user('galabinha'),
  bruno = await user('viniciuslabubu'), jv = await user('JV'), diego = await user('dfontes');

console.log('--- COMUM');
ok((await q('listar_usuarios')).length === 12, 'listar_usuarios: 12 usuarios');
ok(num((await q('expirar_anuncios'))[0].expirados) === 0, 'expirar_anuncios: nenhum vencido hoje');
const saude = (await q('saude_banco'))[0];
ok(Boolean(saude.versao && saude.fuso && saude.agora), 'saude_banco: versao, fuso e hora do banco', `${saude.versao} / ${saude.fuso}`);

console.log('--- CATALOGO');
ok((await q('listar_categorias')).length === 13, 'listar_categorias: 13');
const rar = await q('listar_raridades');
ok(rar.length === 9 && rar.every(r => /^#[0-9a-f]{6}$/i.test(r.cor)), 'listar_raridades: 9 usadas, com cor');
ok((await q('listar_colecoes')).length === 12, 'listar_colecoes: 12');
let cat = await q('buscar_catalogo', filtros());
ok(cat.length === 21, 'catalogo sem filtros: 21 modelos');
ok(cat[0].nome === 'P90 | Sand Spray' && num(cat[0].menor_preco) === 35, 'ordem padrao: menor preco primeiro', cat[0].nome);
// A unica oferta da Capsula Ambush tem venda pendente (reservada): nao pode ser comprada.
const cardAmbush = cat.find(c => c.nome === 'Capsula Ambush');
ok(cardAmbush?.menor_preco === null && num(cardAmbush.ofertas) === 0, 'card da Capsula Ambush: oferta reservada fora do menor preco e das ofertas',
  JSON.stringify({ menor: cardAmbush?.menor_preco, ofertas: cardAmbush?.ofertas }));
cat = await q('buscar_catalogo', filtros({ aVenda: true }));
ok(cat.length === 5 && !cat.some(c => c.nome === 'Capsula Ambush'), 'so a venda: 5 modelos (sem a capsula reservada)', cat.map(c => c.nome).join(' / '));
cat = await q('buscar_catalogo', filtros({ desgastes: ['FN'] }));
ok(cat.length === 2 && cat.every(c => ['Karambit | Doppler', 'Desert Eagle | Blaze'].includes(c.nome)), 'desgaste FN: Karambit e Deagle', cat.map(c => c.nome).join(' / '));
ok((await q('buscar_catalogo', filtros({ st: true }))).length === 0, 'StatTrak: nenhuma oferta ativa');
cat = await q('buscar_catalogo', filtros({ adesivos: true }));
ok(cat.length === 1 && cat[0].nome === 'M4A4 | Howl', 'com adesivos: M4A4', cat.map(c => c.nome).join());
ok((await q('buscar_catalogo', filtros({ busca: 'GLOVES' }))).length === 3, 'busca "GLOVES": 3 luvas');
const luva = await id(`SELECT id FROM categoria_item WHERE nome_categoria = 'Luva'`);
ok((await q('buscar_catalogo', filtros({ categorias: [luva] }))).length === 3, 'categoria Luva: 3');
cat = await q('buscar_catalogo', filtros({ max: 1000 }));
ok(cat.length === 1 && cat[0].nome === 'P90 | Sand Spray', 'preco ate R$ 1000: so a P90 (a capsula reservada de R$ 680 nao conta)',
  cat.map(c => `${c.nome} ${c.menor_preco}`).join(' / '));
cat = await q('buscar_catalogo', filtros({ ordenar: 'maior_preco' }));
ok(cat[0].nome === 'M4A4 | Howl', 'ordenar maior preco: M4A4 primeiro');
cat = await q('buscar_catalogo', filtros({ ordenar: 'mais_vendidas' }));
ok(num(cat[0].vendas) === 1 && num(cat[20].vendas) === 0, 'ordenar mais vendidas');

console.log('--- DETALHE DA SKIN');
const m4 = await modelo('M4A4 | Howl'), ak = await modelo('AK-47 | Redline'), crown = await modelo('Adesivo | Crown (Foil)');
const det = (await q('detalhe_modelo', [m4]))[0];
ok(det.tipo === 'equipamento' && num(det.menor_preco) === 10500 && num(det.ofertas) === 1 && num(det.preco_medio) === 9800 && num(det.vendas) === 1,
  'detalhe M4A4: tipo, menor preco, media e vendas', `${det.tipo} ${det.menor_preco} ${det.preco_medio}`);
ok((await q('detalhe_modelo', [crown]))[0].tipo === 'cosmetico', 'detalhe Adesivo Crown: tipo cosmetico');
let of = await q('ofertas_do_modelo', [m4, N, N, N, N, N, isizinha]);
ok(of.length === 1 && of[0].vendedor === 'lari' && of[0].cosmeticos_aplicados === 'Adesivo | Natus Vincere (Holo)'
  && num(of[0].nota_vendedor) === 5 && of[0].e_minha === false && num(of[0].diferenca_media_pct) === 7.1 && of[0].desgaste === 'MW',
  'ofertas M4A4: vendedor, adesivo, nota, desgaste e +7,1% sobre a media', JSON.stringify({ d: of[0].desgaste, pct: of[0].diferenca_media_pct }));
// A unica venda da M4A4 e do mesmo exemplar: menos de 2 vendas da versao, usa o modelo.
ok(of[0].base_media === 'modelo' && num(of[0].vendas_comparaveis) === 1 && num(of[0].preco_medio_comparavel) === 9800,
  'ofertas M4A4: sem 2 vendas da mesma versao, compara com a media do modelo', `${of[0].base_media}, ${of[0].vendas_comparaveis} venda`);
of = await q('ofertas_do_modelo', [m4, N, N, N, N, N, lari]);
ok(of[0].e_minha === true, 'ofertas M4A4 vistas pela Larissa: marcada como minha');
ok((await q('ofertas_do_modelo', [m4, ['FN'], N, N, N, 'float', isizinha])).length === 0, 'ofertas M4A4 so FN: nenhuma');
const ambush = await modelo('Capsula Ambush');
const detAmbush = (await q('detalhe_modelo', [ambush]))[0];
of = await q('ofertas_do_modelo', [ambush, N, N, N, N, N, isizinha]);
ok(detAmbush.menor_preco === null && num(detAmbush.ofertas) === 0 && of.length === 1 && of[0].reservada === true && num(of[0].preco) === 680,
  'Capsula Ambush: a oferta reservada continua listada, mas fica fora do menor preco e das ofertas a venda');
const semItem = (await db.query('SELECT * FROM fn_media_vendas_comparaveis($1)', [999999])).rows[0];
ok(semItem.preco_medio === null && num(semItem.vendas) === 0 && semItem.base === 'modelo', 'fn_media_vendas_comparaveis de item inexistente: sem media');
const hist = await q('historico_vendas_modelo', [ak]);
ok(hist.length === 1 && num(hist[0].valor) === 850 && hist[0].vendedor === 'galabinha' && hist[0].comprador === 'isizinha' && hist[0].desgaste === 'FT',
  'historico AK-47: 1 venda de R$ 850 (FT), galabinha -> isizinha');
const meses = await q('precos_por_mes_modelo', [ak]);
ok(meses.length === 1 && num(meses[0].vendas) === 1, 'precos por mes AK-47: 1 ponto', meses[0] ? new Date(meses[0].mes).toISOString().slice(0, 7) : '');

console.log('--- INVENTARIO');
const res = (await q('resumo_inventario', [isizinha]))[0];
ok(num(res.itens) === 11 && num(res.negociaveis) === 7 && num(res.anunciados) === 0 && num(res.prontos_para_anunciar) === 7,
  'resumo isizinha: 11 itens, 7 negociaveis, 0 anunciados');
let inv = await q('inventario_usuario', [isizinha, N, N]);
const sit = inv.reduce((m, r) => ({ ...m, [r.situacao]: (m[r.situacao] || 0) + 1 }), {});
ok(inv.length === 11 && sit.aplicado === 4 && sit.disponivel === 7, 'inventario isizinha: 4 aplicados + 7 disponiveis', JSON.stringify(sit));
const akIsa = inv.find(r => r.numero_inspecao === 'INS-EQ-0001');
ok(akIsa.cosmeticos_aplicados.split(', ').length === 3 && akIsa.stattrak === true, 'AK-47 da isizinha: 3 cosmeticos aplicados e StatTrak', akIsa.cosmeticos_aplicados);
ok(inv.find(r => r.numero_inspecao === 'INS-CO-0014').aplicado_em === 'AK-47 | Redline', 'adesivo aplicado mostra a arma');
ok((await q('inventario_usuario', [isizinha, 'cosmetico', N])).length === 6, 'filtro tipo cosmetico: 6');
ok((await q('inventario_usuario', [isizinha, N, true])).length === 7, 'filtro so negociaveis: 7');
ok(num(res.itens_equipamento) + num(res.itens_cosmetico) + num(res.itens_consumivel) === num(res.itens) && num(res.itens_cosmetico) === 6,
  'resumo isizinha: abas somam os 11 itens, 6 cosmeticos', JSON.stringify(res));
// O numero de cada aba (resumo) e o tamanho da lista que a aba mostra, com e sem o filtro.
const TIPOS = ['equipamento', 'cosmetico', 'consumivel'];
const abasErradas = [];
for (const u of await q('listar_usuarios')) {
  const r = (await q('resumo_inventario', [u.id]))[0];
  if (num(r.prontos_para_anunciar) !== (await q('inventario_usuario', [u.id, N, true])).length) abasErradas.push(`${u.apelido} todos`);
  for (const tipo of TIPOS) {
    if (num(r[`itens_${tipo}`]) !== (await q('inventario_usuario', [u.id, tipo, N])).length) abasErradas.push(`${u.apelido} itens_${tipo}`);
    if (num(r[`prontos_${tipo}`]) !== (await q('inventario_usuario', [u.id, tipo, true])).length) abasErradas.push(`${u.apelido} prontos_${tipo}`);
  }
}
ok(abasErradas.length === 0, 'resumo_inventario: numero de cada aba bate com a lista (12 usuarios)', abasErradas.join(', '));
inv = await q('inventario_usuario', [ana, N, N]);
const caixa = inv.find(r => r.numero_inspecao === 'INS-CN-0011'), chave = inv.find(r => r.numero_inspecao === 'INS-CN-0012'),
  obtida = inv.find(r => r.numero_inspecao === 'INS-EQ-0011');
ok(caixa.situacao === 'consumido' && caixa.resultado_abertura === 'AK-47 | Redline' && caixa.aberto_em !== null,
  'caixa aberta da Ana: consumida, com o resultado');
ok(chave.chave_usada_em !== null && obtida.obtido_ao_abrir === 'Caixa Fracture', 'chave usada e AK obtida ao abrir a Caixa Fracture');
const deagleIsa = await item('INS-EQ-0005');
const ap = (await q('analise_preco_anuncio', [deagleIsa, 2000]))[0];
ok(num(ap.menor_preco_atual) === 1950 && num(ap.preco_medio_vendas) === 2100 && num(ap.diferenca_media_pct) === -4.8,
  'analise de preco Deagle a R$ 2000: menor atual 1950, media 2100, -4,8%');
ok(ap.base_media === 'modelo' && num(ap.vendas) === 1, 'analise de preco Deagle: sem 2 vendas da versao, usa o modelo', `${ap.base_media}, ${ap.vendas} venda`);
const apAmbush = (await q('analise_preco_anuncio', [await item('INS-CN-0006'), 600]))[0];
ok(apAmbush.menor_preco_atual === null && num(apAmbush.ofertas_atuais) === 0, 'analise de preco da Capsula Ambush: a oferta reservada nao conta como oferta atual');

console.log('--- NEGOCIACOES');
let cnt = (await q('contar_negociacoes', [lari]))[0];
ok(num(cnt.a_venda) === 2 && num(cnt.vendidos) === 0 && num(cnt.comprados) === 3 && num(cnt.encerrados) === 0, 'abas da lari: 2 / 0 / 3 / 0');
const av = await q('anuncios_a_venda', [bruno]);
ok(av.length === 1 && av[0].venda_pendente === 'VND-2026-0011' && av[0].pode_cancelar === false, 'Bruno: capsula com venda pendente nao pode ser cancelada');
const vend = await q('anuncios_vendidos', [ana]);
ok(vend.length === 4 && vend.every(v => v.metodo_pagamento && v.chave_nota_fiscal), 'vendidos da Ana: 4, com pagamento e nota');
const akVendida = vend.find(v => v.numero_inspecao === 'INS-EQ-0001'), caixaVendida = vend.find(v => v.numero_inspecao === 'INS-CN-0001');
ok(num(akVendida?.float_value) === 0.1523 && akVendida.desgaste === 'FT' && caixaVendida?.float_value === null && caixaVendida.desgaste === null,
  'vendidos da Ana: AK-47 com float e desgaste (FT); caixa sem', `${akVendida?.float_value} ${akVendida?.desgaste}`);
const comp = await q('compras_do_usuario', [lari]);
const m4c = comp.find(c => c.nome === 'M4A4 | Howl'), kc = comp.find(c => c.nome === 'Karambit | Doppler');
ok(comp.length === 3 && m4c.ja_avaliou === true && m4c.pode_avaliar === false && kc.pode_avaliar === true,
  'compras da lari: ja avaliou a M4A4, pode avaliar o Karambit');
ok(m4c.desgaste === 'MW' && kc.desgaste === 'FN' && num(kc.float_value) === 0.0112, 'compras da lari: desgaste da M4A4 (MW) e do Karambit (FN)');
const encJv = await q('anuncios_encerrados', [jv]);
ok(encJv.length === 1 && encJv[0].float_value === null && encJv[0].desgaste === null, 'encerrados do JV: 1 expirado (chaveiro, sem float nem desgaste)');

console.log('--- ANALISE');
let ind = (await q('indicadores_gerais', [N, N, N]))[0];
ok(num(ind.vendas) === 10 && num(ind.volume) === 19967.4 && num(ind.ticket_medio) === 1996.74 && num(ind.ofertas_ativas) === 5,
  'indicadores gerais: 10 vendas, R$ 19.967,40, ticket R$ 1.996,74, 5 ofertas a venda (sem a reservada)');
// ultima_venda: fim dos periodos prontos da pagina; ignora os filtros.
ok(ind.ultima_venda === '2026-02-02', 'indicadores: ultima venda concluida em 2026-02-02', ind.ultima_venda);
const rifle = await id(`SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'`);
ind = (await q('indicadores_gerais', [N, N, rifle]))[0];
ok(num(ind.vendas) === 3 && num(ind.volume) === 11900 && ind.ultima_venda === '2026-02-02', 'indicadores Rifle: 3 vendas, R$ 11.900; ultima venda nao muda');
ind = (await q('indicadores_gerais', ['2026-01-01', '2026-01-31', N]))[0];
ok(num(ind.vendas) === 9 && num(ind.volume) === 19957.5, 'indicadores de janeiro: 9 vendas (fim do periodo inclusive)');
ok(ind.ultima_venda === '2026-02-02', 'indicadores de janeiro: ultima venda continua 2026-02-02 (fora do periodo)', ind.ultima_venda);
ok((await q('vendas_por_mes', [N, N, N])).length === 2, 'vendas por mes: jan e fev');
ok((await q('preco_medio_por_raridade', [N, N, N]))[0].raridade === 'Contraband', 'maior preco medio: Contraband');
ok((await q('volume_por_categoria', [N, N, N]))[0].categoria === 'Rifle', 'maior volume: Rifle');
const top = await q('mais_negociadas', [N, N, N, 5]);
ok(top.length === 5 && top[0].nome === 'M4A4 | Howl', 'mais negociadas (limite 5): M4A4 no topo pelo volume');
ok((await q('maiores_variacoes', [N, N, N, N])).length === 0, 'maiores variacoes: vazio (nenhum modelo com 2 vendas ainda)');
const rep = await q('vendedores_mais_bem_avaliados', [3]);
// So notas recebidas como vendedor: galabinha (5, 5 e 2) e manojoe (3).
ok(rep.length === 2 && rep[0].apelido === 'galabinha' && num(rep[0].nota_media) === 4 && rep.every(r => num(r.vendas) > 0),
  'ranking de vendedores: so notas de vendas, todos com vendas', rep.map(r => `${r.apelido} ${r.nota_media} (${r.avaliacoes})`).join(' / '));

console.log('--- PERFIL');
const pf = (await q('perfil_usuario', [ana]))[0];
ok(num(pf.nota_media) === 4 && num(pf.avaliacoes) === 3 && num(pf.vendas) === 4 && num(pf.compras) === 0 && num(pf.itens) === 3 && !('email' in pf),
  'perfil da Ana: nota 4,0 (3), 4 vendas, 3 itens, sem e-mail');
ok((await q('anuncios_ativos_do_usuario', [lari])).length === 2, 'anuncios ativos da lari: 2');
const ar = await q('avaliacoes_recebidas', [ana]);
ok(ar.length === 3 && ar.every(a => a.origem === 'venda'), 'avaliacoes da Ana: 3, todas de venda');
const tr = await q('trocas_do_usuario', [isizinha]);
const t9 = tr.find(t => t.protocolo === 'TRC-2026-0009');
ok(tr.length === 2 && t9.papel === 'destinatario' && t9.itens_oferecidos === 'Chave de Caixa, Chave de Caixa' && t9.itens_solicitados === 'Chaveiro | Hot Howl',
  'trocas da isizinha: 2; TRC-0009 com 2 chaves por 1 chaveiro');

console.log('--- GRAVACOES');
const novo = (await q('publicar_anuncio', [deagleIsa, isizinha, 2000, 7]))[0];
const dias = (new Date(novo.data_expiracao) - new Date(novo.data_publicacao)) / 86400000;
ok(novo.anuncio_id > 0 && Math.round(dias) === 7, 'publicar anuncio da Deagle por 7 dias');
ok((await q('inventario_usuario', [isizinha, N, N])).find(r => r.item_id === deagleIsa).situacao === 'anunciado', 'inventario mostra a Deagle como anunciada');
try { await q('publicar_anuncio', [deagleIsa, isizinha, 2100, 7]); ok(false, 'segundo anuncio do mesmo item bloqueado'); }
catch (e) { ok(true, 'segundo anuncio do mesmo item bloqueado', e.message); }
try { await q('publicar_anuncio', [await item('INS-EQ-0013'), isizinha, 500, 7]); ok(false, 'anunciar item de outro bloqueado'); }
catch (e) { ok(true, 'anunciar item de outro bloqueado', e.message); }
ok((await q('cancelar_anuncio', [novo.anuncio_id, lari])).length === 0, 'outro usuario nao cancela o anuncio');
ok((await q('cancelar_anuncio', [novo.anuncio_id, isizinha])).length === 1, 'dona cancela o anuncio');
ok((await q('anuncios_encerrados', [isizinha])).some(a => a.anuncio_id === novo.anuncio_id && a.status_anuncio === 'cancelado' && a.desgaste === 'FN'),
  'anuncio cancelado vai para Encerrados, com o desgaste da Deagle (FN)');
const compra = (await q('comprar_anuncio', [await id(`SELECT anuncio_id FROM vw_ofertas_ativas oa JOIN item_instancia i ON i.id = oa.item_id WHERE i.numero_inspecao = 'INS-EQ-0004'`), isizinha, 'pix']))[0];
ok(/^VND-\d{4}-0013$/.test(compra.protocolo), 'comprar AWP do Diego', compra.protocolo);
const dataCompra = await id(`SELECT TO_CHAR(data_venda, 'YYYY-MM-DD') FROM venda WHERE id = $1`, [compra.venda_id]);
ok((await q('indicadores_gerais', [N, N, N]))[0].ultima_venda === dataCompra, 'a compra nova passa a ser a ultima venda da Analise', dataCompra);
const tk = (await q('avaliar_vendedor', [compra.venda_id, isizinha, 5, 'Otimo']))[0].ticket;
ok(/^TKT-\d{4}-0011$/.test(tk), 'avaliar o vendedor depois da compra', tk);
ok(num((await q('perfil_usuario', [diego]))[0].avaliacoes) === 1, 'perfil do Diego ja mostra a nova avaliacao');

console.log('--- COBERTURA E VERIFICACAO FINAL');
const naoTestadas = Object.keys(consultas).filter(n => !usadas.has(n));
ok(naoTestadas.length === 0, `${Object.keys(consultas).length} consultas, todas executadas`, naoTestadas.join(', '));
const ver = await db.exec(fs.readFileSync(path.join(dir, '05_verificacao.sql'), 'utf8'));
ok(ver[1].rows.every(r => r.resultado === 'OK') && ver[0].rows.every(r => r.situacao === 'OK'), '05_verificacao depois das gravacoes: tudo OK');

console.log(falhas ? `\n${falhas} teste(s) falharam` : '\nTodos os testes passaram');
await db.close?.();
process.exitCode = falhas ? 1 : 0;
