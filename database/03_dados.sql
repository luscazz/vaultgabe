-- =====================================================================
-- VAULTGABE
-- 03 - DADOS: populacao do banco com dados de demonstracao
--
-- Execute depois de 01_tabelas.sql e 02_regras.sql.
-- ATENCAO: o TRUNCATE abaixo APAGA todos os dados antes de reinserir.
--
-- Base herdada de Banco de Dados I, ampliada pelo 04_dados_ampliados.sql.
--
-- ORDEM DE POSSE (regra temporal):
--   item_instancia.proprietario_id guarda o dono ATUAL, mas o anuncio so
--   pode ser criado por quem era dono NO MOMENTO DA PUBLICACAO (nos
--   anuncios abertos, trg_validar_anuncio em 02_regras.sql confere isso).
--   Por isso a ordem e:
--     1) inserir os itens com o dono ORIGINAL (o vendedor)
--     2) inserir anuncios e vendas
--     3) SO ENTAO transferir a posse dos itens vendidos/trocados
--        para o comprador/contraparte (secao 12)
--     4) por ultimo, os anuncios de REVENDA, criados pelo novo dono
--        (secao 13)
--
--   Cada item muda de dono NO MAXIMO UMA VEZ (por venda ou por troca),
--   o que mantem validas as regras RS-04 e RS-07 de 05_verificacao.sql.
--
-- TECNICA DE INSERT:
--   Todas as FKs sao resolvidas com subconsulta pela chave natural
--   (ex: (SELECT id FROM usuario WHERE steam_id = '...')). Assim o
--   script nao depende dos valores que o SERIAL gerou e pode ser
--   reexecutado.
-- =====================================================================

BEGIN;

TRUNCATE TABLE
    avaliacao_troca, avaliacao_venda, avaliacao,
    troca_item, troca, nota_fiscal, pagamento, venda, anuncio,
    abertura_recipiente,
    aplicacao_cosmetico, consumivel, equipamento, cosmetico,
    item_instancia, item_catalogo, usuario, colecao, raridade,
    categoria_item
RESTART IDENTITY CASCADE;


-- ---------------------------------------------------------------------
-- 1. CATEGORIA_ITEM  (13)
-- ---------------------------------------------------------------------
INSERT INTO categoria_item (nome_categoria) VALUES
    ('Rifle'),
    ('Pistola'),
    ('SMG'),
    ('Escopeta'),
    ('Metralhadora'),
    ('Faca'),
    ('Luva'),
    ('Adesivo'),
    ('Chaveiro'),
    ('Caixa'),
    ('Capsula'),
    ('Chave'),
    ('Grafite');


-- ---------------------------------------------------------------------
-- 2. RARIDADE  (12) - cores reais do CS2
-- ---------------------------------------------------------------------
INSERT INTO raridade (nome_raridade, cor_hexadecimal) VALUES
    ('Consumer Grade',   '#b0c3d9'),
    ('Industrial Grade', '#5e98d9'),
    ('Mil-Spec',         '#4b69ff'),
    ('Restricted',       '#8847ff'),
    ('Classified',       '#d32ce6'),
    ('Covert',           '#eb4b4b'),
    ('Contraband',       '#e4ae39'),
    ('Extraordinary',    '#eb4b4b'),
    ('Base Grade',       '#b0c3d9'),
    ('High Grade',       '#4b69ff'),
    ('Remarkable',       '#8847ff'),
    ('Exotic',           '#d32ce6');


-- ---------------------------------------------------------------------
-- 3. COLECAO  (12)
-- ---------------------------------------------------------------------
INSERT INTO colecao (nome_colecao, data_lancamento) VALUES
    ('The Dust Collection',      '2013-08-14'),
    ('The Mirage Collection',    '2013-11-27'),
    ('The Cache Collection',     '2014-07-01'),
    ('Operation Bravo',          '2013-09-19'),
    ('The Chroma Collection',    '2015-01-08'),
    ('The Spectrum Collection',  '2017-03-15'),
    ('The Prisma Collection',    '2019-03-13'),
    ('The Danger Zone Case',     '2018-12-06'),
    ('The Fracture Collection',  '2020-08-06'),
    ('The Snakebite Collection', '2021-05-03'),
    ('The Wildfire Collection',  '2016-02-17'),
    ('The Recoil Collection',    '2022-07-01');


-- ---------------------------------------------------------------------
-- 4. USUARIO  (12)
-- ---------------------------------------------------------------------
INSERT INTO usuario (steam_id, nome, email, apelido, data_cadastro, steam_guard_ativo) VALUES
    ('STEAM_76561198000000001', 'Ana Ribeiro',        'ana.ribeiro@vaultmail.com',   'galabinha',       '2021-03-14', TRUE),
    ('STEAM_76561198000000002', 'Bruno Carvalho',     'bruno.c@vaultmail.com',       'viniciuslabubu',  '2022-11-02', TRUE),
    ('STEAM_76561198000000003', 'Carla Menezes',      'carla.m@vaultmail.com',       'manojoe',         '2020-07-26', TRUE),
    ('STEAM_76561198000000004', 'Diego Fontes',       'diego.fontes@vaultmail.com',  'dfontes',   '2023-02-08', FALSE),
    ('STEAM_76561198000000005', 'Elisa Moraes',       'elisa.moraes@vaultmail.com',  'lisa',      '2021-10-19', TRUE),
    ('STEAM_76561198000000006', 'Felipe Andrade',     'felipe.a@vaultmail.com',      'pepaa',     '2022-05-30', FALSE),
    ('STEAM_76561198000000007', 'Gabriela Souza',     'gabi.souza@vaultmail.com',    'gabs',      '2023-06-11', TRUE),
    ('STEAM_76561198000000008', 'Henrique Lopes',     'henrique.l@vaultmail.com',    'rick',      '2019-12-03', TRUE),
    ('STEAM_76561198000000009', 'Isabela Prado',      'isabela.p@vaultmail.com',     'isizinha',  '2022-08-21', FALSE),
    ('STEAM_76561198000000010', 'Joao Vitor Nunes',   'joao.nunes@vaultmail.com',    'JV',        '2020-02-17', TRUE),
    ('STEAM_76561198000000011', 'Larissa Teixeira',   'larissa.t@vaultmail.com',     'lari',      '2023-09-27', TRUE),
    ('STEAM_76561198000000012', 'Marcelo Dias',       'marcelo.dias@vaultmail.com',  'bruninmatador', '2021-06-05', FALSE);


