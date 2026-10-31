// Testes da API e do tratamento de erros. Sobe a aplicacao numa porta livre,
// ligada ao banco de DATABASE_URL (branch development do Neon), e faz
// requisicoes reais. So roda com "npm run test:neon".
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { abrir } from './banco.mjs';
import { criarApp } from '../src/app.js';
import { consultar } from '../src/banco.js';
import { tratarErros } from '../src/erros.js';

// A API usa um PostgreSQL de verdade: estes testes sempre usam o Neon, e a
// trava de abrir() recusa a producao antes de qualquer coisa.
process.env.TESTE_NEON = '1';

// Comeca com os dados de demonstracao, como os outros testes.
const dbInicial = await abrir();
for (const arquivo of ['01_tabelas.sql', '02_regras.sql', '03_dados.sql']) {
  await dbInicial.exec(fs.readFileSync(new URL(`../database/${arquivo}`, import.meta.url), 'utf8'));
}
await dbInicial.close();

let falhas = 0;
const ok = (cond, nome, extra = '') => {
  if (!cond) falhas++;
  console.log(`${cond ? 'OK    ' : 'FALHOU'} ${nome}${extra !== '' ? '  -> ' + extra : ''}`);
};

const servidor = criarApp().listen(0);
await new Promise((resolver) => servidor.once('listening', resolver));
const base = `http://127.0.0.1:${servidor.address().port}`;
const pedir = async (caminho) => {
  const r = await fetch(base + caminho);
  const tipo = r.headers.get('content-type') ?? '';
  return { status: r.status, tipo, corpo: tipo.includes('json') ? await r.json() : await r.text(), cache: r.headers.get('cache-control') };
};

console.log('--- ROTAS');
let r = await pedir('/api/saude');
ok(r.status === 200 && r.corpo.banco.conectado && r.corpo.banco.fuso === 'America/Sao_Paulo' && r.corpo.consultas === 34,
  '/api/saude: banco conectado, fuso de Sao Paulo, 34 consultas', `${r.corpo.banco?.versao} em ${r.corpo.banco?.latencia_ms} ms`);
ok(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(r.corpo.banco.agora), 'datas chegam como texto, sem conversao de fuso', r.corpo.banco.agora);
r = await pedir('/api/usuarios');
ok(r.status === 200 && r.corpo.length === 12 && r.corpo.some((u) => u.apelido === 'isizinha') && r.cache === 'no-store',
  '/api/usuarios: 12 usuarios, sem cache');
r = await pedir('/api/nao-existe');
ok(r.status === 404 && r.corpo.erro, 'rota inexistente da API: 404 em JSON', r.corpo.erro);
r = await pedir('/skin/abc');
ok(r.status === 404 && r.tipo.includes('html'), 'pagina com id invalido: 404 em HTML');
const cabecalhos = (await fetch(`${base}/`)).headers;
ok(/script-src 'self'/.test(cabecalhos.get('content-security-policy') ?? '') && cabecalhos.get('x-content-type-options') === 'nosniff',
  'cabecalhos de seguranca: politica de conteudo e nosniff');
r = await pedir('/usuario/9');
ok(r.status === 200 && r.tipo.includes('html'), 'pagina de perfil: 200');

console.log('--- CATALOGO');
r = await pedir('/api/catalogo/filtros');
ok(r.status === 200 && r.corpo.categorias.length === 13 && r.corpo.raridades.length === 9 && r.corpo.colecoes.length === 12,
  '/api/catalogo/filtros: 13 categorias, 9 raridades, 12 colecoes');
