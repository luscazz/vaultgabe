// Testes dos DADOS AMPLIADOS (database/04_dados_ampliados.sql): monta 01 a 04,
// confere 05_verificacao.sql e se os dados atendem ao que as telas precisam
// (catalogo maior, historico de 12 meses, anuncios validos).
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import { abrir } from './banco.mjs';

const dir = fileURLToPath(new URL('../database/', import.meta.url));
const db = await abrir();
for (const f of ['01_tabelas.sql', '02_regras.sql', '03_dados.sql', '04_dados_ampliados.sql']) {
  await db.exec(fs.readFileSync(path.join(dir, f), 'utf8'));
}

let falhas = 0;
const ok = (cond, nome, extra = '') => {
  if (!cond) falhas++;
  console.log(`${cond ? 'OK    ' : 'FALHOU'} ${nome}${extra !== '' ? '  -> ' + extra : ''}`);
};
const um = async (sql, params = []) => (await db.query(sql, params)).rows[0];
const num = (v) => Number(v);

// Carrega as consultas da aplicacao pelo nome (mesmo formato do backend).
const consultas = {};
for (const arq of fs.readdirSync(path.join(dir, 'consultas')).filter((f) => f.endsWith('.sql'))) {
  for (const p of fs.readFileSync(path.join(dir, 'consultas', arq), 'utf8').split(/^-- name: /m).slice(1)) {
    consultas[p.slice(0, p.indexOf('\n')).trim()] = p.slice(p.indexOf('\n') + 1);
  }
}
const q = async (nome, params = []) => (await db.query(consultas[nome], params)).rows;

console.log('--- VERIFICACAO (05_verificacao.sql)');
const ver = await db.exec(fs.readFileSync(path.join(dir, '05_verificacao.sql'), 'utf8'));
const contagensRuins = ver[0].rows.filter((r) => r.situacao !== 'OK');
const regrasRuins = ver[1].rows.filter((r) => r.resultado !== 'OK');
ok(contagensRuins.length === 0, 'contagens minimas: todas OK', JSON.stringify(contagensRuins));
ok(regrasRuins.length === 0, `regras semanticas: ${ver[1].rows.length} OK`, regrasRuins.length ? JSON.stringify(regrasRuins) : '');

console.log('--- CATALOGO');
const cat = await um(`SELECT COUNT(*) AS modelos,
  COUNT(*) FILTER (WHERE imagem_base LIKE 'https://%') AS com_imagem,
  COUNT(DISTINCT categoria_id) AS categorias FROM item_catalogo`);
ok(num(cat.modelos) >= 75, 'catalogo com cerca de 80 modelos', `${cat.modelos} modelos`);
ok(num(cat.com_imagem) === num(cat.modelos), 'todo modelo tem link de imagem https');
const itens = num((await um('SELECT COUNT(*) AS n FROM item_instancia')).n);
ok(itens >= 200, 'exemplares: pelo menos 200', `${itens} itens`);
const foraDaFaixa = num((await um(`SELECT COUNT(*) AS n FROM equipamento e
  JOIN item_instancia i ON i.id = e.item_instancia_id JOIN item_catalogo ic ON ic.id = i.item_catalogo_id
  WHERE e.float_value < ic.float_min OR e.float_value > ic.float_max`)).n);
ok(foraDaFaixa === 0, 'todo float dentro da faixa do modelo', `${foraDaFaixa} fora`);
ok((await q('buscar_catalogo', Array(12).fill(null))).length === num(cat.modelos), 'buscar_catalogo devolve todos os modelos');

console.log('--- HISTORICO DE VENDAS');
const vendas = await um(`SELECT COUNT(*) AS n, COUNT(DISTINCT date_trunc('month', data_venda)) AS meses,
  MIN(data_venda)::DATE::TEXT AS primeira, MAX(data_venda)::DATE::TEXT AS ultima FROM vw_vendas_concluidas`);
