// Graficos do VaultGabe, desenhados em SVG/HTML sem biblioteca externa:
//   graficoColunas  -> um valor por mes (ex.: volume vendido)
//   graficoLinha    -> evolucao de um valor, com faixa opcional (menor/maior)
//   graficoBarras   -> comparacao entre categorias (barras horizontais)
// Uma cor de dados so (azul, validada contra o fundo escuro; o ambar fica
// para o que e clicavel). Colunas e linha: dica com mouse, toque e setas do
// teclado; barras: dica com mouse ou Tab. Todo grafico tem o botao
// "Ver tabela" com os mesmos numeros.
import { escaparHtml, formatarPreco } from './comum.js';

const SVG = 'http://www.w3.org/2000/svg';
const ALTURA_GRAFICO = 220; // area do desenho
const FAIXA_EIXO_X = 28;    // rotulos dos meses
const MARGEM = { topo: 18, direita: 12, esquerda: 64 };
const LARGURA_ROTULO_MES = 46; // espaco minimo entre dois rotulos de mes

const compacto = new Intl.NumberFormat('pt-BR', {
  style: 'currency', currency: 'BRL', notation: 'compact', maximumFractionDigits: 1,
});
const semCentavos = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

// Valor curto para eixos e rotulos: "R$ 12 mil" a partir de mil; abaixo
// disso, o valor exato ("R$ 250" ou "R$ 9,90").
function moedaCurta(v) {
  if (Math.abs(v) >= 1000) return compacto.format(v);
  return Number.isInteger(v) ? semCentavos.format(v) : formatarPreco(v);
}

// '2026-01-01' -> 'jan/26' (curto) ou 'janeiro de 2026' (longo).
export function nomeDoMes(data, longo = false) {
  const [ano, mes] = String(data).split('-').map(Number);
  if (!longo) return `${MESES[mes - 1]}/${String(ano).slice(2)}`;
  const nome = new Date(Date.UTC(ano, mes - 1, 1)).toLocaleDateString('pt-BR', { month: 'long', timeZone: 'UTC' });
  return `${nome} de ${ano}`;
}

// ---------- Estrutura comum: figura + tabela + dica ----------

// Monta dentro de `alvo`: o desenho, a tabela equivalente (escondida) e o
// botao que alterna entre os dois. Devolve { desenho, dica }.
function montarFigura(alvo, { descricao, colunas, linhas }) {
  alvo.className = 'figura-grafico';
  alvo.innerHTML = `
    <div class="grafico-desenho" role="group" aria-label="${escaparHtml(descricao)}"></div>
    <div class="grafico-tabela oculto">
      <table class="tabela tabela-responsiva">
        <caption class="visualmente-oculto">${escaparHtml(descricao)}</caption>
        <thead><tr>${colunas.map((c, i) => `<th${i ? ' class="numero"' : ''}>${escaparHtml(c)}</th>`).join('')}</tr></thead>
        <tbody>${linhas.map((l) => `<tr>${l.map((v, i) => `<td${i ? ' class="numero"' : ''} data-rotulo="${escaparHtml(colunas[i])}">${escaparHtml(v)}</td>`).join('')}</tr>`).join('')}</tbody>
      </table>
    </div>
    <button type="button" class="botao botao-pequeno alternar-tabela" aria-expanded="false">Ver tabela</button>
    <div class="dica-grafico" aria-hidden="true" hidden></div>`;

  const desenho = alvo.querySelector('.grafico-desenho');
  const tabela = alvo.querySelector('.grafico-tabela');
  const botao = alvo.querySelector('.alternar-tabela');
  botao.addEventListener('click', () => {
    const mostrar = tabela.classList.contains('oculto');
    tabela.classList.toggle('oculto', !mostrar);
    desenho.classList.toggle('oculto', mostrar);
    botao.textContent = mostrar ? 'Ver gráfico' : 'Ver tabela';
    botao.setAttribute('aria-expanded', String(mostrar));
  });

  // A dica e so visual (aria-hidden): para o leitor de tela, o mesmo texto
  // vai no aria-valuetext da area interativa ou no aria-label de cada barra.
  const dica = alvo.querySelector('.dica-grafico');
  return {
    desenho,
    dica: {
      // Mostra a dica perto de (x, y), em coordenadas da figura. O texto entra
      // por textContent.
      mostrar(x, y, titulo, valor, detalhes = []) {
        dica.replaceChildren();
        const forte = document.createElement('strong');
        forte.textContent = valor;
        const rotulo = document.createElement('span');
        rotulo.textContent = titulo;
        dica.append(forte, rotulo);
        for (const d of detalhes) {
          const linha = document.createElement('small');
          linha.textContent = d;
          dica.append(linha);
        }
        // Mede na posicao de origem: a largura nao depende de onde ela estava.
        dica.style.left = '0px';
        dica.style.top = '0px';
        dica.hidden = false;
        const caixa = dica.getBoundingClientRect();
        const esquerda = Math.min(Math.max(x - caixa.width / 2, 0), Math.max(alvo.clientWidth - caixa.width, 0));
        dica.style.left = `${esquerda}px`;
        dica.style.top = `${Math.max(y - caixa.height - 10, 0)}px`;
      },
      esconder() {
        dica.hidden = true;
      },
    },
  };
}

