// API da pagina Detalhe da skin (/api/skins/:id). Consultas em
// database/consultas/detalhe_skin.sql.
import { Router } from 'express';
import { consultar, expirarAnunciosVencidos } from '../banco.js';
import { ErroApi } from '../erros.js';
import { DESGASTES, inteiro, inteiroObrigatorio, marcado, umDe, listaDe } from '../parametros.js';

export function rotasSkins() {
  const rotas = Router();

  // Cabecalho: dados do modelo, menor preco e resumo das vendas.
  rotas.get('/:id', async (req, res) => {
    const id = inteiroObrigatorio(req.params.id, 'o id da skin');
    await expirarAnunciosVencidos();
    const [modelo] = await consultar('detalhe_modelo', [id]);
    if (!modelo) throw new ErroApi(404, 'Skin não encontrada.');
    res.json(modelo);
  });

  // Ofertas ativas do modelo. Parametros opcionais: desgaste (varios),
  // stattrak, souvenir, com_adesivos, ordenar (preco | float) e usuario (o
  // usuario selecionado, para marcar as proprias ofertas).
  rotas.get('/:id/ofertas', async (req, res) => {
    const q = req.query;
    const parametros = [
      inteiroObrigatorio(req.params.id, 'o id da skin'),
      listaDe(q.desgaste, DESGASTES, 'desgaste'),
      marcado(q.stattrak),
      marcado(q.souvenir),
      marcado(q.com_adesivos),
      umDe(q.ordenar, ['preco', 'float'], 'ordenar', 'preco'),
      inteiro(q.usuario, 'usuario'),
    ];
    await expirarAnunciosVencidos();
    res.json(await consultar('ofertas_do_modelo', parametros));
  });

  // Precos registrados: vendas concluidas e o resumo por mes.
  rotas.get('/:id/historico', async (req, res) => {
    const id = inteiroObrigatorio(req.params.id, 'o id da skin');
    const [vendas, porMes] = await Promise.all([
      consultar('historico_vendas_modelo', [id]),
      consultar('precos_por_mes_modelo', [id]),
    ]);
    res.json({ vendas, por_mes: porMes });
  });

  return rotas;
}
