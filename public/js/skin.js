// Pagina Detalhe da skin ( /skin/:id ): dados do modelo, ofertas ativas com
// filtros, precos registrados e a janela Comprar.
import {
  iniciarPagina, api, mostrarEstado, mostrarAvisoGlobal, escaparHtml, idDoEndereco,
  formatarPreco, formatarData, formatarFloat, formatarNota, imagemDoItem,
  celula, analisePreco, nomeVersao, prepararJanela, NOMES_TIPO,
} from './comum.js';
import { graficoLinha } from './graficos.js';

const idModelo = idDoEndereco();
const formFiltros = document.getElementById('filtros-ofertas');
const tabelaOfertas = document.getElementById('tabela-ofertas');
const statusOfertas = document.getElementById('status-ofertas');
const tituloOfertas = document.getElementById('titulo-ofertas');
const janela = document.getElementById('janela-comprar');
const formComprar = document.getElementById('form-comprar');
const botaoConfirmar = document.getElementById('confirmar-compra');
const botaoCancelar = document.getElementById('cancelar-compra');
const erroCompra = document.getElementById('erro-compra');

let usuario = null;             // usuario selecionado em "Entrar como"
let modelo = null;              // dados do modelo (cabecalho)
let ofertas = [];               // ofertas mostradas na tabela
let ofertaEmCompra = null;      // oferta aberta na janela Comprar
let recarregarAoFechar = false; // compra feita ou recusada: atualiza a pagina ao fechar
let pedidoOfertas = 0;          // so a resposta mais recente das ofertas e mostrada
let pedidoTudo = 0;             // idem para modelo e historico (recarga apos compra)

configurarVoltar();
aplicarEnderecoNosFiltros();

// Os eventos sao ligados antes de carregar: a pagina responde assim que
// cada parte aparece.
formFiltros.addEventListener('input', () => {
  atualizarEndereco();
  if (modelo) carregarOfertas();
});
tabelaOfertas.addEventListener('click', (evento) => {
  const botao = evento.target.closest('[data-comprar]');
  if (botao) abrirCompra(Number(botao.dataset.comprar));
});
prepararJanela(janela, { aoEnviar: comprar, retorno: tituloOfertas });
janela.addEventListener('close', () => {
  if (!recarregarAoFechar) return;
  recarregarAoFechar = false;
  tituloOfertas.focus(); // a tabela sera redesenhada
  carregarTudo();
});

usuario = await iniciarPagina(null);
carregarTudo();

// ---------- Navegacao ----------

// Volta ao catalogo com os mesmos filtros, se veio de la.
function configurarVoltar() {
  try {
    const origem = new URL(document.referrer);
    if (origem.origin === location.origin && origem.pathname === '/') {
      document.getElementById('voltar').href = origem.pathname + origem.search;
    }
  } catch {
    // Sem pagina anterior: o link continua apontando para o catalogo.
  }
}

// ---------- Filtros da oferta (no endereco da pagina) ----------

// Aceita o que a API aceita: "?desgaste=FN&desgaste=MW" ou "?desgaste=FN,MW",
// e caixas marcadas como "1", "true" ou "on".
function aplicarEnderecoNosFiltros() {
  for (const [nome, valor] of new URLSearchParams(location.search)) {
    for (const campo of formFiltros.querySelectorAll(`[name="${CSS.escape(nome)}"]`)) {
      if (campo.type === 'checkbox') {
        const marcado = campo.value === 'on'
          ? ['1', 'true', 'on'].includes(valor)
          : valor.split(',').includes(campo.value);
        if (marcado) campo.checked = true;
      } else {
        campo.value = valor;
      }
    }
  }
}

function parametrosDosFiltros() {
  const parametros = new URLSearchParams();
  for (const [nome, valor] of new FormData(formFiltros)) {
    if (nome === 'ordenar' && valor === 'preco') continue;
    parametros.append(nome, valor);
  }
  return parametros;
}

function atualizarEndereco() {
  const parametros = parametrosDosFiltros();
  history.replaceState(null, '', parametros.size ? `?${parametros}` : location.pathname);
}

