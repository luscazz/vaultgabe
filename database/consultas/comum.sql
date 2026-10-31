-- =====================================================================
-- VAULTGABE - CONSULTAS COMUNS A TODAS AS PAGINAS
-- Formato dos blocos: ver database/consultas/README.md
-- =====================================================================


-- name: listar_usuarios
-- Seletor "Entrar como" (topo de todas as paginas).
SELECT u.id,
       u.apelido,
       u.nome
  FROM usuario u
 ORDER BY lower(u.apelido);


-- name: saude_banco
-- GET /api/saude: confirma que o banco responde e mostra o fuso usado.
SELECT current_setting('server_version') AS versao,
       current_setting('TimeZone')       AS fuso,
       now()::timestamp(0)               AS agora;


-- name: expirar_anuncios
-- Executada pela API antes de listar ofertas: encerra os anuncios vencidos.
-- Retorna: quantos anuncios foram expirados.
SELECT fn_expirar_anuncios() AS expirados;
