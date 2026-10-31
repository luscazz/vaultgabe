// Pagina Analise de mercado ( /analise ): indicadores, graficos e rankings
// das vendas concluidas, filtrados por periodo e categoria. Os filtros ficam
// no endereco (?inicio=2026-01-01&fim=2026-06-30&categoria=2).
import {
  iniciarPagina, api, mostrarEstado, escaparHtml, celula,
  formatarPreco, formatarData, formatarNota,
} from './comum.js';
import { graficoColunas, graficoLinha, graficoBarras, nomeDoMes } from './graficos.js';

const form = document.getElementById('filtros-analise');
const conteudo = document.getElementById('conteudo-analise');
const seletorCategoria = document.getElementById('filtro-categoria-analise');
const botoesPeriodo = [...document.querySelectorAll('.periodos [data-dias]')];
const AMOSTRA_PEQUENA = 30; // vendas

let pedidoAtual = 0; // so a resposta mais recente e mostrada
let dataUltimaVenda = null; // AAAA-MM-DD, vem da API (indicadores.ultima_venda)
// Periodo pronto escolhido e as datas usadas nele. Se o clique vier antes de
// a API informar a ultima venda, o periodo e refeito quando ela chegar.
let periodoEscolhido = null;
let carregouUmaVez = false; // ja ha numeros na tela (o erro pode falar do filtro anterior)

iniciarPagina('analise');
await montarCategorias();
aplicarEndereco();
carregar();

form.addEventListener('submit', (evento) => {
  evento.preventDefault();
  periodoEscolhido = null;
  carregar();
});
for (const botao of botoesPeriodo) {
  botao.addEventListener('click', () => {
    aplicarPeriodo(Number(botao.dataset.dias));
    carregar();
  });
}
seletorCategoria.addEventListener('change', carregar);

// ---------- Filtros ----------

async function montarCategorias() {
  try {
    const { categorias } = await api('/catalogo/filtros');
    seletorCategoria.insertAdjacentHTML('beforeend', categorias.map((c) =>
      `<option value="${c.id}">${escaparHtml(c.nome)}</option>`).join(''));
  } catch {
    // Sem a lista, o filtro fica so com "Todas"; o resto da pagina avisa o erro.
  }
}

function aplicarEndereco() {
  const parametros = new URLSearchParams(location.search);
  for (const nome of ['inicio', 'fim', 'categoria']) {
    if (parametros.has(nome)) form[nome].value = parametros.get(nome);
  }
}

// Data de hoje no fuso do navegador, no formato AAAA-MM-DD.
function hoje() {
  const d = new Date();
  return new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 10);
}

