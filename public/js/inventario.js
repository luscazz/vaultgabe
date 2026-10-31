// Pagina Inventario ( /inventario ): itens do usuario selecionado em
// "Entrar como", separados por tipo, com a situacao de cada um, e a janela
// Novo anuncio. A aba e o filtro ficam no endereco (?tipo=...&negociaveis=1)
// e quem filtra e o banco: cada troca pede a lista de novo a API.
import {
  iniciarPagina, api, mostrarEstado, escaparHtml, imagemDoItem,
  formatarPreco, formatarData, formatarDataHora, formatarFloat,
  prepararAbas, prepararJanela, nomeVersao, baseDaMedia, NOMES_DESGASTE, NOMES_TIPO,
} from './comum.js';

const grade = document.getElementById('grade-inventario');
const listaAbas = document.getElementById('abas-tipo');
const soNegociaveis = document.getElementById('so-negociaveis');
const statusInventario = document.getElementById('status-inventario');
const tituloItens = document.getElementById('titulo-itens');
const janela = document.getElementById('janela-anunciar');
const form = document.getElementById('form-anunciar');
const campoPreco = document.getElementById('preco-anuncio');
const sugestoes = document.getElementById('sugestoes-preco');
const botaoPublicar = document.getElementById('publicar-anuncio');
const botaoCancelar = document.getElementById('cancelar-anuncio');
const erroAnuncio = document.getElementById('erro-anuncio');

const TIPOS = ['equipamento', 'cosmetico', 'consumivel'];
const PRECO_MAXIMO = 1_000_000;

let usuario = null;             // usuario selecionado em "Entrar como"
let itens = null;               // itens da aba e do filtro atuais, ja filtrados pelo banco
let resumo = null;              // indicadores do topo e numero de itens de cada aba
let erroCarga = null;           // mensagem da ultima carga que falhou
let tipoAtual = '';             // '' = todos
let pedidoItens = 0;            // so a resposta da carga mais recente vale
let itemEmAnuncio = null;       // item aberto na janela Novo anuncio
let analise = null;             // analise de preco do item aberto
let pedidoAnalise = 0;          // so a resposta da analise mais recente vale
let recarregarAoFechar = false; // anuncio publicado ou recusado: atualiza ao fechar
let esperaAnuncio;              // atraso do aviso da analise para o leitor de tela

const marcarAba = prepararAbas(listaAbas, (aba) => {
  if (aba.dataset.tipo === tipoAtual && itens) return; // mesma aba, ja carregada
  tipoAtual = aba.dataset.tipo;
  atualizarEndereco();
  carregar();
});
lerEndereco();

soNegociaveis.addEventListener('change', () => {
  atualizarEndereco();
  carregar();
});
grade.addEventListener('click', (evento) => {
  const botao = evento.target.closest('[data-anunciar]');
  if (botao) abrirAnuncio(Number(botao.dataset.anunciar));
});
campoPreco.addEventListener('input', () => {
  campoPreco.removeAttribute('aria-invalid');
  atualizarDiferenca();
  // O leitor de tela ouve a comparacao so quando a digitacao para.
  clearTimeout(esperaAnuncio);
  esperaAnuncio = setTimeout(() => {
    document.getElementById('ap-status').textContent = document.getElementById('ap-diferenca').textContent;
  }, 800);
});
sugestoes.addEventListener('click', (evento) => {
  const botao = evento.target.closest('[data-preco]');
  if (!botao) return;
  campoPreco.value = Number(botao.dataset.preco).toFixed(2).replace('.', ',');
  campoPreco.removeAttribute('aria-invalid');
  atualizarDiferenca();
  campoPreco.focus();
});
prepararJanela(janela, { aoEnviar: publicar, retorno: tituloItens });
janela.addEventListener('close', () => {
  pedidoAnalise++; // descarta uma analise que ainda esteja chegando
  if (!recarregarAoFechar) return;
  recarregarAoFechar = false;
  tituloItens.focus(); // os cards serao redesenhados
  carregar();
});

usuario = await iniciarPagina('inventario');
if (usuario) {
  document.getElementById('titulo-inventario').textContent = `Inventário de ${usuario.apelido}`;
  document.getElementById('dono-inventario').textContent =
    `Itens de ${usuario.nome}. Para ver o de outra pessoa, troque o usuário em "Entrar como".`;
  carregar();
} else {
  grade.removeAttribute('aria-busy');
  mostrarEstado(grade, 'Não foi possível carregar o inventário', 'O banco de dados não respondeu. Tente de novo em instantes.', 'erro');
}