function elementoSvg(nome, atributos = {}) {
  const el = document.createElementNS(SVG, nome);
  for (const [k, v] of Object.entries(atributos)) el.setAttribute(k, v);
  return el;
}

// Partes so visuais (grade, rotulos, marcas): o leitor de tela le os
// valores pelo elemento com foco e pela tabela.
function decorativo(el) {
  el.setAttribute('aria-hidden', 'true');
  return el;
}

// Escala "redonda" para o eixo Y: maximo e passo limpos (0, 5 mil, 10 mil...).
function escalaY(maximo, marcas = 4) {
  if (!(maximo > 0)) return { topo: 1, passo: 0.25 };
  const bruto = maximo / marcas;
  const potencia = 10 ** Math.floor(Math.log10(bruto));
  const passo = [1, 2, 2.5, 5, 10].map((m) => m * potencia).find((p) => p >= bruto);
  return { topo: passo * Math.ceil(maximo / passo), passo };
}

function desenharGrade(svg, largura, topo, passo) {
  for (let v = 0; v <= topo + passo / 2; v += passo) {
    const y = MARGEM.topo + ALTURA_GRAFICO - (v / topo) * ALTURA_GRAFICO;
    svg.append(decorativo(elementoSvg('line', {
      x1: MARGEM.esquerda, x2: largura - MARGEM.direita, y1: y, y2: y,
      class: v === 0 ? 'eixo' : 'grade',
    })));
    const texto = decorativo(elementoSvg('text', { x: MARGEM.esquerda - 8, y: y + 4, 'text-anchor': 'end', class: 'rotulo-eixo' }));
    texto.textContent = moedaCurta(v);
    svg.append(texto);
  }
}

// Redesenha quando a largura do quadro muda (celular girado, janela...).
function aoRedimensionar(elemento, desenhar) {
  let largura = 0;
  const observar = new ResizeObserver(() => {
    if (!elemento.isConnected) {
      observar.disconnect();
      return;
    }
    if (elemento.clientWidth && elemento.clientWidth !== largura) {
      largura = elemento.clientWidth;
      desenhar(largura);
    }
  });
  observar.observe(elemento);
}

// Area transparente sobre o desenho que recebe mouse, toque e teclado:
//  - mouse: segue o ponteiro e escolhe o ponto mais proximo;
//  - toque: escolhe o ponto tocado (a dica fica ate tocar fora);
//  - teclado: Tab chega aqui e as setas percorrem os pontos.
// Para o leitor de tela e um "slider": anuncia o ponto atual (aria-valuetext).
function areaInterativa(svg, { x, largura, descricao, quantidade, indiceMaisProximo, mostrar, esconder, textoDoPonto }) {
  const area = elementoSvg('rect', {
    x, y: MARGEM.topo, width: largura, height: ALTURA_GRAFICO,
    class: 'area-toque', tabindex: '0', role: 'slider',
    'aria-label': `${descricao}. Use as setas para percorrer os meses.`,
    'aria-valuemin': '1', 'aria-valuemax': String(quantidade),
  });
  let atual = quantidade - 1;
  const marcar = (i) => {
    atual = i;
    area.setAttribute('aria-valuenow', String(i + 1));
    area.setAttribute('aria-valuetext', textoDoPonto(i));
  };
  const ir = (i) => {
    marcar(i);
    mostrar(i);
  };
  const pontoDoEvento = (evento) => indiceMaisProximo(evento.clientX - svg.getBoundingClientRect().left);

  area.addEventListener('pointermove', (evento) => {
    if (evento.pointerType === 'mouse') ir(pontoDoEvento(evento));
  });
  area.addEventListener('pointerdown', (evento) => ir(pontoDoEvento(evento)));
  area.addEventListener('pointerleave', (evento) => {
    if (evento.pointerType === 'mouse' && document.activeElement !== area) esconder();
  });
  area.addEventListener('focus', () => ir(atual));
  area.addEventListener('blur', esconder);
  area.addEventListener('keydown', (evento) => {
    const destino = { ArrowRight: atual + 1, ArrowLeft: atual - 1, Home: 0, End: quantidade - 1 }[evento.key];
    if (destino === undefined) return;
    evento.preventDefault();
    ir(Math.min(Math.max(destino, 0), quantidade - 1));
  });
  marcar(atual); // a dica so aparece quando o usuario interage
  svg.append(area);
}

