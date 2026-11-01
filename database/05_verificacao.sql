-- =====================================================================
-- VAULTGABE
-- 05 - VERIFICACAO: auditoria e validacao dos dados
--
-- Confere as contagens de referencia e as regras semanticas que o SGBD
-- nao garante sozinho.
--
-- COMO USAR:
--   Rode depois de 01 a 04 (ou de 01 a 03). So tem SELECTs: funciona em
--   qualquer cliente (pgAdmin, DataGrip ou psql).
--
-- COMO LER:
--   As colunas "situacao" (contagens) e "resultado" (regras) devem ser
--   OK em todas as linhas; outro valor indica dado incoerente.
-- =====================================================================


-- ==========================================================
--  1. CONTAGEM DE TUPLAS
-- ==========================================================

WITH contagens (tabela, qtd, minimo, origem) AS (
    SELECT 'categoria_item',      COUNT(*), 10, 'entidade'         FROM categoria_item
    UNION ALL SELECT 'raridade',            COUNT(*), 10, 'entidade'         FROM raridade
    UNION ALL SELECT 'colecao',             COUNT(*), 10, 'entidade'         FROM colecao
    UNION ALL SELECT 'usuario',             COUNT(*), 10, 'entidade'         FROM usuario
    UNION ALL SELECT 'item_catalogo',       COUNT(*), 10, 'entidade'         FROM item_catalogo
    UNION ALL SELECT 'item_instancia',      COUNT(*), 30, 'entidade (*)'     FROM item_instancia
    UNION ALL SELECT 'cosmetico',           COUNT(*), 10, 'especializacao'   FROM cosmetico
    UNION ALL SELECT 'equipamento',         COUNT(*), 10, 'especializacao'   FROM equipamento
    UNION ALL SELECT 'consumivel',          COUNT(*), 10, 'especializacao'   FROM consumivel
    UNION ALL SELECT 'abertura_recipiente', COUNT(*),  5, 'extra'            FROM abertura_recipiente
    UNION ALL SELECT 'aplicacao_cosmetico', COUNT(*),  5, 'relacionamento'   FROM aplicacao_cosmetico
    UNION ALL SELECT 'anuncio',             COUNT(*), 10, 'entidade fraca'   FROM anuncio
    UNION ALL SELECT 'venda',               COUNT(*), 10, 'entidade'         FROM venda
    UNION ALL SELECT 'pagamento',           COUNT(*), 10, 'entidade fraca'   FROM pagamento
    UNION ALL SELECT 'nota_fiscal',         COUNT(*), 10, 'entidade'         FROM nota_fiscal
    UNION ALL SELECT 'troca',               COUNT(*), 10, 'entidade'         FROM troca
    UNION ALL SELECT 'troca_item',          COUNT(*),  5, 'relacionamento'   FROM troca_item
    UNION ALL SELECT 'avaliacao',           COUNT(*), 10, 'entidade'         FROM avaliacao
    UNION ALL SELECT 'avaliacao_venda',     COUNT(*),  5, 'subtipo'          FROM avaliacao_venda
    UNION ALL SELECT 'avaliacao_troca',     COUNT(*),  5, 'subtipo'          FROM avaliacao_troca
)
SELECT
    tabela,
    origem,
    qtd,
    minimo,
    CASE WHEN qtd >= minimo THEN 'OK' ELSE 'FALTAM ' || (minimo - qtd) END AS situacao
FROM contagens
ORDER BY tabela;

-- (*) item_instancia precisa de 30, e nao 10: a especializacao e
--     TOTAL e DISJUNTA, e cada um dos 3 subtipos exige 10 tuplas.



-- ==========================================================
--  2. REGRAS SEMANTICAS (as que CHECK/FK nao garantem)
-- ==========================================================

