-- =====================================================================
-- VAULTGABE - CONSULTAS DA PAGINA ANALISE DE MERCADO ( /analise )
-- Formato dos blocos: ver database/consultas/README.md
--
-- Filtros comuns (todos opcionais, NULL = sem filtro):
--   $1 inicio     DATE  primeiro dia do periodo
--   $2 fim        DATE  ultimo dia do periodo (inclusive)
--   $3 categoria  INT   id de categoria_item
-- =====================================================================


-- name: indicadores_gerais
-- Cartoes do topo: vendas, volume, ticket medio e ofertas (compradores e
-- vendedores tambem vem na resposta).
-- ultima_venda ('AAAA-MM-DD', NULL sem vendas) e a data da venda concluida
-- mais recente de todo o historico, sem os filtros: a pagina conta os
-- periodos prontos ("Ultimos 30 dias"...) ate ela quando e anterior a hoje.
SELECT COUNT(*)                        AS vendas,
       COALESCE(SUM(vc.valor), 0)      AS volume,
       ROUND(AVG(vc.valor), 2)         AS ticket_medio,
       COUNT(DISTINCT vc.comprador_id) AS compradores,
       COUNT(DISTINCT vc.vendedor_id)  AS vendedores,
       (SELECT COUNT(*)
          FROM vw_ofertas_ativas oa
          JOIN item_catalogo ic ON ic.id = oa.modelo_id
         WHERE NOT oa.reservada
           AND ($3::INT IS NULL OR ic.categoria_id = $3::INT)) AS ofertas_ativas,
       (SELECT TO_CHAR(MAX(todas.data_venda), 'YYYY-MM-DD')
          FROM vw_vendas_concluidas todas) AS ultima_venda
  FROM vw_vendas_concluidas vc
 WHERE ($1::DATE IS NULL OR vc.data_venda >= $1::DATE)
   AND ($2::DATE IS NULL OR vc.data_venda <  $2::DATE + 1)
   AND ($3::INT  IS NULL OR vc.categoria_id = $3::INT);


-- name: vendas_por_mes
-- Grafico de vendas e volume por mes.
SELECT date_trunc('month', vc.data_venda)::DATE AS mes,
       COUNT(*)                                AS vendas,
       SUM(vc.valor)                           AS volume,
       ROUND(AVG(vc.valor), 2)                 AS preco_medio
  FROM vw_vendas_concluidas vc
 WHERE ($1::DATE IS NULL OR vc.data_venda >= $1::DATE)
   AND ($2::DATE IS NULL OR vc.data_venda <  $2::DATE + 1)
   AND ($3::INT  IS NULL OR vc.categoria_id = $3::INT)
 GROUP BY 1
 ORDER BY 1;


-- name: preco_medio_por_raridade
-- Grafico de preco medio por raridade (com a cor da raridade).
SELECT r.nome_raridade          AS raridade,
       r.cor_hexadecimal        AS cor,
       COUNT(*)                 AS vendas,
       ROUND(AVG(vc.valor), 2)  AS preco_medio,
       SUM(vc.valor)            AS volume
  FROM vw_vendas_concluidas vc
  JOIN raridade r ON r.id = vc.raridade_id
 WHERE ($1::DATE IS NULL OR vc.data_venda >= $1::DATE)
   AND ($2::DATE IS NULL OR vc.data_venda <  $2::DATE + 1)
   AND ($3::INT  IS NULL OR vc.categoria_id = $3::INT)
 GROUP BY r.id
 ORDER BY preco_medio DESC;


-- name: volume_por_categoria
-- Grafico de volume negociado por categoria.
SELECT c.nome_categoria         AS categoria,
       COUNT(*)                 AS vendas,
       SUM(vc.valor)            AS volume,
       ROUND(AVG(vc.valor), 2)  AS preco_medio
  FROM vw_vendas_concluidas vc
  JOIN categoria_item c ON c.id = vc.categoria_id
 WHERE ($1::DATE IS NULL OR vc.data_venda >= $1::DATE)
   AND ($2::DATE IS NULL OR vc.data_venda <  $2::DATE + 1)
   AND ($3::INT  IS NULL OR vc.categoria_id = $3::INT)
 GROUP BY c.id
 ORDER BY volume DESC;