ok(num(vendas.n) >= 300, 'pelo menos 300 vendas concluidas', `${vendas.n} vendas de ${vendas.primeira} a ${vendas.ultima}`);
ok(num(vendas.meses) >= 12, 'vendas em pelo menos 12 meses', `${vendas.meses} meses`);
ok(vendas.ultima <= '2026-10-27', 'nenhuma venda no futuro', vendas.ultima);
const comHistorico = num((await um(`SELECT COUNT(*) AS n FROM (SELECT modelo_id FROM vw_vendas_concluidas
  GROUP BY modelo_id HAVING COUNT(*) >= 3) t`)).n);
ok(comHistorico >= num(cat.modelos) * 0.6, 'a maioria dos modelos tem 3 ou mais vendas (graficos de preco)', `${comHistorico} modelos`);
const protocolos = await um(`SELECT COUNT(*) AS n, COUNT(DISTINCT protocolo_venda) AS distintos,
  COUNT(*) FILTER (WHERE protocolo_venda !~ '^VND-\\d{4}-\\d{4,}$') AS fora_do_formato,
  COUNT(*) FILTER (WHERE substr(protocolo_venda, 5, 4) <> to_char(data_venda, 'YYYY')) AS ano_errado FROM venda`);
ok(num(protocolos.n) === num(protocolos.distintos) && num(protocolos.fora_do_formato) === 0 && num(protocolos.ano_errado) === 0,
  'protocolos unicos, no formato VND-AAAA-NNNN e com o ano da venda', JSON.stringify(protocolos));

console.log('--- ANUNCIOS ATIVOS');
const anuncios = await um(`SELECT COUNT(*) AS ativos, MIN(data_expiracao)::DATE::TEXT AS primeira_expiracao
  FROM anuncio WHERE status_anuncio = 'ativo'`);
ok(num(anuncios.ativos) >= 60, 'pelo menos 60 anuncios ativos', `${anuncios.ativos}`);
ok(anuncios.primeira_expiracao >= '2027-01-01', 'nenhum anuncio ativo vence em 2026', anuncios.primeira_expiracao);
ok(num((await q('expirar_anuncios'))[0].expirados) === 0, 'expirar_anuncios: nenhum vencido hoje');

console.log('--- PAGINAS COM OS DADOS AMPLIADOS');
const isizinha = num((await um(`SELECT id FROM usuario WHERE apelido = 'isizinha'`)).id);
const [resumo] = await q('resumo_inventario', [isizinha]);
ok(num(resumo.prontos_para_anunciar) >= 3, 'isizinha tem itens prontos para anunciar', JSON.stringify(resumo));
const compras = await q('compras_do_usuario', [isizinha]);
ok(compras.filter((c) => c.pode_avaliar).length >= 2, 'isizinha tem compras ainda nao avaliadas', `${compras.filter((c) => c.pode_avaliar).length}`);
const meses = await q('vendas_por_mes', [null, null, null]);
ok(meses.length >= 12 && meses.every((m) => num(m.vendas) > 0), 'analise: vendas em todos os meses', `${meses.length} meses`);
ok((await q('maiores_variacoes', [null, null, null, 10])).length === 10, 'analise: ranking de variacoes completo (10)');

console.log('--- AJUSTES NOS DADOS DO 03 (secao 11)');
const ak = await um(`SELECT co.nome_colecao FROM item_catalogo ic JOIN colecao co ON co.id = ic.colecao_id WHERE ic.nome_item = 'AK-47 | Redline'`);
ok(ak?.nome_colecao === 'The Phoenix Collection', 'colecao da AK-47 | Redline conferida com o CSGO-API', ak?.nome_colecao);
const variantes = await um(`SELECT
  (SELECT e.stattrak_flag FROM equipamento e JOIN item_instancia i ON i.id = e.item_instancia_id WHERE i.numero_inspecao = 'INS-EQ-0005') AS deagle_st,
  (SELECT e.souvenir_flag FROM equipamento e JOIN item_instancia i ON i.id = e.item_instancia_id WHERE i.numero_inspecao = 'INS-EQ-0003') AS asiimov_sv`);