// '2026-10-21' + (-29) -> '2026-09-22' (em UTC: horario de verao nao interfere).
function somarDias(data, dias) {
  const d = new Date(`${data}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

// Fim dos periodos prontos: hoje, ou a ultima venda quando ela e anterior
// (os dados de demonstracao tem datas fixas; contar a partir de hoje
// deixaria "Ultimos 30 dias" vazio semanas depois).
function fimDosPeriodos() {
  const atual = hoje();
  return dataUltimaVenda && dataUltimaVenda < atual ? dataUltimaVenda : atual;
}

// dias = 0: "Todo o periodo" (sem datas).
function periodoPronto(dias) {
  if (!dias) return { inicio: '', fim: '' };
  const fim = fimDosPeriodos();
  return { inicio: somarDias(fim, -(dias - 1)), fim };
}

function aplicarPeriodo(dias) {
  const periodo = periodoPronto(dias);
  form.inicio.value = periodo.inicio;
  form.fim.value = periodo.fim;
  periodoEscolhido = dias ? { dias, ...periodo } : null;
}

// O fim dos periodos mudou depois do clique: refaz o periodo, se o
// formulario ainda estiver com as datas daquele clique.
function periodoDesatualizado() {
  const e = periodoEscolhido;
  return Boolean(e && form.inicio.value === e.inicio && form.fim.value === e.fim
    && e.fim !== fimDosPeriodos());
}

function mostrarFimDosPeriodos() {
  const nota = document.getElementById('nota-periodos');
  const fim = fimDosPeriodos();
  const antesDeHoje = fim !== hoje();
  nota.textContent = antesDeHoje ? `Períodos contados até a última venda registrada (${formatarData(fim)}).` : '';
  nota.classList.toggle('oculto', !antesDeHoje);
}

function parametrosDoFormulario() {
  const parametros = new URLSearchParams();
  for (const nome of ['inicio', 'fim', 'categoria']) {
    if (form[nome].value) parametros.set(nome, form[nome].value);
  }
  return parametros;
}

// Marca o periodo pronto que corresponde as datas escolhidas (se houver).
function marcarPeriodo() {
  for (const botao of botoesPeriodo) {
    const periodo = periodoPronto(Number(botao.dataset.dias));
    const corresponde = form.inicio.value === periodo.inicio && form.fim.value === periodo.fim;
    botao.setAttribute('aria-pressed', String(corresponde));
  }
}

function descreverFiltro() {
  const { inicio, fim } = form;
  let periodo = 'Todo o período';
  if (inicio.value && fim.value) periodo = `De ${formatarData(inicio.value)} a ${formatarData(fim.value)}`;
  else if (inicio.value) periodo = `A partir de ${formatarData(inicio.value)}`;
  else if (fim.value) periodo = `Até ${formatarData(fim.value)}`;
  const categoria = seletorCategoria.value ? seletorCategoria.selectedOptions[0].textContent : 'todas as categorias';
  return `${periodo} · ${categoria}`;
}

// ---------- Carregamento ----------

// Erro do filtro logo abaixo do formulario (e nao no topo da pagina, que
// pode estar fora da tela no celular).
function mostrarErroFiltro(mensagem) {
  const erro = document.getElementById('erro-filtro');
  erro.textContent = mensagem ?? '';
  erro.classList.toggle('oculto', !mensagem);
  if (mensagem) erro.scrollIntoView({ block: 'nearest' });
}

async function carregar() {
  if (form.inicio.value && form.fim.value && form.inicio.value > form.fim.value) {
    mostrarErroFiltro(`A data "De" precisa ser igual ou anterior à data "Até".${carregouUmaVez ? ' Os números abaixo continuam sendo do filtro anterior.' : ''}`);
    return;
  }
  const parametros = parametrosDoFormulario();
  history.replaceState(null, '', parametros.size ? `?${parametros}` : location.pathname);
  marcarPeriodo();

  const pedido = ++pedidoAtual;
  conteudo.classList.add('carregando'); // mantem o desenho anterior enquanto carrega
  conteudo.setAttribute('aria-busy', 'true');
  try {
    const dados = await api(`/analise?${parametros}`);
    dataUltimaVenda = dados.indicadores.ultima_venda; // nao depende do filtro: vale mesmo se a resposta for antiga
    if (pedido !== pedidoAtual) return;
    if (periodoDesatualizado()) {
      aplicarPeriodo(periodoEscolhido.dias);
      carregar();
      return;
    }
    mostrarErroFiltro(null);
    marcarPeriodo(); // de novo: o fim dos periodos pode ter mudado
    mostrarFimDosPeriodos();
    mostrar(dados);
    carregouUmaVez = true;
  } catch (err) {
    if (pedido !== pedidoAtual) return;
    mostrarErroFiltro(`Não foi possível carregar a análise: ${err.message}${carregouUmaVez ? ' Os números abaixo continuam sendo do filtro anterior.' : ''}`);
  } finally {
    if (pedido === pedidoAtual) {
      conteudo.classList.remove('carregando');
      conteudo.removeAttribute('aria-busy');
    }
  }
}

function mostrar(dados) {
  const ind = dados.indicadores;
  document.getElementById('resumo-filtro').textContent = descreverFiltro();
  document.getElementById('ind-volume').textContent = formatarPreco(ind.volume);
  document.getElementById('ind-vendas').textContent = ind.vendas;
  document.getElementById('ind-ticket').textContent = formatarPreco(ind.ticket_medio);
  document.getElementById('ind-ofertas').textContent = ind.ofertas_ativas;

  const aviso = document.getElementById('aviso-amostra');
  aviso.classList.toggle('oculto', ind.vendas >= AMOSTRA_PEQUENA);
  aviso.textContent = ind.vendas === 0
    ? 'Nenhuma venda concluída neste período e categoria. Escolha um período maior.'
    : `Amostra pequena: ${ind.vendas} ${ind.vendas === 1 ? 'venda' : 'vendas'} no filtro escolhido. Médias, rankings e variações podem não representar o mercado.`;

  mostrarVolumePorMes(dados.vendas_por_mes);
  mostrarTicketPorMes(dados.vendas_por_mes);
  mostrarRaridades(dados.por_raridade);
  mostrarCategorias(dados.por_categoria);
  mostrarMaisNegociadas(dados.mais_negociadas);
  mostrarVariacoes(dados.maiores_variacoes);
  mostrarVendedores(dados.vendedores);
}

// ---------- Graficos ----------

const plural = (n, um, varios) => `${n} ${n === 1 ? um : varios}`;

// Meses sem venda entram com zero: o eixo do tempo nao pode "pular" meses.
// A serie vai do inicio do filtro (ou da primeira venda) ate o fim do
// filtro (ou o fim dos periodos prontos: hoje ou a ultima venda), para nao
// esconder meses parados nas pontas.
function completarMeses(lista) {
  if (!lista.length) return [];
  const indice = (data) => {
    const [ano, mes] = data.split('-').map(Number);
    return ano * 12 + mes - 1;
  };
  const porMes = new Map(lista.map((m) => [m.mes.slice(0, 7), m]));
  // Meses vazios nas pontas: no maximo 12 de cada lado (uma data como
  // 01/01/0001 nao vira milhares de colunas).
  const primeiraVenda = indice(lista[0].mes);
  const ultimaVenda = indice(lista[lista.length - 1].mes);
  const primeiro = Math.max(Math.min(indice(form.inicio.value || lista[0].mes), primeiraVenda), primeiraVenda - 12);
  const ultimo = Math.min(Math.max(indice(form.fim.value || fimDosPeriodos()), ultimaVenda), ultimaVenda + 12);
  const meses = [];
  for (let i = primeiro; i <= ultimo; i++) {
    const chave = `${Math.floor(i / 12)}-${String((i % 12) + 1).padStart(2, '0')}`;
    meses.push(porMes.get(chave) ?? { mes: `${chave}-01`, vendas: 0, volume: 0, preco_medio: null });
  }
  return meses;
}

function mostrarVolumePorMes(lista) {
  const alvo = document.getElementById('grafico-volume-mes');
  if (!lista.length) {
    mostrarEstado(alvo, 'Sem vendas no período');
    return;
  }
  graficoColunas(alvo, {
    descricao: 'Volume vendido por mês, em reais',
    nomeValor: 'Volume',
    formatarValor: formatarPreco,
    pontos: completarMeses(lista).map((m) => ({
      rotulo: nomeDoMes(m.mes),
      rotuloLongo: nomeDoMes(m.mes, true),
      valor: Number(m.volume),
      detalhes: [plural(m.vendas, 'venda', 'vendas'), m.preco_medio === null ? 'sem vendas' : `ticket médio ${formatarPreco(m.preco_medio)}`],
      colunasExtras: [['Vendas', String(m.vendas)], ['Ticket médio', m.preco_medio === null ? '—' : formatarPreco(m.preco_medio)]],
    })),
  });
}

function mostrarTicketPorMes(lista) {
  const alvo = document.getElementById('grafico-ticket-mes');
  if (lista.length < 2) {
    mostrarEstado(alvo, 'Poucos meses no período', 'A evolução aparece quando há vendas em pelo menos dois meses.');
    return;
  }
  graficoLinha(alvo, {
    descricao: 'Ticket médio por mês, em reais',
    nomeValor: 'Ticket médio',
    formatarValor: formatarPreco,
    pontos: lista.map((m) => ({
      mes: m.mes,
      valor: Number(m.preco_medio),
      vendas: m.vendas,
      detalhes: [plural(m.vendas, 'venda', 'vendas')],
    })),
  });
}

function mostrarRaridades(lista) {
  const alvo = document.getElementById('grafico-raridade');
  if (!lista.length) {
    mostrarEstado(alvo, 'Sem vendas no período');
    return;
  }
  graficoBarras(alvo, {
    descricao: 'Preço médio das vendas por raridade',
    nomeRotulo: 'Raridade',
    nomeValor: 'Preço médio',
    formatarValor: formatarPreco,
    itens: lista.map((r) => ({
      rotulo: r.raridade,
      cor: r.cor,
      valor: Number(r.preco_medio),
      detalhes: [plural(r.vendas, 'venda', 'vendas'), `volume ${formatarPreco(r.volume)}`],
      colunasExtras: [['Vendas', String(r.vendas)], ['Volume', formatarPreco(r.volume)]],
    })),
  });
}

function mostrarCategorias(lista) {
  const alvo = document.getElementById('grafico-categoria');
  if (!lista.length) {
    mostrarEstado(alvo, 'Sem vendas no período');
    return;
  }
  graficoBarras(alvo, {
    descricao: 'Volume negociado por categoria, em reais',
    nomeRotulo: 'Categoria',
    nomeValor: 'Volume',
    formatarValor: formatarPreco,
    itens: lista.map((c) => ({
      rotulo: c.categoria,
      valor: Number(c.volume),
      detalhes: [plural(c.vendas, 'venda', 'vendas'), `preço médio ${formatarPreco(c.preco_medio)}`],
      colunasExtras: [['Vendas', String(c.vendas)], ['Preço médio', formatarPreco(c.preco_medio)]],
    })),
  });
}

// ---------- Rankings ----------

function tabela(alvo, legenda, cabecalho, linhas) {
  alvo.className = 'tabela-rolagem';
  alvo.innerHTML = `
    <table class="tabela tabela-responsiva">
      <caption class="visualmente-oculto">${escaparHtml(legenda)}</caption>
      <thead><tr>${cabecalho}</tr></thead>
      <tbody>${linhas.join('')}</tbody>
    </table>`;
}

function linkSkin(id, nome, cor) {
  return `<span class="barra-rotulo">${cor ? `<span class="ponto" style="--cor-raridade: ${escaparHtml(cor)}" aria-hidden="true"></span>` : ''}
    <a href="/skin/${id}">${escaparHtml(nome)}</a></span>`;
}

function mostrarMaisNegociadas(lista) {
  const alvo = document.getElementById('ranking-mais-negociadas');
  if (!lista.length) {
    mostrarEstado(alvo, 'Sem vendas no período');
    return;
  }
  tabela(alvo, 'Skins mais negociadas no período',
    '<th>#</th><th>Skin</th><th class="numero">Vendas</th><th class="numero">Preço médio</th>',
    lista.map((s, i) => `
      <tr>
        ${celula('Posição', `${i + 1}º`)}
        ${celula('Skin', linkSkin(s.modelo_id, s.nome, s.cor_raridade))}
        ${celula('Vendas', String(s.vendas), 'numero')}
        ${celula('Preço médio', formatarPreco(s.preco_medio), 'numero')}
      </tr>`));
}

function mostrarVariacoes(lista) {
  const alvo = document.getElementById('ranking-variacoes');
  if (!lista.length) {
    mostrarEstado(alvo, 'Nenhuma skin com 2 ou mais vendas no período', 'A variação compara a primeira e a última venda de cada skin.');
    return;
  }
  tabela(alvo, 'Maiores variações de preço no período',
    '<th>Skin</th><th class="numero">Primeira</th><th class="numero">Última</th><th class="numero">Variação</th>',
    lista.map((s) => {
      const p = Number(s.variacao_pct);
      const seta = p > 0 ? '▲' : p < 0 ? '▼' : '=';
      const sentido = p > 0 ? 'alta de' : p < 0 ? 'queda de' : 'sem variação,';
      const texto = `<span aria-hidden="true">${seta}</span> <span class="visualmente-oculto">${sentido}</span> ${p > 0 ? '+' : ''}${p.toFixed(1).replace('.', ',')}%`;
      return `
        <tr>
          ${celula('Skin', `${linkSkin(s.modelo_id, s.nome)}<small class="texto-suave">${plural(s.vendas, 'venda', 'vendas')}</small>`)}
          ${celula('Primeira', formatarPreco(s.primeiro_preco), 'numero')}
          ${celula('Última', formatarPreco(s.ultimo_preco), 'numero')}
          ${celula('Variação', `<span class="variacao ${p > 0 ? 'alta' : p < 0 ? 'queda' : ''}">${texto}</span>`, 'numero')}
        </tr>`;
    }));
}

function mostrarVendedores(lista) {
  const alvo = document.getElementById('ranking-vendedores');
  if (!lista.length) {
    mostrarEstado(alvo, 'Nenhuma avaliação registrada');
    return;
  }
  tabela(alvo, 'Vendedores mais bem avaliados',
    '<th>#</th><th>Usuário</th><th class="numero">Nota média</th><th class="numero">Avaliações</th><th class="numero">Vendas</th>',
    lista.map((v, i) => `
      <tr>
        ${celula('Posição', `${i + 1}º`)}
        ${celula('Usuário', `<a href="/usuario/${v.usuario_id}">${escaparHtml(v.apelido)}</a>`)}
        ${celula('Nota média', `★ ${formatarNota(v.nota_media)}`, 'numero')}
        ${celula('Avaliações', String(v.avaliacoes), 'numero')}
        ${celula('Vendas', String(v.vendas), 'numero')}
      </tr>`));
}