// ---------- Carregamento ----------

async function carregarTudo() {
  const pedido = ++pedidoTudo;
  const modeloCarregou = await carregarModelo(pedido);
  if (pedido !== pedidoTudo || !modelo) return;
  // Numa recarga em que o modelo falha, o historico ainda precisa terminar:
  // o pedido anterior dele foi descartado e a tabela ficaria carregando.
  await Promise.all([modeloCarregou ? carregarOfertas() : null, carregarHistorico(pedido)]);
}

async function carregarModelo(pedido) {
  let dados;
  try {
    dados = await api(`/skins/${idModelo}`);
    if (pedido !== pedidoTudo) return false;
  } catch (err) {
    if (pedido !== pedidoTudo) return false;
    if (modelo) {
      // Recarga (depois de uma compra): mantem o que ja esta na tela.
      mostrarAvisoGlobal(`Não foi possível atualizar a página: ${err.message}`);
      return false;
    }
    const naoExiste = err.status === 404 || err.status === 400;
    const titulo = naoExiste ? 'Skin não encontrada' : 'Não foi possível abrir esta skin';
    document.title = `${titulo} — VaultGabe`;
    document.getElementById('conteudo-skin').innerHTML = `
      <h1>${escaparHtml(titulo)}</h1>
      <p class="aviso aviso-erro secao">${naoExiste ? 'Confira o endereço ou procure a skin no catálogo.' : escaparHtml(err.message)}</p>`;
    return false;
  }
  modelo = dados;

  document.title = `${modelo.nome} — VaultGabe`;
  document.documentElement.style.setProperty('--cor-raridade', modelo.cor_raridade);
  document.getElementById('imagem-modelo').innerHTML = imagemDoItem(modelo);
  document.getElementById('nome-modelo').textContent = modelo.nome;
  document.getElementById('selos-modelo').innerHTML = `
    <span class="selo selo-raridade">${escaparHtml(modelo.raridade)}</span>
    <span class="selo">${escaparHtml(modelo.categoria)}</span>`;

  const info = [modelo.colecao ?? 'Sem coleção'];
  if (modelo.lancamento_colecao) info.push(`lançada em ${formatarData(modelo.lancamento_colecao).slice(-4)}`);
  if (modelo.float_min !== null) info.push(`float de ${formatarFloat(modelo.float_min, 2)} a ${formatarFloat(modelo.float_max, 2)}`);
  document.getElementById('info-modelo').textContent = info.join(' · ');
  document.getElementById('descricao-modelo').textContent = modelo.descricao ?? '';

  document.getElementById('ind-menor-preco').textContent = modelo.menor_preco === null ? 'Sem ofertas à venda' : formatarPreco(modelo.menor_preco);
  document.getElementById('ind-preco-medio').textContent = formatarPreco(modelo.preco_medio);
  document.getElementById('ind-vendas').textContent = modelo.vendas;
  document.getElementById('ind-ofertas').textContent = modelo.ofertas;

  // Desgaste, StatTrak, Souvenir e adesivos so existem em armas, facas e luvas.
  document.getElementById('filtros-equipamento').classList.toggle('oculto', modelo.tipo !== 'equipamento');
  return true;
}

async function carregarOfertas() {
  const parametros = modelo.tipo === 'equipamento' ? parametrosDosFiltros() : new URLSearchParams();
  if (usuario) parametros.set('usuario', usuario.id);

  const pedido = ++pedidoOfertas;
  tabelaOfertas.classList.add('carregando');
  tabelaOfertas.setAttribute('aria-busy', 'true');
  try {
    const lista = await api(`/skins/${idModelo}/ofertas?${parametros}`);
    if (pedido !== pedidoOfertas) return;
    ofertas = lista;
    mostrarOfertas(parametros);
    // Reservadas aparecem na tabela, mas nao contam nas ofertas do cabecalho.
    const reservadas = ofertas.filter((o) => o.reservada).length;
    statusOfertas.textContent = ofertas.length
      ? `${ofertas.length} ${ofertas.length === 1 ? 'oferta encontrada' : 'ofertas encontradas'}`
        + (reservadas ? `, ${reservadas} ${reservadas === 1 ? 'reservada' : 'reservadas'}` : '')
      : 'Nenhuma oferta encontrada';
  } catch (err) {
    if (pedido !== pedidoOfertas) return;
    mostrarEstado(tabelaOfertas, 'Não foi possível carregar as ofertas', err.message, 'erro');
  } finally {
    if (pedido === pedidoOfertas) {
      tabelaOfertas.classList.remove('carregando');
      tabelaOfertas.removeAttribute('aria-busy');
    }
  }
}