-- ---------------------------------------------------------------------
-- 5. ITEM_CATALOGO  (21)
--    float_min/float_max SO nos modelos que geram EQUIPAMENTO; nos de
--    cosmetico e consumivel ficam NULL (o CHECK item_catalogo_float_ck
--    exige "ambos ou nenhum").
--    colecao_id e anulavel: exercita o (0,1) de PERTENCE.
--    Todos os modelos sao itens reais do CS2; imagem_base e a imagem
--    oficial (servidor da Steam), obtida no CSGO-API
--    (github.com/ByMykel/CSGO-API). Imagens (c) Valve Corporation.
-- ---------------------------------------------------------------------
-- 5.1 Modelos de EQUIPAMENTO (11)
INSERT INTO item_catalogo (nome_item, categoria_id, raridade_id, colecao_id, imagem_base, float_min, float_max, descricao) VALUES
    ('AK-47 | Redline',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Cache Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwlcK3wiFO0POlPPNSI_-RHGavzedxuPUnFniykEtzsWWBzoyuIiifaAchDZUjTOZe4RC_w4buM-6z7wzbgokUyzK-0H08hRGDMA', 0.10000000, 0.70000000, 'Rifle de assalto com acabamento vermelho sobre fibra de carbono.'),
    ('AWP | Asiimov',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'Operation Bravo'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwiYbf_jdk7uW-V6V-Kf2cGFidxOp_pewnF3nhxEt0sGnSzN76dH3GOg9xC8FyEORftRe-x9PuYurq71bW3d8UnjK-0H0YSTpMGQ', 0.18000000, 1.00000000, 'Sniper com pintura futurista laranja e branca.'),
    ('Desert Eagle | Blaze',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Restricted'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Dust Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL1m5fn8Sdk7vORbqhsLfWAMWuZxuZi_uI_TX6wxxkjsGXXnImsJ37COlUoWcByEOMOtxa5kdXmNu3htVPZjN1bjXKpkHLRfQU', 0.00000000, 0.08000000, 'Pistola com chamas pintadas a mao.'),
    ('M4A4 | Howl',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Contraband'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Mirage Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8ypexwiFO0P_6afVSKP-EAm6extF6ueZhW2exwkl2tmTXwt39eCiUPQR2DMN4TOVetUK8xoLgM-K341eM2otDnC6okGoXufBz_TAB', 0.00000000, 0.40000000, 'Skin removida do jogo, extremamente rara.'),
    ('P90 | Sand Spray',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'SMG'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Consumer Grade'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Dust Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLhx8bf7jJk_OK8ab1SM_GdClicyOl-pK88Sn3gxU91sGiAw9mreSqROgJyCsF5EOVf50S_x9SzP7iztlaLiYJF02yg2VFl2-bi', 0.06000000, 0.80000000, 'Camuflagem simples em tons de areia.'),
    ('Karambit | Doppler',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Faca'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Chroma Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL6kJ_m-B1Q7uCvZaZkNM-SA1iUzv5mvOR7cDm7lA4i4QKJk4jxNWWXawUgA8dxRLEO40KwkobnMbnj5QKL348Qmy-sji5K7i466uxUUKQn5OSJ2KBZjkQR', 0.00000000, 0.08000000, 'Faca curva com acabamento metalico iridescente.'),
    ('Sport Gloves | Pandora''s Box',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Luva'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Tk5UvzWCL2kpn2-DFk_OKherB0H-CGHHecxNF6ueZhW2exk01w4j7cmYn4eHPCbAMhApdwTOIN5BPsx9yyYu605FTeid0Uy3j3kGoXueKyz5wo', 0.06000000, 0.80000000, 'Luvas esportivas pretas e roxas com padrao discreto nas palmas.'),
    ('Specialist Gloves | Crimson Kimono',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Luva'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Tk71ruQBH4jYLf-i5U-fe9V7d9JfOaD2uZ0vpJu-hkQCe8qhkusjCKlIvqHjnCOml8U8UoAfkItBLswdbuNbjr5FHdjNkUzSv73C1K5y46tu4EUvAg-6bU3FrBMOE4_9BdcyhkRns5', 0.06000000, 0.80000000, 'Luvas pretas com detalhes vermelhos em padrao de diamantes.'),
    ('Moto Gloves | Spearmint',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Luva'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu4r7_lb1QgTykpPf-i5U-fe9V6liNP-BDX6TzetJvehnWxanhxQmvTqJn7D1KCzPKhgnW5UmRO4DsxXrlYbhPurmtAXai98UzS73in5I6S5p4OsAU_Zx-KHWkUifZsxBQgc2', 0.06000000, 0.80000000, 'Luvas de motociclista em tons de verde e branco.'),
    ('Nova | Hyper Beast',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Escopeta'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Wildfire Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL_kYDhwiFO0PyhfqVSKOmDC3WSxO9lpN5lRi67gVMhsGrTmd2seH6XbA4pDZR1EbMCtES8m4fiNenl4FDcid1Az32ri3tM8G81tMCTwFwB', 0.00000000, 0.60000000, 'Escopeta com criatura estilizada em cores psicodelicas.'),
    ('M249 | Downtown',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Metralhadora'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Restricted'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Recoil Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8zMK5wiFO0P_8PP1SJP-EAHGf1etJvOhuRz39wUh-5GuGz4mrJHuSbg4jWJp1FLINsRCxwdDuZezm7leK3d5GmSr_jTQJsHj3YwoNRA', 0.00000000, 0.65000000, 'Metralhadora com setas azuis e rosas em estilo urbano.');

-- 5.2 Modelos de COSMETICO (4) - sem faixa de float, sem colecao em 1 caso
INSERT INTO item_catalogo (nome_item, categoria_id, raridade_id, colecao_id, imagem_base, descricao) VALUES
    ('Adesivo | Natus Vincere (Holo)',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Adesivo'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Remarkable'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'Operation Bravo'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJai0ki7VeTHjM-sJnCW8Vli_YTxuAm2FVL_n4DpwipU4_3gav08c6jBWzHElbck5ONvGX2yxU8m6mnXwtetcnOfOgMiCJclRbIMsg74zIPTbZA4cw', 'Adesivo holografico da equipe Natus Vincere.'),
    ('Adesivo | Crown (Foil)',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Adesivo'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Exotic'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJai0ki7VeTHjNm1PHic4ERmpsj3-FbwTyL3kZ_ssycDt6v4PvU_dvTGDWGWl-xwtLZoS36ykB4ltTvXy42seS_EPFQpC8BuBbldJQkRI1c', 'Adesivo metalico de coroa. Nao pertence a nenhuma colecao.'),
    ('Chaveiro | Hot Howl',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Chaveiro'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Snakebite Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGI6zwki4Uf_a0IWsPGiE7Fhy-I764RbsQiL8l4Xz9Cxc4_ugY5tlL-efQGKTmbxztbJoFnvjkBtw4zjcw9v8ICiTOwcpDpZyF-FYsBO9k4W2Nbn8p1uJTS_m1eQ', 'Chaveiro pendurado na arma.'),
    ('Chaveiro | Baby Karat T',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Chaveiro'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Spectrum Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGI6zwki4Uf_a0IW2MHqH6lhKpcj_6WbwURPOip3u9CRe0PWhZKAjJPOXWDGWlOgm47QxTH7jwExy5zmAw977cinCbgcgCJNzFLID50bsw8qnab1NtMpc9Q', 'Chaveiro dourado em miniatura.');

-- 5.3 Modelos de CONSUMIVEL (6)
INSERT INTO item_catalogo (nome_item, categoria_id, raridade_id, colecao_id, imagem_base, descricao) VALUES
    ('Caixa Fracture',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Caixa'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Fracture Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bj35VTqVBP4io_fr3QV7aD7OP01IfbGDzPCmbsm4LU5GnvkzUsi4WvUmIqtci_CPQNyApsjE_lK7EfrhW545A', 'Caixa que requer chave para ser aberta.'),
    ('Caixa Prisma',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Caixa'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Prisma Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bj35VTqVBP4io_fr3AV6aD8O6BpdKKQVmPEwr1zs-c8Tnngl09w52zTmY2sc3jBag8jXpohE_lK7Ede7E2Kfw', 'Caixa da colecao Prisma.'),
    ('Capsula Ambush',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Capsula'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bjn_lDkShjjoYbh_ilk7P2jZbFjKeSKMTXAk7pJs-B5XDy_kFN14mXVz4r4JHuXOAAoXJR2E7UIt0HqwdTuYuKw5gLYjYNAxCn7hi1O8G81tG_FJxt9', 'Capsula moderna de adesivos, aberta sem chave.'),
    ('Capsula de Grafites',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Capsula'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bjn-kvmWCLhn5XrwjRa4-SrV_UjdqPCCzPAl70ntbI4HXCylk4jt2zQm4v_cy7CPVV0A5R0F-IJsxSxmsqnab1NL4_-UQ', 'Capsula que libera um grafite.'),
    ('Chave de Caixa',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Chave'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJG51EejH-HRwtquO0SU5EVwy4zx8xe1EU_3yZfj_HEM7POoOfI0IvOQXzWRkesg5rc_HyzqlkR_5GrRw92obzvJOU2RiCYH', 'Chave usada para abrir caixas.'),
    ('Grafite | EZ',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Grafite'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Remarkable'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Danger Zone Case'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJai0ki7VeTHjNygOW2S2kVl5obt-RbiWyKhzNi3-yReu6r7Ofw9cPaXDTKTlrcktrBtTXHnlh904TzSzNisJHKROwZ1FNIuEo-VmxK1', 'Grafite com 50 cargas de uso.');


-- ---------------------------------------------------------------------
-- 6. ITEM_INSTANCIA  (54 = 20 cosmetico + 16 equipamento + 18 consumivel)
--
--    REGRA TEMPORAL: aqui o proprietario_id e o dono ORIGINAL. Os itens
--    vendidos/trocados so mudam de dono na secao 12.
--    Todas as instancias do mesmo nome_item caem no MESMO subtipo
--    (uma 'AK-47 | Redline' e sempre EQUIPAMENTO).
-- ---------------------------------------------------------------------
-- 6.1 Instancias que serao EQUIPAMENTO (16)
INSERT INTO item_instancia (numero_inspecao, item_catalogo_id, proprietario_id, tradable_flag, data_obtencao, status_item) VALUES
    ('INS-EQ-0001', (SELECT id FROM item_catalogo WHERE nome_item='AK-47 | Redline'),      (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE,  '2024-02-10', 'disponivel'),
    ('INS-EQ-0002', (SELECT id FROM item_catalogo WHERE nome_item='AK-47 | Redline'),      (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), TRUE,  '2024-03-15', 'disponivel'),
    ('INS-EQ-0003', (SELECT id FROM item_catalogo WHERE nome_item='AWP | Asiimov'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), TRUE,  '2024-01-08', 'disponivel'),
    ('INS-EQ-0004', (SELECT id FROM item_catalogo WHERE nome_item='AWP | Asiimov'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), TRUE,  '2024-04-22', 'disponivel'),
    ('INS-EQ-0005', (SELECT id FROM item_catalogo WHERE nome_item='Desert Eagle | Blaze'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000005'), TRUE,  '2024-05-30', 'disponivel'),
    ('INS-EQ-0006', (SELECT id FROM item_catalogo WHERE nome_item='M4A4 | Howl'),          (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE,  '2023-11-11', 'disponivel'),
    ('INS-EQ-0007', (SELECT id FROM item_catalogo WHERE nome_item='P90 | Sand Spray'),     (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000006'), TRUE,  '2024-06-05', 'disponivel'),
    ('INS-EQ-0008', (SELECT id FROM item_catalogo WHERE nome_item='Karambit | Doppler'),   (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000007'), TRUE,  '2024-02-28', 'disponivel'),
    ('INS-EQ-0009', (SELECT id FROM item_catalogo WHERE nome_item='Karambit | Doppler'),   (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000008'), FALSE, '2024-07-19', 'bloqueado'),
    ('INS-EQ-0010', (SELECT id FROM item_catalogo WHERE nome_item='Desert Eagle | Blaze'),            (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000010'), TRUE,  '2024-08-01', 'disponivel'),
    ('INS-EQ-0011', (SELECT id FROM item_catalogo WHERE nome_item='AK-47 | Redline'),                  (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE,  '2026-06-20', 'disponivel'),   -- resultado da abertura de 2026-06-20
    ('INS-EQ-0012', (SELECT id FROM item_catalogo WHERE nome_item='Sport Gloves | Pandora''s Box'),   (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), TRUE,  '2025-01-12', 'disponivel'),
    ('INS-EQ-0013', (SELECT id FROM item_catalogo WHERE nome_item='Specialist Gloves | Crimson Kimono'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), TRUE, '2025-02-18', 'disponivel'),
    ('INS-EQ-0014', (SELECT id FROM item_catalogo WHERE nome_item='Moto Gloves | Spearmint'),          (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000006'), TRUE,  '2025-03-22', 'disponivel'),
    ('INS-EQ-0015', (SELECT id FROM item_catalogo WHERE nome_item='Nova | Hyper Beast'),               (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000008'), TRUE,  '2025-04-09', 'disponivel'),
    ('INS-EQ-0016', (SELECT id FROM item_catalogo WHERE nome_item='M249 | Downtown'),                  (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), TRUE,  '2025-05-17', 'disponivel');

-- 6.2 Instancias que serao COSMETICO (20)
INSERT INTO item_instancia (numero_inspecao, item_catalogo_id, proprietario_id, tradable_flag, data_obtencao, status_item) VALUES
    ('INS-CO-0001', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Natus Vincere (Holo)'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE, '2024-03-01', 'disponivel'),
    ('INS-CO-0002', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Natus Vincere (Holo)'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), TRUE, '2024-03-02', 'disponivel'),
    ('INS-CO-0003', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Crown (Foil)'),         (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), TRUE, '2024-04-10', 'disponivel'),
    ('INS-CO-0004', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Crown (Foil)'),         (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000005'), TRUE, '2024-04-11', 'disponivel'),
    ('INS-CO-0005', (SELECT id FROM item_catalogo WHERE nome_item='Chaveiro | Hot Howl'),            (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000007'), TRUE, '2024-05-20', 'disponivel'),
    ('INS-CO-0006', (SELECT id FROM item_catalogo WHERE nome_item='Chaveiro | Hot Howl'),            (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), TRUE, '2024-05-21', 'disponivel'),
    ('INS-CO-0007', (SELECT id FROM item_catalogo WHERE nome_item='Chaveiro | Baby Karat T'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000010'), TRUE, '2024-06-15', 'disponivel'),
    ('INS-CO-0008', (SELECT id FROM item_catalogo WHERE nome_item='Chaveiro | Baby Karat T'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), TRUE, '2024-06-16', 'disponivel'),
    ('INS-CO-0009', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Natus Vincere (Holo)'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), TRUE, '2024-07-07', 'disponivel'),
    ('INS-CO-0010', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Crown (Foil)'),         (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), TRUE, '2024-07-08', 'disponivel'),
    ('INS-CO-0011', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Natus Vincere (Holo)'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), TRUE, '2026-06-21', 'disponivel'),   -- resultado da abertura de 2026-06-21
    ('INS-CO-0012', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Natus Vincere (Holo)'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), TRUE, '2026-06-23', 'disponivel'),   -- resultado da abertura de 2026-06-23
    ('INS-CO-0013', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Crown (Foil)'),         (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000005'), TRUE, '2026-06-24', 'disponivel'),   -- resultado da 5a abertura (capsula Ambush)
    -- APLICADOS na secao 8 em armas do proprio dono: entram 'disponivel'
    -- e trg_aplicar_cosmetico os marca como 'consumido'.
    ('INS-CO-0014', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Natus Vincere (Holo)'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE, '2024-02-12', 'disponivel'),   -- vai para a AK-47 INS-EQ-0001
    ('INS-CO-0015', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Natus Vincere (Holo)'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE, '2024-02-12', 'disponivel'),   -- vai para a AK-47 INS-EQ-0001
    ('INS-CO-0016', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Crown (Foil)'),         (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE, '2024-02-12', 'disponivel'),   -- vai para a AK-47 INS-EQ-0001
    ('INS-CO-0017', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Crown (Foil)'),         (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), TRUE, '2024-01-10', 'disponivel'),   -- vai para a AWP INS-EQ-0003
    ('INS-CO-0018', (SELECT id FROM item_catalogo WHERE nome_item='Adesivo | Natus Vincere (Holo)'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE, '2023-11-20', 'disponivel'),   -- vai para a M4A4 INS-EQ-0006
    ('INS-CO-0019', (SELECT id FROM item_catalogo WHERE nome_item='Chaveiro | Baby Karat T'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), TRUE, '2024-03-20', 'disponivel'),   -- vai para a AK-47 INS-EQ-0002
    ('INS-CO-0020', (SELECT id FROM item_catalogo WHERE nome_item='Chaveiro | Hot Howl'),            (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), TRUE, '2025-05-20', 'disponivel');   -- vai para a M249 INS-EQ-0016

-- 6.3 Instancias que serao CONSUMIVEL (18)
INSERT INTO item_instancia (numero_inspecao, item_catalogo_id, proprietario_id, tradable_flag, data_obtencao, status_item) VALUES
    ('INS-CN-0001', (SELECT id FROM item_catalogo WHERE nome_item='Caixa Fracture'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE, '2024-08-10', 'disponivel'),
    ('INS-CN-0002', (SELECT id FROM item_catalogo WHERE nome_item='Caixa Fracture'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), TRUE, '2024-08-11', 'disponivel'),
    ('INS-CN-0003', (SELECT id FROM item_catalogo WHERE nome_item='Caixa Prisma'),          (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000005'), TRUE, '2024-08-12', 'disponivel'),
    ('INS-CN-0004', (SELECT id FROM item_catalogo WHERE nome_item='Caixa Prisma'),          (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000006'), TRUE, '2024-08-13', 'disponivel'),
    ('INS-CN-0005', (SELECT id FROM item_catalogo WHERE nome_item='Capsula Ambush'),         (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), TRUE, '2024-09-01', 'disponivel'),
    ('INS-CN-0006', (SELECT id FROM item_catalogo WHERE nome_item='Capsula Ambush'),         (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000008'), TRUE, '2024-09-02', 'disponivel'),
    ('INS-CN-0007', (SELECT id FROM item_catalogo WHERE nome_item='Chave de Caixa'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), TRUE, '2024-09-10', 'disponivel'),
    ('INS-CN-0008', (SELECT id FROM item_catalogo WHERE nome_item='Chave de Caixa'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), TRUE, '2024-09-11', 'disponivel'),
    ('INS-CN-0009', (SELECT id FROM item_catalogo WHERE nome_item='Grafite | EZ'),          (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), TRUE, '2024-10-05', 'disponivel'),
    ('INS-CN-0010', (SELECT id FROM item_catalogo WHERE nome_item='Grafite | EZ'),          (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000007'), TRUE, '2024-10-06', 'disponivel'),
    ('INS-CN-0011', (SELECT id FROM item_catalogo WHERE nome_item='Caixa Fracture'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE, '2026-06-01', 'disponivel'),
    ('INS-CN-0012', (SELECT id FROM item_catalogo WHERE nome_item='Chave de Caixa'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), TRUE, '2026-06-01', 'disponivel'),
    ('INS-CN-0013', (SELECT id FROM item_catalogo WHERE nome_item='Capsula Ambush'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), TRUE, '2026-06-02', 'disponivel'),
    ('INS-CN-0014', (SELECT id FROM item_catalogo WHERE nome_item='Capsula de Grafites'),   (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), TRUE, '2026-06-03', 'disponivel'),
    ('INS-CN-0015', (SELECT id FROM item_catalogo WHERE nome_item='Capsula Ambush'),  (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), TRUE, '2026-06-04', 'disponivel'),
    ('INS-CN-0016', (SELECT id FROM item_catalogo WHERE nome_item='Grafite | EZ'),          (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), TRUE, '2026-06-22', 'disponivel'),   -- resultado da abertura de 2026-06-22
    ('INS-CN-0017', (SELECT id FROM item_catalogo WHERE nome_item='Capsula Ambush'),  (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000005'), TRUE, '2026-06-05', 'disponivel'),   -- recipiente da 5a abertura
    ('INS-CN-0018', (SELECT id FROM item_catalogo WHERE nome_item='Chave de Caixa'),        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), TRUE, '2024-09-12', 'disponivel');   -- oferecida na troca TRC-2026-0009


-- ---------------------------------------------------------------------
-- 7. ESPECIALIZACAO: cada instancia em EXATAMENTE UM subtipo
--    16 equipamento + 20 cosmetico + 18 consumivel = 54: a soma dos
--    subtipos bate com o total de item_instancia -> TOTAL e DISJUNTA.
--    float_value sempre dentro do [float_min, float_max] do catalogo.
-- ---------------------------------------------------------------------
INSERT INTO equipamento (item_instancia_id, float_value, paint_seed, stattrak_flag, souvenir_flag) VALUES
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0001'), 0.15230000, 421, TRUE,  FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0002'), 0.35670000, 118, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0003'), 0.22100000, 690, FALSE, TRUE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0004'), 0.65400000, 302, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0005'), 0.02150000, 55,  TRUE,  FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0006'), 0.09870000, 777, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0007'), 0.78900000, 903, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0008'), 0.01120000, 387, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0009'), 0.03450000, 601, TRUE,  FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0010'), 0.06780000, 244, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0011'), 0.27140000, 144, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0012'), 0.21450000, 618, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0013'), 0.35620000, 247, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0014'), 0.61270000, 804, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0015'), 0.24573047, 682, FALSE, FALSE),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0016'), 0.28585401,  33, FALSE, FALSE);

INSERT INTO cosmetico (item_instancia_id, tipo_cosmetico, arte_visual) VALUES
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0001'), 'adesivo',  'art/navi_holo_v1.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0002'), 'adesivo',  'art/navi_holo_v1.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0003'), 'adesivo',  'art/crown_foil.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0004'), 'adesivo',  'art/crown_foil.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0005'), 'chaveiro', 'art/hot_howl.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0006'), 'chaveiro', 'art/hot_howl.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0007'), 'chaveiro', 'art/baby_karat.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0008'), 'chaveiro', 'art/baby_karat.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0009'), 'adesivo',  'art/navi_holo_v1.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0010'), 'adesivo',  'art/crown_foil.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0011'), 'adesivo',  'art/navi_holo_v1.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0012'), 'adesivo',  'art/navi_holo_v1.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0013'), 'adesivo',  'art/crown_foil.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0014'), 'adesivo',  'art/navi_holo_v1.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0015'), 'adesivo',  'art/navi_holo_v1.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0016'), 'adesivo',  'art/crown_foil.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0017'), 'adesivo',  'art/crown_foil.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0018'), 'adesivo',  'art/navi_holo_v1.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0019'), 'chaveiro', 'art/baby_karat.svg'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0020'), 'chaveiro', 'art/hot_howl.svg');

INSERT INTO consumivel (item_instancia_id, tipo_consumivel, lacrado, cargas_restantes) VALUES
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0001'), 'caixa',   TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0002'), 'caixa',   TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0003'), 'caixa',   TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0004'), 'caixa',   TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0005'), 'capsula', TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0006'), 'capsula', TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0007'), 'chave',   TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0008'), 'chave',   TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0009'), 'grafite', TRUE,  50),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0010'), 'grafite', FALSE, 22),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0011'), 'caixa',   TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0012'), 'chave',   TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0013'), 'capsula', TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0014'), 'capsula', TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0015'), 'capsula', TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0016'), 'grafite', FALSE, 50),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0017'), 'capsula', TRUE,  1),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0018'), 'chave',   TRUE,  1);


-- ---------------------------------------------------------------------
-- 8. APLICACAO_COSMETICO  (7)
--    Cada cosmetico e aplicado numa ARMA DO PROPRIO DONO, antes de a arma
--    ser vendida (trg_aplicar_cosmetico confere e marca o cosmetico como
--    'consumido'). Na venda (secao 12), trg_cosmeticos_acompanham_equipamento
--    leva os cosmeticos aplicados para o novo dono (regra RS-23).
--    INS-EQ-0001 recebe 3 cosmeticos: exercita o lado (0,6) do MER.
--    Chaveiros nao tem raspagem (nivel_raspagem NULL) e, como no CS2, so
--    vao em armas de fogo (nao em facas ou luvas).
-- ---------------------------------------------------------------------
INSERT INTO aplicacao_cosmetico (cosmetico_id, equipamento_id, coord_x, coord_y, rotacao, nivel_raspagem) VALUES
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0014'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0001'),  12.500,  4.200,   0.000,  0.00),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0015'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0001'),  30.100, 10.750,  15.500, 12.50),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0016'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0001'),  48.000, 22.300, -10.000, 45.75),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0017'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0003'),  20.000,  8.000,   0.000,  0.00),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0018'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0006'),  33.330, 11.110, 180.000,  5.00),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0019'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0002'),  15.000,  6.500,  45.250, NULL),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0020'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0016'),   5.250,  2.100,  90.000, NULL);


-- ---------------------------------------------------------------------
-- 9. ANUNCIO  (19)
--    Distribuicao final de status:
--      10 'vendido'   -> tem venda CONCLUIDA
--       6 'ativo'      -> 2 sem venda + 1 com venda pendente + 3 da secao 13 (2 revendas)
--       2 'cancelado'  -> 1 sem venda + 1 com venda cancelada
--       1 'expirado'   -> sem venda
--
--    REGRA RS-10: 'vendido' so quando existe venda CONCLUIDA; venda
--    pendente ou cancelada nao basta.
--    Os 4 anuncios sem venda exercitam o lado (0,1) da VENDA em
--    GERA = ANUNCIO(1,1) - VENDA(0,1).
--    REGRA TEMPORAL: o criador de cada anuncio e o dono do item NESTE
--    momento (a transferencia de posse so acontece na secao 12).
-- ---------------------------------------------------------------------
INSERT INTO anuncio (item_instancia_id, criador_id, data_publicacao, preco, data_expiracao, status_anuncio) VALUES
    -- 12 anuncios que resultam em venda
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0001'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), '2026-01-05 10:00:00',  850.00, '2026-02-05 10:00:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0003'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), '2026-01-08 14:30:00', 1250.00, '2026-02-08 14:30:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0005'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000005'), '2026-01-12 09:15:00', 2100.00, '2026-02-12 09:15:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0006'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), '2026-01-15 16:45:00', 9800.00, '2026-02-15 16:45:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0008'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000007'), '2026-01-18 11:20:00', 5400.00, '2026-02-18 11:20:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0001'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), '2026-01-20 08:00:00',   45.00, '2026-02-20 08:00:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0003'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), '2026-01-22 19:30:00',  320.00, '2026-02-22 19:30:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0005'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000007'), '2026-01-25 13:10:00',  180.00, '2026-02-25 13:10:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0001'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), '2026-01-28 07:45:00',   12.50, '2026-02-28 07:45:00', 'vendido'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0003'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000005'), '2026-02-01 15:00:00',    9.90, '2026-03-01 15:00:00', 'vendido'),
    -- Estes 2 tem venda, mas nao concluida, e por isso NAO estao 'vendido'.
    -- Anuncio com venda PENDENTE: segue 'ativo' ate o pagamento aprovar.
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0005'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), '2026-02-03 12:25:00',  680.00, '2027-04-30 23:59:59', 'ativo'),
    -- Anuncio com venda CANCELADA (pagamento recusado): vendedor cancelou.
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0002'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), '2026-02-05 17:50:00',  790.00, '2026-03-05 17:50:00', 'cancelado'),
    -- 4 anuncios SEM NENHUMA venda (lado (0,1) de GERA)
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0004'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), '2026-06-01 10:00:00', 1100.00, '2027-04-01 10:00:00', 'ativo'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0007'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000006'), '2026-06-02 11:00:00',   35.00, '2027-04-02 11:00:00', 'ativo'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0007'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000010'), '2025-03-01 09:00:00',   95.00, '2025-04-01 09:00:00', 'expirado'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0009'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), '2026-05-10 18:00:00',    4.50, '2026-06-10 18:00:00', 'cancelado');

-- Os 2 anuncios de REVENDA ficam na secao 13, depois da transferencia
-- de posse: so entao o comprador passa a ser o dono e pode anunciar.


-- ---------------------------------------------------------------------
-- 10. VENDA (12), PAGAMENTO (12), NOTA_FISCAL (10)
--     Cada venda referencia o anuncio por UMA coluna (anuncio_id); no
--     modelo relacional essa FK tinha 3 colunas. O anuncio e localizado
--     pelo identificador completo (item, criador, data_publicacao), o de
--     anuncio_identificador_uk: so pelo item, a subconsulta poderia
--     devolver mais de uma linha, ja que um item pode ter varios
--     anuncios ao longo do tempo (ver secao 13).
--     O comprador NUNCA e o criador do anuncio (regra RS-05).
-- ---------------------------------------------------------------------
INSERT INTO venda (protocolo_venda, anuncio_id, comprador_id, data_venda, valor_venda, status_venda) VALUES
    ('VND-2026-0001',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-EQ-0001'
            AND u.steam_id        = 'STEAM_76561198000000001'
            AND a.data_publicacao = '2026-01-05 10:00:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), '2026-01-06 11:00:00',  850.00, 'concluida'),
    ('VND-2026-0002',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-EQ-0003'
            AND u.steam_id        = 'STEAM_76561198000000003'
            AND a.data_publicacao = '2026-01-08 14:30:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), '2026-01-09 15:00:00', 1250.00, 'concluida'),
    ('VND-2026-0003',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-EQ-0005'
            AND u.steam_id        = 'STEAM_76561198000000005'
            AND a.data_publicacao = '2026-01-12 09:15:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), '2026-01-13 10:00:00', 2100.00, 'concluida'),
    ('VND-2026-0004',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-EQ-0006'
            AND u.steam_id        = 'STEAM_76561198000000001'
            AND a.data_publicacao = '2026-01-15 16:45:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), '2026-01-16 17:30:00', 9800.00, 'concluida'),
    ('VND-2026-0005',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-EQ-0008'
            AND u.steam_id        = 'STEAM_76561198000000007'
            AND a.data_publicacao = '2026-01-18 11:20:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), '2026-01-19 12:00:00', 5400.00, 'concluida'),
    ('VND-2026-0006',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-CO-0001'
            AND u.steam_id        = 'STEAM_76561198000000001'
            AND a.data_publicacao = '2026-01-20 08:00:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), '2026-01-21 09:00:00',   45.00, 'concluida'),
    ('VND-2026-0007',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-CO-0003'
            AND u.steam_id        = 'STEAM_76561198000000003'
            AND a.data_publicacao = '2026-01-22 19:30:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), '2026-01-23 20:00:00',  320.00, 'concluida'),
    ('VND-2026-0008',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-CO-0005'
            AND u.steam_id        = 'STEAM_76561198000000007'
            AND a.data_publicacao = '2026-01-25 13:10:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), '2026-01-26 14:00:00',  180.00, 'concluida'),
    ('VND-2026-0009',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-CN-0001'
            AND u.steam_id        = 'STEAM_76561198000000001'
            AND a.data_publicacao = '2026-01-28 07:45:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), '2026-01-29 08:30:00',   12.50, 'concluida'),
    ('VND-2026-0010',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-CN-0003'
            AND u.steam_id        = 'STEAM_76561198000000005'
            AND a.data_publicacao = '2026-02-01 15:00:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), '2026-02-02 16:00:00',    9.90, 'concluida'),
    -- venda PENDENTE: pagamento ainda nao aprovado, posse NAO transferida
    ('VND-2026-0011',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-CN-0005'
            AND u.steam_id        = 'STEAM_76561198000000002'
            AND a.data_publicacao = '2026-02-03 12:25:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000010'), '2026-02-04 13:00:00',  680.00, 'pendente'),
    -- venda CANCELADA por pagamento recusado (regra RS-16)
    ('VND-2026-0012',
        (SELECT a.id FROM anuncio a
            JOIN item_instancia i ON i.id = a.item_instancia_id
            JOIN usuario        u ON u.id = a.criador_id
          WHERE i.numero_inspecao = 'INS-EQ-0002'
            AND u.steam_id        = 'STEAM_76561198000000002'
            AND a.data_publicacao = '2026-02-05 17:50:00'),
        (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000006'), '2026-02-06 18:30:00',  790.00, 'cancelada');

-- PAGAMENTO: 1:1 TOTAL com venda -> exatamente 12.
-- valor = valor_venda (pagamento integral); status coerente com a venda.
INSERT INTO pagamento (venda_id, metodo_pagamento, valor, data_pagamento, status_pagamento) VALUES
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0001'), 'pix',            850.00, '2026-01-06 11:05:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0002'), 'cartao_credito',1250.00, '2026-01-09 15:10:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0003'), 'pix',           2100.00, '2026-01-13 10:02:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0004'), 'boleto',        9800.00, '2026-01-17 09:00:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0005'), 'cartao_credito',5400.00, '2026-01-19 12:03:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0006'), 'saldo_steam',     45.00, '2026-01-21 09:01:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0007'), 'pix',            320.00, '2026-01-23 20:04:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0008'), 'cartao_debito',  180.00, '2026-01-26 14:02:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0009'), 'saldo_steam',     12.50, '2026-01-29 08:31:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0010'), 'pix',              9.90, '2026-02-02 16:01:00', 'aprovado'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0011'), 'boleto',         680.00, NULL,                  'pendente'),
    ((SELECT id FROM venda WHERE protocolo_venda='VND-2026-0012'), 'cartao_credito',  790.00,'2026-02-06 18:35:00', 'recusado');

-- NOTA_FISCAL: so para as 10 vendas concluidas. As vendas 0011
-- (pendente) e 0012 (cancelada) NAO tem NF -> exercita o lado (0,1) de
-- EMITE. valor_total = valor_venda.
INSERT INTO nota_fiscal (chave, venda_id, data_emissao, valor_total) VALUES
    ('35260114200166000187550010000000011000000013', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0001'), '2026-01-06 11:10:00',  850.00),
    ('35260114200166000187550010000000021000000029', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0002'), '2026-01-09 15:15:00', 1250.00),
    ('35260114200166000187550010000000031000000034', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0003'), '2026-01-13 10:05:00', 2100.00),
    ('35260114200166000187550010000000041000000040', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0004'), '2026-01-17 09:05:00', 9800.00),
    ('35260114200166000187550010000000051000000055', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0005'), '2026-01-19 12:08:00', 5400.00),
    ('35260114200166000187550010000000061000000060', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0006'), '2026-01-21 09:05:00',   45.00),
    ('35260114200166000187550010000000071000000076', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0007'), '2026-01-23 20:08:00',  320.00),
    ('35260114200166000187550010000000081000000081', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0008'), '2026-01-26 14:06:00',  180.00),
    ('35260114200166000187550010000000091000000097', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0009'), '2026-01-29 08:35:00',   12.50),
    ('35260214200166000187550010000000101000000105', (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0010'), '2026-02-02 16:05:00',    9.90);


-- ---------------------------------------------------------------------
-- 11. TROCA (10) e TROCA_ITEM (21)
--     Cada troca tem >=1 item 'oferecido' (do proponente) e >=1
--     'solicitado' (do destinatario), conforme a regra RS-08.
--     Cada item pertence ao participante NA DATA DA PROPOSTA (contando as
--     vendas e trocas concluidas antes dela), esta disponivel e
--     negociavel, e nao esta comprometido em outro negocio em aberto.
--     Itens de trocas CONCLUIDAS nao participam de vendas nem de outras
--     trocas concluidas: cada item muda de dono no maximo uma vez.
--     data_efetivacao so existe quando status='concluida' (CHECK).
-- ---------------------------------------------------------------------
INSERT INTO troca (protocolo_troca, proponente_id, destinatario_id, data_proposta, data_efetivacao, status_troca, laudo_troca, observacao) VALUES
    ('TRC-2026-0001', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), '2026-03-01 10:00:00', '2026-03-02 10:00:00', 'concluida', 'Ambas as partes confirmaram.', 'Troca 1x1 de adesivos.'),
    ('TRC-2026-0002', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000006'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000008'), '2026-03-03 11:30:00', '2026-03-04 09:00:00', 'concluida', 'Concluida sem intercorrencias.', NULL),
    ('TRC-2026-0003', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), '2026-03-05 14:00:00', '2026-03-06 14:00:00', 'concluida', 'Chave trocada por chaveiro.', 'Proponente pediu agilidade.'),
    ('TRC-2026-0004', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000007'), '2026-03-08 16:20:00', '2026-03-09 16:20:00', 'concluida', 'Adesivo trocado por grafite.', NULL),
    ('TRC-2026-0005', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000010'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), '2026-03-10 08:00:00', NULL, 'pendente',  NULL, 'Aguardando resposta do destinatario.'),
    ('TRC-2026-0006', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000005'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), '2026-03-12 19:45:00', NULL, 'recusada',  NULL, 'Destinatario achou a oferta baixa.'),
    ('TRC-2026-0007', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000006'), '2026-03-15 12:00:00', NULL, 'cancelada', NULL, 'Proponente desistiu.'),
    ('TRC-2026-0008', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000008'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), '2026-03-18 09:30:00', NULL, 'aceita',    NULL, 'Aceita, aguardando processamento.'),
    ('TRC-2026-0009', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), '2026-03-20 17:00:00', '2026-03-21 17:00:00', 'concluida', 'Troca multipla 2x1.', 'Proponente ofereceu 2 itens.'),
    ('TRC-2026-0010', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000007'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), '2026-03-22 13:15:00', NULL, 'pendente',  NULL, NULL);

INSERT INTO troca_item (troca_id, item_instancia_id, lado_troca) VALUES
    -- TRC-0001: Bruno(2) oferece CO-0002 <-> Diego(4) tem CO-0010
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0001'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0002'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0001'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0010'), 'solicitado'),
    -- TRC-0002: Felipe(6) oferece CN-0004 <-> Henrique(8) tem CN-0006
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0002'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0004'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0002'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0006'), 'solicitado'),
    -- TRC-0003: Isabela(9) oferece CN-0007 <-> Larissa(11) tem CO-0008
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0003'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0007'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0003'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0008'), 'solicitado'),
    -- TRC-0004: Marcelo(12) oferece CO-0009 <-> Gabriela(7) tem CN-0010
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0004'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0009'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0004'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0010'), 'solicitado'),
    -- TRC-0005 (pendente): Joao(10) oferece CO-0007 <-> Carla(3) tem CN-0002
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0005'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0007'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0005'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0002'), 'solicitado'),
    -- TRC-0006 (recusada): Elisa(5) oferece CO-0004 <-> Larissa(11) tem EQ-0006
    --   (Larissa comprou o M4A4 em 16/01 e recusou trocar por um adesivo)
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0006'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0004'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0006'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0006'), 'solicitado'),
    -- TRC-0007 (cancelada): Diego(4) oferece EQ-0004 <-> Felipe(6) tem EQ-0007
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0007'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0004'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0007'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0007'), 'solicitado'),
    -- TRC-0008 (aceita): Henrique(8) oferece EQ-0015 <-> Bruno(2) tem EQ-0002
    --   (Nova e AK-47, ambas Classified)
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0008'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0015'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0008'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0002'), 'solicitado'),
    -- TRC-0009 (concluida, 2x1): Larissa(11) oferece CN-0008 + CN-0018 <-> Isabela(9) tem CO-0006
    --   (duas chaves por um chaveiro)
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0009'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0008'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0009'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0018'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0009'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0006'), 'solicitado'),
    -- TRC-0010 (pendente): Gabriela(7) oferece CO-0009 <-> Marcelo(12) tem CN-0009
    --   (Gabriela recebeu o CO-0009 do Marcelo na TRC-0004 e quer outro grafite)
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0010'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CO-0009'), 'oferecido'),
    ((SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0010'), (SELECT id FROM item_instancia WHERE numero_inspecao='INS-CN-0009'), 'solicitado');


-- ---------------------------------------------------------------------
-- 12. TRANSFERENCIA DE POSSE  (a regra temporal em acao)
--     So agora os itens mudam de dono; anuncios e trocas acima ja foram
--     registrados com o dono de cada item naquele momento.
--     Transferem posse:
--       - vendas CONCLUIDAS  -> item passa ao comprador
--       - trocas CONCLUIDAS  -> oferecidos vao ao destinatario,
--                               solicitados vao ao proponente
--     NAO transferem: venda pendente/cancelada, troca nao concluida.
--     Os cosmeticos aplicados numa arma vendida vao junto com ela
--     (trigger trg_cosmeticos_acompanham_equipamento).
-- ---------------------------------------------------------------------
-- 12.1 Vendas concluidas: o item vai para o comprador.
UPDATE item_instancia ii
   SET proprietario_id = v.comprador_id
  FROM venda v
  JOIN anuncio a ON a.id = v.anuncio_id
 WHERE ii.id = a.item_instancia_id
   AND v.status_venda = 'concluida';

-- 12.2 Trocas concluidas: itens oferecidos -> destinatario.
UPDATE item_instancia ii
   SET proprietario_id = t.destinatario_id
  FROM troca_item ti
  JOIN troca t ON t.id = ti.troca_id
 WHERE ii.id = ti.item_instancia_id
   AND ti.lado_troca = 'oferecido'
   AND t.status_troca = 'concluida';

-- 12.3 Trocas concluidas: itens solicitados -> proponente.
UPDATE item_instancia ii
   SET proprietario_id = t.proponente_id
  FROM troca_item ti
  JOIN troca t ON t.id = ti.troca_id
 WHERE ii.id = ti.item_instancia_id
   AND ti.lado_troca = 'solicitado'
   AND t.status_troca = 'concluida';


-- ---------------------------------------------------------------------
-- 13. REVENDA: 2 anuncios criados DEPOIS da transferencia de posse (e 1 do JV)
--     Larissa comprou o M4A4 e o Karambit (vendas 0004 e 0005) e agora
--     os revende mais caro; Joao anuncia uma Desert Eagle que ja tinha.
--     Exercita o (0,N) de OFERECE: um item pode ter VARIOS anuncios ao
--     longo do tempo (um antigo 'vendido' e um novo 'ativo'). O que NAO
--     pode e um anuncio gerar 2 vendas (UNIQUE(anuncio_id) em venda).
--     So podem entrar agora: trg_validar_anuncio exige que o criador ja
--     seja o dono do item.
-- ---------------------------------------------------------------------
INSERT INTO anuncio (item_instancia_id, criador_id, data_publicacao, preco, data_expiracao, status_anuncio) VALUES
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0006'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), '2026-06-10 09:00:00', 10500.00, '2027-04-10 09:00:00', 'ativo'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0008'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), '2026-06-11 10:30:00',  5900.00, '2027-04-11 10:30:00', 'ativo'),
    ((SELECT id FROM item_instancia WHERE numero_inspecao='INS-EQ-0010'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000010'), '2026-06-12 14:00:00',  1950.00, '2027-04-12 14:00:00', 'ativo');


-- ---------------------------------------------------------------------
-- 14. AVALIACAO (10) + subtipos (5 + 5 = 10, fechando o XOR)
--     Avaliacoes so de operacoes CONCLUIDAS.
--     A venda VND-2026-0001 recebe DUAS avaliacoes (uma de cada parte),
--     que e o (0,N) do lado AVALIACAO em AVALIA_VENDA.
-- ---------------------------------------------------------------------
INSERT INTO avaliacao (ticket_avaliacao, autor_id, avaliado_id, data_avaliacao, comentario, nota) VALUES
    -- 5 referentes a VENDA
    ('TKT-2026-0001', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), '2026-01-07 10:00:00', 'Vendedor rapido, item exatamente como anunciado.', 5),
    ('TKT-2026-0002', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), '2026-01-07 10:30:00', 'Comprador pagou na hora. Recomendo.', 5),
    ('TKT-2026-0003', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000003'), '2026-01-10 12:00:00', 'Demorou para liberar o item, mas correu bem.', 3),
    ('TKT-2026-0004', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), '2026-01-18 09:00:00', 'Item raro e autentico. Excelente negociacao.', 5),
    ('TKT-2026-0005', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000001'), '2026-01-22 11:00:00', 'Adesivo veio certo, mas comunicacao foi fraca.', 2),
    -- 5 referentes a TROCA
    ('TKT-2026-0006', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000004'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000002'), '2026-03-02 12:00:00', 'Troca justa e rapida.', 5),
    ('TKT-2026-0007', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000008'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000006'), '2026-03-04 10:00:00', 'Tudo certo, recomendo o parceiro.', 4),
    ('TKT-2026-0008', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), '2026-03-06 15:00:00', 'Proponente foi honesto na descricao.', 4),
    ('TKT-2026-0009', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000007'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000012'), '2026-03-09 18:00:00', 'Troca simples, sem problemas.', 4),
    ('TKT-2026-0010', (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000009'), (SELECT id FROM usuario WHERE steam_id='STEAM_76561198000000011'), '2026-03-21 19:00:00', 'Aceitou a troca 2x1 sem reclamar. Otimo.', 5);

-- Subtipo VENDA (5)
INSERT INTO avaliacao_venda (avaliacao_id, venda_id) VALUES
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0001'), (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0001')),
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0002'), (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0001')),
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0003'), (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0002')),
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0004'), (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0004')),
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0005'), (SELECT id FROM venda WHERE protocolo_venda='VND-2026-0006'));