const nomes = (lista) => lista.map((i) => i.nome).join(' / ');
const casos = [
  ['', 21, 'sem filtros: 21 modelos, menor preco primeiro', (l) => l[0].nome === 'P90 | Sand Spray'],
  ['?so_a_venda=1', 5, 'so a venda: 5 (a capsula reservada nao conta)', (l) => !l.some((m) => m.nome === 'Capsula Ambush')],
  ['?desgaste=FN', 2, 'desgaste FN: 2'],
  ['?desgaste=FN,MW', 3, 'desgaste FN e MW (separados por virgula): 3'],
  ['?desgaste=FN&desgaste=MW&com_adesivos=on', 1, 'FN ou MW com adesivos: so a M4A4', (l) => l[0].nome === 'M4A4 | Howl'],
  ['?busca=gloves', 3, 'busca "gloves": 3 luvas'],
  ['?preco_max=1000', 1, 'preco ate R$ 1000: so a P90', (l) => l[0].nome === 'P90 | Sand Spray'],
  ['?preco_max=1000,50', 1, 'preco com virgula decimal: aceito'],
  ['?ordenar=maior_preco', 21, 'ordenar por maior preco: M4A4 primeiro', (l) => l[0].nome === 'M4A4 | Howl'],
];
for (const [consulta, esperado, nome, extra = () => true] of casos) {
  r = await pedir(`/api/catalogo${consulta}`);
  ok(r.status === 200 && r.corpo.length === esperado && extra(r.corpo), nome, r.status === 200 ? `${r.corpo.length}: ${nomes(r.corpo).slice(0, 70)}` : r.corpo.erro);
}
for (const consulta of ['?ordenar=xyz', '?categoria=abc', '?desgaste=XX', '?preco_min=-1']) {
  r = await pedir(`/api/catalogo${consulta}`);
  ok(r.status === 400 && /inválido/.test(r.corpo.erro), `parametro invalido ${consulta}: 400`, r.corpo.erro);
}

console.log('--- TRADUCAO DOS ERROS DO BANCO');
// Gera erros reais do banco (nada e gravado: cada operacao falha e e desfeita)
// e confere a resposta que o usuario receberia.
const respostaPara = async (nome, params) => {
  try {
    await consultar(nome, params);
    return { status: 200 };
  } catch (err) {
    const res = { status: 0, corpo: null, headersSent: false, statusFn: null };
    res.status = (s) => { res.codigo = s; return res; };
    res.json = (c) => { res.corpo = c; return res; };
    tratarErros(err, {}, res, () => {});
    return { status: res.codigo, erro: res.corpo?.erro };
  }
};
const id = async (sql) => Object.values((await (async () => {
  const db = await abrir(); const x = await db.query(sql); await db.close(); return x;
})()).rows[0])[0];

let e = await respostaPara('comprar_anuncio', [999999, 1, 'pix']);
ok(e.status === 422 && e.erro === 'Anúncio não encontrado.', 'regra de negocio (trigger/funcao): 422 com mensagem para o usuario', e.erro);
const awp = await id(`SELECT id FROM item_instancia WHERE numero_inspecao = 'INS-EQ-0004'`);
const diego = await id(`SELECT id FROM usuario WHERE apelido = 'dfontes'`);
e = await respostaPara('publicar_anuncio', [awp, diego, 900, 7]);
ok(e.status === 409 && e.erro === 'Este item já tem um anúncio aberto.', 'segundo anuncio aberto do mesmo item: 409', e.erro);
const venda = await id(`SELECT id FROM venda WHERE protocolo_venda = 'VND-2026-0004'`);
const lari = await id(`SELECT id FROM usuario WHERE apelido = 'lari'`);
e = await respostaPara('avaliar_vendedor', [venda, lari, 7, '']);
ok(e.status === 400 && e.erro === 'A nota precisa ser de 1 a 5.', 'nota fora de 1 a 5: 400', e.erro);
e = await respostaPara('publicar_anuncio', [awp, diego, -5, 7]);
ok(e.status === 400 || e.status === 409, 'preco negativo: recusado', `${e.status} ${e.erro}`);

console.log('--- DETALHE DA SKIN');
const usuarios = (await pedir('/api/usuarios')).corpo;
const idDe = (apelido) => usuarios.find((u) => u.apelido === apelido).id;
const modeloDe = async (busca) => (await pedir(`/api/catalogo?busca=${encodeURIComponent(busca)}`)).corpo[0].id;
const m4 = await modeloDe('howl');
r = await pedir(`/api/skins/${m4}`);
ok(r.status === 200 && r.corpo.nome === 'M4A4 | Howl' && r.corpo.tipo === 'equipamento' && Number(r.corpo.menor_preco) === 10500 && r.corpo.vendas === 1,
  'detalhe da M4A4: tipo, menor preco e vendas');
