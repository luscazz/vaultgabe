// Pagina Catalogo ( / ): busca com filtros combinados, um card por modelo.
// Os filtros ficam no endereco da pagina (?categoria=1&desgaste=FN...), entao
// a busca pode ser recarregada e compartilhada.
import { iniciarPagina, api, mostrarEstado, escaparHtml, formatarPreco, imagemDoItem } from './comum.js';

const form = document.getElementById('filtros');
const ordenar = document.getElementById('ordenar');
const grade = document.getElementById('grade-catalogo');
const total = document.getElementById('total-resultados');
const botaoFiltros = document.getElementById('mostrar-filtros');
const painelFiltros = document.getElementById('painel-filtros');

// Filtros que valem para a oferta: seguem para a pagina da skin.
const FILTROS_DA_OFERTA = ['desgaste', 'stattrak', 'souvenir', 'com_adesivos'];
const ORDEM_PADRAO = 'menor_preco';

let espera;          // atraso da busca enquanto o usuario digita
let pedidoAtual = 0; // so a resposta do pedido mais recente e mostrada

iniciarPagina('catalogo');
await montarFiltros();
aplicarEnderecoNoFormulario();
buscar();

// ---------- Eventos ----------

form.addEventListener('input', (evento) => {
  // Digitacao espera uma pausa; caixas e listas buscam na hora.
  clearTimeout(espera);
  const digitando = ['search', 'number'].includes(evento.target.type);
  espera = setTimeout(buscar, digitando ? 350 : 0);
});
form.addEventListener('submit', (evento) => {
  evento.preventDefault();
  buscar();
});
form.addEventListener('reset', () => setTimeout(buscar, 0));
ordenar.addEventListener('change', buscar);
botaoFiltros.addEventListener('click', () => {
  const aberto = painelFiltros.classList.toggle('aberto');
  botaoFiltros.setAttribute('aria-expanded', String(aberto));
});

// ---------- Filtros ----------

async function montarFiltros() {
  try {
    const { categorias, raridades, colecoes } = await api('/catalogo/filtros');

    document.getElementById('filtro-categorias').innerHTML = categorias.map((c) => `
      <label class="opcao">
        <input type="checkbox" name="categoria" value="${c.id}"> ${escaparHtml(c.nome)}
        <span class="contagem">${c.modelos}</span>
      </label>`).join('');

    document.getElementById('filtro-raridades').innerHTML = raridades.map((r) => `
      <label class="opcao" style="--cor-raridade: ${escaparHtml(r.cor)}">
        <input type="checkbox" name="raridade" value="${r.id}">
        <span class="ponto" aria-hidden="true"></span> ${escaparHtml(r.nome)}
        <span class="contagem">${r.modelos}</span>
      </label>`).join('');

    document.getElementById('colecao').insertAdjacentHTML('beforeend', colecoes.map((c) => `
      <option value="${c.id}">${escaparHtml(c.nome)}</option>`).join(''));
  } catch (err) {
    for (const id of ['filtro-categorias', 'filtro-raridades']) {
      document.getElementById(id).innerHTML = `<span class="texto-suave">${escaparHtml(err.message)}</span>`;
    }
  }
}

// Endereco -> formulario (ao abrir a pagina).
function aplicarEnderecoNoFormulario() {
  const parametros = new URLSearchParams(location.search);
  for (const [nome, valor] of parametros) {
    if (nome === 'ordenar') {
      ordenar.value = valor;
      continue;
    }
    for (const campo of form.querySelectorAll(`[name="${CSS.escape(nome)}"]`)) {
      if (campo.type === 'checkbox') {
        // Como na pagina da skin: "?desgaste=FN,MW" e caixas com "1", "true" ou "on".
        const marcado = campo.value === 'on'
          ? ['1', 'true', 'on'].includes(valor)
          : valor.split(',').includes(campo.value);
        if (marcado) campo.checked = true;
      } else {
        campo.value = valor;
      }
    }
  }
  atualizarBotaoFiltros(parametros);
}