ok(variantes.deagle_st === false && variantes.asiimov_sv === false, 'sem variantes que nao existem (Desert Eagle | Blaze StatTrak, AWP | Asiimov Souvenir)');
const colecoes = (await db.query('SELECT nome_colecao FROM colecao')).rows.map((c) => c.nome_colecao);
ok(colecoes.length === 29 && colecoes.every((n) => /Collection$/.test(n)), '29 colecoes, todas com nome de colecao (nao de caixa)', colecoes.filter((n) => !/Collection$/.test(n)).join(', '));
// Chaveiros so existem no CS2 desde 02/10/2024.
const chaveiros = await um(`SELECT COUNT(*) AS n, MIN(i.data_obtencao)::DATE::TEXT AS primeira FROM cosmetico c
  JOIN item_instancia i ON i.id = c.item_instancia_id WHERE c.tipo_cosmetico = 'chaveiro'`);
ok(num(chaveiros.n) > 0 && chaveiros.primeira >= '2024-10-02', 'chaveiros obtidos so depois de 02/10/2024 (chegada ao jogo)', `${chaveiros.n} chaveiros, o primeiro em ${chaveiros.primeira}`);

// Cada abertura da um item que sai daquele recipiente.
const aberturas = (await db.query(`SELECT rc.nome_item AS recipiente, ch.nome_item AS chave, res.nome_item AS resultado,
       rc.colecao_id = res.colecao_id AS mesma_colecao
  FROM abertura_recipiente ab
  JOIN item_instancia r ON r.id = ab.recipiente_id      JOIN item_catalogo rc  ON rc.id  = r.item_catalogo_id
  LEFT JOIN item_instancia c ON c.id = ab.chave_id      LEFT JOIN item_catalogo ch ON ch.id = c.item_catalogo_id
  JOIN item_instancia o ON o.id = ab.item_resultado_id  JOIN item_catalogo res ON res.id = o.item_catalogo_id`)).rows;
const caixa = aberturas.find((a) => a.chave !== null);
const abertasSemChave = aberturas.filter((a) => a.recipiente.startsWith('Cápsula Katowice'));
ok(caixa?.recipiente === 'Caixa Phoenix' && caixa.chave === 'Chave da Caixa Phoenix' && caixa.mesma_colecao
  && abertasSemChave.length === 3 && abertasSemChave.every((a) => a.resultado === 'Adesivo | Natus Vincere (Holo)'),
  'aberturas coerentes com o conteudo dos recipientes', aberturas.map((a) => `${a.recipiente} -> ${a.resultado}`).join(' / '));
const textos = await um(`SELECT
  (SELECT nome_categoria FROM categoria_item WHERE nome_categoria LIKE 'C%psula') AS categoria,
  (SELECT nome FROM usuario WHERE nome LIKE 'Jo%o Vitor Nunes') AS nome,
  (SELECT COUNT(*) FROM avaliacao WHERE comentario ~ '\\m(negociacao|rapido|Nao|so)\\M') AS sem_acento`);
ok(textos.categoria === 'Cápsula' && textos.nome === 'João Vitor Nunes' && num(textos.sem_acento) === 0,
  'textos da tela com acento (categoria, nome e comentarios)', `${textos.categoria} / ${textos.nome}`);
const crase = await um(`SELECT
  (SELECT descricao FROM item_catalogo WHERE nome_item = 'Desert Eagle | Blaze') AS descricao,
  (SELECT COUNT(*) FROM avaliacao WHERE comentario LIKE '%respondia as %') AS sem_crase`);
ok(crase.descricao.includes('à mão') && num(crase.sem_crase) === 0, 'crase nos textos ("pintadas à mão", "respondia às mensagens")', crase.descricao);
const capsulas = await q('buscar_catalogo', ['capsula', ...Array(11).fill(null)]);
ok(capsulas.length >= 3 && capsulas.every((m) => m.nome.startsWith('Cápsula')), 'busca sem acento ("capsula") encontra as Cápsulas', capsulas.map((m) => m.nome).join(' / '));

