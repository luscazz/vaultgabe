// API dos anuncios: analise de preco e publicacao (janela Novo anuncio, no
// Inventario) e cancelamento (Negociacoes). Consultas em
// database/consultas/inventario.sql e negociacoes.sql.
// Dono do item, disponibilidade e "um anuncio aberto por item" sao
// conferidos pelo proprio banco (trigger e indice unico).
import { Router } from 'express';
import { consultar, expirarAnunciosVencidos } from '../banco.js';
import { ErroApi } from '../erros.js';
import { inteiroObrigatorio, numero, preco, umDe } from '../parametros.js';

const VALIDADES = ['7', '14', '30']; // dias

export function rotasAnuncios() {
  const rotas = Router();

  // Quadro "Analise de preco": ofertas atuais (sem as reservadas) e media das
  // vendas comparaveis do item (fn_media_vendas_comparaveis). Parametros: item (obrigatorio) e preco (opcional).
  rotas.get('/analise-preco', async (req, res) => {
    const item = inteiroObrigatorio(req.query.item, 'o item');
    await expirarAnunciosVencidos();
    const [analise] = await consultar('analise_preco_anuncio', [item, numero(req.query.preco, 'preco')]);
    if (!analise) throw new ErroApi(404, 'Item não encontrado.');
    res.json(analise);
  });

  // Publicar. Corpo: { item_id, usuario_id, preco, dias }
  // Resposta 201: { anuncio_id, data_publicacao, data_expiracao }
  rotas.post('/', async (req, res) => {
    const corpo = req.body ?? {};
    const item = inteiroObrigatorio(corpo.item_id, 'o item');
    const usuario = inteiroObrigatorio(corpo.usuario_id, 'o usuário');
    const valor = preco(corpo.preco);
    const dias = umDe(corpo.dias, VALIDADES, 'validade');
    if (!dias) throw new ErroApi(400, 'Escolha a validade: 7, 14 ou 30 dias.');

    // Um anuncio vencido ainda marcado como ativo bloquearia o novo.
    await expirarAnunciosVencidos();
    const [anuncio] = await consultar('publicar_anuncio', [item, usuario, valor, Number(dias)]);
    res.status(201).json(anuncio);
  });

  // Cancelar. Corpo: { usuario_id } (so o criador cancela).
  rotas.post('/:id/cancelar', async (req, res) => {
    const [cancelado] = await consultar('cancelar_anuncio', [
      inteiroObrigatorio(req.params.id, 'o anúncio'),
      inteiroObrigatorio(req.body?.usuario_id, 'o usuário'),
    ]);
    if (!cancelado) throw new ErroApi(409, 'Este anúncio não está mais aberto ou não é seu.');
    res.json(cancelado);
  });

  return rotas;
}
