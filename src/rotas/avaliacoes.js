// API da janela Avaliar vendedor (POST /api/avaliacoes). A avaliacao e o
// vinculo com a venda sao gravados juntos por fn_avaliar_venda (02_regras.sql).
import { Router } from 'express';
import { consultar } from '../banco.js';
import { ErroApi } from '../erros.js';
import { inteiro, inteiroObrigatorio, texto } from '../parametros.js';

export function rotasAvaliacoes() {
  const rotas = Router();

  // Corpo: { venda_id, autor_id, nota (1 a 5), comentario (opcional) }
  // Resposta 201: { ticket }
  rotas.post('/', async (req, res) => {
    const corpo = req.body ?? {};
    const nota = inteiro(corpo.nota, 'nota');
    if (nota === null || nota < 1 || nota > 5) throw new ErroApi(400, 'Escolha uma nota de 1 a 5.');

    const [avaliacao] = await consultar('avaliar_vendedor', [
      inteiroObrigatorio(corpo.venda_id, 'a compra'),
      inteiroObrigatorio(corpo.autor_id, 'o autor'),
      nota,
      texto(corpo.comentario, 500),
    ]);
    res.status(201).json(avaliacao);
  });

  return rotas;
}