-- Subtipo TROCA (5)
INSERT INTO avaliacao_troca (avaliacao_id, troca_id) VALUES
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0006'), (SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0001')),
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0007'), (SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0002')),
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0008'), (SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0003')),
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0009'), (SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0004')),
    ((SELECT id FROM avaliacao WHERE ticket_avaliacao='TKT-2026-0010'), (SELECT id FROM troca WHERE protocolo_troca='TRC-2026-0009'));


-- ---------------------------------------------------------------------
-- 15. ABERTURA_RECIPIENTE  (5)
--     Uma caixa aberta com chave e capsulas abertas sem chave.
--     Cada INSERT dispara trg_registrar_abertura_recipiente (02_regras.sql),
--     que valida a abertura e marca o recipiente e a chave como
--     consumidos; por isso 02_regras.sql roda ANTES deste arquivo.
-- ---------------------------------------------------------------------
INSERT INTO abertura_recipiente
    (usuario_id, recipiente_id, chave_id, item_resultado_id, data_abertura)
SELECT
    u.id, recipiente.id, chave.id, resultado.id, '2026-06-20 10:00:00'
FROM usuario u
JOIN item_instancia recipiente ON recipiente.numero_inspecao = 'INS-CN-0011'
JOIN item_instancia chave      ON chave.numero_inspecao = 'INS-CN-0012'
JOIN item_instancia resultado  ON resultado.numero_inspecao = 'INS-EQ-0011'
WHERE u.steam_id = 'STEAM_76561198000000001'
  AND NOT EXISTS (
      SELECT 1 FROM abertura_recipiente a
       WHERE a.recipiente_id = recipiente.id
  );