// Formulario -> parametros da busca (sem campos vazios).
// Preco negativo nao vale como filtro: o campo fica marcado e e ignorado.
function parametrosAtuais() {
  const parametros = new URLSearchParams();
  for (const campo of [form.preco_min, form.preco_max]) {
    if (Number(campo.value) < 0) campo.setAttribute('aria-invalid', 'true');
    else campo.removeAttribute('aria-invalid');
  }
  for (const [nome, valor] of new FormData(form)) {
    const texto = String(valor).trim();
    if (texto === '' || (nome.startsWith('preco_') && Number(texto) < 0)) continue;
    parametros.append(nome, texto);
  }
  if (ordenar.value !== ORDEM_PADRAO) parametros.set('ordenar', ordenar.value);
  return parametros;
}

function atualizarBotaoFiltros(parametros) {
  const ativos = [...parametros.keys()].filter((nome) => nome !== 'ordenar').length;
  botaoFiltros.textContent = ativos ? `Filtros (${ativos})` : 'Filtros';
}

// ---------- Busca ----------

async function buscar() {
  const parametros = parametrosAtuais();
  history.replaceState(null, '', parametros.size ? `?${parametros}` : location.pathname);
  atualizarBotaoFiltros(parametros);

  const pedido = ++pedidoAtual;
  grade.classList.add('carregando');
  grade.setAttribute('aria-busy', 'true');

  try {
    const itens = await api(`/catalogo?${parametros}`);
    if (pedido !== pedidoAtual) return;
    mostrarResultados(itens, parametros);
  } catch (err) {
    if (pedido !== pedidoAtual) return;
    total.textContent = '—';
    mostrarEstado(grade, 'Não foi possível carregar o catálogo', err.message, 'erro');
  } finally {
    if (pedido === pedidoAtual) {
      grade.classList.remove('carregando');
      grade.removeAttribute('aria-busy');
    }
  }
}

function mostrarResultados(itens, parametros) {
  total.textContent = itens.length;
  document.getElementById('titulo-resultados').lastChild.textContent = itens.length === 1 ? ' skin' : ' skins';

  if (itens.length === 0) {
    mostrarEstado(grade, 'Nenhuma skin encontrada', 'Tente outra busca ou limpe os filtros.');
    return;
  }

  const daOferta = new URLSearchParams();
  for (const [nome, valor] of parametros) {
    if (FILTROS_DA_OFERTA.includes(nome)) daOferta.append(nome, valor);
  }
  const sufixo = daOferta.size ? `?${daOferta}` : '';

  grade.className = 'grade-cards';
  grade.innerHTML = itens.map((item) => cartao(item, sufixo)).join('');
}

function cartao(item, sufixo) {
  const detalhes = [item.categoria, item.colecao].filter(Boolean).map(escaparHtml).join(' · ');
  const vendas = `${item.vendas} ${item.vendas === 1 ? 'venda' : 'vendas'}`;
  const preco = item.menor_preco === null
    ? `<span class="sem-oferta">Sem ofertas à venda</span><small>${vendas}</small>`
    : `<small class="rotulo-preco">A partir de</small>${formatarPreco(item.menor_preco)}
       <small>${item.ofertas} ${item.ofertas === 1 ? 'oferta' : 'ofertas'} · ${vendas}</small>`;

  return `
    <a class="card-item" href="/skin/${item.id}${sufixo}" style="--cor-raridade: ${escaparHtml(item.cor_raridade)}">
      <div class="card-imagem">${imagemDoItem(item)}</div>
      <div class="card-corpo">
        <span><span class="selo selo-raridade">${escaparHtml(item.raridade)}</span></span>
        <span class="card-nome">${escaparHtml(item.nome)}</span>
        <span class="card-meta">${detalhes}</span>
        <div class="card-preco">${preco}</div>
      </div>
    </a>`;
}