// ---------- Endereco (aba e filtro) ----------

function lerEndereco() {
  const parametros = new URLSearchParams(location.search);
  const tipo = parametros.get('tipo');
  if (TIPOS.includes(tipo)) {
    tipoAtual = tipo;
    marcarAba(listaAbas.querySelector(`[data-tipo="${tipo}"]`));
  }
  soNegociaveis.checked = ['1', 'true', 'on'].includes(parametros.get('negociaveis'));
}

function atualizarEndereco() {
  const parametros = new URLSearchParams();
  if (tipoAtual) parametros.set('tipo', tipoAtual);
  if (soNegociaveis.checked) parametros.set('negociaveis', '1');
  history.replaceState(null, '', parametros.size ? `?${parametros}` : location.pathname);
}

// ---------- Itens ----------

// Pede ao banco so os itens da aba e do filtro atuais. Trocas rapidas de aba
// geram varios pedidos: so a resposta do ultimo e mostrada.
async function carregar() {
  if (!usuario) return; // "Entrar como" ainda nao carregou (ou falhou)
  const parametros = new URLSearchParams({ usuario: usuario.id });
  if (tipoAtual) parametros.set('tipo', tipoAtual);
  if (soNegociaveis.checked) parametros.set('negociaveis', '1');

  const pedido = ++pedidoItens;
  grade.classList.add('carregando'); // mantem os cards anteriores enquanto carrega
  grade.setAttribute('aria-busy', 'true');
  try {
    const dados = await api(`/inventario?${parametros}`);
    if (pedido !== pedidoItens) return;
    itens = dados.itens;
    resumo = dados.resumo;
    erroCarga = null;
    mostrarItens();
  } catch (err) {
    if (pedido !== pedidoItens) return;
    // Sem dados atualizados, a lista e os numeros antigos nao podem ficar na tela.
    itens = null;
    resumo = null;
    erroCarga = err.message;
    mostrarItens();
  } finally {
    if (pedido === pedidoItens) {
      grade.classList.remove('carregando');
      grade.removeAttribute('aria-busy');
    }
  }
}

// Indicadores do topo e numero de cada aba, todos vindos de resumo_inventario.
function mostrarNumeros() {
  const indicadores = {
    'ind-itens': 'itens', 'ind-negociaveis': 'negociaveis',
    'ind-anunciados': 'anunciados', 'ind-prontos': 'prontos_para_anunciar',
  };
  for (const [id, coluna] of Object.entries(indicadores)) {
    document.getElementById(id).textContent = resumo ? resumo[coluna] : '—';
  }
  // O numero de cada aba ja respeita "So os que posso anunciar".
  const prontos = soNegociaveis.checked;
  for (const aba of listaAbas.querySelectorAll('[role="tab"]')) {
    const tipo = aba.dataset.tipo;
    const coluna = tipo ? `${prontos ? 'prontos' : 'itens'}_${tipo}` : (prontos ? 'prontos_para_anunciar' : 'itens');
    aba.querySelector('.contador').textContent = resumo ? `(${resumo[coluna]})` : '';
  }
}

function mostrarItens() {
  mostrarNumeros();
  if (!itens) {
    statusInventario.textContent = '';
    mostrarEstado(grade, 'Não foi possível carregar o inventário', erroCarga ?? '', 'erro');
    return;
  }

  statusInventario.textContent = `${itens.length} ${itens.length === 1 ? 'item' : 'itens'}`;
  if (!itens.length) {
    if (!Number(resumo.itens)) {
      mostrarEstado(grade, 'Nenhum item no inventário', 'Os itens comprados no catálogo aparecem aqui.');
    } else {
      mostrarEstado(grade, 'Nenhum item neste filtro',
        soNegociaveis.checked ? 'Desmarque "Só os que posso anunciar" ou troque de aba.' : 'Troque de aba para ver os outros itens.');
    }
    return;
  }
  grade.className = 'grade-cards';
  grade.innerHTML = itens.map(cartao).join('');
}