INSERT INTO abertura_recipiente
    (usuario_id, recipiente_id, chave_id, item_resultado_id, data_abertura)
SELECT
    u.id, recipiente.id, NULL, resultado.id, '2026-06-21 11:00:00'
FROM usuario u
JOIN item_instancia recipiente ON recipiente.numero_inspecao = 'INS-CN-0013'
JOIN item_instancia resultado  ON resultado.numero_inspecao = 'INS-CO-0011'
WHERE u.steam_id = 'STEAM_76561198000000002'
  AND NOT EXISTS (
      SELECT 1 FROM abertura_recipiente a
       WHERE a.recipiente_id = recipiente.id
  );

INSERT INTO abertura_recipiente
    (usuario_id, recipiente_id, chave_id, item_resultado_id, data_abertura)
SELECT
    u.id, recipiente.id, NULL, resultado.id, '2026-06-22 14:00:00'
FROM usuario u
JOIN item_instancia recipiente ON recipiente.numero_inspecao = 'INS-CN-0014'
JOIN item_instancia resultado  ON resultado.numero_inspecao = 'INS-CN-0016'
WHERE u.steam_id = 'STEAM_76561198000000003'
  AND NOT EXISTS (
      SELECT 1 FROM abertura_recipiente a
       WHERE a.recipiente_id = recipiente.id
  );

