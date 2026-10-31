-- =====================================================================
-- VAULTGABE - CONSULTAS DA PAGINA DETALHE DA SKIN ( /skin/:id )
-- e da janela Comprar
-- Formato dos blocos: ver database/consultas/README.md
-- =====================================================================


-- name: detalhe_modelo
-- Cabecalho da pagina: dados do modelo, menor preco e resumo das vendas.
--   $1 modelo  INT  id de item_catalogo
-- "tipo" define quais colunas a pagina mostra nas ofertas. menor_preco e
-- ofertas contam so o que pode ser comprado (sem as reservadas); a media
-- das vendas e a do modelo inteiro, de todas as versoes.
SELECT ic.id,
       ic.nome_item          AS nome,
       ic.descricao,
       ic.imagem_base        AS imagem,
       c.nome_categoria      AS categoria,
       r.nome_raridade       AS raridade,
       r.cor_hexadecimal     AS cor_raridade,
       co.nome_colecao       AS colecao,
       co.data_lancamento    AS lancamento_colecao,
       ic.float_min,
       ic.float_max,
       CASE
           WHEN ic.float_min IS NOT NULL THEN 'equipamento'
           WHEN EXISTS (SELECT 1 FROM item_instancia i
                          JOIN cosmetico x ON x.item_instancia_id = i.id
                         WHERE i.item_catalogo_id = ic.id) THEN 'cosmetico'
           ELSE 'consumivel'
       END                   AS tipo,
       ofe.menor_preco,
       ofe.ofertas,
       ven.preco_medio,
       ven.vendas,
       ven.ultima_venda
  FROM item_catalogo ic
  JOIN categoria_item c ON c.id  = ic.categoria_id
  JOIN raridade r       ON r.id  = ic.raridade_id
  LEFT JOIN colecao co  ON co.id = ic.colecao_id
  CROSS JOIN LATERAL (
      SELECT MIN(oa.preco) AS menor_preco,
             COUNT(*)      AS ofertas
        FROM vw_ofertas_ativas oa
       WHERE oa.modelo_id = ic.id
         AND NOT oa.reservada
  ) ofe
  CROSS JOIN LATERAL (
      SELECT ROUND(AVG(vc.valor), 2) AS preco_medio,
             COUNT(*)                AS vendas,
             MAX(vc.data_venda)      AS ultima_venda
        FROM vw_vendas_concluidas vc
       WHERE vc.modelo_id = ic.id
  ) ven
 WHERE ic.id = $1::INT;