r = await pedir('/api/skins/999999');
ok(r.status === 404 && r.corpo.erro === 'Skin não encontrada.', 'skin inexistente: 404', r.corpo.erro);
r = await pedir('/api/skins/abc');
ok(r.status === 400, 'id nao numerico: 400', r.corpo.erro);
r = await pedir(`/api/skins/${m4}/ofertas?usuario=${idDe('isizinha')}`);
ok(r.status === 200 && r.corpo.length === 1 && r.corpo[0].e_minha === false && r.corpo[0].reservada === false, 'ofertas da M4A4 vistas pela isizinha: 1, nao e dela');
const ofertaM4Isa = r.corpo[0] ?? {};
ok(ofertaM4Isa.base_media === 'modelo' && ofertaM4Isa.vendas_comparaveis === 1 && Number(ofertaM4Isa.preco_medio_comparavel) === 9800
  && Number(ofertaM4Isa.diferenca_media_pct) === 7.1, 'analise de preco da oferta: sem 2 vendas da versao, media do modelo (+7,1%)',
  `${ofertaM4Isa.base_media}, ${ofertaM4Isa.vendas_comparaveis} venda, ${ofertaM4Isa.diferenca_media_pct}%`);
r = await pedir(`/api/skins/${m4}/ofertas?usuario=${idDe('lari')}`);
ok(r.corpo[0]?.e_minha === true, 'ofertas da M4A4 vistas pela lari: marcada como dela');
r = await pedir(`/api/skins/${m4}/ofertas?desgaste=FN`);
ok(r.status === 200 && r.corpo.length === 0, 'ofertas da M4A4 so FN: nenhuma');
r = await pedir(`/api/skins/${m4}/ofertas?ordenar=xyz`);
ok(r.status === 400, 'ordenar invalido nas ofertas: 400', r.corpo.erro);
r = await pedir(`/api/skins/${m4}/historico`);
ok(r.status === 200 && r.corpo.vendas.length === 1 && r.corpo.por_mes.length === 1, 'historico da M4A4: 1 venda, 1 mes');
const capsula = await modeloDe('Ambush');
const ofertaCapsula = (await pedir(`/api/skins/${capsula}/ofertas`)).corpo[0];
ok(ofertaCapsula?.reservada === true, 'oferta com venda pendente aparece como reservada');
r = await pedir(`/api/skins/${capsula}`);
ok(r.status === 200 && r.corpo.menor_preco === null && r.corpo.ofertas === 0, 'detalhe da capsula: a oferta reservada fica fora do menor preco e das ofertas a venda',
  `${r.corpo.menor_preco} / ${r.corpo.ofertas}`);
const cardCapsula = (await pedir('/api/catalogo?busca=Ambush')).corpo[0];
ok(cardCapsula?.menor_preco === null && cardCapsula.ofertas === 0, 'card da capsula no catalogo: sem preco e com 0 ofertas');

console.log('--- COMPRA');
const enviar = async (corpo) => {
  const resposta = await fetch(`${base}/api/compras`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo),
  });
  return { status: resposta.status, corpo: await resposta.json() };
};
const modeloAwp = await modeloDe('asiimov');
const ofertaAwp = (await pedir(`/api/skins/${modeloAwp}/ofertas`)).corpo[0].anuncio_id;
let c = await enviar({ anuncio_id: ofertaAwp, comprador_id: idDe('isizinha'), metodo: 'pix' });
ok(c.status === 201 && /^VND-\d{4}-0013$/.test(c.corpo.protocolo) && /^\d{44}$/.test(c.corpo.chave_nota_fiscal),
  'compra da AWP pela isizinha: 201, protocolo e chave da nota', c.corpo.protocolo);