const ambush = await um(`SELECT a.preco, v.valor_venda, p.valor FROM anuncio a
  JOIN item_instancia i ON i.id = a.item_instancia_id JOIN venda v ON v.anuncio_id = a.id JOIN pagamento p ON p.venda_id = v.id
  WHERE i.numero_inspecao = 'INS-CN-0005' AND v.protocolo_venda = 'VND-2026-0011'`);
ok([ambush.preco, ambush.valor_venda, ambush.valor].every((v) => num(v) === 6.8), 'capsula reservada (VND-2026-0011) a R$ 6,80 no anuncio, na venda e no pagamento');

// Ninguem anuncia, compra, troca ou avalia antes de se cadastrar.
const antesDoCadastro = num((await um(`SELECT COUNT(*) AS n FROM usuario u WHERE
     EXISTS (SELECT 1 FROM anuncio a   WHERE a.criador_id = u.id   AND a.data_publicacao::DATE < u.data_cadastro)
  OR EXISTS (SELECT 1 FROM venda v     WHERE v.comprador_id = u.id AND v.data_venda::DATE      < u.data_cadastro)
  OR EXISTS (SELECT 1 FROM troca t     WHERE u.id IN (t.proponente_id, t.destinatario_id) AND t.data_proposta::DATE < u.data_cadastro)
  OR EXISTS (SELECT 1 FROM avaliacao x WHERE x.autor_id = u.id     AND x.data_avaliacao::DATE  < u.data_cadastro)`)).n);
const anosDeCadastro = num((await um(`SELECT COUNT(DISTINCT EXTRACT(YEAR FROM data_cadastro)) AS n FROM usuario`)).n);
ok(antesDoCadastro === 0 && anosDeCadastro >= 4, 'cadastros em anos variados e antes de qualquer atividade do usuario', `${anosDeCadastro} anos`);

// Avaliacao de VENDA fala da entrega; "troca" e so para avaliacao de troca.
const vendaFalandoDeTroca = num((await um(`SELECT COUNT(*) AS n FROM avaliacao x
  JOIN avaliacao_venda av ON av.avaliacao_id = x.id WHERE x.comentario ILIKE '%troca%'`)).n);
const semGuard = await um(`SELECT ROUND(AVG(x.nota), 1)::TEXT AS media FROM avaliacao x
  JOIN avaliacao_venda av ON av.avaliacao_id = x.id JOIN venda v ON v.id = av.venda_id
  JOIN anuncio a ON a.id = v.anuncio_id JOIN usuario u ON u.id = a.criador_id
  WHERE x.avaliado_id = a.criador_id AND NOT u.steam_guard_ativo`);
ok(vendaFalandoDeTroca === 0 && num(semGuard.media) < 3.6, 'avaliacoes de venda falam da entrega; vendedores sem Steam Guard com nota menor',
  `media sem Steam Guard ${semGuard.media}`);
// Quem fala da espera de 15 dias so escreve depois que o item chega.
const esperaCedo = num((await um(`SELECT COUNT(*) AS n FROM avaliacao x
  JOIN avaliacao_venda av ON av.avaliacao_id = x.id JOIN venda v ON v.id = av.venda_id
  WHERE (x.comentario LIKE '%15 dias%' OR x.comentario LIKE '%duas semanas%')
    AND x.data_avaliacao < v.data_venda + INTERVAL '15 days'`)).n);
ok(esperaCedo === 0, 'avaliacoes sobre a espera de 15 dias escritas depois de 15 dias da venda');
// E quem comprou so anuncia o item de novo depois que ele chega.
const anuncioRetido = num((await um(`SELECT COUNT(*) AS n FROM venda v
  JOIN anuncio a ON a.id = v.anuncio_id JOIN usuario vend ON vend.id = a.criador_id
  JOIN anuncio novo ON novo.item_instancia_id = a.item_instancia_id AND novo.criador_id = v.comprador_id
  WHERE v.status_venda = 'concluida' AND NOT vend.steam_guard_ativo
    AND novo.data_publicacao > v.data_venda AND novo.data_publicacao < v.data_venda + INTERVAL '15 days'`)).n);