-- name: ofertas_do_modelo
-- Tabela "Anuncios ativos": cada oferta (inclusive as reservadas) com as
-- caracteristicas do item, a reputacao do vendedor e a analise de preco:
-- diferenca para a media das vendas da mesma versao do item, ou de todo o
-- modelo se houver poucas (fn_media_vendas_comparaveis; base_media diz qual).
--   $1 modelo        INT      id de item_catalogo
--   $2 desgastes     TEXT[]   'FN', 'MW', 'FT', 'WW', 'BS' (NULL = todos)
--   $3 stattrak      BOOLEAN  TRUE = so StatTrak
--   $4 souvenir      BOOLEAN  TRUE = so Souvenir
--   $5 com_adesivos  BOOLEAN  TRUE = so com cosmetico aplicado
--   $6 ordenar       TEXT     'preco' (padrao) ou 'float'
--   $7 usuario       INT      usuario selecionado: marca as proprias ofertas
SELECT oa.anuncio_id,
       oa.preco,
       oa.data_publicacao,
       oa.data_expiracao,
       oa.item_id,
       oa.numero_inspecao,
       e.float_value,
       fn_desgaste(e.float_value)      AS desgaste,
       fn_desgaste_nome(e.float_value) AS desgaste_nome,
       e.paint_seed,
       e.stattrak_flag                 AS stattrak,
       e.souvenir_flag                 AS souvenir,
       cos.cosmeticos_aplicados,
       x.tipo_cosmetico,
       k.tipo_consumivel,
       k.lacrado,
       k.cargas_restantes,
       u.id                            AS vendedor_id,
       u.apelido                       AS vendedor,
       u.steam_guard_ativo             AS vendedor_steam_guard,  -- sem ele, a Steam retem a troca por ate 15 dias
       rep.nota_media                  AS nota_vendedor,
       COALESCE(rep.avaliacoes, 0)     AS avaliacoes_vendedor,
       COALESCE(u.id = $7::INT, FALSE) AS e_minha,
       oa.reservada,                   -- venda pendente: nao pode ser comprada agora
       ROUND(m.preco_medio, 2)         AS preco_medio_comparavel,
       m.vendas                        AS vendas_comparaveis,
       m.base                          AS base_media,           -- 'versao' ou 'modelo'
       ROUND((oa.preco - m.preco_medio) / m.preco_medio * 100, 1) AS diferenca_media_pct
  FROM vw_ofertas_ativas oa
  JOIN usuario u             ON u.id = oa.vendedor_id
  LEFT JOIN equipamento e    ON e.item_instancia_id = oa.item_id
  LEFT JOIN cosmetico x      ON x.item_instancia_id = oa.item_id
  LEFT JOIN consumivel k     ON k.item_instancia_id = oa.item_id
  LEFT JOIN vw_reputacao rep ON rep.usuario_id = u.id
  CROSS JOIN LATERAL fn_media_vendas_comparaveis(oa.item_id) m
  CROSS JOIN LATERAL (
      SELECT string_agg(cc.nome_item, ', ' ORDER BY cc.nome_item) AS cosmeticos_aplicados,
             COUNT(*)                                             AS qtd
        FROM aplicacao_cosmetico ac
        JOIN item_instancia ci ON ci.id = ac.cosmetico_id
        JOIN item_catalogo cc  ON cc.id = ci.item_catalogo_id
       WHERE ac.equipamento_id = oa.item_id
  ) cos
 WHERE oa.modelo_id = $1::INT
   AND ($2::TEXT[]  IS NULL OR fn_desgaste(e.float_value) = ANY ($2::TEXT[]))
   AND ($3::BOOLEAN IS NOT TRUE OR e.stattrak_flag)
   AND ($4::BOOLEAN IS NOT TRUE OR e.souvenir_flag)
   AND ($5::BOOLEAN IS NOT TRUE OR cos.qtd > 0)
 ORDER BY CASE WHEN $6::TEXT = 'float' THEN e.float_value END ASC NULLS LAST,
          oa.preco ASC;


-- name: historico_vendas_modelo
-- Tabela "Historico de vendas": vendas concluidas do modelo, da mais recente.
--   $1 modelo  INT  id de item_catalogo
SELECT vc.protocolo,
       vc.data_venda,
       vc.valor,
       e.float_value,
       fn_desgaste(e.float_value) AS desgaste,
       vend.apelido               AS vendedor,
       comp.apelido               AS comprador
  FROM vw_vendas_concluidas vc
  JOIN usuario vend       ON vend.id = vc.vendedor_id
  JOIN usuario comp       ON comp.id = vc.comprador_id
  LEFT JOIN equipamento e ON e.item_instancia_id = vc.item_id
 WHERE vc.modelo_id = $1::INT
 ORDER BY vc.data_venda DESC;


-- name: precos_por_mes_modelo
-- Grafico "preco ao longo do tempo": um ponto por mes com vendas.
--   $1 modelo  INT  id de item_catalogo
SELECT date_trunc('month', vc.data_venda)::DATE AS mes,
       ROUND(AVG(vc.valor), 2)                 AS preco_medio,
       MIN(vc.valor)                           AS menor_preco,
       MAX(vc.valor)                           AS maior_preco,
       COUNT(*)                                AS vendas
  FROM vw_vendas_concluidas vc
 WHERE vc.modelo_id = $1::INT
 GROUP BY 1
 ORDER BY 1;


-- name: comprar_anuncio
-- Janela Comprar: compra completa e atomica (ver fn_comprar_anuncio em
-- 02_regras.sql). Erros de regra voltam como mensagem para o usuario.
--   $1 anuncio    INT
--   $2 comprador  INT
--   $3 metodo     VARCHAR  'pix', 'cartao_credito', 'cartao_debito', 'boleto', 'saldo_steam'
-- Retorna: venda_id, protocolo, chave_nota_fiscal.
SELECT *
  FROM fn_comprar_anuncio($1::INT, $2::INT, $3::VARCHAR);
