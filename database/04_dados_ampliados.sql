-- =====================================================================
-- VAULTGABE
-- 04 - DADOS AMPLIADOS: mais modelos, mais exemplares e um ano de
--      historico de negociacoes para os graficos e rankings da aplicacao
--
-- ORDEM DE EXECUCAO: 01_tabelas -> 02_regras -> 03_dados -> 04_dados_ampliados -> 05_verificacao
-- Este script ACRESCENTA dados aos do 03, corrige alguns deles (secao 11)
-- e roda com os triggers do 02 ligados: cada anuncio, venda e avaliacao passa pelas
-- mesmas regras que valem para a aplicacao.
-- Para executa-lo de novo, rode antes o 03 (que limpa e recarrega tudo).
--
-- ATENCAO: PRECOS E NEGOCIACOES SAO SIMULADOS
--   Os 80 modelos sao itens reais do CS2: nome, raridade, colecao, faixa
--   de float e imagem oficial vem do CSGO-API
--   (github.com/ByMykel/CSGO-API). Imagens (c) Valve Corporation.
--   Ja os precos, vendas, avaliacoes e anuncios sao valores SIMULADOS
--   para a demonstracao. NAO sao precos reais de mercado.
--
-- O QUE ESTE SCRIPT ACRESCENTA (numeros exatos no resumo, no fim):
--   colecao             16 colecoes reais novas, com a data de lancamento
--                       (a secao 11.1 acrescenta 2 e remove 1 que fica vazia)
--   item_catalogo       59 modelos novos (21 do 03 + 59 = 80)
--   item_instancia      exemplares novos dos 80 modelos, espalhados entre
--                       os 12 usuarios (+ adesivos e chaveiros aplicados)
--   anuncio, venda,     um ano de vendas concluidas (01/11/2025 a
--   pagamento, NF       26/10/2026), cada uma com anuncio, pagamento
--                       aprovado e nota fiscal, inclusive revendas
--   avaliacao           cerca de 39% das vendas novas, do comprador
--                       para o vendedor
--   anuncio             anuncios ativos publicados em outubro/2026 e
--                       anuncios cancelados/expirados (aba Encerrados)
--   ajustes no 03       colecoes conferidas com o CSGO-API, datas dos
--                       chaveiros, variantes impossiveis, preco da capsula,
--                       aberturas coerentes com os recipientes e acentos
--                       nos textos (secao 11)
--
-- COMO OS DADOS SAO GERADOS
--   A secao 3 tem uma linha de parametros por modelo (preco de
--   referencia e quantidade de exemplares). A partir dela, os exemplares
--   e as vendas saem de generate_series. Os "sorteios" (dono, float,
--   datas, comprador, ruido do preco...) usam pg_temp.sorteio(texto),
--   que tira um numero entre 0 e 1 do md5 de um texto fixo. Nao ha
--   random() nem now(): o script gera SEMPRE os mesmos dados, em
--   qualquer dia em que for executado.
--   Por isso a chave da nota fiscal vem de pg_temp.chave_nfe(numero,
--   data de emissao): o mesmo calculo de fn_gerar_chave_nfe
--   (02_regras.sql), mas com o ano/mes da EMISSAO da nota, e nao o da
--   execucao (fn_gerar_chave_nfe continua sendo usada nas compras feitas
--   pela aplicacao, emitidas no proprio dia).
--
-- PRECO SIMULADO (pg_temp.preco_simulado, secao 3)
--   preco_ref do modelo
--     x desgaste   FN 1,30 | MW 1,12 | FT 1,00 | WW 0,90 | BS 0,80,
--                  em relacao ao desgaste tipico do modelo
--     x StatTrak   1,45 (facas 1,15)      x Souvenir 1,50
--     x tendencia  cada modelo sobe ou cai entre -2% e +3% ao mes
--     x ajuste     ruido de +-7% na venda; margem do vendedor nos anuncios
--
-- CLASSE VENDIDA (secao 3) E EXEMPLARES DE REFERENCIA (secao 4.5)
--   Cada modelo tem uma classe vendida: a versao mais negociada dele, no
--   desgaste tipico e sem StatTrak (nos modelos com versao Souvenir,
--   cerca de metade, sorteada por modelo, e vendida como Souvenir). Nos
--   modelos que o 03 ja vendeu, vale a classe do exemplar vendido no 03.
--   Os exemplares que tem a 1a ou a ultima venda (cronologica) de cada
--   modelo sao os de REFERENCIA e ficam nessa classe: assim o ranking de
--   maiores variacoes (primeira x ultima venda) mostra a TENDENCIA do
--   preco, e nao a troca de um FN por um BS ou de um StatTrak por um
--   comum.
--   Os demais exemplares vendidos variam de desgaste e de StatTrak
--   (secao 4.5): por isso o historico de vendas mostra o FN mais caro
--   que o BS e o premio do StatTrak.
--   Os exemplares que nunca foram vendidos cobrem todos os desgastes,
--   StatTrak e Souvenir, e aparecem nos anuncios ativos e encerrados.
--
-- LINHA DO TEMPO DE POSSE (a mesma regra temporal do 03)
--   - Os exemplares novos sao obtidos ate 15/10/2025, antes da 1a venda
--     (exceto alguns 'bloqueado', recebidos em outubro/2026, que nunca
--     sao anunciados).
--   - Cada exemplar tem uma CADEIA de 0 a 3 vendas: o 1o vendedor e o
--     dono original e o comprador de uma venda e o vendedor da seguinte
--     (revenda). Cada anuncio e publicado DEPOIS da compra anterior.
--   - As vendas sao gravadas em ordem cronologica (secao 7). Em cada
--     anuncio, o trigger trg_validar_anuncio confere que o vendedor e o
--     dono do item NAQUELE momento; so depois da venda a posse passa ao
--     comprador. No fim, o dono de cada item e o comprador da sua ultima
--     venda (regras RS-04 e RS-07 de 05_verificacao.sql).
--   - Anuncios cancelados/expirados usam so itens que nunca foram
--     vendidos; os anuncios ativos de outubro vem depois da ultima venda
--     do item (as cadeias desses itens terminam ate 30/09/2026).
-- =====================================================================

BEGIN;


-- ---------------------------------------------------------------------
-- 0. PREPARACAO
--    Confere que o 03 acabou de rodar e cria os auxiliares TEMPORARIOS
--    (pg_temp): somem no fim do script e nao fazem parte do banco.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM item_catalogo WHERE nome_item = 'AK-47 | Redline') THEN
        RAISE EXCEPTION 'Execute 01_tabelas.sql, 02_regras.sql e 03_dados.sql antes deste script.';
    END IF;
    IF EXISTS (SELECT 1 FROM item_catalogo WHERE nome_item = 'AWP | Dragon Lore') THEN
        RAISE EXCEPTION 'Este script ja foi executado. Rode 03_dados.sql de novo antes de repeti-lo.';
    END IF;
END $$;

-- Sorteio deterministico: o mesmo texto da sempre o mesmo numero em [0, 1).
CREATE FUNCTION pg_temp.sorteio(p_chave TEXT)
RETURNS NUMERIC AS $$
    SELECT ('x' || substr(md5(p_chave), 1, 8))::bit(32)::bigint / 4294967296.0;
$$ LANGUAGE sql IMMUTABLE;

-- Fator de preco do desgaste (exterior calculado por fn_desgaste).
CREATE FUNCTION pg_temp.fator_desgaste(p_float NUMERIC)
RETURNS NUMERIC AS $$
    SELECT CASE fn_desgaste(p_float)
               WHEN 'FN' THEN 1.30
               WHEN 'MW' THEN 1.12
               WHEN 'FT' THEN 1.00
               WHEN 'WW' THEN 0.90
               WHEN 'BS' THEN 0.80
               ELSE 1
           END;
$$ LANGUAGE sql IMMUTABLE;

-- Chave da NF-e (44 digitos) de uma nota emitida na data p_data. E o
-- mesmo calculo de fn_gerar_chave_nfe (02_regras.sql): UF 35, ano/mes,
-- CNPJ do VaultGabe, modelo 55, serie 001, numero da nota (9 digitos),
-- emissao normal (1), codigo numerico (8 digitos) e digito verificador
-- (modulo 11, pesos de 2 a 9 da direita para a esquerda). A diferenca
-- e o ano/mes: o da EMISSAO, e nao o do dia em que o script roda.
CREATE FUNCTION pg_temp.chave_nfe(p_numero BIGINT, p_data TIMESTAMP)
RETURNS VARCHAR(44) AS $$
DECLARE
    v_base  VARCHAR(43);
    v_soma  INTEGER := 0;
    v_peso  INTEGER := 2;
    v_resto INTEGER;
BEGIN
    v_base := '35' || to_char(p_data, 'YYMM') || '14200166000187' || '55' || '001'
              || lpad(p_numero::TEXT, 9, '0') || '1' || lpad(p_numero::TEXT, 8, '0');

    FOR i IN REVERSE 43..1 LOOP
        v_soma := v_soma + substr(v_base, i, 1)::INTEGER * v_peso;
        v_peso := CASE WHEN v_peso = 9 THEN 2 ELSE v_peso + 1 END;
    END LOOP;

    v_resto := v_soma % 11;
    RETURN v_base || CASE WHEN v_resto < 2 THEN 0 ELSE 11 - v_resto END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Confere que o calculo e o mesmo de fn_gerar_chave_nfe: com a data de
-- hoje, as duas funcoes tem de dar a mesma chave.
DO $$
BEGIN
    IF pg_temp.chave_nfe(123, now()::TIMESTAMP) <> fn_gerar_chave_nfe(123) THEN
        RAISE EXCEPTION 'pg_temp.chave_nfe difere de fn_gerar_chave_nfe.';
    END IF;
END $$;

-- Usuarios numerados de 1 a 12 na ordem do steam_id (os 12 do 03).
-- O usuario de demonstracao isizinha e o numero 9.
CREATE TEMP TABLE tmp_usuario AS
SELECT ROW_NUMBER() OVER (ORDER BY steam_id)::INTEGER AS n,
       id,
       apelido
  FROM usuario;


-- ---------------------------------------------------------------------
-- 1. COLECAO  (16 novas; 29 no total depois da secao 11.1)
--    Colecoes reais dos modelos novos: nome do CSGO-API e data de
--    lancamento. Os modelos novos da "The Danger Zone Collection" e da
--    "The Bravo Collection" usam as linhas que o 03 ja criou
--    ('The Danger Zone Case' e 'Operation Bravo', renomeadas na 11.1).
-- ---------------------------------------------------------------------
INSERT INTO colecao (nome_colecao, data_lancamento) VALUES
    ('The eSports 2013 Collection',           '2013-08-14'),
    ('The Winter Offensive Collection',       '2013-12-18'),
    ('The Phoenix Collection',                '2014-02-20'),
    ('The Huntsman Collection',               '2014-05-01'),
    ('The Breakout Collection',               '2014-07-01'),
    ('The Cobblestone Collection',            '2014-07-01'),
    ('The Chroma 2 Collection',               '2015-04-15'),
    ('The Falchion Collection',               '2015-05-26'),
    ('The Shadow Collection',                 '2015-09-17'),
    ('The Chroma 3 Collection',               '2016-04-27'),
    ('The Operation Hydra Collection',        '2017-05-23'),
    ('The Clutch Collection',                 '2018-02-15'),
    ('The Horizon Collection',                '2018-08-02'),
    ('The Operation Broken Fang Collection',  '2020-12-03'),
    ('The Dreams & Nightmares Collection',    '2022-01-20'),
    ('Missing Link Charm Collection',         '2024-10-02');