const protocoloAwp = c.corpo.protocolo;
r = await pedir(`/api/skins/${modeloAwp}`);
ok(r.corpo.ofertas === 0 && r.corpo.vendas === 2, 'depois da compra: AWP sem ofertas e com 2 vendas');
c = await enviar({ anuncio_id: ofertaAwp, comprador_id: idDe('dfontes'), metodo: 'pix' });
ok(c.status === 422 && c.corpo.erro === 'Este anúncio não está mais à venda.', 'comprar de novo: 422 com mensagem clara', c.corpo.erro);
const ofertaM4 = (await pedir(`/api/skins/${m4}/ofertas`)).corpo[0].anuncio_id;
c = await enviar({ anuncio_id: ofertaM4, comprador_id: idDe('lari'), metodo: 'pix' });
ok(c.status === 422 && c.corpo.erro === 'Você não pode comprar o seu próprio anúncio.', 'comprar o proprio anuncio: 422', c.corpo.erro);
c = await enviar({ anuncio_id: ofertaCapsula.anuncio_id, comprador_id: idDe('isizinha'), metodo: 'pix' });
ok(c.status === 422 && c.corpo.erro === 'Este anúncio já tem uma venda em andamento.', 'comprar oferta reservada: 422', c.corpo.erro);
c = await enviar({ anuncio_id: ofertaM4, comprador_id: idDe('isizinha'), metodo: 'cheque' });
ok(c.status === 400, 'forma de pagamento invalida: 400', c.corpo.erro);
c = await enviar({ anuncio_id: ofertaM4, comprador_id: idDe('isizinha') });
ok(c.status === 400 && c.corpo.erro === 'Escolha a forma de pagamento.', 'sem forma de pagamento: 400', c.corpo.erro);
c = await enviar({ anuncio_id: 'abc', comprador_id: idDe('isizinha'), metodo: 'pix' });
ok(c.status === 400, 'anuncio nao numerico: 400', c.corpo.erro);
c = await enviar({ anuncio_id: ofertaM4, comprador_id: 999999, metodo: 'pix' });
ok(c.status === 400, 'comprador inexistente: 400', c.corpo.erro);
const corpoQuebrado = await fetch(`${base}/api/compras`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{"anuncio_id": 1,',
});
ok(corpoQuebrado.status === 400 && /JSON/.test((await corpoQuebrado.json()).erro), 'corpo que nao e JSON valido: 400, nao 500');
r = await pedir(`/api/skins/${m4}`);
ok(r.corpo.ofertas === 1 && r.corpo.vendas === 1, 'compras recusadas nao mudam nada (M4A4 continua a venda)');

const postar = async (caminho, corpo) => {
  const resposta = await fetch(base + caminho, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo),
  });
  return { status: resposta.status, corpo: await resposta.json() };
};
const isizinha = idDe('isizinha');

console.log('--- INVENTARIO');
r = await pedir(`/api/inventario?usuario=${isizinha}`);
const inv = r.corpo;
ok(r.status === 200 && inv.resumo.itens === inv.itens.length && inv.resumo.prontos_para_anunciar === inv.itens.filter((i) => i.pode_anunciar).length,
  'inventario da isizinha: resumo bate com a lista', JSON.stringify(inv.resumo));
const ak = inv.itens.find((i) => i.numero_inspecao === 'INS-EQ-0001');
ok(ak?.situacao === 'disponivel' && ak.pode_anunciar && ak.desgaste === 'FT', 'AK-47 da isizinha disponivel para anunciar, com desgaste calculado');
r = await pedir(`/api/inventario?usuario=${isizinha}&tipo=cosmetico&negociaveis=1`);
ok(r.status === 200 && r.corpo.itens.every((i) => i.tipo === 'cosmetico' && i.pode_anunciar), 'filtro por tipo e so negociaveis');
// Os filtros valem so para a lista: o resumo traz o numero de cada aba, com e sem o filtro.
ok(r.corpo.itens.length === inv.resumo.prontos_cosmetico && JSON.stringify(r.corpo.resumo) === JSON.stringify(inv.resumo),
  'filtro nao muda o resumo; a lista tem prontos_cosmetico itens', `${r.corpo.itens.length} / ${inv.resumo.prontos_cosmetico}`);
for (const tipo of ['equipamento', 'cosmetico', 'consumivel']) {
  r = await pedir(`/api/inventario?usuario=${isizinha}&tipo=${tipo}`);
  ok(r.status === 200 && r.corpo.itens.length === inv.resumo[`itens_${tipo}`] && r.corpo.itens.every((i) => i.tipo === tipo),
    `aba ${tipo}: a lista tem o numero do resumo (itens_${tipo})`, `${r.corpo.itens?.length} / ${inv.resumo[`itens_${tipo}`]}`);
}
r = await pedir(`/api/inventario?usuario=${isizinha}&negociaveis=1`);
ok(r.status === 200 && r.corpo.itens.length === inv.resumo.prontos_para_anunciar && r.corpo.itens.every((i) => i.pode_anunciar),
  'so os que posso anunciar (aba Todos): a lista tem prontos_para_anunciar itens');
for (const consulta of ['', '?usuario=abc', `?usuario=${isizinha}&tipo=arma`]) {
  r = await pedir(`/api/inventario${consulta}`);
  ok(r.status === 400, `inventario com parametro faltando/invalido "${consulta}": 400`, r.corpo.erro);
}