ok(anuncioRetido === 0, 'item comprado de vendedor sem Steam Guard so volta a ser anunciado depois de 15 dias');

console.log('--- BUSCA E ORDEM DO CATALOGO');
ok((await q('buscar_catalogo', ['_', ...Array(11).fill(null)])).length === 0, '"_" e "%" na busca valem como texto, nao como curinga');
const porNome = (await q('buscar_catalogo', [...Array(11).fill(null), 'nome'])).map((m) => m.nome);
ok(porNome[0].startsWith('Adesivo') && porNome.indexOf('Cápsula Katowice 2014 Challengers') < porNome.indexOf('Chave da Caixa Phoenix'),
  'ordem por nome alfabetica (sem pesar maiusculas e acentos)', porNome.slice(0, 3).join(' / '));
const categorias = (await q('listar_categorias')).map((c) => c.nome);
ok(categorias.indexOf('Cápsula') < categorias.indexOf('Chave'), 'categorias em ordem alfabetica', categorias.join(', '));

console.log('--- OFERTAS RESERVADAS (venda pendente)');
// Recalcula o card de cada modelo sem a coluna reservada da visao.
const aVenda = new Map((await db.query(`SELECT modelo_id, MIN(preco) AS menor, COUNT(*) AS n FROM vw_ofertas_ativas oa
  WHERE NOT EXISTS (SELECT 1 FROM venda v WHERE v.anuncio_id = oa.anuncio_id AND v.status_venda = 'pendente')
  GROUP BY modelo_id`)).rows.map((r) => [r.modelo_id, r]));
const cardsErrados = (await q('buscar_catalogo', Array(12).fill(null))).filter((m) => {
  const e = aVenda.get(m.id);
  return num(m.ofertas) !== (e ? num(e.n) : 0) || (e ? num(m.menor_preco) !== num(e.menor) : m.menor_preco !== null);
});
ok(cardsErrados.length === 0, 'catalogo: menor preco e ofertas de cada card so com o que pode ser comprado', cardsErrados.map((m) => m.nome).join(', '));
const katowice = num((await um('SELECT id FROM item_catalogo WHERE nome_item = $1', ['Cápsula Katowice 2014 Challengers'])).id);
const [detKatowice] = await q('detalhe_modelo', [katowice]);
const ofKatowice = await q('ofertas_do_modelo', [katowice, null, null, null, null, null, null]);
const reservada = ofKatowice.filter((o) => o.reservada);
ok(num(detKatowice.menor_preco) === 6.84 && num(detKatowice.ofertas) === 1 && ofKatowice.length === 2 && reservada.length === 1 && num(reservada[0].preco) === 6.8,
  'Cápsula Katowice: a oferta reservada de R$ 6,80 continua listada, mas o menor preco e R$ 6,84 (1 oferta)', `${detKatowice.menor_preco} / ${detKatowice.ofertas}`);
const capsulaLivre = await um(`SELECT i.id FROM item_instancia i WHERE i.item_catalogo_id = $1 AND i.status_item = 'disponivel'
  AND NOT EXISTS (SELECT 1 FROM anuncio a WHERE a.item_instancia_id = i.id AND a.status_anuncio IN ('pendente', 'ativo')) ORDER BY i.id LIMIT 1`, [katowice]);
const [apKatowice] = await q('analise_preco_anuncio', [capsulaLivre.id, 7]);
ok(num(apKatowice.menor_preco_atual) === 6.84 && num(apKatowice.ofertas_atuais) === 1, 'Novo anuncio da Cápsula Katowice: menor preco atual sem a reservada (R$ 6,84)', apKatowice.menor_preco_atual);

console.log('--- ANALISE DE PRECO POR VERSAO');
// Recalcula em JS a media de cada oferta ativa: vendas da mesma versao
// (desgaste, StatTrak, Souvenir) se forem 2 ou mais; senao, todo o modelo.
const vendidas = (await db.query(`SELECT vc.modelo_id, vc.valor, fn_desgaste(e.float_value) AS desgaste, e.stattrak_flag AS st, e.souvenir_flag AS sv
  FROM vw_vendas_concluidas vc LEFT JOIN equipamento e ON e.item_instancia_id = vc.item_id`)).rows;