function cartao(item) {
  const linhas = [];
  const selos = [`<span class="selo selo-raridade">${escaparHtml(item.raridade)}</span>`];

  if (item.tipo === 'equipamento') {
    if (item.stattrak) selos.push('<span class="selo selo-stattrak">StatTrak™</span>');
    if (item.souvenir) selos.push('<span class="selo selo-souvenir">Souvenir</span>');
    linhas.push(`${escaparHtml(NOMES_DESGASTE[item.desgaste] ?? '')} · float ${formatarFloat(item.float_value, 4)}${item.paint_seed !== null ? ` · seed ${item.paint_seed}` : ''}`);
    if (item.cosmeticos_aplicados) linhas.push(`Aplicados: ${escaparHtml(item.cosmeticos_aplicados)}`);
  } else if (item.tipo === 'cosmetico') {
    linhas.push(escaparHtml(NOMES_TIPO[item.tipo_cosmetico] ?? item.tipo_cosmetico));
    if (item.aplicado_em) linhas.push(`Aplicado em ${escaparHtml(item.aplicado_em)}`);
  } else {
    const estado = item.lacrado ? 'Lacrado'
      : item.cargas_restantes === null ? '' : `${item.cargas_restantes} ${item.cargas_restantes === 1 ? 'carga' : 'cargas'}`;
    linhas.push([NOMES_TIPO[item.tipo_consumivel] ?? item.tipo_consumivel, estado].filter(Boolean).map(escaparHtml).join(' · '));
    if (item.aberto_em) {
      linhas.push(`Aberta em ${formatarData(item.aberto_em)}${item.resultado_abertura ? ` → ${escaparHtml(item.resultado_abertura)}` : ''}`);
    }
    if (item.chave_usada_em) linhas.push(`Usada em ${formatarData(item.chave_usada_em)}`);
  }
  if (item.obtido_ao_abrir) linhas.push(`Obtido ao abrir ${escaparHtml(item.obtido_ao_abrir)}`);

  return `
    <article class="card-item card-inventario" style="--cor-raridade: ${escaparHtml(item.cor_raridade)}">
      <div class="card-imagem">${imagemDoItem(item)}</div>
      <div class="card-corpo">
        <div class="selos">${selos.join('')}</div>
        <a class="card-nome" href="/skin/${item.modelo_id}">${escaparHtml(item.nome)}</a>
        ${linhas.map((l) => `<span class="card-meta">${l}</span>`).join('')}
        <div class="card-rodape">${situacao(item)}</div>
      </div>
    </article>`;
}

function situacao(item) {
  switch (item.situacao) {
    case 'disponivel':
      return `<span class="selo selo-sucesso">Disponível</span>
        <button type="button" class="botao botao-primario botao-pequeno" data-anunciar="${item.item_id}"
          aria-label="Anunciar ${escaparHtml(item.nome)}">Anunciar</button>`;
    case 'anunciado':
      return `<span class="selo selo-aviso">Anunciado</span>
        <a href="/skin/${item.modelo_id}" title="Ver a oferta na página da skin">${formatarPreco(item.preco_anunciado)}</a>`;
    case 'aplicado':
      return '<span class="selo">Aplicado em uma arma</span>';
    case 'consumido':
      return '<span class="selo">Consumido</span>';
    default:
      return `<span class="selo selo-perigo">Bloqueado</span>
        <small class="texto-suave">${item.negociavel ? 'Bloqueado para negociação' : 'Item não negociável'}</small>`;
  }
}

// ---------- Janela Novo anuncio ----------

function abrirAnuncio(idItem) {
  itemEmAnuncio = itens?.find((i) => i.item_id === idItem);
  if (!itemEmAnuncio) return;

  const item = itemEmAnuncio;
  const detalhe = item.tipo === 'equipamento'
    ? `${nomeVersao(item)} · float ${formatarFloat(item.float_value, 4)}`
    : NOMES_TIPO[item.tipo_cosmetico ?? item.tipo_consumivel] ?? '';
  document.getElementById('resumo-anuncio').innerHTML = `
    <div class="card-imagem" style="--cor-raridade: ${escaparHtml(item.cor_raridade)}">${imagemDoItem(item)}</div>
    <div>
      <strong>${escaparHtml(item.nome)}</strong><br>
      <small class="texto-suave">${escaparHtml(detalhe)}</small><br>
      <small class="texto-suave">${escaparHtml(item.raridade)} · ${escaparHtml(item.numero_inspecao)}</small>
    </div>`;

  form.reset();
  campoPreco.removeAttribute('aria-invalid');
  analise = null;
  document.getElementById('ap-menor').textContent = 'Carregando…';
  document.getElementById('ap-media').textContent = 'Carregando…';
  document.getElementById('ap-diferenca').textContent = '';
  document.getElementById('ap-diferenca').className = '';
  document.getElementById('ap-status').textContent = '';
  sugestoes.innerHTML = '';
  erroAnuncio.classList.add('oculto');
  botaoPublicar.disabled = false;
  botaoPublicar.textContent = 'Publicar anúncio';
  alternarEtapa(false);
  janela.showModal();
  campoPreco.focus();
  carregarAnalise(item.item_id);
}

