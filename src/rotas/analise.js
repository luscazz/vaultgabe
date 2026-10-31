// API da pagina Analise de mercado (/api/analise). Consultas em
// database/consultas/analise.sql.
import { Router } from 'express';
import { consultar, expirarAnunciosVencidos } from '../banco.js';
import { ErroApi } from '../erros.js';
import { data, inteiro } from '../parametros.js';

const LIMITE_RANKING = 10;

export function rotasAnalise() {
  const rotas = Router();

  // Indicadores, graficos e rankings. Parametros opcionais: inicio e fim
  // (AAAA-MM-DD, inclusive) e categoria. O ranking de vendedores nao usa os
  // filtros: considera todo o periodo e todas as categorias.
  rotas.get('/', async (req, res) => {
    const q = req.query;
    const inicio = data(q.inicio, 'inicio');
    const fim = data(q.fim, 'fim');
    if (inicio && fim && inicio > fim) throw new ErroApi(400, 'A data inicial precisa ser igual ou anterior à final.');
    const filtros = [inicio, fim, inteiro(q.categoria, 'categoria')];

    await expirarAnunciosVencidos();
    const [[indicadores], vendasPorMes, porRaridade, porCategoria, maisNegociadas, maioresVariacoes, vendedores] =
      await Promise.all([
        consultar('indicadores_gerais', filtros),
        consultar('vendas_por_mes', filtros),
        consultar('preco_medio_por_raridade', filtros),
        consultar('volume_por_categoria', filtros),
        consultar('mais_negociadas', [...filtros, LIMITE_RANKING]),
        consultar('maiores_variacoes', [...filtros, LIMITE_RANKING]),
        consultar('vendedores_mais_bem_avaliados', [LIMITE_RANKING]),
      ]);
    res.json({
      indicadores,
      vendas_por_mes: vendasPorMes,
      por_raridade: porRaridade,
      por_categoria: porCategoria,
      mais_negociadas: maisNegociadas,
      maiores_variacoes: maioresVariacoes,
      vendedores,
    });
  });

  return rotas;
}
