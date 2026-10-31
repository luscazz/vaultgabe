# Publicação do VaultGabe

Guia de publicação do projeto: o código é enviado manualmente ao **GitHub**, e a aplicação roda no **Render**, conectada ao banco **production** do Neon.

---

## 1. Pré-requisitos

Antes de publicar, as condições abaixo devem estar atendidas:

- **Banco `development` do Neon:** montado com `01` a `04` e conferido com `05_verificacao.sql` (todas as verificações com `OK`).
- **Banco `production` do Neon:** montado com `npm run banco:producao -- --confirmo` (seção 2). Sem esse comando, a branch continua com os dados que já tinha, sem os dados ampliados do `04`.
- **Testes:** `npm test` e `npm run test:neon` passando.
- **Configuração do Render:** definida em [`render.yaml`](../render.yaml) (região Ohio, plano gratuito, verificação em `/api/saude`).
- **Credenciais:** apenas no `.env` (fora do Git), sem nenhuma senha no código, nos documentos ou nos testes.

---

## 2. Atualizar o banco de produção (uma vez, antes de publicar)

No terminal, dentro da pasta `vaultgabe_t1`:

```bash
npm run banco:producao -- --confirmo
```

O comando apaga e recria o banco da branch `production` com os scripts `01` a `04` e no fim roda o `05_verificacao.sql`. O resultado esperado é:

```
05_verificacao: tudo OK (25 regras)
Banco production: 80 modelos, 297 itens, 394 vendas concluidas, 80 anuncios ativos, fuso America/Sao_Paulo.
```

Sempre que `01_tabelas.sql` ou `02_regras.sql` mudarem, as duas branches precisam ser montadas de novo (`npm run banco:dev` e este comando), porque as consultas da aplicação dependem das visões e funções desses scripts. Sem o `--confirmo`, o comando não executa nada (proteção contra execução acidental). Para restaurar os dados de demonstração na produção, execute o comando novamente.

---

## 3. Enviar o código ao GitHub (manual)

O repositório é **público** e recebe o **conteúdo da pasta `vaultgabe_t1`**, exceto o `.env` e a pasta `node_modules`. O envio é feito manualmente, por uma das opções abaixo.

### Opção A: GitHub Desktop (recomendada)

O GitHub Desktop respeita o `.gitignore`, de modo que o `.env` e a `node_modules` ficam de fora automaticamente.

