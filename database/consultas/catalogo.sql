-- =====================================================================
-- VAULTGABE - CONSULTAS DA PAGINA CATALOGO ( / )
-- Formato dos blocos: ver database/consultas/README.md
-- =====================================================================


-- name: listar_categorias
-- Filtro "Categoria": categorias que tem modelos, com a quantidade.
SELECT c.id,
       c.nome_categoria AS nome,
       COUNT(ic.id)     AS modelos
  FROM categoria_item c
  JOIN item_catalogo ic ON ic.categoria_id = c.id
 GROUP BY c.id
 ORDER BY fn_sem_acento(c.nome_categoria);   -- ordem alfabetica, sem pesar acento


-- name: listar_raridades
-- Filtro "Raridade": raridades que tem modelos, com a cor e a quantidade.
SELECT r.id,
       r.nome_raridade   AS nome,
       r.cor_hexadecimal AS cor,
       COUNT(ic.id)      AS modelos
  FROM raridade r
  JOIN item_catalogo ic ON ic.raridade_id = r.id
 GROUP BY r.id
 ORDER BY r.id;


-- name: listar_colecoes
-- Filtro "Colecao": colecoes com a data de lancamento e a quantidade de modelos.
SELECT co.id,
       co.nome_colecao AS nome,
       co.data_lancamento,
       COUNT(ic.id)    AS modelos
  FROM colecao co
  JOIN item_catalogo ic ON ic.colecao_id = co.id
 GROUP BY co.id
 ORDER BY fn_sem_acento(co.nome_colecao);


-- name: buscar_catalogo
-- Busca principal do catalogo: um card por modelo, com o menor preco e o
-- numero de ofertas que podem ser compradas (sem as reservadas, que tem
-- venda pendente). Todos os filtros sao opcionais (NULL = desligado).
--
-- Filtros do MODELO:
--   $1  busca          TEXT     parte do nome, sem diferenciar maiusculas nem acentos
--   $2  categorias     INT[]    ids de categoria_item
--   $3  raridades      INT[]    ids de raridade
--   $4  colecao        INT      id de colecao
-- Filtros da OFERTA (o "a partir de" passa a considerar so as ofertas
-- que atendem; o modelo so aparece se tiver ao menos uma):
--   $5  preco_min      NUMERIC
--   $6  preco_max      NUMERIC
--   $7  so_a_venda     BOOLEAN  TRUE = so modelos com oferta que pode ser comprada
--   $8  desgastes      TEXT[]   'FN', 'MW', 'FT', 'WW', 'BS'
--   $9  stattrak       BOOLEAN  TRUE = so ofertas StatTrak
--   $10 souvenir       BOOLEAN  TRUE = so ofertas Souvenir
--   $11 com_adesivos   BOOLEAN  TRUE = so armas com cosmetico aplicado
-- Ordenacao:
--   $12 ordenar        TEXT     'menor_preco' (padrao), 'maior_preco',
--                               'mais_ofertas', 'mais_vendidas', 'nome'
WITH ofertas_filtradas AS (
    SELECT oa.modelo_id,
           oa.preco
      FROM vw_ofertas_ativas oa
      LEFT JOIN equipamento e ON e.item_instancia_id = oa.item_id
     WHERE NOT oa.reservada
       AND ($5::NUMERIC  IS NULL OR oa.preco >= $5::NUMERIC)
       AND ($6::NUMERIC  IS NULL OR oa.preco <= $6::NUMERIC)
       AND ($8::TEXT[]   IS NULL OR fn_desgaste(e.float_value) = ANY ($8::TEXT[]))
       AND ($9::BOOLEAN  IS NOT TRUE OR e.stattrak_flag)
       AND ($10::BOOLEAN IS NOT TRUE OR e.souvenir_flag)
       AND ($11::BOOLEAN IS NOT TRUE
            OR EXISTS (SELECT 1 FROM aplicacao_cosmetico ac
                        WHERE ac.equipamento_id = oa.item_id))
),
resumo_ofertas AS (
    SELECT modelo_id,
           MIN(preco) AS menor_preco,
           COUNT(*)   AS ofertas
      FROM ofertas_filtradas
     GROUP BY modelo_id
),
resumo_vendas AS (
    SELECT modelo_id,
           COUNT(*) AS vendas
      FROM vw_vendas_concluidas
     GROUP BY modelo_id
)
SELECT ic.id,
       ic.nome_item          AS nome,
       ic.imagem_base        AS imagem,
       c.nome_categoria      AS categoria,
       r.nome_raridade       AS raridade,
       r.cor_hexadecimal     AS cor_raridade,
       co.nome_colecao       AS colecao,
       ro.menor_preco,
       COALESCE(ro.ofertas, 0) AS ofertas,
       COALESCE(rv.vendas, 0)  AS vendas
  FROM item_catalogo ic
  JOIN categoria_item c      ON c.id  = ic.categoria_id
  JOIN raridade r            ON r.id  = ic.raridade_id
  LEFT JOIN colecao co       ON co.id = ic.colecao_id
  LEFT JOIN resumo_ofertas ro ON ro.modelo_id = ic.id
  LEFT JOIN resumo_vendas rv  ON rv.modelo_id = ic.id
 -- Busca: % e _ digitados valem como texto, nao como curinga do LIKE.
 WHERE ($1::TEXT  IS NULL
        OR fn_sem_acento(ic.nome_item) LIKE '%' || replace(replace(replace(fn_sem_acento($1::TEXT),
                                                    '\', '\\'), '%', '\%'), '_', '\_') || '%')
   AND ($2::INT[] IS NULL OR ic.categoria_id = ANY ($2::INT[]))
   AND ($3::INT[] IS NULL OR ic.raridade_id  = ANY ($3::INT[]))
   AND ($4::INT   IS NULL OR ic.colecao_id   = $4::INT)
   -- Com qualquer filtro da oferta ligado, so entram modelos com oferta que atende.
   AND (ro.ofertas IS NOT NULL
        OR NOT (COALESCE($7::BOOLEAN, FALSE)
                OR $5::NUMERIC IS NOT NULL OR $6::NUMERIC IS NOT NULL
                OR $8::TEXT[] IS NOT NULL
                OR $9::BOOLEAN IS TRUE OR $10::BOOLEAN IS TRUE OR $11::BOOLEAN IS TRUE))
 ORDER BY
       CASE WHEN COALESCE($12::TEXT, 'menor_preco') = 'menor_preco' THEN ro.menor_preco END ASC NULLS LAST,
       CASE WHEN $12::TEXT = 'maior_preco'   THEN ro.menor_preco END DESC NULLS LAST,
       CASE WHEN $12::TEXT = 'mais_ofertas'  THEN COALESCE(ro.ofertas, 0) END DESC,
       CASE WHEN $12::TEXT = 'mais_vendidas' THEN COALESCE(rv.vendas, 0) END DESC,
       fn_sem_acento(ic.nome_item),
       ic.nome_item;