WITH violacoes (regra, descricao, qtd) AS (
    SELECT 'RS-01', 'Especializacao TOTAL: toda instancia em algum subtipo', COUNT(*)
      FROM item_instancia i
     WHERE NOT EXISTS (SELECT 1 FROM cosmetico   c WHERE c.item_instancia_id = i.id)
       AND NOT EXISTS (SELECT 1 FROM equipamento e WHERE e.item_instancia_id = i.id)
       AND NOT EXISTS (SELECT 1 FROM consumivel  k WHERE k.item_instancia_id = i.id)

    UNION ALL
    SELECT 'RS-02', 'Especializacao DISJUNTA: nenhuma instancia em 2+ subtipos', COUNT(*)
      FROM (
        SELECT i.id,
               (SELECT COUNT(*) FROM cosmetico   c WHERE c.item_instancia_id = i.id)
             + (SELECT COUNT(*) FROM equipamento e WHERE e.item_instancia_id = i.id)
             + (SELECT COUNT(*) FROM consumivel  k WHERE k.item_instancia_id = i.id) AS n
          FROM item_instancia i
      ) t WHERE n <> 1

    UNION ALL
    SELECT 'RS-03', 'Maximo 6 cosmeticos por equipamento (o (0,6) do MER)', COUNT(*)
      FROM (SELECT equipamento_id FROM aplicacao_cosmetico
             GROUP BY equipamento_id HAVING COUNT(*) > 6) t

    UNION ALL
    -- RS-04 e RS-07 valem para a transferencia MAIS RECENTE do item: se
    -- ele foi revendido ou trocado depois, o dono atual e o da operacao
    -- seguinte.
    SELECT 'RS-04', 'Venda concluida: item pertence ao comprador', COUNT(*)
      FROM venda v
      JOIN anuncio a        ON a.id = v.anuncio_id
      JOIN item_instancia i ON i.id = a.item_instancia_id
     WHERE v.status_venda = 'concluida'
       AND i.proprietario_id <> v.comprador_id
       AND NOT EXISTS (SELECT 1 FROM venda v2
                         JOIN anuncio a2 ON a2.id = v2.anuncio_id
                        WHERE a2.item_instancia_id = i.id
                          AND v2.status_venda = 'concluida'
                          AND v2.data_venda > v.data_venda)
       AND NOT EXISTS (SELECT 1 FROM troca_item x
                         JOIN troca t2 ON t2.id = x.troca_id
                        WHERE x.item_instancia_id = i.id
                          AND t2.status_troca = 'concluida'
                          AND t2.data_efetivacao > v.data_venda)

    UNION ALL
    SELECT 'RS-05', 'Comprador nunca e o criador do anuncio', COUNT(*)
      FROM venda v
      JOIN anuncio a ON a.id = v.anuncio_id
     WHERE v.comprador_id = a.criador_id

    UNION ALL
    SELECT 'RS-06', 'Toda venda tem exatamente 1 pagamento (REGISTRA 1:1 total)', COUNT(*)
      FROM venda v
     WHERE NOT EXISTS (SELECT 1 FROM pagamento p WHERE p.venda_id = v.id)

    UNION ALL
    SELECT 'RS-07', 'Troca concluida: oferecidos com o destinatario, solicitados com o proponente', COUNT(*)
      FROM troca_item ti
      JOIN troca t          ON t.id = ti.troca_id
      JOIN item_instancia i ON i.id = ti.item_instancia_id
     WHERE t.status_troca = 'concluida'
       AND i.proprietario_id <> CASE ti.lado_troca
                                    WHEN 'oferecido' THEN t.destinatario_id
                                    ELSE t.proponente_id
                                END
       AND NOT EXISTS (SELECT 1 FROM venda v2
                         JOIN anuncio a2 ON a2.id = v2.anuncio_id
                        WHERE a2.item_instancia_id = i.id
                          AND v2.status_venda = 'concluida'
                          AND v2.data_venda > t.data_efetivacao)
       AND NOT EXISTS (SELECT 1 FROM troca_item x
                         JOIN troca t2 ON t2.id = x.troca_id
                        WHERE x.item_instancia_id = i.id
                          AND t2.status_troca = 'concluida'
                          AND t2.data_efetivacao > t.data_efetivacao)

    UNION ALL
    SELECT 'RS-08', 'Toda troca tem >=1 oferecido E >=1 solicitado', COUNT(*)
      FROM troca t
     WHERE NOT EXISTS (SELECT 1 FROM troca_item x WHERE x.troca_id = t.id AND x.lado_troca = 'oferecido')
        OR NOT EXISTS (SELECT 1 FROM troca_item x WHERE x.troca_id = t.id AND x.lado_troca = 'solicitado')

    UNION ALL
    SELECT 'RS-09', 'XOR: toda avaliacao em EXATAMENTE um subtipo', COUNT(*)
      FROM (
        SELECT a.id,
               (SELECT COUNT(*) FROM avaliacao_venda v WHERE v.avaliacao_id = a.id)
             + (SELECT COUNT(*) FROM avaliacao_troca r WHERE r.avaliacao_id = a.id) AS n
          FROM avaliacao a
      ) t WHERE n <> 1

    UNION ALL
    SELECT 'RS-10', 'Anuncio "vendido" <=> existe venda CONCLUIDA', COUNT(*)
      FROM anuncio a
      LEFT JOIN venda v ON v.anuncio_id = a.id
     WHERE (a.status_anuncio = 'vendido')
       <> (v.id IS NOT NULL AND v.status_venda = 'concluida')

    UNION ALL
    SELECT 'RS-11', 'float_value da instancia dentro da faixa do catalogo', COUNT(*)
      FROM equipamento e
      JOIN item_instancia i ON i.id = e.item_instancia_id
      JOIN item_catalogo  c ON c.id = i.item_catalogo_id
     WHERE e.float_value NOT BETWEEN c.float_min AND c.float_max

    UNION ALL
    SELECT 'RS-12', 'nota_fiscal.valor_total = venda.valor_venda', COUNT(*)
      FROM nota_fiscal n
      JOIN venda v ON v.id = n.venda_id
     WHERE n.valor_total <> v.valor_venda

    UNION ALL
    SELECT 'RS-13', 'pagamento.valor = venda.valor_venda (pagamento integral)', COUNT(*)
      FROM pagamento p
      JOIN venda v ON v.id = p.venda_id
     WHERE p.valor <> v.valor_venda

    UNION ALL
    SELECT 'RS-14', 'Instancias do mesmo modelo caem no mesmo subtipo', COUNT(*)
      FROM (
        SELECT i.item_catalogo_id,
               COUNT(DISTINCT CASE
                   WHEN c.item_instancia_id IS NOT NULL THEN 'COSMETICO'
                   WHEN e.item_instancia_id IS NOT NULL THEN 'EQUIPAMENTO'
                   ELSE 'CONSUMIVEL' END) AS n
          FROM item_instancia i
          LEFT JOIN cosmetico   c ON c.item_instancia_id = i.id
          LEFT JOIN equipamento e ON e.item_instancia_id = i.id
         GROUP BY i.item_catalogo_id
      ) t WHERE n > 1

    UNION ALL
    SELECT 'RS-15', 'float_min/max preenchido so em modelo de equipamento', COUNT(*)
      FROM item_catalogo c
     WHERE c.float_min IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM item_instancia i
             JOIN equipamento e ON e.item_instancia_id = i.id
            WHERE i.item_catalogo_id = c.id)

    UNION ALL
    SELECT 'RS-16', 'Pagamento recusado => venda cancelada', COUNT(*)
      FROM pagamento p
      JOIN venda v ON v.id = p.venda_id
     WHERE p.status_pagamento = 'recusado'
       AND v.status_venda <> 'cancelada'

    UNION ALL
    SELECT 'RS-17', 'Anuncio ativo: criador e o dono atual do item', COUNT(*)
      FROM anuncio a
      JOIN item_instancia i ON i.id = a.item_instancia_id
     WHERE a.status_anuncio = 'ativo'
       AND i.proprietario_id <> a.criador_id

    UNION ALL
    -- Lado (1,N) de PERTENCE no MER: minimo que FK nao garante.
    SELECT 'RS-18', 'Toda colecao agrupa ao menos 1 modelo de item', COUNT(*)
      FROM colecao c
     WHERE NOT EXISTS (
           SELECT 1 FROM item_catalogo ic WHERE ic.colecao_id = c.id)

    UNION ALL
    -- RS-19 a RS-22: abertura de recipientes (extra de baixo nivel).
    SELECT 'RS-19', 'Abertura usa recipiente valido e itens do mesmo usuario', COUNT(*)
      FROM abertura_recipiente a
      JOIN consumivel r       ON r.item_instancia_id = a.recipiente_id
      JOIN item_instancia ri  ON ri.id = a.recipiente_id
      JOIN item_instancia res ON res.id = a.item_resultado_id
     WHERE r.tipo_consumivel NOT IN ('caixa', 'capsula')
        OR ri.proprietario_id <> a.usuario_id
        OR res.proprietario_id <> a.usuario_id

    UNION ALL
    SELECT 'RS-20', 'Caixa usa chave valida; capsula nao usa chave', COUNT(*)
      FROM abertura_recipiente a
      JOIN consumivel r      ON r.item_instancia_id = a.recipiente_id
      LEFT JOIN consumivel k ON k.item_instancia_id = a.chave_id
      LEFT JOIN item_instancia ki ON ki.id = a.chave_id
     WHERE (r.tipo_consumivel = 'caixa'
            AND (a.chave_id IS NULL
                 OR k.tipo_consumivel <> 'chave'
                 OR ki.proprietario_id <> a.usuario_id))
        OR (r.tipo_consumivel = 'capsula' AND a.chave_id IS NOT NULL)

    UNION ALL
    SELECT 'RS-21', 'Resultado compativel com o tipo de recipiente', COUNT(*)
      FROM abertura_recipiente a
      JOIN consumivel r       ON r.item_instancia_id = a.recipiente_id
      LEFT JOIN equipamento e ON e.item_instancia_id = a.item_resultado_id
      LEFT JOIN cosmetico co  ON co.item_instancia_id = a.item_resultado_id
      LEFT JOIN consumivel cr ON cr.item_instancia_id = a.item_resultado_id
     WHERE (r.tipo_consumivel = 'caixa' AND e.item_instancia_id IS NULL)
        OR (r.tipo_consumivel = 'capsula'
            AND co.item_instancia_id IS NULL
            AND (cr.item_instancia_id IS NULL OR cr.tipo_consumivel <> 'grafite'))

    UNION ALL
    SELECT 'RS-22', 'Recipiente e chave usados ficam consumidos', COUNT(*)
      FROM abertura_recipiente a
      JOIN item_instancia ri ON ri.id = a.recipiente_id
      JOIN consumivel r      ON r.item_instancia_id = a.recipiente_id
      LEFT JOIN item_instancia ki ON ki.id = a.chave_id
      LEFT JOIN consumivel k      ON k.item_instancia_id = a.chave_id
     WHERE ri.status_item <> 'consumido'
        OR ri.tradable_flag
        OR r.lacrado
        OR r.cargas_restantes <> 0
        OR (a.chave_id IS NOT NULL
            AND (ki.status_item <> 'consumido'
                 OR ki.tradable_flag
                 OR k.lacrado
                 OR k.cargas_restantes <> 0))

    UNION ALL
    -- Cosmetico aplicado passa a fazer parte do equipamento.
    SELECT 'RS-23', 'Cosmetico aplicado: dono do equipamento, consumido e nao negociavel', COUNT(*)
      FROM aplicacao_cosmetico ac
      JOIN item_instancia co ON co.id = ac.cosmetico_id
      JOIN item_instancia eq ON eq.id = ac.equipamento_id
     WHERE co.proprietario_id <> eq.proprietario_id
        OR co.status_item <> 'consumido'
        OR co.tradable_flag

    UNION ALL
    SELECT 'RS-24', 'Anuncio aberto: item disponivel e negociavel', COUNT(*)
      FROM anuncio a
      JOIN item_instancia i ON i.id = a.item_instancia_id
     WHERE a.status_anuncio IN ('pendente', 'ativo')
       AND (i.status_item <> 'disponivel' OR NOT i.tradable_flag)

    UNION ALL
    -- Avaliacao: entre as duas partes de uma operacao concluida, depois
    -- dela, e no maximo uma por autor em cada operacao.
    SELECT 'RS-25', 'Avaliacao: entre as partes da operacao concluida, uma por autor', COUNT(*)
      FROM (
        SELECT av.avaliacao_id
          FROM avaliacao_venda av
          JOIN avaliacao x ON x.id = av.avaliacao_id
          JOIN venda v     ON v.id = av.venda_id
          JOIN anuncio a   ON a.id = v.anuncio_id
         WHERE v.status_venda <> 'concluida'
            OR x.data_avaliacao < v.data_venda
            OR NOT ((x.autor_id = v.comprador_id AND x.avaliado_id = a.criador_id)
                 OR (x.autor_id = a.criador_id AND x.avaliado_id = v.comprador_id))
            OR EXISTS (SELECT 1 FROM avaliacao_venda av2
                         JOIN avaliacao x2 ON x2.id = av2.avaliacao_id
                        WHERE av2.venda_id = av.venda_id
                          AND x2.autor_id = x.autor_id
                          AND av2.avaliacao_id <> av.avaliacao_id)
        UNION ALL
        SELECT avt.avaliacao_id
          FROM avaliacao_troca avt
          JOIN avaliacao x ON x.id = avt.avaliacao_id
          JOIN troca t     ON t.id = avt.troca_id
         WHERE t.status_troca <> 'concluida'
            OR x.data_avaliacao < t.data_efetivacao
            OR NOT ((x.autor_id = t.proponente_id AND x.avaliado_id = t.destinatario_id)
                 OR (x.autor_id = t.destinatario_id AND x.avaliado_id = t.proponente_id))
            OR EXISTS (SELECT 1 FROM avaliacao_troca avt2
                         JOIN avaliacao x2 ON x2.id = avt2.avaliacao_id
                        WHERE avt2.troca_id = avt.troca_id
                          AND x2.autor_id = x.autor_id
                          AND avt2.avaliacao_id <> avt.avaliacao_id)
      ) t
)
SELECT
    regra,
    descricao,
    qtd AS violacoes,
    CASE WHEN qtd = 0 THEN 'OK' ELSE '*** VIOLADA ***' END AS resultado