INSERT INTO abertura_recipiente
    (usuario_id, recipiente_id, chave_id, item_resultado_id, data_abertura)
SELECT
    u.id, recipiente.id, NULL, resultado.id, '2026-06-23 16:00:00'
FROM usuario u
JOIN item_instancia recipiente ON recipiente.numero_inspecao = 'INS-CN-0015'
JOIN item_instancia resultado  ON resultado.numero_inspecao = 'INS-CO-0012'
WHERE u.steam_id = 'STEAM_76561198000000004'
  AND NOT EXISTS (
      SELECT 1 FROM abertura_recipiente a
       WHERE a.recipiente_id = recipiente.id
  );

-- 5a abertura: outra capsula Ambush, sem chave.
INSERT INTO abertura_recipiente
    (usuario_id, recipiente_id, chave_id, item_resultado_id, data_abertura)
SELECT
    u.id, recipiente.id, NULL, resultado.id, '2026-06-24 09:30:00'
FROM usuario u
JOIN item_instancia recipiente ON recipiente.numero_inspecao = 'INS-CN-0017'
JOIN item_instancia resultado  ON resultado.numero_inspecao = 'INS-CO-0013'
WHERE u.steam_id = 'STEAM_76561198000000005'
  AND NOT EXISTS (
      SELECT 1 FROM abertura_recipiente a
       WHERE a.recipiente_id = recipiente.id
  );


-- ---------------------------------------------------------------------
-- 16. NUMERACAO DAS PROXIMAS VENDAS E AVALIACOES
--     As vendas e avaliacoes criadas pela aplicacao (fn_comprar_anuncio
--     e fn_avaliar_venda) continuam a numeracao a partir das que ja
--     existem: a proxima venda sera VND-AAAA-0013, e assim por diante.
-- ---------------------------------------------------------------------
SELECT setval('venda_protocolo_seq',
              (SELECT MAX(SUBSTRING(protocolo_venda FROM 10)::INTEGER) FROM venda));
SELECT setval('avaliacao_ticket_seq',
              (SELECT MAX(SUBSTRING(ticket_avaliacao FROM 10)::INTEGER) FROM avaliacao));

COMMIT;