console.log('--- NOVO ANUNCIO E CANCELAMENTO');
r = await pedir(`/api/anuncios/analise-preco?item=${ak.item_id}&preco=900`);
ok(r.status === 200 && r.corpo.nome === 'AK-47 | Redline' && Number(r.corpo.preco_medio_vendas) === 850 && Number(r.corpo.diferenca_media_pct) === 5.9,
  'analise de preco: media das vendas e diferenca do preco digitado', `${r.corpo.diferenca_media_pct}%`);
ok(r.corpo.base_media === 'modelo' && r.corpo.vendas === 1, 'analise de preco: sem 2 vendas da versao, usa a media do modelo', `${r.corpo.base_media}, ${r.corpo.vendas} venda`);
const capsulaPepaa = (await pedir(`/api/inventario?usuario=${idDe('pepaa')}`)).corpo.itens.find((i) => i.numero_inspecao === 'INS-CN-0006');
r = await pedir(`/api/anuncios/analise-preco?item=${capsulaPepaa?.item_id}&preco=600`);
ok(r.status === 200 && r.corpo.menor_preco_atual === null && r.corpo.ofertas_atuais === 0, 'analise de preco da capsula: a oferta reservada nao conta como oferta atual',
  `${r.corpo.menor_preco_atual} / ${r.corpo.ofertas_atuais}`);
r = await pedir('/api/anuncios/analise-preco?item=999999');
ok(r.status === 404, 'analise de preco de item inexistente: 404', r.corpo.erro);
const novoAnuncio = { item_id: ak.item_id, usuario_id: isizinha, preco: '900,50', dias: 7 };
c = await postar('/api/anuncios', novoAnuncio);
ok(c.status === 201 && c.corpo.anuncio_id > 0 && c.corpo.data_expiracao > c.corpo.data_publicacao, 'publicar anuncio: 201', c.corpo.data_expiracao);
const idNovoAnuncio = c.corpo.anuncio_id;
r = await pedir(`/api/skins/${ak.modelo_id}/ofertas?usuario=${isizinha}`);
const oferta = r.corpo.find((o) => o.anuncio_id === idNovoAnuncio);
ok(oferta?.e_minha === true && Number(oferta.preco) === 900.5, 'o anuncio aparece nas ofertas da skin, marcado como da isizinha');
c = await postar('/api/anuncios', novoAnuncio);
ok(c.status === 409 && c.corpo.erro === 'Este item já tem um anúncio aberto.', 'segundo anuncio do mesmo item: 409', c.corpo.erro);
const itemDeOutro = (await pedir(`/api/inventario?usuario=${idDe('dfontes')}`)).corpo.itens.find((i) => i.pode_anunciar);
c = await postar('/api/anuncios', { item_id: itemDeOutro.item_id, usuario_id: isizinha, preco: 50, dias: 7 });
ok(c.status === 422 && c.corpo.erro === 'Você não é dono deste item.', 'anunciar item de outra pessoa: 422', c.corpo.erro);
const outroItem = inv.itens.find((i) => i.pode_anunciar && i.item_id !== ak.item_id);
for (const [corpo, esperado, nome] of [
  [{ preco: 0, dias: 7 }, 'O preço precisa ser maior que zero.', 'preco zero'],
  [{ preco: 'abc', dias: 7 }, 'O preço precisa ser um número.', 'preco que nao e numero'],
  [{ preco: 10.123, dias: 7 }, 'Use no máximo 2 casas decimais no preço.', 'preco com 3 casas'],
  [{ preco: 10, dias: 10 }, 'Parâmetro inválido: validade.', 'validade fora de 7/14/30'],
  [{ preco: 10 }, 'Escolha a validade: 7, 14 ou 30 dias.', 'sem validade'],
]) {
  c = await postar('/api/anuncios', { item_id: outroItem.item_id, usuario_id: isizinha, ...corpo });
  ok(c.status === 400 && c.corpo.erro === esperado, `anuncio com ${nome}: 400`, c.corpo.erro);
}
c = await postar(`/api/anuncios/${idNovoAnuncio}/cancelar`, { usuario_id: idDe('lari') });
ok(c.status === 409, 'cancelar anuncio de outra pessoa: 409', c.corpo.erro);
c = await postar(`/api/anuncios/${idNovoAnuncio}/cancelar`, { usuario_id: isizinha });
ok(c.status === 200 && c.corpo.anuncio_id === idNovoAnuncio, 'cancelar o proprio anuncio: 200');
c = await postar(`/api/anuncios/${idNovoAnuncio}/cancelar`, { usuario_id: isizinha });
ok(c.status === 409, 'cancelar de novo: 409', c.corpo.erro);
c = await postar(`/api/anuncios/${ofertaCapsula.anuncio_id}/cancelar`, { usuario_id: ofertaCapsula.vendedor_id });
ok(c.status === 422 && /venda pendente/.test(c.corpo.erro), 'cancelar anuncio com venda pendente: 422', c.corpo.erro);
r = await pedir(`/api/inventario?usuario=${isizinha}`);
ok(r.corpo.itens.find((i) => i.item_id === ak.item_id)?.pode_anunciar === true, 'depois de cancelar, o item volta a poder ser anunciado');