FROM violacoes
ORDER BY regra;



-- ==========================================================
--  3. RASTREABILIDADE: as cardinalidades do MER nos dados
-- ==========================================================


-- GERA: ANUNCIO(1,1) - VENDA(0,1) --
--    VENDA participa com (0,1): um anuncio pode nao gerar venda, entao
--    "anuncio SEM venda" tem contagem maior que zero.
SELECT
    CASE WHEN v.id IS NULL THEN 'anuncio SEM venda' ELSE 'anuncio COM venda' END AS situacao,
    COUNT(*) AS qtd
FROM anuncio a
LEFT JOIN venda v ON v.anuncio_id = a.id
GROUP BY 1
ORDER BY 1;


-- OFERECE: ITEM(1,1) - ANUNCIO(0,N) --
--    Um item pode aparecer em varios anuncios ao longo do tempo.
SELECT
    qtd_anuncios || ' anuncio(s)' AS por_item,
    COUNT(*) AS qtd_itens
FROM (
    SELECT ii.id, COUNT(a.id) AS qtd_anuncios
      FROM item_instancia ii
      LEFT JOIN anuncio a ON a.item_instancia_id = ii.id
     GROUP BY ii.id
) t
GROUP BY qtd_anuncios
ORDER BY qtd_anuncios;