const ofertasAtivas = (await db.query(`SELECT oa.item_id, oa.modelo_id, e.item_instancia_id IS NOT NULL AS equipamento,
  fn_desgaste(e.float_value) AS desgaste, e.stattrak_flag AS st, e.souvenir_flag AS sv
  FROM vw_ofertas_ativas oa LEFT JOIN equipamento e ON e.item_instancia_id = oa.item_id`)).rows;
const bases = { versao: 0, modelo: 0 };
const mediasErradas = [];
for (const o of ofertasAtivas) {
  const doModelo = vendidas.filter((v) => v.modelo_id === o.modelo_id);
  const daVersao = o.equipamento ? doModelo.filter((v) => v.desgaste === o.desgaste && v.st === o.st && v.sv === o.sv) : [];
  const usadas = daVersao.length >= 2 ? daVersao : doModelo;
  const esperada = usadas.length ? usadas.reduce((t, v) => t + num(v.valor), 0) / usadas.length : null;
  const r = await um('SELECT * FROM fn_media_vendas_comparaveis($1)', [o.item_id]);
  bases[r.base]++;
  if (r.base !== (daVersao.length >= 2 ? 'versao' : 'modelo') || num(r.vendas) !== usadas.length
    || (esperada === null ? r.preco_medio !== null : Math.abs(num(r.preco_medio) - esperada) > 1e-6)) mediasErradas.push(o.item_id);
}
ok(mediasErradas.length === 0 && bases.versao > 0 && bases.modelo > 0, 'fn_media_vendas_comparaveis: media conferida em todas as ofertas ativas',
  `${bases.versao} pela versao, ${bases.modelo} pelo modelo${mediasErradas.length ? `; erradas: ${mediasErradas.join(', ')}` : ''}`);
const deagle = await um(`SELECT oa.item_id, oa.preco, oa.modelo_id FROM vw_ofertas_ativas oa JOIN item_catalogo ic ON ic.id = oa.modelo_id
  WHERE ic.nome_item = 'Desert Eagle | Blaze' ORDER BY oa.preco LIMIT 1`);
const naPagina = (await q('ofertas_do_modelo', [deagle.modelo_id, null, null, null, null, null, null])).find((o) => o.item_id === deagle.item_id);
const [naJanela] = await q('analise_preco_anuncio', [deagle.item_id, deagle.preco]);
ok(naPagina.base_media === 'versao' && naJanela.base_media === 'versao' && num(naPagina.diferenca_media_pct) === num(naJanela.diferenca_media_pct)
  && num(naPagina.vendas_comparaveis) === num(naJanela.vendas) && num(naPagina.preco_medio_comparavel) === num(naJanela.preco_medio_vendas),
  'Desert Eagle: pagina da skin e Novo anuncio comparam com a mesma versao e dao a mesma %',
  `${naJanela.diferenca_media_pct}% sobre R$ ${naJanela.preco_medio_vendas} (${naJanela.vendas} vendas)`);
// AK-47 | Vulcan FT StatTrak: so 1 venda dessa versao, entao vale a media do modelo.
const vulcan = num((await um(`SELECT id FROM item_catalogo WHERE nome_item = 'AK-47 | Vulcan'`)).id);
const vulcanFtSt = (await q('ofertas_do_modelo', [vulcan, ['FT'], true, null, null, null, null]))[0];
const vendasFtSt = vendidas.filter((v) => v.modelo_id === vulcan && v.desgaste === 'FT' && v.st).length;
ok(vendasFtSt === 1 && vulcanFtSt?.base_media === 'modelo' && num(vulcanFtSt.vendas_comparaveis) === vendidas.filter((v) => v.modelo_id === vulcan).length,
  'AK-47 | Vulcan FT StatTrak: com 1 venda da versao, usa todas as vendas do modelo', `${vulcanFtSt?.vendas_comparaveis} vendas, ${vulcanFtSt?.diferenca_media_pct}%`);