async function carregarHistorico(pedido) {
  const resumo = document.getElementById('resumo-historico');
  const tabela = document.getElementById('tabela-historico');
  try {
    const { vendas, por_mes: porMes } = await api(`/skins/${idModelo}/historico`);
    if (pedido !== pedidoTudo) return false;
    mostrarGraficoPrecos(porMes);
    if (!vendas.length) {
      resumo.textContent = '';
      mostrarEstado(tabela, 'Nenhuma venda registrada ainda', 'Quando esta skin for vendida, o preço aparece aqui.');
      return;
    }
    const valores = vendas.map((v) => Number(v.valor));
    resumo.textContent = [
      `${vendas.length} ${vendas.length === 1 ? 'venda' : 'vendas'}`,
      `menor ${formatarPreco(Math.min(...valores))}`,
      `maior ${formatarPreco(Math.max(...valores))}`,
      `última em ${formatarData(vendas[0].data_venda)}`,
    ].join(' · ');
    tabela.className = 'tabela-rolagem';
    tabela.innerHTML = tabelaHistorico(vendas);
  } catch (err) {
    if (pedido !== pedidoTudo) return false;
    resumo.textContent = '';
    mostrarEstado(tabela, 'Não foi possível carregar os preços registrados', err.message, 'erro');
  } finally {
    if (pedido === pedidoTudo) tabela.removeAttribute('aria-busy');
  }
}

// Grafico do preco ao longo do tempo: so faz sentido com 2 meses ou mais.
function mostrarGraficoPrecos(porMes) {
  const painel = document.getElementById('painel-grafico-precos');
  painel.classList.toggle('oculto', porMes.length < 2);
  if (porMes.length < 2) return;
  graficoLinha(document.getElementById('grafico-precos'), {
    descricao: `Preço médio por mês de ${modelo.nome}`,
    nomeValor: 'Preço médio',
    formatarValor: formatarPreco,
    comFaixa: true,
    pontos: porMes.map((m) => ({
      mes: m.mes,
      valor: Number(m.preco_medio),
      menor: Number(m.menor_preco),
      maior: Number(m.maior_preco),
      vendas: m.vendas,
      detalhes: [`${m.vendas} ${m.vendas === 1 ? 'venda' : 'vendas'}`],
    })),
  });
}

// ---------- Tabelas ----------

function mostrarOfertas(parametros) {
  if (!ofertas.length) {
    const comFiltro = [...parametros.keys()].some((nome) => nome !== 'usuario' && nome !== 'ordenar');
    mostrarEstado(tabelaOfertas, 'Nenhuma oferta no momento',
      comFiltro ? 'Nenhum anúncio atende a esses filtros. Tente outros.' : 'Quando alguém anunciar esta skin, a oferta aparece aqui.');
    return;
  }

  const equipamento = modelo.tipo === 'equipamento';
  const consumivel = modelo.tipo === 'consumivel';
  const cabecalho = equipamento
    ? '<th>Float</th><th>Desgaste</th><th>Detalhes</th>'
    : consumivel ? '<th>Tipo</th><th>Estado</th>' : '<th>Tipo</th>';

  tabelaOfertas.className = 'tabela-rolagem';
  tabelaOfertas.innerHTML = `
    <table class="tabela tabela-responsiva">
      <caption class="visualmente-oculto">Anúncios ativos de ${escaparHtml(modelo.nome)}</caption>
      <thead><tr>${cabecalho}<th>Vendedor</th><th class="numero">Preço</th><th><span class="visualmente-oculto">Ação</span></th></tr></thead>
      <tbody>${ofertas.map((o) => linhaOferta(o, equipamento, consumivel)).join('')}</tbody>
    </table>`;
}