async function carregarAnalise(idItem) {
  const pedido = ++pedidoAnalise;
  try {
    const dados = await api(`/anuncios/analise-preco?item=${idItem}`);
    if (pedido !== pedidoAnalise) return;
    analise = dados;
    document.getElementById('ap-menor').textContent = dados.menor_preco_atual === null
      ? 'Nenhuma outra oferta à venda'
      : `${formatarPreco(dados.menor_preco_atual)} (${dados.ofertas_atuais} ${dados.ofertas_atuais === 1 ? 'oferta' : 'ofertas'})`;
    const referencia = baseDaMedia(dados.base_media, nomeVersao(itemEmAnuncio));
    document.getElementById('ap-media').textContent = dados.vendas
      ? `${formatarPreco(dados.preco_medio_vendas)} (${dados.vendas} ${dados.vendas === 1 ? 'venda' : 'vendas'}${referencia ? ` · ${referencia}` : ''})`
      : 'Sem vendas registradas';

    const opcoes = [];
    if (dados.preco_medio_vendas !== null) opcoes.push(['Usar a média', dados.preco_medio_vendas]);
    if (dados.menor_preco_atual !== null) opcoes.push(['Igualar a menor oferta', dados.menor_preco_atual]);
    sugestoes.innerHTML = opcoes.map(([texto, valor]) => `
      <button type="button" class="botao botao-pequeno" data-preco="${Number(valor)}">${texto} (${formatarPreco(valor)})</button>`).join('');
    atualizarDiferenca();
  } catch (err) {
    if (pedido !== pedidoAnalise) return;
    document.getElementById('ap-menor').textContent = '—';
    document.getElementById('ap-media').textContent = '—';
    document.getElementById('ap-diferenca').className = '';
    document.getElementById('ap-diferenca').textContent = `Análise de preço indisponível: ${err.message}`;
  }
}

// Compara o preco digitado com a media das vendas e com a menor oferta.
function atualizarDiferenca() {
  const alvo = document.getElementById('ap-diferenca');
  if (!analise) return;
  alvo.className = '';
  if (!analise.vendas) {
    alvo.textContent = 'Ainda não há vendas deste modelo para comparar.';
    return;
  }
  const valor = lerPreco(campoPreco.value);
  if (!(valor > 0)) {
    alvo.textContent = 'Digite um preço para comparar com a média das vendas.';
    return;
  }
  // Media sem arredondar e da mesma base: a mesma conta da pagina da skin.
  const media = Number(analise.preco_medio_exato ?? analise.preco_medio_vendas);
  // Arredonda como o ROUND(..., 1) do SQL, para o texto bater com a pagina da skin.
  const bruto = (valor - media) / media * 100;
  const p = Math.sign(bruto) * Math.round(Math.abs(bruto) * 10 + 1e-9) / 10;
  const referencia = baseDaMedia(analise.base_media, nomeVersao(itemEmAnuncio));
  const base = referencia ? ` (${referencia})` : '';
  let texto = Math.abs(p) < 0.5
    ? `Seu preço está na média das vendas${base}.`
    : `Seu preço está ${Math.abs(p).toFixed(1).replace('.', ',')}% ${p < 0 ? 'abaixo' : 'acima'} da média das vendas${base}.`;
  if (analise.menor_preco_atual !== null && valor > Number(analise.menor_preco_atual)) {
    texto += ` Já existe oferta mais barata (${formatarPreco(analise.menor_preco_atual)}).`;
  }
  alvo.textContent = texto;
  alvo.className = `analise-preco ${Math.abs(p) < 0.5 ? '' : p < 0 ? 'abaixo' : 'acima'}`;
}