console.log('--- NEGOCIACOES E AVALIACAO');
r = await pedir(`/api/negociacoes?usuario=${isizinha}`);
const neg = r.corpo;
ok(r.status === 200 && ['a_venda', 'vendidos', 'comprados', 'encerrados'].every((aba) => neg.contagens[aba] === neg[aba].length),
  'negociacoes: o numero de cada aba bate com a lista', JSON.stringify(neg.contagens));
ok(neg.encerrados.some((a) => a.anuncio_id === idNovoAnuncio && a.status_anuncio === 'cancelado' && a.desgaste === ak.desgaste),
  'anuncio cancelado aparece em Encerrados, com o desgaste da AK');
const compraAwp = neg.comprados.find((v) => v.protocolo === protocoloAwp);
ok(compraAwp?.pode_avaliar === true && compraAwp.metodo_pagamento === 'pix' && compraAwp.desgaste === 'BS',
  'compra da AWP aparece em Comprados, pronta para avaliar e com o desgaste (BS)', compraAwp?.desgaste);
c = await postar('/api/avaliacoes', { venda_id: compraAwp.venda_id, autor_id: isizinha, nota: 6 });
ok(c.status === 400 && c.corpo.erro === 'Escolha uma nota de 1 a 5.', 'nota 6: 400', c.corpo.erro);
c = await postar('/api/avaliacoes', { venda_id: compraAwp.venda_id, autor_id: idDe('lari'), nota: 3 });
ok(c.status === 422 && c.corpo.erro === 'Só quem participou da venda pode avaliá-la.', 'quem nao participou: 422', c.corpo.erro);
c = await postar('/api/avaliacoes', { venda_id: 999999, autor_id: isizinha, nota: 3 });
ok(c.status === 422 && c.corpo.erro === 'Compra não encontrada.', 'compra inexistente: 422', c.corpo.erro);
c = await postar('/api/avaliacoes', { venda_id: compraAwp.venda_id, autor_id: isizinha, nota: 5, comentario: '  Tudo certo.  ' });
ok(c.status === 201 && /^TKT-\d{4}-\d{4,}$/.test(c.corpo.ticket), 'avaliar o vendedor: 201 com ticket', c.corpo.ticket);
c = await postar('/api/avaliacoes', { venda_id: compraAwp.venda_id, autor_id: isizinha, nota: 4 });
ok(c.status === 422 && c.corpo.erro === 'Você já avaliou esta compra.', 'avaliar de novo: 422', c.corpo.erro);
r = await pedir(`/api/negociacoes?usuario=${isizinha}`);
ok(r.corpo.comprados.find((v) => v.venda_id === compraAwp.venda_id)?.ja_avaliou === true, 'a compra passa a aparecer como avaliada');
// Dois envios ao mesmo tempo (ex.: duplo clique em duas abas): so um grava.
const outraCompra = r.corpo.comprados.find((v) => v.pode_avaliar);
const simultaneos = await Promise.all([1, 2].map(() =>
  postar('/api/avaliacoes', { venda_id: outraCompra.venda_id, autor_id: isizinha, nota: 4 })));
ok(simultaneos.map((x) => x.status).sort().join() === '201,422', 'duas avaliacoes simultaneas da mesma compra: so uma e gravada',
  simultaneos.map((x) => x.status).join(' e '));