-- ---------------------------------------------------------------------
-- 2. ITEM_CATALOGO  (59 modelos novos -> 80 no total)
--    Mesmo formato do 03: FKs pela chave natural, faixa de float so nos
--    modelos de EQUIPAMENTO e imagem_base = campo "image" do CSGO-API.
--    Raridade, colecao e faixa de float tambem sao as do CSGO-API.
--    Nenhum modelo repete os 21 do 03.
-- ---------------------------------------------------------------------
-- 2.1 Modelos de EQUIPAMENTO (49)
INSERT INTO item_catalogo (nome_item, categoria_id, raridade_id, colecao_id, imagem_base, float_min, float_max, descricao) VALUES
    -- Rifles (16): as snipers ficam em Rifle, como a AWP do 03
    ('AK-47 | Asiimov',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Danger Zone Case'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwlcK3wiFO0POlPPNSIeOaB2qf19F6ueZhW2e2wEt-t2jcytf6dymSO1JxA5oiRecLsRa5kIfkYr-241aLgotHz3-rkGoXuUp8oX57', 0.05000000, 0.70000000, 'Rifle com o visual futurista Asiimov em laranja, preto e branco.'),
    ('AK-47 | Vulcan',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Huntsman Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwlcK3wiFO0POlPPNSMuWRDGKC_uJ_t-l9AXCxxEh14zjTztivci2ePQZ2W8NzTecD4BKwloLiYeqxtAOIj9gUyyngznQeF7I6QE8', 0.00000000, 0.90000000, 'Rifle com grafismo esportivo em azul, branco e preto.'),
    ('AK-47 | Fire Serpent',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'Operation Bravo'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwlcK3wiFO0PSneqF-JeKDC2mE_u995LZWTTuygxIYvzSCkpu3cnvFPQB2DpUkROFY4Rntw93lP7i241DbiI1BxSuviHlKunk_6-sHU71lpPMTRLyP4Q', 0.06000000, 0.76000000, 'Rifle com uma serpente de fogo em estilo asteca. Item classico e raro.'),
    ('AK-47 | Slate',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Restricted'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Snakebite Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwlcK3wiVI0POlPPNSMOKcCGKD0ud5vuBlcCW6khUz_W3Sytb4cCqTOFUpWJtzTOUD5hPsw9a0Yrnrs1SK3ooXzy6shilM5311o7FVYrIufmI', 0.00000000, 1.00000000, 'Rifle em tons de cinza ardosia com detalhes discretos.'),
    ('AK-47 | Ice Coaled',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Recoil Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwlcK3wiFO0POlPPNSI_-UGm-Zz-llj-1gSCGn2x4l5z_RyNj6JXnEbgFzXMYjEOUIsBe5m9exP-zg4leMj4pGxXn7jCJXrnE84asPq_0', 0.00000000, 0.77000000, 'Rifle com padrao de gelo em azul e preto.'),
    ('AK-47 | Legion of Anubis',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Fracture Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwlcK3wiFO0POlPPNSIf6GDG6D_uJ_t-l9AX_nzBhw4TvWwo6udC2QbgZyWcN2RuMP4xHrlYDnYezm7geP3d5FyH3gznQeY_Oe4QY', 0.00000000, 0.70000000, 'Rifle com motivos egipcios do deus Anubis em dourado.'),
    ('AK-47 | Bloodsport',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Spectrum Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwlcK3wiVI0POlPPNSIvycAWOD0eFkpN5lRi67gVN15mmDw9egci_EPFAkDMQlTeZe4EXplNa0Yrvr5wbd345GyHioiC4b8G81tFuqg_k_', 0.00000000, 0.45000000, 'Rifle com pintura vermelha, preta e branca em estilo tecnologico.'),
    ('M4A1-S | Printstream',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Operation Broken Fang Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8ypexwjFS4_ega6F_H_OGMWrEwL9lj_F7Rienhgk1tjyIpYPwJiPTcAAoCpsiEO5ZsUbpm9C2Zuni4VHW3o5EzSX62HxP7Sg96-hWVqYi_6TJz1aW0nxrkGs', 0.00000000, 0.80000000, 'Rifle com silenciador em branco perolado com detalhes pretos.'),
    ('M4A1-S | Hyper Beast',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Chroma 2 Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8ypexwjFS4_ega6F_H_OGMWrEwL9JuPh5SjuMlxgmoCm6lob-KT-JbwF1WZEjR-YJskK9k9XiYePltAeNjYlAxSn5j34dvCZstb4LB6Ut-7qX0V8Xkv5_2A', 0.00000000, 1.00000000, 'Rifle com silenciador e criatura estilizada em cores vibrantes.'),
    ('M4A4 | The Emperor',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Prisma Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8ypexwiVI0P_6afBSJf2DC3Wf09F6ueZhW2exwBh_6m3dnt36InjDPQ4oXJt1TbJeshW_mtfjN-vrsgaKiokWy333kGoXuRj4z9Nd', 0.00000000, 0.80000000, 'Rifle com o retrato de um imperador em azul e dourado.'),
    ('AWP | Dragon Lore',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Cobblestone Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwiYbf_jdk4veqYaF7IfysCnWRxuF4j-B-Xxa_nBovp3Pdwtj9cC_GaAd0DZdwQu9fuhS4kNy0NePntVTbjYpCyyT_3CgY5i9j_a9cBkcCWUKV', 0.00000000, 0.70000000, 'Sniper com um dragao medieval pintado. Uma das skins mais desejadas do jogo.'),
    ('AWP | Neo-Noir',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Danger Zone Case'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwiYbf_jdk7uW-V6poL_6cB3WvzedxuPUnHirrxR4l423SyI39I3KXPwdxWZclQeNZ5EXskYfnNeyw71OMi9lNzDK-0H3r66pOTw', 0.00000000, 0.50000000, 'Sniper com ilustracao em estilo de quadrinhos noir.'),
    ('AWP | Atheris',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Restricted'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Prisma Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwiYbf_jdk7uW-V7JkMPWBMWuZxuZi_rZsS3zgzU8isW3dnIr6eHKfPVAhDpojEe9YsUW4xta1Nuzm5FDci4NbjXKpmWVQppo', 0.00000000, 1.00000000, 'Sniper com padrao de escamas de serpente.'),
    ('AWP | Chromatic Aberration',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Recoil Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwiYbf_jdk7uW-V6dlMv-eD1iAyOB9j-1gSCGn2x50tT_Tm9f4cXORPA4oWJckFOMLtha_x9e1Nu-35QfbjYtHyiythitXrnE8ylr09zg', 0.00000000, 0.70000000, 'Sniper com efeito de aberracao cromatica em tons neon.'),
    ('AWP | Hyper Beast',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Falchion Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLwiYbf_jdk7uW-V6x0MPWBMWWVwP1ij-1gSCGn20pxtm_WzNuoeHKeaFAnCZUiTe5bt0HqxofmZOrm5Q2IjoMQzS_5iShXrnE8NzWs__c', 0.00000000, 1.00000000, 'Sniper com criatura estilizada em cores psicodelicas.'),
    ('Galil AR | Chatterbox',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Rifle'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Chroma Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL2n5rp8SNJ0PG7V6NsLPmfMWaS0-9lue5ncCS2kRQyvnPXnIn7eSrEZ1AnD5NxTeII4ESwxN3jN7zl5QHXjdhAnyuo2y9Nv3xs_a9cBuAhdjfO', 0.35000000, 0.85000000, 'Rifle com caveiras desenhadas e detalhes em laranja.'),
    -- Pistolas (10)
    ('Desert Eagle | Printstream',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Fracture Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL1m5fn8Sdk7OeRbKFsJ8-DHG6e1f1iouRoQha_nBovp3OGmdeqInyVP1V0XsYlRbEI50a5wNyzZr605AyI3t5MmCSohylAuC89_a9cBoMY9UkV', 0.00000000, 0.80000000, 'Pistola em branco perolado com detalhes pretos.'),
    ('Desert Eagle | Code Red',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Horizon Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL1m5fn8Sdk6OGRbKFsJ_yWMWaXxvxzo_JmXRa_nBovp3PRmNj4c3mTb1RxC5cjF-EItRnrlNzkYrnk5gaI3Y0UmyX52H9K7ixs_a9cBsGEcOCn', 0.00000000, 1.00000000, 'Pistola com detalhes tecnologicos em vermelho e preto.'),
    ('Desert Eagle | Kumicho Dragon',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Wildfire Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL1m5fn8Sdk7uORbKF-JeKHC2aXzetJu_RkRiq7mhk1sjqKlLD1KCzPKhh0CcBwQLVe5BHrloKyZOnr5w3XiYhDnC39iCpK7X1psrlUWaFw8qXekUifZlV_fDVZ', 0.00000000, 0.76000000, 'Pistola com dragao japones em vermelho e dourado.'),
    ('USP-S | Kill Confirmed',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Shadow Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLkjYbf7itX6vytbbZSI-WsG3SA_uV_vO1WTCa9kxQ1vjiBpYPwJiPTcFB2Xpp5TO5cskG9lYCxZu_jsVCL3o4Xnij23ClO5ik9tegFA_It8qHJz1aWe-uc160', 0.00000000, 1.00000000, 'Pistola com silenciador e uma caveira ilustrada.'),
    ('USP-S | Neo-Noir',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Spectrum Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLkjYbf7itX6vytbbZSI-WsG3SA0tF4v-h7cCW6khUz_WXdmd-vI3uRPwEkApR4QuBcu0Xrk4biYr_mtQXdidlCz3r63Ska7Hx1o7FVWuokIcU', 0.00000000, 0.70000000, 'Pistola com silenciador e ilustracao em estilo noir.'),
    ('USP-S | Printstream',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Recoil Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLkjYbf7itX6vytbbZSI-WsG3SA_v5kue99XD2hkBwqjDGMnYftb3yUPFR0XsNyRrNc5kO5ltziMenr5lONj4kXyi2riywc7y9o5LtQAqQ7uvqAkScWnv4', 0.00000000, 0.85000000, 'Pistola com silenciador em branco perolado e preto.'),
    ('Glock-18 | Vogue',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Fracture Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL2kpnj9h1Y-s2pZKtuK8-WF2KTzuBiseJ9cCW6khUz_T-GyNavdCqRawN1CMFwTOcO5hO7loXiY-zmsQKPi44QzHj22ikcvy11o7FVfFOBmfY', 0.00000000, 0.75000000, 'Pistola com estampa de moda em cores fortes.'),
    ('Glock-18 | Water Elemental',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Breakout Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL2kpnj9h1Y-s2pZKtuK72fB3aFxP11te99cCW6khUz_TjVyompc3-QOFR2DJQkFOMJtBbqk9LlY-7n5QLZjtkTxCWqhixPv311o7FVIf8eASQ', 0.00000000, 0.70000000, 'Pistola com criatura aquatica em azul e vermelho.'),
    ('Glock-18 | Groundwater',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Industrial Grade'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Mirage Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL2kpnj9h1I4M2hZK17Jc-fB2CY1aBzseQ4GXG1lEwk4mWHmd39dC7BOwImD8F2QedeshjrkYKyML-z4Q3flcsbmqxtqryL', 0.06000000, 0.80000000, 'Pistola com camuflagem simples em verde e marrom.'),
    ('Five-SeveN | Hyper Beast',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Pistola'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Operation Hydra Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL3l4Dl7idN6vyRa7FSJvmFC3SV1-t4j-lwXyyhlxgmoCm6lob-KT-JO1QgWZVyELEPu0W4l9KzYbzn5Fbf3YkTzn_8hihIvXxtsOoFUKYirLqX0V_f6-eqCw', 0.00000000, 1.00000000, 'Pistola com criatura estilizada em cores vibrantes.'),
    -- SMGs (7)
    ('MAC-10 | Neon Rider',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'SMG'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Chroma 2 Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8n5WxrR1Y-s2jaac8cM-dC2ie0-dytfNWQyC0nQlp5DzTntmgdC7COABxX5NxQrUOtUS5w4LgMu6zsVCK2IJCmyisjitM6DErvbicsEA0SQ', 0.00000000, 0.45000000, 'Submetralhadora com piloto em estilo neon dos anos 80.'),
    ('MP9 | Starlight Protector',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'SMG'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Dreams & Nightmares Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8js_f-jFk4uL3V7d5IeKfB2CY1dF6ueZhW2flkUtztz_SzYypJSqRalUhDJNwQO4PsBXtx9HkN-K37w3bgohGmHn3kGoXuZ3lRdvF', 0.00000000, 0.80000000, 'Submetralhadora com um guardiao estelar em tons de azul.'),
    ('UMP-45 | Primal Saber',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'SMG'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Chroma 3 Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLkk4a0qB1Y-s27ZbQ5dc-DHG6dwOJlseNsXRa_nBovp3PRn478JHmePQ8hDcF2Q7YDtxXrk92zYbyw7gXYjIhEyCn_3Hsbui44_a9cBklqRdMs', 0.00000000, 0.77000000, 'Submetralhadora com tigre dente-de-sabre ilustrado.'),
    ('P90 | Asiimov',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'SMG'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Breakout Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLhx8bf_jdk_6v-JaV-KfmeAXGvzedxuPUnTSjikRgksjuBzoz4dXLFb1QoC8QlTLQD4EPqk4LvN-Pns1aMioNBzTK-0H3gQVv65g', 0.00000000, 0.92000000, 'Submetralhadora com o visual futurista Asiimov.'),
    ('MP7 | Bloodsport',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'SMG'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Clutch Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8jsHf-jFk4uL5V6ZhL_-XHXef0_pJvOhuRz39lxsk4W3Ry96pIHrFOgElDZN2Q-9etUSwk4LnYu3h5wLejYwWxSr43zQJsHiIGMoJQA', 0.00000000, 0.65000000, 'Submetralhadora com pintura vermelha, preta e branca.'),
    ('MP5-SD | Phosphor',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'SMG'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Danger Zone Case'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8jsPz-R1c_M2jePFSJvWAGm6GwOJJtPNgXxa_nBovp3PRzd-vdCqQOgYgCMYkRrECskLuwdfkZeqz5QKMjYwUnHj33SlI630__a9cBl0Wy4S-', 0.00000000, 0.80000000, 'Submetralhadora com detalhes fosforescentes em verde.'),
    ('P90 | Death by Kitty',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'SMG'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The eSports 2013 Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLhx8bf_jdk7PO6e694LPyAMXfJkdF6ueZhW2fgkUh042jUnN2geSqTaFN2CcQmQuRfsBXtxtfkN7mztASIg91Bniv8kGoXucYQxgOQ', 0.08000000, 0.32000000, 'Submetralhadora rosa com estampa de gatinhos.'),
    -- Escopetas (4)
    ('XM1014 | Entombed',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Escopeta'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Fracture Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLpk8ewrHZk7OeRcKk8cKHHMWad1OJzpN5rQzy2qhEutDWR1N-hI3yWbVRyD8YiEOVZ50TqmoKyZb7rtVfWgosQzX7-3X9K5yc4tr4cEf1yVvkijss', 0.00000000, 0.50000000, 'Escopeta com motivos de tumba egipcia.'),
    ('Sawed-Off | The Kraken',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Escopeta'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Winter Offensive Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLin4Hl-S1d6c2tfZt-IeeWCmiWx9F5s_VmXzy-hSIrujqNjsH_eXmWaVRyXpF3EOZe5Bm8w93gMbzn4waPg98Tzir8jHwbuC5p4uZUT-N7rZ8ILI16', 0.00000000, 0.40000000, 'Escopeta de cano curto com um polvo gigante ilustrado.'),
    ('Nova | Antique',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Escopeta'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Classified'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Phoenix Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL_kYDhwiFO0PyhfqVSIf6HB3aFxNF6ueZhW2fmwRwl6jyHw96vIn2UbVVzXMdyRuYLt0O7ltPjZbu0tQTejo9Hyn2skGoXucYtjcOH', 0.00000000, 0.30000000, 'Escopeta com acabamento antigo de madeira e metal gravado.'),
    ('Nova | Wood Fired',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Escopeta'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Mil-Spec'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Danger Zone Case'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL_kYDhwiVI0PyhfqVSKOWdGmKC_uxkpfVscCW6khUz_WiByIr8IyiXbQYlD5d1E-BftxW_lNbgMb7n7gyM3tkXnimr3C1O6n11o7FVLv86c40', 0.00000000, 0.75000000, 'Escopeta com chamas pintadas sobre a madeira.'),
    -- Metralhadoras (2)
    ('M249 | Emerald Poison Dart',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Metralhadora'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Restricted'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Spectrum Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL8zMK5wjFL0P_8PP1SJuKcCVif0-dxue9oQxa_nBovp3PRzNb8JX2VO1IpDsclRrEPtxXtxNSxYuuw4QHai9gWyCT2j3gYuHlt_a9cBlcR8wa2', 0.00000000, 0.45000000, 'Metralhadora com padrao verde de sapo venenoso.'),
    ('Negev | Drop Me',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Metralhadora'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Mil-Spec'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Recoil Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL_m5Hl6x1Y-s2gbaNoNs-QAmKR09Flu_hWQyC0nQlpsDnVy4mpcSiQOlB2CJRxR-AK4BDrw4azN-225lfc2t0Tznr6iX4f6zErvbg1B8-kIw', 0.00000000, 1.00000000, 'Metralhadora com estampa divertida em cores fortes.'),
    -- Facas (6): sem colecao (saem como item raro de varias caixas), nunca Souvenir
    ('Butterfly Knife | Fade',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Faca'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL6kJ_m-B1Z-ua6bbZrLOmsD2avx-9ytd5lRi67gVNwsDvSwtqqc3iXZg4kCZYjReYLtRbum9XgYuvm5wbWjtgUzCn3iSsf8G81tFEeH9rw', 0.00000000, 0.08000000, 'Faca borboleta com degrade em rosa, roxo e amarelo.'),
    ('M9 Bayonet | Crimson Web',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Faca'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL6kJ_m-B1Wts2sab1iLvWHMW-J_vlzsvJWQyC0nQlp4GrWzYuqeHjDZlN1XJohTecO5xawwdDvNuLm5wPcjY0QzyX83Xsd7zErvbgxKe4lfw', 0.06000000, 0.80000000, 'Baioneta com teia de aranha preta sobre fundo vermelho.'),
    ('Bayonet | Tiger Tooth',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Faca'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyLzn4_v8ydP0POgV7BkJ_WBMWiCwOBxtd5lRi67gVMhsGrTntn4ci-ROAYlXMBwE7YL5BaxxIHjY-vq7w3X398RxS78iylK8G81tBow9RWL', 0.00000000, 0.08000000, 'Baioneta dourada com listras de tigre.'),
    ('Flip Knife | Marble Fade',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Faca'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL6kJ_m-B1d4_u-V6VgH_2SHGWcxNFwseVscCW6khUz_WqBnt2qIyrBPwMoCcN1R7YCtRa7kofhY7nk4gzajNhEzyT43HhK6CZ1o7FVaZCrJoQ', 0.00000000, 0.08000000, 'Faca dobravel com degrade marmorizado em vermelho, azul e amarelo.'),
    ('Talon Knife | Case Hardened',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Faca'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL6kJ_m-B1M5vahf6lsK_WBMWaB_uF_vORtcCW6khUz_WqBzd39Ii_CaVApAsYlEeUO4xXslNexY7nl5ALWjI0WmSqq3XlN5yx1o7FV8eN3eSM', 0.00000000, 1.00000000, 'Faca curva com tempera azul e dourada; o desenho muda com o seed.'),
    ('Huntsman Knife | Slaughter',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Faca'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Covert'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Dx60noTyL6kJ_m-B1P7vG6YadsLM-SA1iKxOxksd5lRi67gVN_42jTnourc3OSbA4iCJV5F7UCsEXpx93jYrnn7gfago4QyH6ri3tL8G81tAzA6RBm', 0.01000000, 0.26000000, 'Faca de caca com padrao vermelho marmorizado.'),
    -- Luvas (4): sem colecao, nunca StatTrak nem Souvenir
    ('Driver Gloves | King Snake',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Luva'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5T441rsfhr9kYDl7h1I4_utY5t-LvGYC3SbyOBJp-lgWyyMmRQguynLz4r6Iy7EbFchApNyR-dbtEbuw4XkN7jq7gHdjtoQzi37hiwYvytvt_FCD_Ql24JgJg', 0.06000000, 0.80000000, 'Luvas de motorista com padrao de pele de cobra.'),
    ('Hand Wraps | Cobalt Skulls',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Luva'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu4vx603vRA_Olpfu-TVJ7uK9V6xsLvSEHGaA_uJzsfVhSjuqqhsmsS-MmbD7LT7CAUV7T84sBohW60fg1srnZb6zsw2Ng41MmST43C1L7is9574CBKIh_q2Big_IMOdutcNRd_iuU13QD7PQAmaY', 0.06000000, 0.80000000, 'Faixas de mao azuis estampadas com caveiras.'),
    ('Specialist Gloves | Fade',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Luva'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Tk71ruQBH4jYLf-i5U-fe9V7d9JfOaD2uZ0vpJtuBtSha_nBovp3PQy42sdX6eagIjW5AlQOVetBXuk92xNLvg4gOMjd5AmC2ointB53w__a9cBqntWBk3', 0.06000000, 0.80000000, 'Luvas taticas com degrade em rosa, roxo e amarelo.'),
    ('Sport Gloves | Vice',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Luva'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Extraordinary'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGIGz3UqlXOLrxM-vMGmW8VNxu5Tk5UvzWCL2kpn2-DFk_OKherB0H_KfG2Kv0ed4u95lRi67gVNx4T-Bw434IHyVb1QlAsd1FOUDthG4xNznMu3m4QXXg90Wzn_33C1I8G81tLaDi_rK', 0.06000000, 0.80000000, 'Luvas esportivas em rosa e azul-claro, no estilo anos 80.');

-- 2.2 Modelos de COSMETICO (5)
INSERT INTO item_catalogo (nome_item, categoria_id, raridade_id, colecao_id, imagem_base, descricao) VALUES
    -- Adesivos (3)
    ('Adesivo | Howling Dawn',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Adesivo'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Contraband'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJai0ki7VeTHjMmuOHaC619h7delpVHoVhH4kJHf-SNM4bz9bKY_dPWQWDCUkLxy57g_H3DgkB5w42uAzIv4I3meOAQlApdwFO5YrFDmxUNp_lL7', 'Adesivo de lobo uivando. E o unico adesivo Contraband do jogo.'),
    ('Adesivo | Gold Web (Foil)',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Adesivo'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Exotic'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJai0ki7VeTHjNmpNG-D4ERw8Ljj71uoRhL9mqn3-CBk4f28ZaVhbqaRCGbAmOt157A-GHDqwx4m5TuEyYyodCmXaldxDZQhE-4IsBLpkdP5d7S1feagbts', 'Adesivo metalico com uma teia dourada.'),
    ('Adesivo | Bish (Holo)',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Adesivo'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Remarkable'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJai0ki7VeTHjNm1PHic4ERmpsj240rvfhX-kpmu-yBevqP2O_E4I6mVDTCWlLYjtblvG3vglEt-4m3VzdmpIimSOAImWIwwG7DEtAgJ5w', 'Adesivo holografico do trio Bish, Bash e Bosh.'),
    -- Chaveiros (2)
    ('Chaveiro | Diamond Dog',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Chaveiro'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Exotic'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'Missing Link Charm Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGI6zwki4Uf_a0IWsPGiE7Fhy-I764RbsQiL8l4Xz9Cxc4_ugY5t-If2sCm6RzOF4tK9sFyi3wUki4TvSnNytdC7FPQBzApIkQuRfukTql93vMung4FTXjIlC02yg2RVCPh13', 'Chaveiro de cachorrinho cravejado de diamantes.'),
    ('Chaveiro | Lil'' Squatch',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Chaveiro'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Remarkable'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'Missing Link Charm Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGI6zwki4Uf_a0IWsPGiE7Fhy-I764RbsQiL8l4Xz9Cxc4_ugY5tvKfeVAWiEj-10suQ6Fy2ylkolsj6BmNuvInzDZgciApAlF-JYuxK9xN2yNL-24gHAy9USv4cN0g0', 'Chaveiro do pequeno pe-grande.');

-- 2.3 Modelos de CONSUMIVEL (5)
INSERT INTO item_catalogo (nome_item, categoria_id, raridade_id, colecao_id, imagem_base, descricao) VALUES
    -- Caixas (2)
    ('Caixa Recoil',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Caixa'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Recoil Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bj35VTqVBP4io_frnMVu6b-avA-JqSSCjSWwuhz47U9TCzlxh9yt2WGnNqgIi-fbgUkWMNxFPlK7EdIJF6a2Q', 'Caixa da colecao Recoil. Requer chave para ser aberta.'),
    ('Caixa Dreams & Nightmares',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Caixa'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        (SELECT id FROM colecao        WHERE nome_colecao   = 'The Dreams & Nightmares Collection'),
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bj35VTqVBP4io_frnIV7Kb5OaU-JqfHDzXFle0u4LY8Gy_kkRgisGzcm4v4J3vDOAQmDMdyRvlK7EcmeCU3yw', 'Caixa com skins criadas pela comunidade. Requer chave.'),
    -- Capsula de adesivos (1)
    ('Capsula Copenhagen 2024 Legends',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Capsula'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bjn_lDkShjjoYbh_ilk7OKmOvQ_dM-fC2CVz-pl_rZvTXDqzRxw523Rm4mocy6QOgUmDcR4Q-8Mu0O5wNPkNuLnsleL3tlbjXKpQyK7hjg', 'Capsula de adesivos das equipes Legends do Major de Copenhague 2024.'),
    -- Chave (1)
    ('Chave da Caixa Dreams & Nightmares',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Chave'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Base Grade'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJG51EejH_XGwt6kCnCS_Gl2-4r5_1fuVQTOzcauqicPvPP_PKU4JKaQWGPCl7kutOQ-SS2wxBl-4j_RmI2seHLDZwEnXowwG7Az4p8gTQ', 'Chave usada para abrir a Caixa Dreams & Nightmares.'),
    -- Grafite (1)
    ('Grafite | Clutch King',
        (SELECT id FROM categoria_item WHERE nome_categoria = 'Grafite'),
        (SELECT id FROM raridade       WHERE nome_raridade  = 'Exotic'),
        NULL,
        'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJai0ki7VeTHjNygOW2S2kVl5obt-RbkTQjlnZ7frXMVvvf5OaBudqfCX2LElLgi4uNvS3zjlxwksmvUyNqgJH-fPQF1XMF3RflK7EduJBJCTQ', 'Grafite lacrado com 50 cargas de uso.');


-- ---------------------------------------------------------------------
-- 3. PARAMETROS DA SIMULACAO  (tabela temporaria, um modelo por linha)
--    preco_ref   preco SIMULADO em reais, no desgaste tipico do modelo,
--                sem StatTrak e em 01/11/2025 (inicio da tendencia).
--                Segue os precos do 03. Exemplos: AWP | Asiimov
--                R$ 1.150 (FT), M4A4 | Howl R$ 9.300 (FT; as vendas sao
--                de MW, como a do 03) e Karambit | Doppler R$ 5.300 (FN).
--                Com a tendencia e o ruido, a media das vendas desses
--                tres modelos fica em cerca de R$ 1.090, R$ 9.750 e
--                R$ 5.920 (contando as vendas do 03).
--    exemplares  quantos exemplares novos do modelo este script cria.
--    permite_st  o CSGO-API indica versao StatTrak (luvas: nunca).
--    permite_sv  existe versao Souvenir (skin que sai de pacote de
--                lembranca de campeonato). Facas e luvas: nunca.
--    Calculados abaixo: o float tipico, a tendencia e a CLASSE VENDIDA
--    (faixa de float e StatTrak/Souvenir dos exemplares de referencia,
--    que tem a 1a ou a ultima venda do modelo; ver o cabecalho).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_modelo (
    ordem        INTEGER        PRIMARY KEY,
    nome_item    VARCHAR(150)   NOT NULL UNIQUE,
    preco_ref    NUMERIC(12,2)  NOT NULL,
    exemplares   INTEGER        NOT NULL,
    permite_st   BOOLEAN        NOT NULL,
    permite_sv   BOOLEAN        NOT NULL,
    -- preenchidos abaixo, a partir do catalogo:
    modelo_id    INTEGER,
    categoria    VARCHAR(80),
    float_min    NUMERIC(10,8),
    float_max    NUMERIC(10,8),
    tipo         VARCHAR(20),   -- equipamento, cosmetico ou consumivel
    subtipo      VARCHAR(20),   -- adesivo, chaveiro, caixa, capsula, chave, grafite
    float_tipico NUMERIC,       -- float do desgaste tipico (base do preco_ref)
    tendencia    NUMERIC,       -- variacao mensal do preco (-2% a +3%)
    vendas_base  INTEGER,       -- desloca a quantidade de vendas dos exemplares
    -- classe vendida (so equipamentos):
    venda_float_min  NUMERIC,
    venda_float_max  NUMERIC,
    venda_st     BOOLEAN        NOT NULL DEFAULT FALSE,
    venda_sv     BOOLEAN        NOT NULL DEFAULT FALSE
);

INSERT INTO tmp_modelo (ordem, nome_item, preco_ref, exemplares, permite_st, permite_sv) VALUES
    -- modelos do 03
    ( 1, 'AK-47 | Redline',                       560.00, 2, TRUE,  FALSE),
    ( 2, 'AWP | Asiimov',                        1150.00, 2, TRUE,  FALSE),
    ( 3, 'Desert Eagle | Blaze',                 1950.00, 2, FALSE, FALSE),
    ( 4, 'M4A4 | Howl',                          9300.00, 2, TRUE,  FALSE),
    ( 5, 'P90 | Sand Spray',                       38.00, 2, FALSE, TRUE ),
    ( 6, 'Karambit | Doppler',                   5300.00, 2, TRUE,  FALSE),
    ( 7, 'Sport Gloves | Pandora''s Box',       13500.00, 2, FALSE, FALSE),
    ( 8, 'Specialist Gloves | Crimson Kimono',   7800.00, 2, FALSE, FALSE),
    ( 9, 'Moto Gloves | Spearmint',              3700.00, 2, FALSE, FALSE),
    (10, 'Nova | Hyper Beast',                     22.00, 2, TRUE,  FALSE),
    (11, 'M249 | Downtown',                         9.00, 2, TRUE,  FALSE),
    (12, 'Adesivo | Natus Vincere (Holo)',         48.00, 2, FALSE, FALSE),
    (13, 'Adesivo | Crown (Foil)',                330.00, 2, FALSE, FALSE),
    (14, 'Chaveiro | Hot Howl',                   175.00, 2, FALSE, FALSE),
    (15, 'Chaveiro | Baby Karat T',                92.00, 2, FALSE, FALSE),
    (16, 'Caixa Fracture',                         12.00, 2, FALSE, FALSE),
    (17, 'Caixa Prisma',                           10.00, 2, FALSE, FALSE),
    (18, 'Capsula Ambush',                          7.50, 2, FALSE, FALSE),
    (19, 'Capsula de Grafites',                     3.20, 2, FALSE, FALSE),
    (20, 'Chave de Caixa',                         14.50, 2, FALSE, FALSE),
    (21, 'Grafite | EZ',                            4.50, 2, FALSE, FALSE),
    -- modelos novos deste script
    (22, 'AK-47 | Asiimov',                       620.00, 3, TRUE,  FALSE),
    (23, 'AK-47 | Vulcan',                       1400.00, 3, TRUE,  FALSE),
    (24, 'AK-47 | Fire Serpent',                 4600.00, 3, TRUE,  FALSE),
    (25, 'AK-47 | Slate',                          22.00, 4, TRUE,  FALSE),
    (26, 'AK-47 | Ice Coaled',                     48.00, 3, TRUE,  FALSE),
    (27, 'AK-47 | Legion of Anubis',              140.00, 3, TRUE,  FALSE),
    (28, 'AK-47 | Bloodsport',                    390.00, 3, TRUE,  FALSE),
    (29, 'M4A1-S | Printstream',                 1100.00, 3, TRUE,  FALSE),
    (30, 'M4A1-S | Hyper Beast',                  175.00, 3, TRUE,  FALSE),
    (31, 'M4A4 | The Emperor',                    230.00, 3, TRUE,  FALSE),
    (32, 'AWP | Dragon Lore',                   48000.00, 3, FALSE, TRUE ),
    (33, 'AWP | Neo-Noir',                        240.00, 3, TRUE,  FALSE),
    (34, 'AWP | Atheris',                          26.00, 3, TRUE,  FALSE),
    (35, 'AWP | Chromatic Aberration',            170.00, 3, TRUE,  FALSE),
    (36, 'AWP | Hyper Beast',                     200.00, 3, TRUE,  FALSE),
    (37, 'Galil AR | Chatterbox',                 115.00, 3, TRUE,  FALSE),
    (38, 'Desert Eagle | Printstream',            240.00, 3, TRUE,  FALSE),
    (39, 'Desert Eagle | Code Red',               280.00, 3, TRUE,  FALSE),
    (40, 'Desert Eagle | Kumicho Dragon',          65.00, 3, TRUE,  FALSE),
    (41, 'USP-S | Kill Confirmed',                340.00, 3, TRUE,  FALSE),
    (42, 'USP-S | Neo-Noir',                      140.00, 3, TRUE,  FALSE),
    (43, 'USP-S | Printstream',                   330.00, 3, TRUE,  FALSE),
    (44, 'Glock-18 | Vogue',                       28.00, 4, TRUE,  FALSE),
    (45, 'Glock-18 | Water Elemental',             48.00, 3, TRUE,  FALSE),
    (46, 'Glock-18 | Groundwater',                  6.00, 3, FALSE, TRUE ),
    (47, 'Five-SeveN | Hyper Beast',               65.00, 3, TRUE,  FALSE),
    (48, 'MAC-10 | Neon Rider',                    70.00, 3, TRUE,  FALSE),
    (49, 'MP9 | Starlight Protector',              85.00, 3, TRUE,  FALSE),
    (50, 'UMP-45 | Primal Saber',                  22.00, 3, TRUE,  FALSE),
    (51, 'P90 | Asiimov',                          90.00, 3, TRUE,  FALSE),
    (52, 'MP7 | Bloodsport',                       60.00, 3, TRUE,  FALSE),
    (53, 'MP5-SD | Phosphor',                      12.00, 4, TRUE,  FALSE),
    (54, 'P90 | Death by Kitty',                  520.00, 3, TRUE,  FALSE),
    (55, 'XM1014 | Entombed',                      12.00, 4, TRUE,  FALSE),
    (56, 'Sawed-Off | The Kraken',                 85.00, 3, TRUE,  FALSE),
    (57, 'Nova | Antique',                         48.00, 3, TRUE,  FALSE),
    (58, 'Nova | Wood Fired',                       5.00, 4, TRUE,  FALSE),
    (59, 'M249 | Emerald Poison Dart',              6.00, 4, TRUE,  FALSE),
    (60, 'Negev | Drop Me',                         7.00, 4, TRUE,  FALSE),
    (61, 'Butterfly Knife | Fade',              11500.00, 3, TRUE,  FALSE),
    (62, 'M9 Bayonet | Crimson Web',             3300.00, 3, TRUE,  FALSE),
    (63, 'Bayonet | Tiger Tooth',                2700.00, 3, TRUE,  FALSE),
    (64, 'Flip Knife | Marble Fade',             2400.00, 3, TRUE,  FALSE),
    (65, 'Talon Knife | Case Hardened',          2700.00, 3, TRUE,  FALSE),
    (66, 'Huntsman Knife | Slaughter',           1450.00, 3, TRUE,  FALSE),
    (67, 'Driver Gloves | King Snake',           2700.00, 3, FALSE, FALSE),
    (68, 'Hand Wraps | Cobalt Skulls',           1500.00, 3, FALSE, FALSE),
    (69, 'Specialist Gloves | Fade',             5200.00, 3, FALSE, FALSE),
    (70, 'Sport Gloves | Vice',                 11000.00, 3, FALSE, FALSE),
    (71, 'Adesivo | Howling Dawn',               7800.00, 3, FALSE, FALSE),
    (72, 'Adesivo | Gold Web (Foil)',              65.00, 3, FALSE, FALSE),
    (73, 'Adesivo | Bish (Holo)',                  28.00, 4, FALSE, FALSE),
    (74, 'Chaveiro | Diamond Dog',                 26.00, 3, FALSE, FALSE),
    (75, 'Chaveiro | Lil'' Squatch',                9.00, 3, FALSE, FALSE),
    (76, 'Caixa Recoil',                            3.50, 4, FALSE, FALSE),
    (77, 'Caixa Dreams & Nightmares',               8.00, 3, FALSE, FALSE),
    (78, 'Capsula Copenhagen 2024 Legends',         2.80, 4, FALSE, FALSE),
    (79, 'Chave da Caixa Dreams & Nightmares',     14.50, 4, FALSE, FALSE),
    (80, 'Grafite | Clutch King',                   6.00, 4, FALSE, FALSE);

UPDATE tmp_modelo m
   SET modelo_id   = ic.id,
       categoria   = c.nome_categoria,
       float_min   = ic.float_min,
       float_max   = ic.float_max,
       tipo        = CASE WHEN ic.float_min IS NOT NULL               THEN 'equipamento'
                          WHEN c.nome_categoria IN ('Adesivo', 'Chaveiro') THEN 'cosmetico'
                          ELSE 'consumivel' END,
       subtipo     = CASE c.nome_categoria
                          WHEN 'Adesivo'  THEN 'adesivo'
                          WHEN 'Chaveiro' THEN 'chaveiro'
                          WHEN 'Caixa'    THEN 'caixa'
                          WHEN 'Capsula'  THEN 'capsula'
                          WHEN 'Chave'    THEN 'chave'
                          WHEN 'Grafite'  THEN 'grafite' END,
       -- desgaste tipico: o meio da faixa de float, limitado a 0,25 (FT)
       float_tipico = CASE WHEN ic.float_min IS NOT NULL THEN
                          GREATEST(ic.float_min, LEAST(0.25, (ic.float_min + ic.float_max) / 2)) END,
       tendencia   = ROUND(-0.02 + 0.05 * pg_temp.sorteio('tendencia|' || m.nome_item), 4),
       vendas_base = FLOOR(4 * pg_temp.sorteio('vendas|' || m.nome_item))::INTEGER
  FROM item_catalogo ic
  JOIN categoria_item c ON c.id = ic.categoria_id
 WHERE ic.nome_item = m.nome_item;

-- CLASSE VENDIDA de cada equipamento (ver o cabecalho). Nos modelos que
-- o 03 ja vendeu, e a do exemplar vendido no 03 (StatTrak/Souvenir so se
-- o CSGO-API permitir), para essa venda ficar na mesma serie de precos.
WITH vendido_no_03 AS (
    SELECT DISTINCT ON (vc.modelo_id)
           vc.modelo_id, e.float_value, e.stattrak_flag, e.souvenir_flag
      FROM vw_vendas_concluidas vc
      JOIN equipamento e ON e.item_instancia_id = vc.item_id
     ORDER BY vc.modelo_id, vc.data_venda
),
referencia AS (
    SELECT m.ordem,
           fn_desgaste(COALESCE(v.float_value, m.float_tipico)) AS desgaste,
           COALESCE(v.stattrak_flag, FALSE) AND m.permite_st    AS st,
           CASE WHEN v.modelo_id IS NOT NULL THEN v.souvenir_flag
                ELSE pg_temp.sorteio('classe|' || m.nome_item) < 0.50
           END AND m.permite_sv                                 AS sv
      FROM tmp_modelo m
      LEFT JOIN vendido_no_03 v ON v.modelo_id = m.modelo_id
     WHERE m.tipo = 'equipamento'
)
UPDATE tmp_modelo m
   SET venda_float_min = GREATEST(m.float_min,
                                  CASE r.desgaste WHEN 'FN' THEN 0.00 WHEN 'MW' THEN 0.07
                                                  WHEN 'FT' THEN 0.15 WHEN 'WW' THEN 0.38
                                                  ELSE 0.45 END),
       venda_float_max = LEAST(m.float_max,
                               CASE r.desgaste WHEN 'FN' THEN 0.07 WHEN 'MW' THEN 0.15
                                               WHEN 'FT' THEN 0.38 WHEN 'WW' THEN 0.45
                                               ELSE 1.00 END),
       venda_st        = r.st,
       venda_sv        = r.sv
  FROM referencia r
 WHERE r.ordem = m.ordem;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM tmp_modelo WHERE modelo_id IS NULL)
       OR (SELECT COUNT(*) FROM tmp_modelo) <> (SELECT COUNT(*) FROM item_catalogo) THEN
        RAISE EXCEPTION 'Os parametros da secao 3 nao batem com o catalogo.';
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_modelo
                WHERE tipo = 'equipamento'
                  AND (venda_float_min IS NULL OR venda_float_min >= venda_float_max)) THEN
        RAISE EXCEPTION 'Classe vendida sem faixa de float na secao 3.';
    END IF;
END $$;

-- Preco SIMULADO de um exemplar numa data (formula do cabecalho).
--   p_ajuste: ruido da venda ou margem do anunciante (1 = sem ajuste).
--   Arredondamento: centavos abaixo de R$ 100, dezenas de centavos
--   ate R$ 1.000 e reais inteiros acima disso.
CREATE FUNCTION pg_temp.preco_simulado(
    p_ordem     INTEGER,
    p_float     NUMERIC,
    p_stattrak  BOOLEAN,
    p_souvenir  BOOLEAN,
    p_data      TIMESTAMP,
    p_ajuste    NUMERIC)
RETURNS NUMERIC AS $$
    SELECT CASE WHEN x < 100  THEN ROUND(x, 2)
                WHEN x < 1000 THEN ROUND(x, 1)
                ELSE ROUND(x, 0) END
      FROM (
        SELECT m.preco_ref
             * pg_temp.fator_desgaste(p_float)
             / pg_temp.fator_desgaste(m.float_tipico)
             * CASE WHEN NOT p_stattrak         THEN 1
                    WHEN m.categoria = 'Faca'   THEN 1.15
                    ELSE 1.45 END
             * CASE WHEN p_souvenir THEN 1.50 ELSE 1 END
             * (1 + m.tendencia * EXTRACT(EPOCH FROM p_data - TIMESTAMP '2025-11-01')
                                / (86400 * 30.4))
             * p_ajuste AS x
          FROM tmp_modelo m
         WHERE m.ordem = p_ordem
      ) t;
$$ LANGUAGE sql STABLE;


-- ---------------------------------------------------------------------
-- 4. PLANO DOS EXEMPLARES E DAS VENDAS  (tabelas temporarias)
--
-- 4.1 Um exemplar por (modelo, j), j = 1..exemplares. Cada um recebe:
--     numero de inspecao (INS-EQ/CO/CN-1001 em diante, sem colidir com
--     os do 03), dono original, data de obtencao, float/seed/StatTrak/
--     Souvenir (equipamentos) e quantas vezes sera vendido.
--     Vendas por exemplar: (vendas_base + j) mod 4 nos modelos com 3 ou
--     mais exemplares -- assim cada modelo novo junta de 3 a 6 vendas;
--     nos modelos do 03 (2 exemplares), 1 + (vendas_base + j) mod 3.
--     Os exemplares que serao vendidos nascem na CLASSE VENDIDA do modelo
--     (float na faixa do seu desgaste; StatTrak/Souvenir do modelo); os
--     que nao forem de referencia ainda podem variar na secao 4.5.
--     Os nunca vendidos tem float em toda a faixa do modelo e podem ser
--     StatTrak (30%) ou Souvenir (40% dos que nao sao StatTrak), quando
--     o CSGO-API permite.
--     Alguns exemplares nunca vendidos ficam 'bloqueado' (recebidos ha
--     poucos dias, ainda sem poder ser negociados).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_exemplar AS
WITH base AS (
    SELECT m.*,
           g.j,
           m.nome_item || '#' || g.j AS chave
      FROM tmp_modelo m
     CROSS JOIN LATERAL generate_series(1, m.exemplares) AS g(j)
),
vendas AS (
    SELECT b.*,
           CASE WHEN b.exemplares >= 3 THEN (b.vendas_base + b.j) % 4
                ELSE 1 + (b.vendas_base + b.j) % 3 END                      AS qtd_vendas
      FROM base b
),
sorteado AS (
    SELECT v.*,
           1 + FLOOR(12 * pg_temp.sorteio('dono|' || v.chave))::INTEGER      AS dono_inicial,
           CASE WHEN v.qtd_vendas > 0 THEN v.venda_st
                ELSE v.permite_st AND pg_temp.sorteio('stattrak|' || v.chave) < 0.30
           END                                                               AS stattrak
      FROM vendas v
)
SELECT s.ordem,
       s.j,
       s.chave,
       s.modelo_id,
       s.tipo,
       s.subtipo,
       'INS-' || CASE s.tipo WHEN 'equipamento' THEN 'EQ'
                             WHEN 'cosmetico'   THEN 'CO'
                             ELSE 'CN' END
              || '-' || (1000 + ROW_NUMBER() OVER (PARTITION BY s.tipo ORDER BY s.ordem, s.j)) AS numero_inspecao,
       s.qtd_vendas,
       s.dono_inicial,
       s.dono_inicial AS dono_final,   -- ajustado depois das cadeias de venda
       (s.qtd_vendas = 0
        AND s.tipo IN ('equipamento', 'cosmetico')
        AND pg_temp.sorteio('bloqueio|' || s.chave) < 0.12)               AS bloqueado,
       -- equipamento: float dentro da faixa do modelo (a da classe
       -- vendida, se o exemplar sera vendido), seed de 0 a 1000
       CASE WHEN s.tipo <> 'equipamento' THEN NULL
            WHEN s.qtd_vendas > 0 THEN
                 ROUND(s.venda_float_min + (s.venda_float_max - s.venda_float_min)
                       * (0.02 + 0.96 * pg_temp.sorteio('float|' || s.chave)), 8)
            ELSE ROUND(s.float_min + (s.float_max - s.float_min)
                       * (0.002 + 0.996 * pg_temp.sorteio('float|' || s.chave)), 8)
       END                                                                  AS float_value,
       CASE WHEN s.tipo = 'equipamento' THEN
            FLOOR(1001 * pg_temp.sorteio('seed|' || s.chave))::INTEGER END  AS paint_seed,
       s.stattrak,
       CASE WHEN s.qtd_vendas > 0 THEN s.venda_sv
            ELSE s.permite_sv AND NOT s.stattrak
                 AND pg_temp.sorteio('souvenir|' || s.chave) < 0.40
       END                                                                  AS souvenir,
       NULL::DATE        AS data_obtencao,
       NULL::BOOLEAN     AS lacrado,
       NULL::INTEGER     AS cargas,
       NULL::BOOLEAN     AS anuncio_ativo,
       NULL::VARCHAR(30) AS anuncio_encerrado,
       FALSE             AS referencia      -- marcado na secao 4.5
  FROM sorteado s;

-- Obtencao: entre 01/11/2024 e 15/10/2025 (antes da 1a venda, em
-- 01/11/2025). Os bloqueados chegaram entre 20 e 25/10/2026.
UPDATE tmp_exemplar
   SET data_obtencao = CASE
           WHEN bloqueado THEN DATE '2026-10-20' + FLOOR(6 * pg_temp.sorteio('obtencao|' || chave))::INTEGER
           ELSE DATE '2024-11-01' + FLOOR(349 * pg_temp.sorteio('obtencao|' || chave))::INTEGER
       END;

-- 4.2 CADEIAS DE VENDA: uma linha por venda (exemplar, j = 1..qtd_vendas).
--     O comprador da venda j "anda" de 1 a 11 posicoes na lista de
--     usuarios a partir do dono anterior: nunca e o proprio vendedor
--     (RS-05). O vendedor da venda j e o comprador da venda j-1.
CREATE TEMP TABLE tmp_venda AS
WITH passos AS (
    SELECT e.numero_inspecao, e.chave, e.ordem, e.qtd_vendas, e.dono_inicial,
           g.j,
           1 + FLOOR(11 * pg_temp.sorteio('passo|' || e.chave || '|' || g.j))::INTEGER AS passo
      FROM tmp_exemplar e
     CROSS JOIN LATERAL generate_series(1, e.qtd_vendas) AS g(j)
),
donos AS (
    SELECT p.*,
           1 + (p.dono_inicial - 1
                + SUM(p.passo) OVER (PARTITION BY p.numero_inspecao ORDER BY p.j)) % 12 AS comprador_n
      FROM passos p
)
SELECT d.numero_inspecao,
       d.chave || '|' || d.j AS chave,
       d.ordem,
       d.qtd_vendas,
       d.j,
       COALESCE(LAG(d.comprador_n) OVER (PARTITION BY d.numero_inspecao ORDER BY d.j),
                d.dono_inicial)  AS vendedor_n,
       d.comprador_n,
       NULL::TIMESTAMP     AS data_publicacao,
       NULL::TIMESTAMP     AS data_expiracao,
       NULL::TIMESTAMP     AS data_venda,
       NULL::NUMERIC(12,2) AS valor,
       NULL::VARCHAR(40)   AS metodo,
       NULL::TIMESTAMP     AS data_pagamento,
       NULL::TIMESTAMP     AS data_emissao,
       NULL::INTEGER       AS venda_id
  FROM donos d;

UPDATE tmp_exemplar e
   SET dono_final = v.comprador_n
  FROM tmp_venda v
 WHERE v.numero_inspecao = e.numero_inspecao
   AND v.j = e.qtd_vendas;

-- 4.3 DESTINO DE CADA EXEMPLAR
--     ~30% terminam com anuncio ATIVO (outubro/2026), publicado pelo dono
--     final. Dos nunca vendidos, ~45% tiveram um anuncio no passado que
--     foi cancelado ou expirou (~80% nos da isizinha, para a aba Encerrados da
--     demonstracao). Um grafite que nao esta anunciado pode ter sido
--     aberto pelo dono atual, depois da ultima venda (deslacrado, com
--     parte das 50 cargas).
UPDATE tmp_exemplar
   SET anuncio_ativo = NOT bloqueado
                       AND pg_temp.sorteio('ativo|' || chave) < 0.30,
       anuncio_encerrado = CASE
           WHEN qtd_vendas = 0 AND NOT bloqueado
                AND pg_temp.sorteio('encerrado|' || chave)
                    < CASE WHEN dono_inicial = (SELECT n FROM tmp_usuario WHERE apelido = 'isizinha')
                           THEN 0.80 ELSE 0.45 END
           THEN CASE WHEN pg_temp.sorteio('encerrado-status|' || chave) < 0.65
                     THEN 'expirado' ELSE 'cancelado' END
       END;

UPDATE tmp_exemplar
   SET lacrado = NOT (subtipo = 'grafite'
                      AND NOT anuncio_ativo
                      AND pg_temp.sorteio('lacre|' || chave) < 0.40)
 WHERE tipo = 'consumivel';

UPDATE tmp_exemplar
   SET cargas = CASE WHEN subtipo <> 'grafite' THEN 1
                     WHEN lacrado              THEN 50
                     ELSE 5 + FLOOR(41 * pg_temp.sorteio('cargas|' || chave))::INTEGER END
 WHERE tipo = 'consumivel';

-- 4.4 DATAS E PAGAMENTO DE CADA VENDA (o preco vem depois, na 4.5)
--     A janela vai de 01/11/2025 a 26/10/2026 (ate 30/09/2026 para os
--     itens que terminam com anuncio ativo) e e dividida em tantos
--     trechos quantas forem as vendas do exemplar: a venda j cai no
--     trecho j, das 8h as 22h. A 1a venda pode cair em qualquer ponto
--     do seu trecho; as seguintes ficam a pelo menos 12% do inicio do
--     trecho (e cada trecho tem mais de 100 dias), o que garante a
--     revenda publicada DEPOIS da compra anterior.
WITH datas AS (
    SELECT v.numero_inspecao,
           v.j,
           (TIMESTAMP '2025-11-01'
              + (CASE WHEN e.anuncio_ativo THEN TIMESTAMP '2026-09-30'
                      ELSE TIMESTAMP '2026-10-26' END - TIMESTAMP '2025-11-01')
                / v.qtd_vendas
                * (v.j - 1 + CASE WHEN v.j = 1
                                  THEN 0.02 + 0.96 * pg_temp.sorteio('dia|' || v.chave)
                                  ELSE 0.12 + 0.86 * pg_temp.sorteio('dia|' || v.chave) END)
           )::DATE
           + TIME '08:00'
           + FLOOR(840 * pg_temp.sorteio('hora|' || v.chave)) * INTERVAL '1 minute' AS data_venda
      FROM tmp_venda v
      JOIN tmp_exemplar e ON e.numero_inspecao = v.numero_inspecao
)
UPDATE tmp_venda v
   SET data_venda = d.data_venda
  FROM datas d
 WHERE d.numero_inspecao = v.numero_inspecao
   AND d.j = v.j;

-- Anuncio publicado de 12 horas a 5,5 dias antes da venda, com a
-- validade que a aplicacao oferece (7, 14 ou 30 dias): a venda sempre
-- acontece antes de o anuncio vencer.
UPDATE tmp_venda
   SET data_publicacao = data_venda
                         - FLOOR(720 + 7200 * pg_temp.sorteio('publicacao|' || chave)) * INTERVAL '1 minute',
       metodo = CASE
           WHEN pg_temp.sorteio('metodo|' || chave) < 0.40 THEN 'pix'
           WHEN pg_temp.sorteio('metodo|' || chave) < 0.65 THEN 'cartao_credito'
           WHEN pg_temp.sorteio('metodo|' || chave) < 0.80 THEN 'saldo_steam'
           WHEN pg_temp.sorteio('metodo|' || chave) < 0.92 THEN 'cartao_debito'
           ELSE 'boleto' END;

UPDATE tmp_venda
   SET data_expiracao = data_publicacao
                        + CASE WHEN pg_temp.sorteio('validade|' || chave) < 0.25 THEN 7
                               WHEN pg_temp.sorteio('validade|' || chave) < 0.55 THEN 14
                               ELSE 30 END * INTERVAL '1 day',
       -- boleto compensa em 1 a 3 horas; os demais metodos, em minutos
       data_pagamento = data_venda
                        + CASE WHEN metodo = 'boleto'
                               THEN 60 + FLOOR(120 * pg_temp.sorteio('pagamento|' || chave))
                               ELSE 1 + FLOOR(5 * pg_temp.sorteio('pagamento|' || chave)) END
                          * INTERVAL '1 minute';

UPDATE tmp_venda
   SET data_emissao = data_pagamento
                      + (2 + FLOOR(7 * pg_temp.sorteio('emissao|' || chave))) * INTERVAL '1 minute';

-- 4.5 EXEMPLARES DE REFERENCIA, VARIACAO DE CLASSE E PRECO DAS VENDAS
--     As datas das vendas (4.4) nao dependem da classe do exemplar. Com
--     elas, marca os exemplares de REFERENCIA: os que tem a 1a ou a
--     ultima venda de cada modelo. Eles ficam na classe vendida, e o
--     ranking de maiores variacoes compara sempre a mesma classe.
UPDATE tmp_exemplar e
   SET referencia = TRUE
 WHERE EXISTS (SELECT 1
                 FROM tmp_venda v
                WHERE v.numero_inspecao = e.numero_inspecao
                  AND (v.data_venda = (SELECT MIN(x.data_venda) FROM tmp_venda x WHERE x.ordem = v.ordem)
                    OR v.data_venda = (SELECT MAX(x.data_venda) FROM tmp_venda x WHERE x.ordem = v.ordem)));

--     Os outros equipamentos vendidos variam (sorteio por exemplar):
--       desgaste  60% trocam por outro desgaste da faixa do modelo
--                 (FN, MW, FT, WW ou BS; float a pelo menos 2% das bordas
--                 do desgaste e dentro da faixa do modelo)
--       StatTrak  45%, so quando o CSGO-API permite (luvas: nunca)
--       Souvenir  35% invertem a versao Souvenir, so nos modelos que a
--                 tem (nunca junto com StatTrak)
--     O preco continua vindo de pg_temp.preco_simulado: FN mais caro que
--     BS e premio do StatTrak tambem no historico de vendas.
WITH alvo AS (
    SELECT e.numero_inspecao, e.chave,
           m.float_min, m.float_max, m.venda_float_min, m.venda_float_max,
           m.permite_st, m.permite_sv, m.venda_sv,
           m.permite_st AND pg_temp.sorteio('var-stattrak|' || e.chave) < 0.45 AS stattrak
      FROM tmp_exemplar e
      JOIN tmp_modelo m ON m.ordem = e.ordem
     WHERE e.tipo = 'equipamento'
       AND e.qtd_vendas > 0
       AND NOT e.referencia
),
opcao AS (
    -- desgastes possiveis na faixa do modelo, menos o da classe vendida
    SELECT a.numero_inspecao,
           GREATEST(a.float_min, d.de) AS de,
           LEAST(a.float_max, d.ate)   AS ate,
           ROW_NUMBER() OVER (PARTITION BY a.numero_inspecao ORDER BY d.de) AS k,
           COUNT(*)     OVER (PARTITION BY a.numero_inspecao)              AS n
      FROM alvo a
      JOIN (VALUES (0.00, 0.07),    -- FN
                   (0.07, 0.15),    -- MW
                   (0.15, 0.38),    -- FT
                   (0.38, 0.45),    -- WW
                   (0.45, 1.00))    -- BS
           AS d(de, ate)
        ON LEAST(a.float_max, d.ate) - GREATEST(a.float_min, d.de) >= 0.01
       AND NOT (d.de < a.venda_float_max AND d.ate > a.venda_float_min)
),
novo AS (
    SELECT a.numero_inspecao,
           CASE WHEN pg_temp.sorteio('var-desgaste|' || a.chave) < 0.60 THEN
                (SELECT ROUND(o.de + (o.ate - o.de)
                              * (0.02 + 0.96 * pg_temp.sorteio('var-float|' || a.chave)), 8)
                   FROM opcao o
                  WHERE o.numero_inspecao = a.numero_inspecao
                    AND o.k = 1 + FLOOR(o.n * pg_temp.sorteio('var-qual|' || a.chave)))
           END AS float_value,
           a.stattrak,
           a.permite_sv AND NOT a.stattrak
             AND (a.venda_sv <> (pg_temp.sorteio('var-souvenir|' || a.chave) < 0.35)) AS souvenir
      FROM alvo a
)
UPDATE tmp_exemplar e
   SET float_value = COALESCE(n.float_value, e.float_value),
       stattrak    = n.stattrak,
       souvenir    = n.souvenir
  FROM novo n
 WHERE n.numero_inspecao = e.numero_inspecao;

DO $$
BEGIN
    IF EXISTS (SELECT 1
                 FROM tmp_exemplar e
                 JOIN tmp_modelo m ON m.ordem = e.ordem
                WHERE e.tipo = 'equipamento'
                  AND (e.float_value NOT BETWEEN m.float_min AND m.float_max
                       OR (e.stattrak AND NOT m.permite_st)
                       OR (e.souvenir AND NOT m.permite_sv)
                       OR (e.stattrak AND e.souvenir))) THEN
        RAISE EXCEPTION 'Exemplar fora da faixa de float ou com StatTrak/Souvenir impossivel (secao 4.5).';
    END IF;
END $$;

-- Preco da venda: preco simulado do exemplar na data, com ruido de +-7%.
UPDATE tmp_venda v
   SET valor = pg_temp.preco_simulado(e.ordem, e.float_value, e.stattrak, e.souvenir,
                                      v.data_venda,
                                      0.93 + 0.14 * pg_temp.sorteio('ruido|' || v.chave))
  FROM tmp_exemplar e
 WHERE e.numero_inspecao = v.numero_inspecao;


-- ---------------------------------------------------------------------
-- 5. ITEM_INSTANCIA + SUBTIPO  (especializacao TOTAL e DISJUNTA)
--    Os exemplares entram com o dono ORIGINAL; a posse muda so na
--    secao 7, venda a venda. Cada modelo cai sempre no mesmo subtipo.
-- ---------------------------------------------------------------------
INSERT INTO item_instancia (numero_inspecao, item_catalogo_id, proprietario_id, tradable_flag, data_obtencao, status_item)
SELECT e.numero_inspecao,
       e.modelo_id,
       u.id,
       NOT e.bloqueado,
       e.data_obtencao,
       CASE WHEN e.bloqueado THEN 'bloqueado' ELSE 'disponivel' END
  FROM tmp_exemplar e
  JOIN tmp_usuario u ON u.n = e.dono_inicial
 ORDER BY CASE e.tipo WHEN 'equipamento' THEN 1 WHEN 'cosmetico' THEN 2 ELSE 3 END,
          e.numero_inspecao;

INSERT INTO equipamento (item_instancia_id, float_value, paint_seed, stattrak_flag, souvenir_flag)
SELECT i.id, e.float_value, e.paint_seed, e.stattrak, e.souvenir
  FROM tmp_exemplar e
  JOIN item_instancia i ON i.numero_inspecao = e.numero_inspecao
 WHERE e.tipo = 'equipamento'
 ORDER BY i.id;

-- arte_visual: a mesma dos exemplares do 03 do mesmo modelo, ou
-- art/<nome>.svg para os modelos novos.
INSERT INTO cosmetico (item_instancia_id, tipo_cosmetico, arte_visual)
SELECT i.id,
       e.subtipo,
       COALESCE((SELECT MIN(c.arte_visual)
                   FROM cosmetico c
                   JOIN item_instancia x ON x.id = c.item_instancia_id
                  WHERE x.item_catalogo_id = e.modelo_id),
                'art/' || btrim(lower(regexp_replace(split_part(ic.nome_item, '| ', 2),
                                                     '[^A-Za-z0-9]+', '_', 'g')), '_') || '.svg')
  FROM tmp_exemplar e
  JOIN item_instancia i ON i.numero_inspecao = e.numero_inspecao
  JOIN item_catalogo ic ON ic.id = e.modelo_id
 WHERE e.tipo = 'cosmetico'
 ORDER BY i.id;

-- Caixas, capsulas e chaves lacradas com 1 carga; grafites com 50
-- cargas (ou menos, se ja foram abertos).
INSERT INTO consumivel (item_instancia_id, tipo_consumivel, lacrado, cargas_restantes)
SELECT i.id, e.subtipo, e.lacrado, e.cargas
  FROM tmp_exemplar e
  JOIN item_instancia i ON i.numero_inspecao = e.numero_inspecao
 WHERE e.tipo = 'consumivel'
 ORDER BY i.id;


-- ---------------------------------------------------------------------
-- 6. APLICACAO_COSMETICO  (adesivos e chaveiros aplicados em armas)
--    Cada cosmetico e um exemplar NOVO, do mesmo dono da arma, obtido no
--    mesmo dia que ela, e e aplicado ANTES das vendas: o trigger
--    trg_aplicar_cosmetico confere o dono e o marca como 'consumido', e
--    quando a arma e vendida o trigger trg_cosmeticos_acompanham_equipamento
--    leva os cosmeticos junto (RS-23). No maximo 3 por arma (limite: 6)
--    e 1 chaveiro por arma, so em armas de fogo.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_aplicacao (
    n               INTEGER        PRIMARY KEY,
    arma            VARCHAR(150)   NOT NULL,  -- modelo da arma
    exemplar        INTEGER        NOT NULL,  -- j-esimo exemplar novo desse modelo
    cosmetico       VARCHAR(150)   NOT NULL,  -- modelo aplicado
    coord_x         NUMERIC(8,3)   NOT NULL,
    coord_y         NUMERIC(8,3)   NOT NULL,
    rotacao         NUMERIC(8,3)   NOT NULL,
    nivel_raspagem  NUMERIC(5,2),
    numero_inspecao VARCHAR(80)
);

INSERT INTO tmp_aplicacao (n, arma, exemplar, cosmetico, coord_x, coord_y, rotacao, nivel_raspagem) VALUES
    ( 1, 'AK-47 | Fire Serpent',     1, 'Adesivo | Crown (Foil)',          12.500,  4.100,   0.000,  0.00),
    ( 2, 'AK-47 | Fire Serpent',     1, 'Adesivo | Natus Vincere (Holo)',  28.300,  9.600,  10.000,  0.00),
    ( 3, 'AK-47 | Fire Serpent',     1, 'Adesivo | Natus Vincere (Holo)',  44.000, 15.200,  -5.000, 12.50),
    ( 4, 'AK-47 | Asiimov',          1, 'Adesivo | Gold Web (Foil)',       10.000,  3.500,   0.000,  0.00),
    ( 5, 'AK-47 | Asiimov',          1, 'Adesivo | Gold Web (Foil)',       26.000,  8.800,   0.000,  0.00),
    ( 6, 'AK-47 | Asiimov',          1, 'Chaveiro | Diamond Dog',           4.800,  2.200,  90.000,  NULL),
    ( 7, 'M4A1-S | Printstream',     1, 'Adesivo | Bish (Holo)',           18.200,  6.000,  -8.500,  0.00),
    ( 8, 'M4A1-S | Printstream',     1, 'Adesivo | Bish (Holo)',           35.700, 11.400,   8.500, 25.00),
    ( 9, 'AWP | Dragon Lore',        2, 'Adesivo | Crown (Foil)',          40.000, 12.000, 180.000,  3.20),
    (10, 'USP-S | Kill Confirmed',   1, 'Adesivo | Natus Vincere (Holo)',  14.400,  5.100,   0.000,  0.00),
    (11, 'Desert Eagle | Code Red',  1, 'Chaveiro | Lil'' Squatch',         5.000,  2.000,  45.000,  NULL),
    (12, 'AWP | Neo-Noir',           1, 'Adesivo | Bish (Holo)',           22.600,  7.300,  15.000, 60.75);

UPDATE tmp_aplicacao
   SET numero_inspecao = 'INS-CO-' || (1000 + n + (SELECT COUNT(*) FROM tmp_exemplar WHERE tipo = 'cosmetico'));

INSERT INTO item_instancia (numero_inspecao, item_catalogo_id, proprietario_id, tradable_flag, data_obtencao, status_item)
SELECT a.numero_inspecao, ic.id, arma.proprietario_id, TRUE, arma.data_obtencao, 'disponivel'
  FROM tmp_aplicacao a
  JOIN tmp_exemplar e         ON e.chave = a.arma || '#' || a.exemplar
  JOIN item_instancia arma    ON arma.numero_inspecao = e.numero_inspecao
  JOIN item_catalogo ic       ON ic.nome_item = a.cosmetico
 ORDER BY a.n;

INSERT INTO cosmetico (item_instancia_id, tipo_cosmetico, arte_visual)
SELECT i.id,
       CASE WHEN a.cosmetico LIKE 'Chaveiro%' THEN 'chaveiro' ELSE 'adesivo' END,
       COALESCE((SELECT MIN(c.arte_visual)
                   FROM cosmetico c
                   JOIN item_instancia x ON x.id = c.item_instancia_id
                  WHERE x.item_catalogo_id = i.item_catalogo_id),
                'art/' || btrim(lower(regexp_replace(split_part(a.cosmetico, '| ', 2),
                                                     '[^A-Za-z0-9]+', '_', 'g')), '_') || '.svg')
  FROM tmp_aplicacao a
  JOIN item_instancia i ON i.numero_inspecao = a.numero_inspecao
 ORDER BY a.n;

INSERT INTO aplicacao_cosmetico (cosmetico_id, equipamento_id, coord_x, coord_y, rotacao, nivel_raspagem)
SELECT c.id, arma.id, a.coord_x, a.coord_y, a.rotacao, a.nivel_raspagem
  FROM tmp_aplicacao a
  JOIN item_instancia c    ON c.numero_inspecao = a.numero_inspecao
  JOIN tmp_exemplar e      ON e.chave = a.arma || '#' || a.exemplar
  JOIN item_instancia arma ON arma.numero_inspecao = e.numero_inspecao
 ORDER BY a.n;


-- ---------------------------------------------------------------------
-- 7. VENDAS HISTORICAS  (anuncio -> venda -> pagamento -> NF -> posse)
--    Em ordem cronologica, cada venda segue a mesma cadeia da compra
--    feita pela aplicacao (fn_comprar_anuncio):
--      1) anuncio 'ativo' do dono atual (trg_validar_anuncio confere)
--      2) venda 'concluida', protocolo VND-AAAA-NNNN: AAAA = ano da
--         venda, NNNN = nextval('venda_protocolo_seq'), que continua a
--         numeracao do 03 (sem repetir)
--      3) pagamento 'aprovado' com o valor integral
--      4) nota fiscal com pg_temp.chave_nfe(NNNN, data de emissao): a
--         chave de fn_gerar_chave_nfe, com o ano/mes da emissao
--      5) anuncio -> 'vendido' (trg_transicao_anuncio confere a venda)
--      6) o item passa ao comprador (os cosmeticos aplicados vao junto)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r          RECORD;
    v_anuncio  INTEGER;
    v_venda    INTEGER;
    v_numero   BIGINT;
BEGIN
    FOR r IN
        SELECT v.*,
               i.id  AS item_id,
               vd.id AS vendedor_id,
               cp.id AS comprador_id
          FROM tmp_venda v
          JOIN item_instancia i ON i.numero_inspecao = v.numero_inspecao
          JOIN tmp_usuario vd   ON vd.n = v.vendedor_n
          JOIN tmp_usuario cp   ON cp.n = v.comprador_n
         ORDER BY v.data_venda, v.numero_inspecao
    LOOP
        INSERT INTO anuncio (item_instancia_id, criador_id, data_publicacao, preco, data_expiracao, status_anuncio)
        VALUES (r.item_id, r.vendedor_id, r.data_publicacao, r.valor, r.data_expiracao, 'ativo')
        RETURNING id INTO v_anuncio;

        v_numero := nextval('venda_protocolo_seq');

        INSERT INTO venda (protocolo_venda, anuncio_id, comprador_id, data_venda, valor_venda, status_venda)
        VALUES ('VND-' || to_char(r.data_venda, 'YYYY') || '-'
                    || lpad(v_numero::TEXT, GREATEST(4, length(v_numero::TEXT)), '0'),
                v_anuncio, r.comprador_id, r.data_venda, r.valor, 'concluida')
        RETURNING id INTO v_venda;

        INSERT INTO pagamento (venda_id, metodo_pagamento, valor, data_pagamento, status_pagamento)
        VALUES (v_venda, r.metodo, r.valor, r.data_pagamento, 'aprovado');

        INSERT INTO nota_fiscal (chave, venda_id, data_emissao, valor_total)
        VALUES (pg_temp.chave_nfe(v_numero, r.data_emissao), v_venda, r.data_emissao, r.valor);

        UPDATE anuncio SET status_anuncio = 'vendido' WHERE id = v_anuncio;

        UPDATE item_instancia SET proprietario_id = r.comprador_id WHERE id = r.item_id;

        UPDATE tmp_venda SET venda_id = v_venda
         WHERE numero_inspecao = r.numero_inspecao AND j = r.j;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 8. AVALIACAO + AVALIACAO_VENDA  (comprador avalia o vendedor)
--    Cerca de 39% das vendas novas (148 de 384: sorteio de 42%, sem as
--    compras da isizinha desde 01/09/2026 e as que passariam de
--    26/10/2026), de 3 horas a 3,5 dias depois da venda. Notas na
--    maioria 4 e 5, com algumas de 1 a 3.
--    Vendedor SEM Steam Guard: a Steam segura por ate 15 dias os itens
--    enviados por contas sem o autenticador movel, entao a avaliacao vem
--    15 dias mais tarde, com nota de 2 a 4 (media perto de 3) e comentario
--    sobre a demora (tmp_comentario_retido).
--    Ticket TKT-AAAA-NNNN com nextval('avaliacao_ticket_seq'), em ordem
--    cronologica.
--    As compras da isizinha a partir de 01/09/2026 ficam SEM avaliacao,
--    para a demonstracao do botao "Avaliar vendedor".
--    O trigger trg_validar_avaliacao_venda confere cada uma (RS-25).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_comentario (
    nota    INTEGER  NOT NULL,
    ordem   INTEGER  NOT NULL,
    texto   TEXT,              -- NULL = avaliacao sem comentario
    PRIMARY KEY (nota, ordem)
);

INSERT INTO tmp_comentario (nota, ordem, texto) VALUES
    (5, 0, 'Entrega rapida e item igual ao anuncio.'),
    (5, 1, 'Vendedor atencioso, recomendo!'),
    (5, 2, 'Tudo certo, negociacao tranquila.'),
    (5, 3, 'Item exatamente como descrito.'),
    (5, 4, 'Excelente vendedor, compraria de novo.'),
    (5, 5, 'Rapido e confiavel.'),
    (5, 6, 'Item perfeito, chegou na hora.'),
    (5, 7, NULL),
    (4, 0, 'Bom vendedor, so demorou um pouco para responder.'),
    (4, 1, 'Item ok e preco justo.'),
    (4, 2, 'Negociacao boa, recomendo.'),
    (4, 3, 'Chegou certinho, mas a entrega levou algumas horas.'),
    (4, 4, 'Tudo certo, faltou so um pouco de comunicacao.'),
    (4, 5, NULL),
    (3, 0, 'Demorou para liberar o item, mas chegou.'),
    (3, 1, 'Negociacao regular, nada demais.'),
    (3, 2, 'Item certo, porem o vendedor sumiu por um tempo.'),
    (2, 0, 'Comunicacao ruim, quase desisti da compra.'),
    (2, 1, 'O item veio certo, mas atrasou bastante.'),
    (1, 0, 'Nao respondia as mensagens. Nao recomendo.'),
    (1, 1, 'Experiencia ruim: o item demorou dias para chegar.');

-- Comentarios para vendedor sem Steam Guard (entrega retida por ate 15
-- dias). Nenhum fala em "troca", que no site e outra coisa (tabela troca).
CREATE TEMP TABLE tmp_comentario_retido (
    nota    INTEGER  NOT NULL,
    ordem   INTEGER  NOT NULL,
    texto   TEXT     NOT NULL,
    PRIMARY KEY (nota, ordem)
);

INSERT INTO tmp_comentario_retido (nota, ordem, texto) VALUES
    (4, 0, 'Item certo, mas a entrega ficou retida por 15 dias. Vendedor sem Steam Guard.'),
    (4, 1, 'Bom preco, porem a entrega levou mais de 15 dias por falta de Steam Guard.'),
    (4, 2, 'Tudo certo no fim, so a espera de 15 dias que pesou.'),
    (3, 0, 'Demorou mais de 15 dias para o item chegar. Ative o Steam Guard!'),
    (3, 1, 'O item ficou preso por 15 dias porque o vendedor nao usa Steam Guard.'),
    (3, 2, 'Item certo, mas a retencao de 15 dias atrapalhou.'),
    (2, 0, 'Esperei mais de duas semanas pelo item. Faltou Steam Guard no vendedor.'),
    (2, 1, 'Muita demora: mais de 15 dias ate o item chegar.');

DO $$
DECLARE
    r         RECORD;
    v_aval    INTEGER;
    v_numero  BIGINT;
BEGIN
    FOR r IN
        WITH escolhidas AS (
            SELECT v.venda_id,
                   v.chave,
                   vd.id AS vendedor_id,
                   cp.id AS comprador_id,
                   uv.steam_guard_ativo AS vendedor_com_guard,
                   v.data_venda
                     + CASE WHEN uv.steam_guard_ativo THEN INTERVAL '0 days' ELSE INTERVAL '15 days' END
                     + FLOOR(180 + 4860 * pg_temp.sorteio('quando|' || v.chave)) * INTERVAL '1 minute' AS data_avaliacao,
                   CASE WHEN NOT uv.steam_guard_ativo THEN
                            CASE WHEN pg_temp.sorteio('nota|' || v.chave) < 0.30 THEN 4
                                 WHEN pg_temp.sorteio('nota|' || v.chave) < 0.75 THEN 3
                                 ELSE 2 END
                        WHEN pg_temp.sorteio('nota|' || v.chave) < 0.55 THEN 5
                        WHEN pg_temp.sorteio('nota|' || v.chave) < 0.82 THEN 4
                        WHEN pg_temp.sorteio('nota|' || v.chave) < 0.91 THEN 3
                        WHEN pg_temp.sorteio('nota|' || v.chave) < 0.96 THEN 2
                        ELSE 1 END AS nota
              FROM tmp_venda v
              JOIN tmp_usuario vd ON vd.n = v.vendedor_n
              JOIN usuario uv     ON uv.id = vd.id
              JOIN tmp_usuario cp ON cp.n = v.comprador_n
             WHERE pg_temp.sorteio('avaliacao|' || v.chave) < 0.42
               AND NOT (cp.apelido = 'isizinha' AND v.data_venda >= TIMESTAMP '2026-09-01')
        )
        SELECT x.*,
               CASE WHEN x.vendedor_com_guard THEN
                   (SELECT c.texto
                      FROM tmp_comentario c
                     WHERE c.nota = x.nota
                       AND c.ordem = FLOOR(pg_temp.sorteio('comentario|' || x.chave)
                                           * (SELECT COUNT(*) FROM tmp_comentario k WHERE k.nota = x.nota)))
               ELSE
                   (SELECT c.texto
                      FROM tmp_comentario_retido c
                     WHERE c.nota = x.nota
                       AND c.ordem = FLOOR(pg_temp.sorteio('comentario|' || x.chave)
                                           * (SELECT COUNT(*) FROM tmp_comentario_retido k WHERE k.nota = x.nota)))
               END AS comentario
          FROM escolhidas x
         WHERE x.data_avaliacao <= TIMESTAMP '2026-10-26 22:00'
         ORDER BY x.data_avaliacao, x.venda_id
    LOOP
        v_numero := nextval('avaliacao_ticket_seq');

        INSERT INTO avaliacao (ticket_avaliacao, autor_id, avaliado_id, data_avaliacao, comentario, nota)
        VALUES ('TKT-' || to_char(r.data_avaliacao, 'YYYY') || '-'
                    || lpad(v_numero::TEXT, GREATEST(4, length(v_numero::TEXT)), '0'),
                r.comprador_id, r.vendedor_id, r.data_avaliacao, r.comentario, r.nota)
        RETURNING id INTO v_aval;

        INSERT INTO avaliacao_venda (avaliacao_id, venda_id)
        VALUES (v_aval, r.venda_id);
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 9. ANUNCIOS ENCERRADOS  (aba Encerrados: 'expirado' e 'cancelado')
--    So exemplares que nunca foram vendidos (o dono e sempre o
--    original). Publicados entre 05/11/2025 e 31/08/2026, com preco
--    acima do mercado (10% a 30%) -- por isso nao venderam. Cada um nasce
--    'ativo' e depois muda de status, passando pelo trg_transicao_anuncio
--    (so expira o que ja venceu).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_encerrado AS
SELECT e.numero_inspecao,
       e.anuncio_encerrado AS status_final,
       e.dono_inicial,
       DATE '2025-11-05' + FLOOR(300 * pg_temp.sorteio('enc-dia|' || e.chave))::INTEGER
         + TIME '08:00'
         + FLOOR(840 * pg_temp.sorteio('enc-hora|' || e.chave)) * INTERVAL '1 minute' AS data_publicacao,
       CASE WHEN pg_temp.sorteio('enc-validade|' || e.chave) < 0.30 THEN 7
            WHEN pg_temp.sorteio('enc-validade|' || e.chave) < 0.60 THEN 14
            ELSE 30 END AS validade_dias,
       e.ordem, e.float_value, e.stattrak, e.souvenir, e.chave
  FROM tmp_exemplar e
 WHERE e.anuncio_encerrado IS NOT NULL;

INSERT INTO anuncio (item_instancia_id, criador_id, data_publicacao, preco, data_expiracao, status_anuncio)
SELECT i.id,
       u.id,
       x.data_publicacao,
       pg_temp.preco_simulado(x.ordem, x.float_value, x.stattrak, x.souvenir, x.data_publicacao,
                              1.10 + 0.20 * pg_temp.sorteio('enc-preco|' || x.chave)),
       x.data_publicacao + x.validade_dias * INTERVAL '1 day',
       'ativo'
  FROM tmp_encerrado x
  JOIN item_instancia i ON i.numero_inspecao = x.numero_inspecao
  JOIN tmp_usuario u    ON u.n = x.dono_inicial
 ORDER BY x.data_publicacao, x.numero_inspecao;

UPDATE anuncio a
   SET status_anuncio = x.status_final
  FROM tmp_encerrado x
  JOIN item_instancia i ON i.numero_inspecao = x.numero_inspecao
 WHERE a.item_instancia_id = i.id
   AND a.data_publicacao   = x.data_publicacao
   AND a.status_anuncio    = 'ativo';


-- ---------------------------------------------------------------------
-- 10. ANUNCIOS ATIVOS  (a vitrine da demonstracao)
--     Publicados pelo dono atual entre 01 e 25/10/2026, depois da ultima
--     venda do item, com validade ate uma data entre 15/04/2027 e
--     30/09/2027. Se o vendedor dessa venda nao tem Steam Guard, o item so
--     chega 15 dias depois, e so entao pode ser anunciado de novo.
--     Preco perto do mercado: de 10% abaixo a 15% acima do preco simulado
--     do exemplar.
-- ---------------------------------------------------------------------
INSERT INTO anuncio (item_instancia_id, criador_id, data_publicacao, preco, data_expiracao, status_anuncio)
SELECT i.id,
       i.proprietario_id,
       x.data_publicacao,
       pg_temp.preco_simulado(e.ordem, e.float_value, e.stattrak, e.souvenir, x.data_publicacao,
                              0.90 + 0.25 * pg_temp.sorteio('atv-preco|' || e.chave)),
       DATE '2027-04-15' + FLOOR(169 * pg_temp.sorteio('atv-validade|' || e.chave))::INTEGER
         + x.data_publicacao::TIME,
       'ativo'
  FROM tmp_exemplar e
  JOIN item_instancia i ON i.numero_inspecao = e.numero_inspecao
  LEFT JOIN LATERAL (
       SELECT v.data_venda, u.steam_guard_ativo
         FROM venda v
         JOIN anuncio a ON a.id = v.anuncio_id
         JOIN usuario u ON u.id = a.criador_id
        WHERE a.item_instancia_id = i.id
          AND v.status_venda = 'concluida'
        ORDER BY v.data_venda DESC
        LIMIT 1
  ) ult ON TRUE
 CROSS JOIN LATERAL (
       SELECT GREATEST(
                DATE '2026-10-01' + FLOOR(25 * pg_temp.sorteio('atv-dia|' || e.chave))::INTEGER
                  + TIME '08:00'
                  + FLOOR(840 * pg_temp.sorteio('atv-hora|' || e.chave)) * INTERVAL '1 minute',
                CASE WHEN NOT ult.steam_guard_ativo THEN ult.data_venda + INTERVAL '15 days' END
              ) AS data_publicacao
 ) x
 WHERE e.anuncio_ativo
 ORDER BY x.data_publicacao, e.numero_inspecao;


-- ---------------------------------------------------------------------
-- 11. AJUSTES NOS DADOS DO 03
--     Correcoes feitas depois de conferir o catalogo com o CSGO-API. So
--     valem quando o 04 e executado.
--
-- 11.1 Colecoes conferidas com o CSGO-API: alguns modelos do 03 estavam
--      em colecoes trocadas. Facas, luvas e adesivos de torneio nao
--      pertencem a colecao nenhuma (NULL), como no CSGO-API.
--      5 dos 6 chaveiros do 03 eram obtidos antes de 02/10/2024, quando
--      os chaveiros chegaram ao jogo: a data passa 7 meses para frente.
-- ---------------------------------------------------------------------
INSERT INTO colecao (nome_colecao, data_lancamento) VALUES
    ('The Dust 2 Collection',       NULL),   -- data nao confirmada
    ('Small Arms Charm Collection', NULL);   -- data nao confirmada

UPDATE item_catalogo ic
   SET colecao_id = (SELECT co.id FROM colecao co WHERE co.nome_colecao = c.colecao)
  FROM (VALUES
        ('AK-47 | Redline',                'The Phoenix Collection'),
        ('AWP | Asiimov',                  'The Phoenix Collection'),
        ('P90 | Sand Spray',               'The Dust 2 Collection'),
        ('Chaveiro | Hot Howl',            'Missing Link Charm Collection'),
        ('Chaveiro | Baby Karat T',        'Small Arms Charm Collection'),
        ('M4A4 | Howl',                    NULL),
        ('Karambit | Doppler',             NULL),
        ('Adesivo | Natus Vincere (Holo)', NULL),
        ('Grafite | EZ',                   NULL)
       ) AS c(modelo, colecao)
 WHERE ic.nome_item = c.modelo;

-- Chaveiros so existem no CS2 desde 02/10/2024.
UPDATE item_instancia SET data_obtencao = data_obtencao + INTERVAL '7 months'
 WHERE numero_inspecao IN ('INS-CO-0005', 'INS-CO-0006', 'INS-CO-0007', 'INS-CO-0008', 'INS-CO-0019');

-- A The Cache Collection so tinha a AK-47 | Redline e ficou vazia: sai,
-- porque toda colecao precisa agrupar ao menos um modelo (RS-18 de
-- 05_verificacao.sql).
DELETE FROM colecao co
 WHERE NOT EXISTS (SELECT 1 FROM item_catalogo ic WHERE ic.colecao_id = co.id);

-- Dois nomes do 03 eram de caixa/operacao, nao de colecao.
UPDATE colecao SET nome_colecao = 'The Danger Zone Collection' WHERE nome_colecao = 'The Danger Zone Case';
UPDATE colecao SET nome_colecao = 'The Bravo Collection'       WHERE nome_colecao = 'Operation Bravo';

-- ---------------------------------------------------------------------
-- 11.2 Variantes que nao existem no jogo (CSGO-API):
--      - a Desert Eagle | Blaze so existe na The Dust Collection, que nao
--        tem versao StatTrak; o exemplar INS-EQ-0005 estava como StatTrak;
--      - o AWP | Asiimov so sai da Operation Phoenix Weapon Case, sem
--        versao Souvenir; o exemplar INS-EQ-0003 estava como Souvenir.
-- ---------------------------------------------------------------------
UPDATE equipamento
   SET stattrak_flag = FALSE
 WHERE item_instancia_id = (SELECT id FROM item_instancia WHERE numero_inspecao = 'INS-EQ-0005');

UPDATE equipamento
   SET souvenir_flag = FALSE
 WHERE item_instancia_id = (SELECT id FROM item_instancia WHERE numero_inspecao = 'INS-EQ-0003');

-- ---------------------------------------------------------------------
-- 11.3 A Capsula Ambush do 03 (renomeada na 11.4) estava anunciada por
--      R$ 680,00 (com venda pendente), enquanto as vendas simuladas do
--      modelo ficam perto de R$ 7. O valor certo e R$ 6,80: anuncio, venda
--      e pagamento juntos (RS-13: pagamento = valor da venda).
-- ---------------------------------------------------------------------
UPDATE anuncio a
   SET preco = 6.80
  FROM item_instancia i
 WHERE i.id = a.item_instancia_id
   AND i.numero_inspecao = 'INS-CN-0005'
   AND a.preco = 680.00;

UPDATE venda SET valor_venda = 6.80 WHERE protocolo_venda = 'VND-2026-0011';

UPDATE pagamento
   SET valor = 6.80
 WHERE venda_id = (SELECT id FROM venda WHERE protocolo_venda = 'VND-2026-0011');

-- ---------------------------------------------------------------------
-- 11.4 ABERTURAS coerentes com o conteudo dos recipientes (CSGO-API).
--      No 03, a Caixa Fracture dava uma AK-47 | Redline, que sai da
--      Operation Phoenix Weapon Case; a chave era a do CS:GO, que nao abre
--      essa caixa; e a Capsula Ambush dava adesivos que nao estao nela.
--      abertura_recipiente nao aceita UPDATE (trigger), entao o ajuste e
--      nos modelos e no item obtido:
--      - Caixa Fracture -> Caixa Phoenix (The Phoenix Collection, a mesma
--        da AK-47 | Redline e da AWP | Asiimov);
--      - Chave de Caixa -> Chave da Caixa Phoenix;
--      - Capsula Ambush -> Capsula Katowice 2014 Challengers, que tem o
--        adesivo Natus Vincere (Holo) da imagem do catalogo;
--      - o adesivo da 5a abertura (INS-CO-0013) era Crown (Foil), que sai
--        de outra capsula; passa a ser Natus Vincere (Holo), como os
--        das outras duas aberturas de capsula.
-- ---------------------------------------------------------------------
UPDATE item_catalogo
   SET nome_item   = 'Caixa Phoenix',
       colecao_id  = (SELECT id FROM colecao WHERE nome_colecao = 'The Phoenix Collection'),
       imagem_base = 'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bj35VTqVBP4io_fr2wPtqP5PKVvJPSQDWSSl7sn6eMxHC3hwhl3sDuDztivJHrEagJzWZd3W6dU5fXcT7oM',
       descricao   = 'Caixa da Operation Phoenix, aberta com a Chave da Caixa Phoenix.'
 WHERE nome_item = 'Caixa Fracture';

UPDATE item_catalogo
   SET nome_item   = 'Chave da Caixa Phoenix',
       imagem_base = 'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJG51EejH_XGwt6kCnCS_Gl2-4r5_1fuVQTOzNjkrCBZuquoO6JpeaaVWjTDk7ch6bcwHyrjzRkk4GzRnNitJX-falJ1FNIuEtlTaEjz',
       descricao   = 'Chave que abre somente a Caixa Phoenix.'
 WHERE nome_item = 'Chave de Caixa';

UPDATE item_catalogo
   SET nome_item   = 'Capsula Katowice 2014 Challengers',
       imagem_base = 'https://community.akamai.steamstatic.com/economy/image/i0CoZ81Ui0m-9KwlBY1L_18myuGuq1wfhWSaZgMttyVfPaERSR0Wqmu7LAocGJKz2lu_XsnXwtmkJjSU91dh8bjn_lDkShjjoYbh_ilk5PO6OvQ8dM_DXynCkLkv6LJrSSrilkRw4GzSw9-qIHmSPFNxWJR2TeIMt0HsltXgYrzq-UWA3Meo50Y4',
       descricao   = 'Capsula de adesivos das equipes Challengers do Major de Katowice 2014, aberta sem chave.'
 WHERE nome_item = 'Capsula Ambush';

UPDATE item_instancia
   SET item_catalogo_id = (SELECT id FROM item_catalogo WHERE nome_item = 'Adesivo | Natus Vincere (Holo)')
 WHERE numero_inspecao = 'INS-CO-0013';

UPDATE cosmetico
   SET arte_visual = 'art/navi_holo_v1.svg'
 WHERE item_instancia_id = (SELECT id FROM item_instancia WHERE numero_inspecao = 'INS-CO-0013');

-- ---------------------------------------------------------------------
-- 11.5 ACENTOS nos textos que aparecem na tela (nomes, comentarios,
--      descricoes e observacoes de troca). Os scripts sao ASCII, para
--      rodar em qualquer cliente sem problema de codificacao; por isso as
--      letras acentuadas vem como escape Unicode (U&'\00E1' = a com
--      acento agudo). A troca e feita por palavra inteira; as expressoes
--      mais longas (com crase) vao antes das palavras soltas.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_acento (sem TEXT PRIMARY KEY, com TEXT NOT NULL);
INSERT INTO tmp_acento (sem, com) VALUES
    ('Otimo',           U&'\00D3timo'),
    ('comunicacao',     U&'comunica\00E7\00E3o'),
    ('Comunicacao',     U&'Comunica\00E7\00E3o'),
    ('so',              U&'s\00F3'),
    ('rapida',          U&'r\00E1pida'),
    ('rapido',          U&'r\00E1pido'),
    ('Rapido',          U&'R\00E1pido'),
    ('anuncio',         U&'an\00FAncio'),
    ('Experiencia',     U&'Experi\00EAncia'),
    ('porem',           U&'por\00E9m'),
    ('preco',           U&'pre\00E7o'),
    ('autentico',       U&'aut\00EAntico'),
    ('negociacao',      U&'negocia\00E7\00E3o'),
    ('Negociacao',      U&'Negocia\00E7\00E3o'),
    ('Nao',             U&'N\00E3o'),
    ('nao',             U&'n\00E3o'),
    ('retencao',        U&'reten\00E7\00E3o'),
    ('ate',             U&'at\00E9'),
    ('descricao',       U&'descri\00E7\00E3o'),
    ('confiavel',       U&'confi\00E1vel'),
    ('mao',             U&'m\00E3o'),
    ('metalico',        U&'met\00E1lico'),
    ('padrao',          U&'padr\00E3o'),
    ('psicodelicas',    U&'psicod\00E9licas'),
    ('holografico',     U&'hologr\00E1fico'),
    ('colecao',         U&'cole\00E7\00E3o'),
    ('Capsula',         U&'C\00E1psula'),
    ('classico',        U&'cl\00E1ssico'),
    ('ardosia',         U&'ard\00F3sia'),
    ('egipcios',        U&'eg\00EDpcios'),
    ('egipcia',         U&'eg\00EDpcia'),
    ('tecnologico',     U&'tecnol\00F3gico'),
    ('tecnologicos',    U&'tecnol\00F3gicos'),
    ('dragao',          U&'drag\00E3o'),
    ('ilustracao',      U&'ilustra\00E7\00E3o'),
    ('aberracao',       U&'aberra\00E7\00E3o'),
    ('cromatica',       U&'crom\00E1tica'),
    ('japones',         U&'japon\00EAs'),
    ('aquatica',        U&'aqu\00E1tica'),
    ('guardiao',        U&'guardi\00E3o'),
    ('degrade',         U&'degrad\00EA'),
    ('dobravel',        U&'dobr\00E1vel'),
    ('tempera',         U&'t\00EAmpera'),
    ('caca',            U&'ca\00E7a'),
    ('taticas',         U&'t\00E1ticas'),
    ('E o unico',       U&'\00C9 o \00FAnico'),
    ('pe',              U&'p\00E9'),
    ('Concluida',       U&'Conclu\00EDda'),
    ('intercorrencias', U&'intercorr\00EAncias'),
    ('multipla',        U&'m\00FAltipla'),
    ('destinatario',    U&'destinat\00E1rio'),
    ('Destinatario',    U&'Destinat\00E1rio'),
    ('Joao',            U&'Jo\00E3o'),
    ('pintadas a mao',         U&'pintadas \00E0 m\00E3o'),
    ('respondia as mensagens', U&'respondia \00E0s mensagens');

DO $$
DECLARE
    r       RECORD;
    v_busca TEXT;
BEGIN
    FOR r IN SELECT sem, com FROM tmp_acento ORDER BY length(sem) DESC, sem LOOP
        v_busca := '\m' || r.sem || '\M';
        UPDATE avaliacao      SET comentario     = regexp_replace(comentario,     v_busca, r.com, 'g') WHERE comentario     ~ v_busca;
        UPDATE item_catalogo  SET descricao      = regexp_replace(descricao,      v_busca, r.com, 'g') WHERE descricao      ~ v_busca;
        UPDATE item_catalogo  SET nome_item      = regexp_replace(nome_item,      v_busca, r.com, 'g') WHERE nome_item      ~ v_busca;
        UPDATE categoria_item SET nome_categoria = regexp_replace(nome_categoria, v_busca, r.com, 'g') WHERE nome_categoria ~ v_busca;
        UPDATE usuario        SET nome           = regexp_replace(nome,           v_busca, r.com, 'g') WHERE nome           ~ v_busca;
        UPDATE troca          SET laudo_troca    = regexp_replace(laudo_troca,    v_busca, r.com, 'g') WHERE laudo_troca    ~ v_busca;
        UPDATE troca          SET observacao     = regexp_replace(observacao,     v_busca, r.com, 'g') WHERE observacao     ~ v_busca;
    END LOOP;
END $$;

DROP TABLE tmp_acento;


-- ---------------------------------------------------------------------
-- 12. NUMERACAO DAS PROXIMAS VENDAS E AVALIACOES
--     Igual a secao 16 do 03: as sequencias ficam no maior numero usado,
--     e a proxima compra/avaliacao feita pela aplicacao continua dali.
-- ---------------------------------------------------------------------
SELECT setval('venda_protocolo_seq',
              (SELECT MAX(SUBSTRING(protocolo_venda FROM 10)::INTEGER) FROM venda));
SELECT setval('avaliacao_ticket_seq',
              (SELECT MAX(SUBSTRING(ticket_avaliacao FROM 10)::INTEGER) FROM avaliacao));


-- ---------------------------------------------------------------------
-- 13. LIMPEZA dos auxiliares temporarios
-- ---------------------------------------------------------------------
DROP TABLE tmp_encerrado, tmp_comentario, tmp_comentario_retido, tmp_aplicacao, tmp_venda,
           tmp_exemplar, tmp_modelo, tmp_usuario;
DROP FUNCTION pg_temp.preco_simulado(INTEGER, NUMERIC, BOOLEAN, BOOLEAN, TIMESTAMP, NUMERIC);
DROP FUNCTION pg_temp.chave_nfe(BIGINT, TIMESTAMP);
DROP FUNCTION pg_temp.fator_desgaste(NUMERIC);
DROP FUNCTION pg_temp.sorteio(TEXT);

COMMIT;

-- =====================================================================
-- RESUMO: o banco depois de 01 + 02 + 03 + 04
--
--   tabela                  03    04 (novos)   total
--   colecao                 12        17          29   (16 da secao 1 + 2 da 11.1 - 1 vazia)
--   item_catalogo           21        59          80   modelos
--     equipamento           11        49          60   (19 rifles, 11 pistolas, 8 SMGs,
--                                                       5 escopetas, 3 metralhadoras,
--                                                       7 facas, 7 luvas)
--     cosmetico              4         5           9   (5 adesivos, 4 chaveiros)
--     consumivel             6         5          11   (4 caixas, 3 capsulas,
--                                                       2 chaves, 2 grafites)
--   item_instancia          54       243         297   itens
--     equipamento           16       176         192
--     cosmetico             20        36          56   (12 aplicados em armas)
--     consumivel            18        31          49
--   aplicacao_cosmetico      7        12          19
--   anuncio                 19       479         498
--     vendido               10       384         394
--     ativo                  6        74          80   (vencem entre 01/04 e 19/09/2027)
--     cancelado              2        13          15
--     expirado               1         8           9
--   venda                   12       384         396   (394 concluidas)
--   pagamento               12       384         396
--   nota_fiscal             10       384         394
--   avaliacao               10       148         158
--   avaliacao_venda          5       148         153
--
--   Vendas concluidas por mes (inclui as 10 do 03, em jan-fev/2026):
--     11/2025  26 | 12/2025  36 | 01/2026  47 | 02/2026  27
--     03/2026  25 | 04/2026  40 | 05/2026  27 | 06/2026  30
--     07/2026  37 | 08/2026  33 | 09/2026  38 | 10/2026  28   = 394
--   Todos os 80 modelos tem 3 ou mais vendas; 132 itens foram revendidos.
--   Protocolos novos: VND-2025-0013 a VND-2026-0396; tickets novos:
--   TKT-2025-0011 a TKT-2026-0158. As sequencias ficam em 396 e 158: a
--   proxima compra da aplicacao sera VND-2026-0397.
--   A numeracao segue a ordem de cadastro, nao a cronologica: as 12 vendas
--   do 03 (jan-fev/2026) mantem 0001-0012 e as do 04 continuam de 0013,
--   inclusive as de nov-dez/2025 (vale tambem para os tickets e para o
--   numero da NF).
--   Notas fiscais novas: chave com o ano/mes da EMISSAO (2511 a 2610).
--
--   Precos: a primeira e a ultima venda de cada modelo sao da mesma
--   classe (exemplares de referencia; ver o cabecalho), e o ranking de
--   maiores variacoes (analise.sql) vai de -26,5% a +32,6%: a tendencia
--   simulada de cada modelo mais o ruido.
--   As 290 vendas de equipamento cobrem os 5 desgastes:
--     FN 25 | MW 25 | FT 216 | WW 11 | BS 13   (24 StatTrak, 10 Souvenir)
--   26 modelos tem vendas em mais de um desgaste e 14 tem vendas com e
--   sem StatTrak. Comparando cada venda com as FT comuns do mesmo modelo
--   no mesmo trimestre, o preco medio fica em FN 1,26 | MW 1,10 |
--   FT 1,00 | WW 0,90 | BS 0,77, e o StatTrak custa cerca de 1,45 vez o
--   comum do mesmo desgaste.
--   Equipamentos (03 + 04): 30 StatTrak e 5 Souvenir.
--
--   Usuario de demonstracao isizinha: 34 itens (23 prontos para anunciar,
--   entre armas, adesivos/chaveiros e consumiveis), 7 anuncios ativos,
--   3 encerrados, 26 vendas e 41 compras. 27 compras ainda nao foram
--   avaliadas por ela, entre elas todas as de setembro e outubro/2026
--   (botao "Avaliar vendedor" na aba Comprados).
-- =====================================================================
