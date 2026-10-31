-- =====================================================================
-- VAULTGABE - CONSULTAS DA PAGINA NEGOCIACOES ( /negociacoes )
-- e da janela Avaliar vendedor
-- Formato dos blocos: ver database/consultas/README.md
-- =====================================================================


-- name: contar_negociacoes
-- Numeros das abas: A venda | Vendidos | Comprados | Encerrados.
--   $1 usuario  INT
SELECT (SELECT COUNT(*) FROM anuncio
         WHERE criador_id = $1::INT
           AND status_anuncio IN ('pendente', 'ativo'))      AS a_venda,
       (SELECT COUNT(*) FROM vw_vendas_concluidas
         WHERE vendedor_id = $1::INT)                        AS vendidos,
       (SELECT COUNT(*) FROM venda
         WHERE comprador_id = $1::INT)                       AS comprados,
       (SELECT COUNT(*) FROM anuncio
         WHERE criador_id = $1::INT
           AND status_anuncio IN ('cancelado', 'expirado'))  AS encerrados;


-- name: anuncios_a_venda
-- Aba "A venda": anuncios abertos do usuario. Quem tem venda pendente
-- nao pode ser cancelado (pode_cancelar = FALSE).
--   $1 usuario  INT
SELECT a.id                       AS anuncio_id,
       ic.id                      AS modelo_id,
       ic.nome_item               AS nome,
       ic.imagem_base             AS imagem,
       i.numero_inspecao,
       e.float_value,
       fn_desgaste(e.float_value) AS desgaste,
       a.preco,
       a.data_publicacao,
       a.data_expiracao,
       a.status_anuncio,
       vp.protocolo_venda         AS venda_pendente,
       (vp.id IS NULL)            AS pode_cancelar
  FROM anuncio a
  JOIN item_instancia i   ON i.id  = a.item_instancia_id
  JOIN item_catalogo ic   ON ic.id = i.item_catalogo_id
  LEFT JOIN equipamento e ON e.item_instancia_id = i.id
  LEFT JOIN venda vp      ON vp.anuncio_id = a.id
                         AND vp.status_venda = 'pendente'
 WHERE a.criador_id = $1::INT
   AND a.status_anuncio IN ('pendente', 'ativo')
 ORDER BY a.data_publicacao DESC;


-- name: anuncios_vendidos
-- Aba "Vendidos": vendas concluidas em que o usuario foi o vendedor.
--   $1 usuario  INT
SELECT vc.venda_id,
       vc.protocolo,
       vc.data_venda,
       vc.valor,
       ic.id          AS modelo_id,
       ic.nome_item   AS nome,
       ic.imagem_base AS imagem,
       i.numero_inspecao,
       e.float_value,
       fn_desgaste(e.float_value) AS desgaste,
       comp.id        AS comprador_id,
       comp.apelido   AS comprador,
       p.metodo_pagamento,
       n.chave        AS chave_nota_fiscal
  FROM vw_vendas_concluidas vc
  JOIN item_instancia i   ON i.id    = vc.item_id
  JOIN item_catalogo ic   ON ic.id   = vc.modelo_id
  JOIN usuario comp       ON comp.id = vc.comprador_id
  JOIN pagamento p        ON p.venda_id = vc.venda_id
  LEFT JOIN nota_fiscal n ON n.venda_id = vc.venda_id
  LEFT JOIN equipamento e ON e.item_instancia_id = i.id
 WHERE vc.vendedor_id = $1::INT
 ORDER BY vc.data_venda DESC;


-- name: compras_do_usuario
-- Aba "Comprados": todas as compras do usuario (inclusive pendentes e
-- canceladas), com pagamento, nota fiscal e se ja avaliou o vendedor.
--   $1 usuario  INT
SELECT v.id                    AS venda_id,
       v.protocolo_venda       AS protocolo,
       v.data_venda,
       v.valor_venda           AS valor,
       v.status_venda,
       ic.id                   AS modelo_id,
       ic.nome_item            AS nome,
       ic.imagem_base          AS imagem,
       i.numero_inspecao,
       e.float_value,
       fn_desgaste(e.float_value) AS desgaste,
       vend.id                 AS vendedor_id,
       vend.apelido            AS vendedor,
       p.metodo_pagamento,
       p.status_pagamento,
       n.chave                 AS chave_nota_fiscal,
       aval.ja_avaliou,
       (v.status_venda = 'concluida' AND NOT aval.ja_avaliou) AS pode_avaliar
  FROM venda v
  JOIN anuncio a          ON a.id    = v.anuncio_id
  JOIN item_instancia i   ON i.id    = a.item_instancia_id
  JOIN item_catalogo ic   ON ic.id   = i.item_catalogo_id
  JOIN usuario vend       ON vend.id = a.criador_id
  JOIN pagamento p        ON p.venda_id = v.id
  LEFT JOIN nota_fiscal n ON n.venda_id = v.id
  LEFT JOIN equipamento e ON e.item_instancia_id = i.id
  CROSS JOIN LATERAL (
      SELECT EXISTS (SELECT 1
                       FROM avaliacao_venda av
                       JOIN avaliacao x ON x.id = av.avaliacao_id
                      WHERE av.venda_id = v.id
                        AND x.autor_id  = $1::INT) AS ja_avaliou
  ) aval
 WHERE v.comprador_id = $1::INT
 ORDER BY v.data_venda DESC;


-- name: anuncios_encerrados
-- Aba "Encerrados": anuncios cancelados e expirados do usuario.
--   $1 usuario  INT
SELECT a.id           AS anuncio_id,
       ic.id          AS modelo_id,
       ic.nome_item   AS nome,
       ic.imagem_base AS imagem,
       i.numero_inspecao,
       e.float_value,
       fn_desgaste(e.float_value) AS desgaste,
       a.preco,
       a.data_publicacao,
       a.data_expiracao,
       a.status_anuncio
  FROM anuncio a
  JOIN item_instancia i   ON i.id  = a.item_instancia_id
  JOIN item_catalogo ic   ON ic.id = i.item_catalogo_id
  LEFT JOIN equipamento e ON e.item_instancia_id = i.id
 WHERE a.criador_id = $1::INT
   AND a.status_anuncio IN ('cancelado', 'expirado')
 ORDER BY a.data_publicacao DESC;


-- name: cancelar_anuncio
-- Aba "A venda", botao "Cancelar". So o criador cancela, e so anuncio
-- aberto; nenhuma linha retornada = anuncio inexistente, de outro usuario
-- ou ja encerrado. Venda pendente e bloqueada pelo trg_transicao_anuncio.
--   $1 anuncio  INT
--   $2 usuario  INT
UPDATE anuncio
   SET status_anuncio = 'cancelado'
 WHERE id = $1::INT
   AND criador_id = $2::INT
   AND status_anuncio IN ('pendente', 'ativo')
RETURNING id AS anuncio_id;


-- name: avaliar_vendedor
-- Janela Avaliar vendedor (ver fn_avaliar_venda em 02_regras.sql).
--   $1 venda       INT
--   $2 autor       INT      usuario selecionado
--   $3 nota        INT      1 a 5
--   $4 comentario  TEXT     opcional
-- Retorna: o ticket da avaliacao.
SELECT fn_avaliar_venda($1::INT, $2::INT, $3::INT, $4::TEXT) AS ticket;
