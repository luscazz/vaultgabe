-- =====================================================================
-- VAULTGABE - CONSULTAS DA PAGINA PERFIL DO USUARIO ( /usuario/:id )
-- Formato dos blocos: ver database/consultas/README.md
-- O e-mail do usuario nao e exibido: o perfil e publico.
-- =====================================================================


-- name: perfil_usuario
-- Cabecalho do perfil: dados publicos, reputacao e numeros.
--   $1 usuario  INT
SELECT u.id,
       u.apelido,
       u.nome,
       u.data_cadastro,
       u.steam_guard_ativo,
       rep.nota_media,
       COALESCE(rep.avaliacoes, 0) AS avaliacoes,
       (SELECT COUNT(*) FROM vw_vendas_concluidas vc
         WHERE vc.vendedor_id  = u.id)                 AS vendas,
       (SELECT COUNT(*) FROM vw_vendas_concluidas vc
         WHERE vc.comprador_id = u.id)                 AS compras,
       (SELECT COUNT(*) FROM troca t
         WHERE t.status_troca = 'concluida'
           AND u.id IN (t.proponente_id, t.destinatario_id)) AS trocas,
       (SELECT COUNT(*) FROM vw_ofertas_ativas oa
         WHERE oa.vendedor_id  = u.id)                 AS anuncios_ativos,
       (SELECT COUNT(*) FROM item_instancia i
         WHERE i.proprietario_id = u.id)               AS itens
  FROM usuario u
  LEFT JOIN vw_reputacao rep ON rep.usuario_id = u.id
 WHERE u.id = $1::INT;


-- name: anuncios_ativos_do_usuario
-- Secao "Anuncios ativos" do perfil.
--   $1 usuario  INT
SELECT oa.anuncio_id,
       ic.id                      AS modelo_id,
       ic.nome_item               AS nome,
       ic.imagem_base             AS imagem,
       r.cor_hexadecimal          AS cor_raridade,
       e.float_value,
       fn_desgaste(e.float_value) AS desgaste,
       oa.preco,
       oa.data_expiracao,
       oa.reservada
  FROM vw_ofertas_ativas oa
  JOIN item_catalogo ic   ON ic.id = oa.modelo_id
  JOIN raridade r         ON r.id  = ic.raridade_id
  LEFT JOIN equipamento e ON e.item_instancia_id = oa.item_id
 WHERE oa.vendedor_id = $1::INT
 ORDER BY oa.data_publicacao DESC;


-- name: avaliacoes_recebidas
-- Secao "Avaliacoes recebidas": autor, nota, comentario e a operacao avaliada.
--   $1 usuario  INT
SELECT x.ticket_avaliacao AS ticket,
       x.data_avaliacao,
       x.nota,
       x.comentario,
       autor.id           AS autor_id,
       autor.apelido      AS autor,
       CASE WHEN av.venda_id IS NOT NULL THEN 'venda' ELSE 'troca' END AS origem,
       COALESCE(v.protocolo_venda, t.protocolo_troca)                 AS protocolo
  FROM avaliacao x
  JOIN usuario autor            ON autor.id = x.autor_id
  LEFT JOIN avaliacao_venda av  ON av.avaliacao_id = x.id
  LEFT JOIN venda v             ON v.id = av.venda_id
  LEFT JOIN avaliacao_troca avt ON avt.avaliacao_id = x.id
  LEFT JOIN troca t             ON t.id = avt.troca_id
 WHERE x.avaliado_id = $1::INT
 ORDER BY x.data_avaliacao DESC;


-- name: trocas_do_usuario
-- Secao "Historico de trocas" (somente consulta): o papel do usuario, a
-- outra parte e os itens de cada lado.
--   $1 usuario  INT
SELECT t.protocolo_troca AS protocolo,
       t.status_troca    AS status,
       t.data_proposta,
       t.data_efetivacao,
       CASE WHEN t.proponente_id = $1::INT THEN 'proponente' ELSE 'destinatario' END AS papel,
       outro.id          AS outro_usuario_id,
       outro.apelido     AS outro_usuario,
       string_agg(ic.nome_item, ', ' ORDER BY ic.nome_item)
           FILTER (WHERE ti.lado_troca = 'oferecido')  AS itens_oferecidos,
       string_agg(ic.nome_item, ', ' ORDER BY ic.nome_item)
           FILTER (WHERE ti.lado_troca = 'solicitado') AS itens_solicitados
  FROM troca t
  JOIN usuario outro    ON outro.id = CASE WHEN t.proponente_id = $1::INT
                                           THEN t.destinatario_id
                                           ELSE t.proponente_id END
  JOIN troca_item ti    ON ti.troca_id = t.id
  JOIN item_instancia i ON i.id  = ti.item_instancia_id
  JOIN item_catalogo ic ON ic.id = i.item_catalogo_id
 WHERE $1::INT IN (t.proponente_id, t.destinatario_id)
 GROUP BY t.id, outro.id
 ORDER BY t.data_proposta DESC;
