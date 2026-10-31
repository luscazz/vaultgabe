-- =====================================================================
-- VAULTGABE - CONSULTAS DA PAGINA INVENTARIO ( /inventario )
-- e da janela Novo anuncio
-- Formato dos blocos: ver database/consultas/README.md
-- =====================================================================


-- name: resumo_inventario
-- Linha de resumo do topo da pagina e numero de itens de cada aba.
--   $1 usuario  INT
-- Abas: itens_<tipo> conta todos os itens do tipo; prontos_<tipo>, so os
-- que podem ser anunciados (caixa "So os que posso anunciar"). A aba Todos
-- usa itens e prontos_para_anunciar. Tipo e "pronto" seguem as mesmas
-- regras de inventario_usuario (tipo e pode_anunciar).
WITH itens AS (
    SELECT CASE WHEN e.item_instancia_id IS NOT NULL THEN 'equipamento'
                WHEN x.item_instancia_id IS NOT NULL THEN 'cosmetico'
                ELSE 'consumivel'
           END                                              AS tipo,
           (i.status_item = 'disponivel' AND i.tradable_flag) AS negociavel,
           a.id IS NOT NULL                                 AS anunciado
      FROM item_instancia i
      LEFT JOIN equipamento e ON e.item_instancia_id = i.id
      LEFT JOIN cosmetico x   ON x.item_instancia_id = i.id
      LEFT JOIN anuncio a     ON a.item_instancia_id = i.id
                             AND a.status_anuncio IN ('pendente', 'ativo')
     WHERE i.proprietario_id = $1::INT
)
SELECT COUNT(*)                                                 AS itens,
       COUNT(*) FILTER (WHERE negociavel)                       AS negociaveis,
       COUNT(*) FILTER (WHERE anunciado)                        AS anunciados,
       COUNT(*) FILTER (WHERE negociavel AND NOT anunciado)     AS prontos_para_anunciar,
       COUNT(*) FILTER (WHERE tipo = 'equipamento')             AS itens_equipamento,
       COUNT(*) FILTER (WHERE tipo = 'equipamento'
                          AND negociavel AND NOT anunciado)     AS prontos_equipamento,
       COUNT(*) FILTER (WHERE tipo = 'cosmetico')               AS itens_cosmetico,
       COUNT(*) FILTER (WHERE tipo = 'cosmetico'
                          AND negociavel AND NOT anunciado)     AS prontos_cosmetico,
       COUNT(*) FILTER (WHERE tipo = 'consumivel')              AS itens_consumivel,
       COUNT(*) FILTER (WHERE tipo = 'consumivel'
                          AND negociavel AND NOT anunciado)     AS prontos_consumivel
  FROM itens;