// ---------- Colunas (um valor por mes) ----------

// pontos: [{ rotulo, rotuloLongo, valor, detalhes: [], colunasExtras: [[titulo, valor]] }]
export function graficoColunas(alvo, { pontos, descricao, formatarValor, nomeValor }) {
  const { desenho, dica } = montarFigura(alvo, {
    descricao,
    colunas: ['Mês', nomeValor, ...(pontos[0]?.colunasExtras?.map((c) => c[0]) ?? [])],
    linhas: pontos.map((p) => [p.rotuloLongo, formatarValor(p.valor), ...(p.colunasExtras?.map((c) => c[1]) ?? [])]),
  });

  aoRedimensionar(desenho, (largura) => {
    const altura = MARGEM.topo + ALTURA_GRAFICO + FAIXA_EIXO_X;
    const svg = elementoSvg('svg', { width: largura, height: altura, viewBox: `0 0 ${largura} ${altura}` });
    const maior = Math.max(...pontos.map((p) => p.valor), 0);
    const { topo, passo } = escalaY(maior);
    desenharGrade(svg, largura, topo, passo);

    const faixa = (largura - MARGEM.esquerda - MARGEM.direita) / pontos.length;
    const larguraBarra = Math.min(24, faixa * 0.6);
    // Rotulos de mes sem encostar; o ultimo mes sempre aparece.
    const pularRotulos = Math.max(1, Math.ceil(LARGURA_ROTULO_MES / faixa));
    const base = MARGEM.topo + ALTURA_GRAFICO;
    const indiceMaior = pontos.findIndex((p) => p.valor === maior);

    const barras = pontos.map((p, i) => {
      const altBarra = topo ? (p.valor / topo) * ALTURA_GRAFICO : 0;
      const x = MARGEM.esquerda + i * faixa + (faixa - larguraBarra) / 2;
      const y = base - altBarra;
      const r = Math.min(4, altBarra, larguraBarra / 2);
      // Ponta arredondada (4px) em cima, quadrada na base.
      const barra = decorativo(elementoSvg('path', {
        class: 'marca-barra',
        d: `M${x},${base} V${y + r} Q${x},${y} ${x + r},${y} H${x + larguraBarra - r} Q${x + larguraBarra},${y} ${x + larguraBarra},${y + r} V${base} Z`,
      }));
      svg.append(barra);

      if ((pontos.length - 1 - i) % pularRotulos === 0) {
        const mes = decorativo(elementoSvg('text', { x: x + larguraBarra / 2, y: base + 18, 'text-anchor': 'middle', class: 'rotulo-eixo' }));
        mes.textContent = p.rotulo;
        svg.append(mes);
      }
      // Rotulo direto so no maior valor (o resto fica na dica e na tabela).
      if (i === indiceMaior && maior > 0) {
        const valor = decorativo(elementoSvg('text', { x: x + larguraBarra / 2, y: y - 6, 'text-anchor': 'middle', class: 'rotulo-valor' }));
        valor.textContent = moedaCurta(p.valor);
        svg.append(valor);
      }
      return { barra, centro: x + larguraBarra / 2, topo: y };
    });

    areaInterativa(svg, {
      x: MARGEM.esquerda,
      largura: largura - MARGEM.esquerda - MARGEM.direita,
      descricao,
      quantidade: pontos.length,
      indiceMaisProximo: (x) => Math.min(Math.max(Math.floor((x - MARGEM.esquerda) / faixa), 0), pontos.length - 1),
      textoDoPonto: (i) => `${pontos[i].rotuloLongo}: ${formatarValor(pontos[i].valor)}. ${pontos[i].detalhes.join('. ')}`,
      mostrar: (i) => {
        barras.forEach((b, n) => b.barra.classList.toggle('ativa', n === i));
        dica.mostrar(barras[i].centro, barras[i].topo, pontos[i].rotuloLongo, formatarValor(pontos[i].valor), pontos[i].detalhes);
      },
      esconder: () => {
        for (const b of barras) b.barra.classList.remove('ativa');
        dica.esconder();
      },
    });

    desenho.replaceChildren(svg);
  });
}