function linhaOferta(o, equipamento, consumivel) {
  let colunas;
  if (equipamento) {
    const extras = [
      o.stattrak ? '<span class="selo selo-stattrak">StatTrak™</span>' : '',
      o.souvenir ? '<span class="selo selo-souvenir">Souvenir</span>' : '',
    ].join('');
    colunas = [
      celula('Float', `
        <span class="float">${formatarFloat(o.float_value, 4)}</span>
        <span class="barra-float" title="${escaparHtml(o.desgaste_nome)}"><i style="left: ${Number(o.float_value) * 100}%"></i></span>`),
      celula('Desgaste', `<span class="desgaste">${escaparHtml(o.desgaste_nome)}</span>${o.paint_seed !== null ? `<small class="texto-suave">seed ${o.paint_seed}</small>` : ''}`),
      celula('Detalhes', `
        ${extras ? `<div class="extras">${extras}</div>` : ''}
        ${o.cosmeticos_aplicados ? `<small class="texto-suave aplicados">Aplicados: ${escaparHtml(o.cosmeticos_aplicados)}</small>` : (extras ? '' : '<span class="texto-suave">—</span>')}`),
    ].join('');
  } else if (consumivel) {
    const estado = o.lacrado ? 'Lacrado' : `${o.cargas_restantes} ${o.cargas_restantes === 1 ? 'carga' : 'cargas'}`;
    colunas = celula('Tipo', escaparHtml(NOMES_TIPO[o.tipo_consumivel] ?? o.tipo_consumivel)) + celula('Estado', estado);
  } else {
    colunas = celula('Tipo', escaparHtml(NOMES_TIPO[o.tipo_cosmetico] ?? o.tipo_cosmetico));
  }

  let acao;
  if (o.e_minha) acao = '<span class="selo">Seu anúncio</span>';
  else if (o.reservada) acao = '<span class="selo selo-aviso">Reservado</span><small class="texto-suave">venda em andamento</small>';
  else acao = `<button type="button" class="botao botao-primario botao-pequeno" data-comprar="${o.anuncio_id}"${usuario ? '' : ' disabled'}>Comprar</button>`;

  return `
    <tr>
      ${colunas}
      ${celula('Vendedor', `
        <a href="/usuario/${o.vendedor_id}">${escaparHtml(o.vendedor)}</a>
        <small>${o.nota_vendedor === null ? 'Sem avaliações' : `★ ${formatarNota(o.nota_vendedor)} (${o.avaliacoes_vendedor})`}</small>
        ${o.vendedor_steam_guard === false ? '<small class="texto-aviso">Sem Steam Guard: na Steam, a entrega levaria até 15 dias</small>' : ''}`, 'vendedor')}
      ${celula('Preço', `
        <strong>${formatarPreco(o.preco)}</strong>
        ${analisePreco(o.diferenca_media_pct, o.base_media, nomeVersao(o))}
        <small class="texto-suave expira">expira em ${formatarData(o.data_expiracao)}</small>`, 'numero')}
      ${celula('', acao, 'acao')}
    </tr>`;
}

function tabelaHistorico(vendas) {
  const equipamento = modelo.tipo === 'equipamento';
  return `
    <table class="tabela tabela-responsiva">
      <caption class="visualmente-oculto">Vendas concluídas de ${escaparHtml(modelo.nome)}</caption>
      <thead><tr>
        <th>Data</th>${equipamento ? '<th>Float</th>' : ''}<th>Vendedor</th><th>Comprador</th><th>Protocolo</th><th class="numero">Preço</th>
      </tr></thead>
      <tbody>${vendas.map((v) => `
        <tr>
          ${celula('Data', formatarData(v.data_venda))}
          ${equipamento ? celula('Float', `<span class="float">${formatarFloat(v.float_value, 4)}</span> <small class="texto-suave">${escaparHtml(v.desgaste ?? '')}</small>`) : ''}
          ${celula('Vendedor', escaparHtml(v.vendedor))}
          ${celula('Comprador', escaparHtml(v.comprador))}
          ${celula('Protocolo', `<small class="texto-suave">${escaparHtml(v.protocolo)}</small>`)}
          ${celula('Preço', formatarPreco(v.valor), 'numero')}
        </tr>`).join('')}
      </tbody>
    </table>`;
}