-- EMITE: VENDA(1,1) - NOTA_FISCAL(0,1) --
--    A nota fiscal e opcional: vendas nao concluidas ficam sem NF.
SELECT
    v.status_venda,
    COUNT(*) AS vendas,
    COUNT(n.id) AS com_nota_fiscal
FROM venda v
LEFT JOIN nota_fiscal n ON n.venda_id = v.id
GROUP BY v.status_venda
ORDER BY v.status_venda;


-- AVALIA_VENDA: VENDA(0,1) - AVALIACAO(0,N) --
--    Uma venda pode receber varias avaliacoes (uma de cada parte).
SELECT
    v.protocolo_venda,
    COUNT(*) AS qtd_avaliacoes
FROM avaliacao_venda av
JOIN venda v ON v.id = av.venda_id
GROUP BY v.protocolo_venda
HAVING COUNT(*) > 1
ORDER BY v.protocolo_venda;


-- Especializacao TOTAL e DISJUNTA de ITEM_INSTANCIA --
SELECT
    'cosmetico'   AS subtipo, COUNT(*) AS qtd FROM cosmetico
UNION ALL SELECT 'equipamento', COUNT(*) FROM equipamento
UNION ALL SELECT 'consumivel',  COUNT(*) FROM consumivel
UNION ALL SELECT '= TOTAL',     COUNT(*) FROM item_instancia
ORDER BY subtipo;