// ---------- Linha (evolucao no tempo, com faixa menor-maior) ----------

// pontos: [{ mes: 'AAAA-MM-01', valor, menor?, maior?, vendas, detalhes: [] }]
// O eixo X e o tempo de verdade: meses sem venda ficam como intervalo.
export function graficoLinha(alvo, { pontos, descricao, formatarValor, nomeValor, comFaixa = false }) {
  const indiceMes = (data) => {
    const [ano, mes] = data.split('-').map(Number);
    return ano * 12 + mes - 1;
  };
  const primeiro = indiceMes(pontos[0].mes);
  const ultimo = indiceMes(pontos[pontos.length - 1].mes);
  const meses = Math.max(ultimo - primeiro, 1);

  const colunas = ['Mês', nomeValor];
  if (comFaixa) colunas.push('Menor', 'Maior');
  colunas.push('Vendas');
  const { desenho, dica } = montarFigura(alvo, {
    descricao,
    colunas,
    linhas: pontos.map((p) => [
      nomeDoMes(p.mes, true), formatarValor(p.valor),
      ...(comFaixa ? [formatarValor(p.menor), formatarValor(p.maior)] : []),
      String(p.vendas),
    ]),
  });
  const detalhesDo = (p) => [...(comFaixa ? [`menor ${formatarValor(p.menor)} · maior ${formatarValor(p.maior)}`] : []), ...p.detalhes];

  aoRedimensionar(desenho, (largura) => {
    const altura = MARGEM.topo + ALTURA_GRAFICO + FAIXA_EIXO_X;
    const svg = elementoSvg('svg', { width: largura, height: altura, viewBox: `0 0 ${largura} ${altura}` });
    const maior = Math.max(...pontos.map((p) => (comFaixa ? p.maior : p.valor)));
    const { topo, passo } = escalaY(maior);
    desenharGrade(svg, largura, topo, passo);

    const util = largura - MARGEM.esquerda - MARGEM.direita - 24;
    const xDe = (p) => MARGEM.esquerda + 12 + ((indiceMes(p.mes) - primeiro) / meses) * util;
    const yDe = (v) => MARGEM.topo + ALTURA_GRAFICO - (v / topo) * ALTURA_GRAFICO;

    if (comFaixa) {
      const ida = pontos.map((p) => `${xDe(p)},${yDe(p.maior)}`);
      const volta = [...pontos].reverse().map((p) => `${xDe(p)},${yDe(p.menor)}`);
      svg.append(decorativo(elementoSvg('polygon', { points: [...ida, ...volta].join(' '), class: 'marca-faixa' })));
    }
    svg.append(decorativo(elementoSvg('polyline', { points: pontos.map((p) => `${xDe(p)},${yDe(p.valor)}`).join(' '), class: 'marca-linha' })));
    for (const p of pontos) {
      svg.append(decorativo(elementoSvg('circle', { cx: xDe(p), cy: yDe(p.valor), r: 4, class: 'marca-ponto' })));
    }

    // Meses no eixo X, contados a partir do ultimo (que sempre aparece),
    // sem encostar um no outro.
    const passoRotulo = Math.max(1, Math.ceil(meses / Math.max(1, Math.floor(util / LARGURA_ROTULO_MES))));
    for (let m = meses; m >= 0; m -= passoRotulo) {
      const idx = primeiro + m;
      const data = `${Math.floor(idx / 12)}-${String((idx % 12) + 1).padStart(2, '0')}-01`;
      const texto = decorativo(elementoSvg('text', { x: xDe({ mes: data }), y: MARGEM.topo + ALTURA_GRAFICO + 18, 'text-anchor': 'middle', class: 'rotulo-eixo' }));
      texto.textContent = nomeDoMes(data);
      svg.append(texto);
    }

    const fim = pontos[pontos.length - 1];
    const rotuloFim = decorativo(elementoSvg('text', { x: xDe(fim), y: yDe(fim.valor) - 10, 'text-anchor': 'end', class: 'rotulo-valor' }));
    rotuloFim.textContent = moedaCurta(fim.valor);
    svg.append(rotuloFim);

    // Linha-guia vertical: segue o ponteiro e "gruda" no mes mais proximo.
    const guia = decorativo(elementoSvg('line', { y1: MARGEM.topo, y2: MARGEM.topo + ALTURA_GRAFICO, class: 'linha-guia', visibility: 'hidden' }));
    svg.append(guia);

    areaInterativa(svg, {
      x: MARGEM.esquerda,
      largura: largura - MARGEM.esquerda - MARGEM.direita,
      descricao,
      quantidade: pontos.length,
      indiceMaisProximo: (x) => {
        let melhor = 0;
        pontos.forEach((p, i) => {
          if (Math.abs(xDe(p) - x) < Math.abs(xDe(pontos[melhor]) - x)) melhor = i;
        });
        return melhor;
      },
      textoDoPonto: (i) => `${nomeDoMes(pontos[i].mes, true)}: ${formatarValor(pontos[i].valor)}. ${detalhesDo(pontos[i]).join('. ')}`,
      mostrar: (i) => {
        const p = pontos[i];
        guia.setAttribute('x1', xDe(p));
        guia.setAttribute('x2', xDe(p));
        guia.setAttribute('visibility', 'visible');
        dica.mostrar(xDe(p), yDe(comFaixa ? p.maior : p.valor), nomeDoMes(p.mes, true), formatarValor(p.valor), detalhesDo(p));
      },
      esconder: () => {
        guia.setAttribute('visibility', 'hidden');
        dica.esconder();
      },
    });

    desenho.replaceChildren(svg);
  });
}