-- name: inventario_usuario
-- Itens do usuario, com os dados de cada subtipo e a situacao calculada.
--   $1 usuario          INT
--   $2 tipo             TEXT     'equipamento', 'cosmetico', 'consumivel' (NULL = todos)
--   $3 so_negociaveis   BOOLEAN  TRUE = so os que podem ser anunciados
-- situacao: 'anunciado', 'aplicado', 'consumido', 'bloqueado' ou 'disponivel'.
WITH itens AS (
    SELECT i.*,
           CASE WHEN e.item_instancia_id IS NOT NULL THEN 'equipamento'
                WHEN x.item_instancia_id IS NOT NULL THEN 'cosmetico'
                ELSE 'consumivel'
           END AS tipo
      FROM item_instancia i
      LEFT JOIN equipamento e ON e.item_instancia_id = i.id
      LEFT JOIN cosmetico x   ON x.item_instancia_id = i.id
     WHERE i.proprietario_id = $1::INT
)
SELECT i.id                       AS item_id,
       i.numero_inspecao,
       i.data_obtencao,
       i.tipo,
       ic.id                      AS modelo_id,
       ic.nome_item               AS nome,
       ic.imagem_base             AS imagem,
       c.nome_categoria           AS categoria,
       r.nome_raridade            AS raridade,
       r.cor_hexadecimal          AS cor_raridade,
       -- equipamento
       e.float_value,
       fn_desgaste(e.float_value) AS desgaste,
       e.paint_seed,
       e.stattrak_flag            AS stattrak,
       e.souvenir_flag            AS souvenir,
       cos.cosmeticos_aplicados,
       -- cosmetico
       x.tipo_cosmetico,
       arma.nome_item             AS aplicado_em,
       -- consumivel
       k.tipo_consumivel,
       k.lacrado,
       k.cargas_restantes,
       -- aberturas de caixas e capsulas
       ab_rec.data_abertura       AS aberto_em,
       res.nome_item              AS resultado_abertura,
       ab_chave.data_abertura     AS chave_usada_em,
       rec.nome_item              AS obtido_ao_abrir,
       -- negociacao
       i.status_item,
       i.tradable_flag            AS negociavel,
       a.id                       AS anuncio_id,
       a.preco                    AS preco_anunciado,
       CASE
           WHEN a.id IS NOT NULL               THEN 'anunciado'
           WHEN ac.cosmetico_id IS NOT NULL    THEN 'aplicado'
           WHEN i.status_item = 'consumido'    THEN 'consumido'
           WHEN i.status_item = 'bloqueado'
             OR NOT i.tradable_flag            THEN 'bloqueado'
           ELSE 'disponivel'
       END                        AS situacao,
       (a.id IS NULL AND i.status_item = 'disponivel' AND i.tradable_flag) AS pode_anunciar
  FROM itens i
  JOIN item_catalogo ic   ON ic.id = i.item_catalogo_id
  JOIN categoria_item c   ON c.id  = ic.categoria_id
  JOIN raridade r         ON r.id  = ic.raridade_id
  LEFT JOIN equipamento e ON e.item_instancia_id = i.id
  LEFT JOIN cosmetico x   ON x.item_instancia_id = i.id
  LEFT JOIN consumivel k  ON k.item_instancia_id = i.id
  LEFT JOIN anuncio a     ON a.item_instancia_id = i.id
                         AND a.status_anuncio IN ('pendente', 'ativo')
  -- se este item e um cosmetico aplicado: em qual arma
  LEFT JOIN aplicacao_cosmetico ac ON ac.cosmetico_id = i.id
  LEFT JOIN item_instancia arma_i  ON arma_i.id = ac.equipamento_id
  LEFT JOIN item_catalogo arma     ON arma.id   = arma_i.item_catalogo_id
  -- se este item e uma arma: quais cosmeticos estao aplicados nela
  CROSS JOIN LATERAL (
      SELECT string_agg(cc.nome_item, ', ' ORDER BY cc.nome_item) AS cosmeticos_aplicados
        FROM aplicacao_cosmetico ap
        JOIN item_instancia ci ON ci.id = ap.cosmetico_id
        JOIN item_catalogo cc  ON cc.id = ci.item_catalogo_id
       WHERE ap.equipamento_id = i.id
  ) cos
  -- se este item foi aberto, usado como chave ou obtido numa abertura
  LEFT JOIN abertura_recipiente ab_rec   ON ab_rec.recipiente_id     = i.id
  LEFT JOIN item_instancia res_i         ON res_i.id = ab_rec.item_resultado_id
  LEFT JOIN item_catalogo res            ON res.id   = res_i.item_catalogo_id
  LEFT JOIN abertura_recipiente ab_chave ON ab_chave.chave_id        = i.id
  LEFT JOIN abertura_recipiente ab_res   ON ab_res.item_resultado_id = i.id
  LEFT JOIN item_instancia rec_i         ON rec_i.id = ab_res.recipiente_id
  LEFT JOIN item_catalogo rec            ON rec.id   = rec_i.item_catalogo_id
 WHERE ($2::TEXT IS NULL OR i.tipo = $2::TEXT)
   AND ($3::BOOLEAN IS NOT TRUE
        OR (a.id IS NULL AND i.status_item = 'disponivel' AND i.tradable_flag))
 ORDER BY CASE i.tipo WHEN 'equipamento' THEN 1 WHEN 'cosmetico' THEN 2 ELSE 3 END,
          fn_sem_acento(ic.nome_item), ic.nome_item,
          i.numero_inspecao;


-- name: analise_preco_anuncio
-- Janela Novo anuncio, quadro "Analise de preco": compara o preco digitado
-- com as ofertas que podem ser compradas agora (sem as reservadas) e com a
-- media das vendas da mesma versao do item, ou de todo o modelo se houver
-- poucas (fn_media_vendas_comparaveis, a mesma conta da pagina da skin).
--   $1 item   INT      item que sera anunciado
--   $2 preco  NUMERIC  preco digitado (NULL = ainda nao digitado)
SELECT ic.nome_item                    AS nome,
       ofe.menor_preco_atual,
       ofe.ofertas_atuais,
       ROUND(ven.preco_medio, 2)       AS preco_medio_vendas,
       ven.preco_medio                 AS preco_medio_exato,   -- para a % igual a da pagina da skin
       ven.vendas,
       ven.base                        AS base_media,          -- 'versao' ou 'modelo'
       ROUND(($2::NUMERIC - ven.preco_medio) / ven.preco_medio * 100, 1) AS diferenca_media_pct
  FROM item_instancia i
  JOIN item_catalogo ic ON ic.id = i.item_catalogo_id
  CROSS JOIN LATERAL (
      SELECT MIN(oa.preco) AS menor_preco_atual,
             COUNT(*)      AS ofertas_atuais
        FROM vw_ofertas_ativas oa
       WHERE oa.modelo_id = ic.id
         AND oa.item_id  <> i.id
         AND NOT oa.reservada
  ) ofe
  CROSS JOIN LATERAL fn_media_vendas_comparaveis(i.id) ven
 WHERE i.id = $1::INT;


-- name: publicar_anuncio
-- Janela Novo anuncio, botao "Publicar". O anuncio nasce 'ativo'.
-- Dono, disponibilidade e "um anuncio aberto por item" sao conferidos
-- pelo banco (trg_validar_anuncio e anuncio_aberto_por_item_uk).
--   $1 item     INT
--   $2 usuario  INT      criador (usuario selecionado)
--   $3 preco    NUMERIC  maior que zero
--   $4 dias     INT      validade: 7, 14 ou 30
INSERT INTO anuncio (item_instancia_id, criador_id, data_publicacao, preco,
                     data_expiracao, status_anuncio)
VALUES ($1::INT, $2::INT, now(), $3::NUMERIC,
        now() + make_interval(days => $4::INT), 'ativo')
RETURNING id AS anuncio_id, data_publicacao, data_expiracao;