1. Instale o [GitHub Desktop](https://desktop.github.com) e faça login na conta do GitHub.
2. **File › Add local repository…** e escolha a pasta `vaultgabe_t1`. No aviso *This directory does not appear to be a Git repository*, clique em **create a repository**. Na janela *Create a new repository*, **não altere** *Name* (`vaultgabe_t1`) nem *Local path*: a linha *The repository will be created at …\vaultgabe_t1* deve apontar para a própria pasta. Deixe *Initialize this repository with a README* desmarcado (ele substituiria o `README.md`) e *Git ignore* e *License* em *None*, e clique em **Create repository**.
3. O GitHub Desktop cria sozinho o commit **Initial commit** com todos os arquivos da pasta, exceto os do `.gitignore`, mais um `.gitattributes` que ele mesmo acrescenta. Na aba **History**, abra esse commit e confira que **não aparecem** `.env` nem `node_modules`.
4. Clique em **Publish repository**. No campo **Name**, troque `vaultgabe_t1` por `vaultgabe`, **desmarque** *Keep this code private* e clique em **Publish repository**.
5. Abra o repositório no site (**Repository › View on GitHub**) e confira: **não existem** `.env` nem `node_modules`, e estão lá as pastas `src/` e `database/` e o arquivo `render.yaml`.

### Opção B: pelo site do GitHub (upload)

> O upload pelo navegador **não lê o `.gitignore`**. Ao arrastar a pasta inteira, o `.env` (com a senha do banco) e a `node_modules` também são enviados. Arraste apenas os itens da lista abaixo.

1. No GitHub: **New repository** › nome `vaultgabe` › **Public** › sem README › **Create repository**.
2. Clique em **uploading an existing file**.
3. No Windows Explorer, os arquivos que começam com ponto (`.env.example`, `.gitignore`, `.node-version` e também o `.env`, que **não** deve ir) aparecem normalmente na pasta; selecione só os itens da lista abaixo.
4. Selecione e arraste **somente**:
   - pastas: `database`, `docs`, `public`, `src`, `tests`, `views`
   - arquivos: `.env.example`, `.gitignore`, `.node-version`, `package.json`, `package-lock.json`, `README.md`, `render.yaml`
5. **Commit changes**.
6. Confira no repositório: **não pode existir** `.env` nem `node_modules`.

> Se o `.env` for publicado por engano: apague o repositório, troque a senha do banco no Neon (**Branches › production › Roles › Reset password**, e o mesmo na `development`), atualize o `.env` e envie o código novamente. Remover apenas o arquivo não é suficiente, porque ele permanece no histórico.

---

## 4. Publicar no Render

### Opção A: Blueprint (usa o `render.yaml`)

1. Crie a conta em [render.com](https://render.com) entrando com o GitHub.
2. **New › Blueprint** e clique em **Connect** ao lado do repositório `vaultgabe` (se ele não aparecer, autorize o Render a acessar esse repositório no GitHub).
3. Em **Blueprint Name**, digite `vaultgabe` e mantenha a **Branch** `main`. O Render lê o `render.yaml` e pede o valor de **`DATABASE_URL`**: cole a connection string da branch **production** (o valor de `DATABASE_URL_PRODUCAO` no `.env`). Esse valor só é pedido nesta criação; para corrigi-lo depois, use o serviço `vaultgabe` › **Environment**.
4. Clique em **Deploy Blueprint**. O primeiro build leva de 2 a 4 minutos. Se o deploy não passar da verificação de saúde (`/api/saude`), confira o `DATABASE_URL`.

### Opção B: Web Service manual

**New › Web Service**, escolha o repositório e preencha:

| Campo | Valor |
|---|---|
| Region | **Ohio (US East)**, a mesma do banco |
| Branch | `main` |
| Language | Node |
| Build Command | `npm ci --omit=dev` |
| Start Command | `npm start` |
| Instance Type | Free |
| Environment Variables (em Advanced) › `DATABASE_URL` | connection string da branch **production** do Neon |
| Health Check Path (em Advanced) | `/api/saude` |

Clique em **Create Web Service**.

> No plano gratuito, o Render suspende a aplicação depois de 15 minutos sem acesso, e o Neon suspende o banco. O primeiro acesso após a suspensão pode levar cerca de 1 minuto; os seguintes são rápidos.

---

## 5. Testar o endereço público

Substitua `SEU-ENDERECO` pelo endereço exibido pelo Render (ex.: `https://vaultgabe.onrender.com`).

1. `SEU-ENDERECO/api/saude` deve responder `"status": "ok"` e `"fuso": "America/Sao_Paulo"`.
2. **Catálogo:** buscar e filtrar (ex.: categoria Faca, desgaste FN).
3. **Detalhe da skin:** ofertas, gráfico de preço e **Comprar** (como `isizinha`).
4. **Inventário:** **Anunciar** um item disponível.
5. **Negociações:** cancelar o anúncio criado e **Avaliar vendedor** numa compra.
6. **Análise** e **Perfil:** carregamento sem erros.

> As operações feitas no site publicado (compras, anúncios, avaliações) ficam gravadas na produção. Para restaurar os dados de demonstração, execute novamente `npm run banco:producao -- --confirmo`.

---

## 6. Links do projeto

| O quê | Link |
|---|---|
| Repositório no GitHub | `https://github.com/SEU-USUARIO/vaultgabe` |
| Aplicação no ar | `SEU-ENDERECO` (ex.: `https://vaultgabe.onrender.com`) |