// Preco digitado. So aceita formatos sem ambiguidade:
//   com virgula: "1.234,56", "1234,56", "99,9"  (pontos so como milhar)
//   sem virgula: "1.500", "1.500.000" (milhar) e "1234", "12.5", "12.50"
// Qualquer outra coisa ("1,500.00", "1,5.0", "0.500") vira NaN e o usuario
// e avisado, em vez de publicar um valor diferente do que quis dizer.
function lerPreco(texto) {
  const t = String(texto).replace(/R\$|\s/g, '');
  if (!t) return null;
  if (/^(\d{1,3}(\.\d{3})+|\d+),\d{1,2}$/.test(t)) return Number(t.replace(/\./g, '').replace(',', '.'));
  if (/^[1-9]\d{0,2}(\.\d{3})+$/.test(t)) return Number(t.replace(/\./g, ''));
  if (/^\d+(\.\d{1,2})?$/.test(t)) return Number(t);
  return NaN;
}

function problemaNoPreco(valor) {
  if (valor === null) return 'Informe o preço.';
  if (Number.isNaN(valor)) return 'Preço em formato não reconhecido. Use, por exemplo, 150,00 ou 1.500,00 (vírgula antes dos centavos).';
  if (valor <= 0) return 'O preço precisa ser maior que zero.';
  if (valor > PRECO_MAXIMO) return 'O preço pode ser de no máximo R$ 1.000.000,00.';
  if (Math.abs(valor * 100 - Math.round(valor * 100)) > 1e-6) return 'Use no máximo 2 casas decimais no preço.';
  return null;
}

function mostrarErro(mensagem) {
  erroAnuncio.textContent = mensagem;
  erroAnuncio.classList.remove('oculto');
}

// Chamada por prepararJanela (Enter ou "Publicar anuncio"). Devolve onde
// o foco deve ficar.
async function publicar() {
  if (botaoPublicar.disabled || !itemEmAnuncio) return null;
  const valor = lerPreco(campoPreco.value);
  const problema = problemaNoPreco(valor);
  if (problema) {
    mostrarErro(problema);
    campoPreco.setAttribute('aria-invalid', 'true');
    return campoPreco;
  }

  const item = itemEmAnuncio; // o item deste envio, mesmo que a variavel mude
  botaoPublicar.disabled = true;
  botaoPublicar.textContent = 'Publicando…';
  erroAnuncio.classList.add('oculto');
  try {
    const dias = Number(new FormData(form).get('dias'));
    const anuncio = await api('/anuncios', {
      method: 'POST',
      body: { item_id: item.item_id, usuario_id: usuario.id, preco: valor, dias },
    });
    document.getElementById('publicado-preco').textContent = formatarPreco(valor);
    document.getElementById('publicado-validade').textContent = `${formatarDataHora(anuncio.data_expiracao)} (${dias} dias)`;
    document.getElementById('link-skin-anunciada').href = `/skin/${item.modelo_id}`;
    recarregarAoFechar = true;
    alternarEtapa(true);
    return document.getElementById('anuncio-publicado');
  } catch (err) {
    mostrarErro(err.message);
    // 400: dado invalido, da para corrigir e publicar de novo. Falha de
    // conexao ou do servidor: vale tentar de novo. Regra de negocio (item ja
    // anunciado, nao e mais seu...): a pagina e atualizada ao fechar.
    const tentarDeNovo = !err.status || err.status >= 500;
    const corrigivel = err.status === 400;
    botaoPublicar.disabled = !(tentarDeNovo || corrigivel);
    botaoPublicar.textContent = tentarDeNovo ? 'Tentar de novo' : 'Publicar anúncio';
    if (botaoPublicar.disabled) {
      recarregarAoFechar = true;
      return botaoCancelar;
    }
    return corrigivel ? campoPreco : botaoPublicar;
  }
}

// false: preencher o anuncio; true: anuncio publicado.
function alternarEtapa(publicado) {
  document.getElementById('etapa-anunciar').classList.toggle('oculto', publicado);
  document.getElementById('acoes-anunciar').classList.toggle('oculto', publicado);
  document.getElementById('etapa-publicado').classList.toggle('oculto', !publicado);
  document.getElementById('acoes-publicado').classList.toggle('oculto', !publicado);
}