ok(ofKatowice.every((o) => o.base_media === 'modelo'), 'Cápsula (fora de equipamento): media de todo o modelo');

console.log('--- ABAS DO INVENTARIO');
const abasErradas = [], foraDeOrdem = [];
for (const u of await q('listar_usuarios')) {
  // Ordem alfabetica sem pesar acentos: as Capsulas vem antes das Chaves.
  const consumiveis = (await q('inventario_usuario', [u.id, 'consumivel', null])).map((i) => i.nome);
  const primeiraChave = consumiveis.findIndex((n) => n.startsWith('Chave'));
  if (primeiraChave >= 0 && consumiveis.findLastIndex((n) => n.startsWith('Cápsula')) > primeiraChave) foraDeOrdem.push(u.apelido);
  const [r] = await q('resumo_inventario', [u.id]);
  if (num(r.prontos_para_anunciar) !== (await q('inventario_usuario', [u.id, null, true])).length) abasErradas.push(`${u.apelido} todos`);
  for (const tipo of ['equipamento', 'cosmetico', 'consumivel']) {
    if (num(r[`itens_${tipo}`]) !== (await q('inventario_usuario', [u.id, tipo, null])).length) abasErradas.push(`${u.apelido} itens_${tipo}`);
    if (num(r[`prontos_${tipo}`]) !== (await q('inventario_usuario', [u.id, tipo, true])).length) abasErradas.push(`${u.apelido} prontos_${tipo}`);
  }
}
ok(abasErradas.length === 0, 'resumo_inventario: numero de cada aba bate com a lista filtrada pelo banco (12 usuarios)', abasErradas.join(', '));
ok(foraDeOrdem.length === 0, 'inventario em ordem alfabetica sem pesar acentos (Cápsula antes de Chave)', foraDeOrdem.join(', '));

console.log('--- PERIODOS DA ANALISE');
const [indicadores] = await q('indicadores_gerais', [null, null, null]);
const rifle = num((await um(`SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'`)).id);
const [filtrado] = await q('indicadores_gerais', ['2027-01-01', '2027-12-31', rifle]);
ok(indicadores.ultima_venda === vendas.ultima && filtrado.ultima_venda === vendas.ultima && num(filtrado.vendas) === 0,
  'indicadores: ultima_venda e a venda concluida mais recente e nao depende dos filtros', indicadores.ultima_venda);
// "Ultimos 30 dias" contados ate a ultima venda (como faz a pagina) tem vendas.
const fim = new Date(`${indicadores.ultima_venda}T00:00:00Z`);
const inicio = new Date(fim.getTime() - 29 * 86400000).toISOString().slice(0, 10);
const [ultimos30] = await q('indicadores_gerais', [inicio, indicadores.ultima_venda, null]);
ok(num(ultimos30.vendas) > 0, '"Ultimos 30 dias" ate a ultima venda: periodo com vendas', `${inicio} a ${indicadores.ultima_venda}: ${ultimos30.vendas} vendas`);

console.log('--- COMPRA NOVA DEPOIS DA AMPLIACAO');
const oferta = await um(`SELECT anuncio_id, vendedor_id FROM vw_ofertas_ativas oa
  WHERE NOT EXISTS (SELECT 1 FROM venda v WHERE v.anuncio_id = oa.anuncio_id) ORDER BY anuncio_id LIMIT 1`);
const comprador = num((await um('SELECT id FROM usuario WHERE id <> $1 ORDER BY id LIMIT 1', [oferta.vendedor_id])).id);
const compra = await um('SELECT * FROM fn_comprar_anuncio($1, $2, $3)', [oferta.anuncio_id, comprador, 'pix']);
ok(/^VND-\d{4}-\d{4,}$/.test(compra.protocolo), 'a sequencia de protocolos continua sem colidir', compra.protocolo);

console.log(falhas ? `\n${falhas} teste(s) falharam` : '\nTodos os testes passaram');
await db.close?.();
process.exitCode = falhas ? 1 : 0;