// ---------- Barras horizontais (categorias) ----------

// itens: [{ rotulo, valor, cor? (ponto de identidade ao lado do nome), detalhes: [], colunasExtras }]
// Todas as linhas dividem as mesmas colunas (subgrid): as barras ficam na
// mesma escala.
export function graficoBarras(alvo, { itens, descricao, formatarValor, nomeValor, nomeRotulo }) {
  const { desenho, dica } = montarFigura(alvo, {
    descricao,
    colunas: [nomeRotulo, nomeValor, ...(itens[0]?.colunasExtras?.map((c) => c[0]) ?? [])],
    linhas: itens.map((i) => [i.rotulo, formatarValor(i.valor), ...(i.colunasExtras?.map((c) => c[1]) ?? [])]),
  });
  const maior = Math.max(...itens.map((i) => i.valor), 0) || 1;

  desenho.innerHTML = `<ul class="barras">${itens.map((i, n) => `
    <li class="barra-linha" tabindex="0" data-indice="${n}"
        aria-label="${escaparHtml(`${i.rotulo}: ${formatarValor(i.valor)}. ${i.detalhes.join('. ')}`)}">
      <span class="barra-rotulo" aria-hidden="true">${i.cor ? `<span class="ponto" style="--cor-raridade: ${escaparHtml(i.cor)}"></span>` : ''}${escaparHtml(i.rotulo)}</span>
      <span class="barra-trilho" aria-hidden="true"><span class="barra-dado" style="width: ${Math.max((i.valor / maior) * 100, 0.5)}%"></span></span>
      <span class="barra-valor" aria-hidden="true">${escaparHtml(formatarValor(i.valor))}</span>
    </li>`).join('')}</ul>`;

  const mostrar = (linha) => {
    const i = itens[Number(linha.dataset.indice)];
    const barra = linha.querySelector('.barra-dado').getBoundingClientRect();
    const figura = alvo.getBoundingClientRect();
    dica.mostrar(barra.right - figura.left, barra.top - figura.top, i.rotulo, formatarValor(i.valor), i.detalhes);
  };
  for (const linha of desenho.querySelectorAll('.barra-linha')) {
    linha.addEventListener('pointerenter', () => mostrar(linha));
    linha.addEventListener('focus', () => mostrar(linha));
    linha.addEventListener('pointerleave', () => dica.esconder());
    linha.addEventListener('blur', () => dica.esconder());
  }
}