console.log('--- PERFIL');
r = await pedir(`/api/usuarios/${compraAwp.vendedor_id}`);
ok(r.status === 200 && r.corpo.usuario.apelido === compraAwp.vendedor && r.corpo.avaliacoes.some((a) => a.comentario === 'Tudo certo.' && a.origem === 'venda'),
  'perfil do vendedor mostra a avaliacao nova (comentario sem espacos sobrando)');
ok(!('email' in r.corpo.usuario), 'perfil publico nao expoe o e-mail');
r = await pedir('/api/usuarios/999999');
ok(r.status === 404 && r.corpo.erro === 'Usuário não encontrado.', 'usuario inexistente: 404');
r = await pedir('/api/usuarios/abc');
ok(r.status === 400, 'id de usuario invalido: 400');

console.log('--- ANALISE');
r = await pedir('/api/analise');
const an = r.corpo;
const soma = (lista, campo) => lista.reduce((t, x) => t + Number(x[campo]), 0);
ok(r.status === 200 && an.indicadores.vendas === soma(an.vendas_por_mes, 'vendas') && Math.abs(Number(an.indicadores.volume) - soma(an.por_categoria, 'volume')) < 0.01,
  'analise: vendas e volume batem entre indicadores, meses e categorias', `${an.indicadores.vendas} vendas, R$ ${an.indicadores.volume}`);
// A compra da AWP feita acima e a venda concluida mais recente.
ok(an.indicadores.ultima_venda === compraAwp?.data_venda?.slice(0, 10), 'analise: ultima_venda (AAAA-MM-DD) e a data da compra mais recente', an.indicadores.ultima_venda);
const faca = (await pedir('/api/catalogo/filtros')).corpo.categorias.find((x) => x.nome === 'Faca');
r = await pedir(`/api/analise?categoria=${faca.id}&inicio=2026-01-01&fim=2026-12-31`);
ok(r.status === 200 && r.corpo.por_categoria.every((x) => x.categoria === 'Faca'), 'analise filtrada por categoria e periodo');
ok(r.corpo.indicadores.ultima_venda === an.indicadores.ultima_venda, 'ultima_venda nao depende dos filtros', r.corpo.indicadores.ultima_venda);
for (const consulta of ['?inicio=2026-02-30', '?inicio=2026-05-01&fim=2026-01-01', '?categoria=abc', '?fim=31/12/2026', '?inicio=0000-01-01']) {
  r = await pedir(`/api/analise${consulta}`);
  ok(r.status === 400, `analise com filtro invalido ${consulta}: 400`, r.corpo.erro);
}

servidor.close();

console.log('--- BANCO FORA DO AR E SEM CONFIGURACAO');
// Sobe a aplicacao em outro processo, com um banco inexistente ou sem
// DATABASE_URL, e confere que ela responde 503 sem cair.
const testarSemBanco = (databaseUrl) => {
  const codigo = `
    import { criarApp } from './src/app.js';
    const s = criarApp().listen(0, async () => {
      const base = 'http://127.0.0.1:' + s.address().port;
      const a = await fetch(base + '/api/usuarios'); const b = await fetch(base + '/api/saude');
      const p = await fetch(base + '/');
      console.log(JSON.stringify({ usuarios: a.status, erro: (await a.json()).erro, saude: b.status, pagina: p.status }));
      s.close(); process.exit(0);
    });`;
  const env = { ...process.env };
  if (databaseUrl) env.DATABASE_URL = databaseUrl; else delete env.DATABASE_URL;
  const r = spawnSync(process.execPath, ['--input-type=module', '-e', codigo], {
    cwd: new URL('..', import.meta.url), env, encoding: 'utf8', timeout: 60_000,
  });
  try { return JSON.parse(r.stdout.trim().split('\n').pop()); } catch { return { saida: r.stdout + r.stderr }; }
};
let s = testarSemBanco('postgresql://ninguem:senha@127.0.0.1:1/nada?sslmode=disable');
ok(s.usuarios === 503 && s.saude === 503 && s.pagina === 200, 'banco fora do ar: API responde 503 e o site continua no ar', s.erro);
s = testarSemBanco(null);
ok(s.usuarios === 503 && /não configurado/.test(s.erro ?? ''), 'sem DATABASE_URL: 503 explicando o que falta', s.erro);

console.log(falhas ? `\n${falhas} teste(s) falharam` : '\nTodos os testes passaram');
process.exit(falhas ? 1 : 0);
