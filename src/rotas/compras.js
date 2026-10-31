// API da janela Comprar (POST /api/compras). A compra inteira acontece no
// banco, numa unica operacao: fn_comprar_anuncio (02_regras.sql).
import { Router } from 'express';
import { consultar } from '../banco.js';
import { inteiroObrigatorio, umDe } from '../parametros.js';
import { ErroApi } from '../erros.js';

const METODOS = ['pix', 'cartao_credito', 'cartao_debito', 'boleto', 'saldo_steam'];

export function rotasCompras() {
  const rotas = Router();

  // Corpo: { anuncio_id, comprador_id, metodo }
  // Resposta 201: { venda_id, protocolo, chave_nota_fiscal }
  rotas.post('/', async (req, res) => {
    const corpo = req.body ?? {};
    const metodo = umDe(corpo.metodo, METODOS, 'metodo');
    if (!metodo) throw new ErroApi(400, 'Escolha a forma de pagamento.');

    const [venda] = await consultar('comprar_anuncio', [
      inteiroObrigatorio(corpo.anuncio_id, 'o anúncio'),
      inteiroObrigatorio(corpo.comprador_id, 'o comprador'),
      metodo,
    ]);
    res.status(201).json(venda);
  });

  return rotas;
}