// ---------- Janela Comprar ----------

function abrirCompra(idAnuncio) {
  ofertaEmCompra = ofertas.find((o) => o.anuncio_id === idAnuncio);
  if (!ofertaEmCompra || !usuario) return;

  const o = ofertaEmCompra;
  const detalhe = o.float_value !== null
    ? `${escaparHtml(nomeVersao(o))} · float ${formatarFloat(o.float_value, 4)}`
    : escaparHtml(NOMES_TIPO[o.tipo_cosmetico ?? o.tipo_consumivel] ?? '');
  document.getElementById('resumo-compra').innerHTML = `
    <div class="card-imagem">${imagemDoItem(modelo)}</div>
    <div>
      <strong>${escaparHtml(modelo.nome)}</strong><br>
      <small class="texto-suave">${detalhe}</small><br>
      <small class="texto-suave">Vendedor: ${escaparHtml(o.vendedor)} · ${o.nota_vendedor === null ? 'sem avaliações' : `★ ${formatarNota(o.nota_vendedor)} (${o.avaliacoes_vendedor})`}</small>
      ${o.vendedor_steam_guard === false ? '<br><small class="texto-aviso">Sem Steam Guard: na Steam, a entrega levaria até 15 dias</small>' : ''}
      <div class="preco">${formatarPreco(o.preco)}</div>
    </div>`;

  const pix = formComprar.querySelector('input[name="metodo"][value="pix"]');
  pix.checked = true;
  alternarEtapa(false);
  erroCompra.classList.add('oculto');
  botaoConfirmar.disabled = false;
  botaoConfirmar.textContent = 'Confirmar compra';
  janela.showModal();
  pix.focus();
}

// Chamada por prepararJanela (Enter ou "Confirmar compra"). Devolve onde o
// foco deve ficar.
async function comprar() {
  if (botaoConfirmar.disabled || !ofertaEmCompra) return null;
  botaoConfirmar.disabled = true;
  botaoConfirmar.textContent = 'Comprando…';
  erroCompra.classList.add('oculto');

  try {
    const metodo = new FormData(formComprar).get('metodo');
    const compra = await api('/compras', {
      method: 'POST',
      body: { anuncio_id: ofertaEmCompra.anuncio_id, comprador_id: usuario.id, metodo },
    });
    document.getElementById('protocolo-compra').textContent = compra.protocolo;
    document.getElementById('chave-compra').textContent = compra.chave_nota_fiscal.replace(/(\d{4})(?=\d)/g, '$1 ');
    recarregarAoFechar = true;
    alternarEtapa(true);
    return document.getElementById('compra-concluida');
  } catch (err) {
    erroCompra.textContent = err.message;
    erroCompra.classList.remove('oculto');
    // Falha de conexao ou do servidor: vale tentar de novo. Regra de negocio
    // (ex.: anuncio ja vendido): repetir daria o mesmo erro, e a pagina e
    // atualizada ao fechar a janela.
    const tentarDeNovo = !err.status || err.status >= 500;
    botaoConfirmar.disabled = !tentarDeNovo;
    botaoConfirmar.textContent = tentarDeNovo ? 'Tentar de novo' : 'Confirmar compra';
    if (!tentarDeNovo) recarregarAoFechar = true;
    return tentarDeNovo ? botaoConfirmar : botaoCancelar;
  }
}

// false: confirmar a compra; true: compra concluida.
function alternarEtapa(concluida) {
  document.getElementById('etapa-confirmar').classList.toggle('oculto', concluida);
  document.getElementById('acoes-confirmar').classList.toggle('oculto', concluida);
  document.getElementById('etapa-concluida').classList.toggle('oculto', !concluida);
  document.getElementById('acoes-concluida').classList.toggle('oculto', !concluida);
}