-- name: mais_negociadas
-- Ranking das skins mais vendidas no periodo.
--   $4 limite  INT  quantas linhas (padrao 10)
SELECT ic.id                    AS modelo_id,
       ic.nome_item             AS nome,
       r.cor_hexadecimal        AS cor_raridade,
       COUNT(*)                 AS vendas,
       SUM(vc.valor)            AS volume,
       ROUND(AVG(vc.valor), 2)  AS preco_medio
  FROM vw_vendas_concluidas vc
  JOIN item_catalogo ic ON ic.id = vc.modelo_id
  JOIN raridade r       ON r.id  = ic.raridade_id
 WHERE ($1::DATE IS NULL OR vc.data_venda >= $1::DATE)
   AND ($2::DATE IS NULL OR vc.data_venda <  $2::DATE + 1)
   AND ($3::INT  IS NULL OR vc.categoria_id = $3::INT)
 GROUP BY ic.id, r.id
 ORDER BY vendas DESC, volume DESC, ic.nome_item
 LIMIT COALESCE($4::INT, 10);


-- name: maiores_variacoes
-- Ranking das maiores variacoes de preco no periodo: compara a primeira
-- e a ultima venda de cada modelo (so modelos com 2 ou mais vendas).
--   $4 limite  INT  quantas linhas (padrao 10)
WITH serie AS (
    SELECT vc.modelo_id,
           FIRST_VALUE(vc.valor) OVER janela AS primeiro_preco,
           LAST_VALUE(vc.valor)  OVER janela AS ultimo_preco
      FROM vw_vendas_concluidas vc
     WHERE ($1::DATE IS NULL OR vc.data_venda >= $1::DATE)
       AND ($2::DATE IS NULL OR vc.data_venda <  $2::DATE + 1)
       AND ($3::INT  IS NULL OR vc.categoria_id = $3::INT)
    WINDOW janela AS (PARTITION BY vc.modelo_id
                      ORDER BY vc.data_venda
                      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
)
SELECT ic.id                  AS modelo_id,
       ic.nome_item           AS nome,
       COUNT(*)               AS vendas,
       MAX(s.primeiro_preco)  AS primeiro_preco,
       MAX(s.ultimo_preco)    AS ultimo_preco,
       ROUND((MAX(s.ultimo_preco) - MAX(s.primeiro_preco))
             / MAX(s.primeiro_preco) * 100, 1) AS variacao_pct
  FROM serie s
  JOIN item_catalogo ic ON ic.id = s.modelo_id
 GROUP BY ic.id
HAVING COUNT(*) >= 2
 ORDER BY ABS(MAX(s.ultimo_preco) - MAX(s.primeiro_preco)) / MAX(s.primeiro_preco) DESC,
          ic.nome_item
 LIMIT COALESCE($4::INT, 10);


-- name: vendedores_mais_bem_avaliados
-- Ranking de reputacao COMO VENDEDOR: so notas recebidas dos compradores
-- (avaliacao_venda com avaliado = criador do anuncio); notas de troca e as
-- que ele recebeu como comprador ficam de fora. Nao usa os filtros comuns.
--   $1 limite  INT  quantas linhas (padrao 10)
WITH notas_de_venda AS (
    SELECT a.criador_id AS vendedor_id,
           x.nota
      FROM avaliacao_venda av
      JOIN avaliacao x ON x.id = av.avaliacao_id
      JOIN venda v     ON v.id = av.venda_id
      JOIN anuncio a   ON a.id = v.anuncio_id
     WHERE x.avaliado_id = a.criador_id
)
SELECT u.id                       AS usuario_id,
       u.apelido,
       ROUND(AVG(n.nota), 1)      AS nota_media,
       COUNT(*)                   AS avaliacoes,
       (SELECT COUNT(*) FROM vw_vendas_concluidas vc
         WHERE vc.vendedor_id = u.id) AS vendas
  FROM notas_de_venda n
  JOIN usuario u ON u.id = n.vendedor_id
 GROUP BY u.id
 ORDER BY AVG(n.nota) DESC, COUNT(*) DESC, u.apelido   -- media exata, nao a arredondada
 LIMIT COALESCE($1::INT, 10);
