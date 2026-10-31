// Ponto de entrada: sobe o servidor web do VaultGabe.
// Variaveis de ambiente vem do .env (no computador) ou do Render (no ar).
import { criarApp } from './app.js';

const porta = Number(process.env.PORT) || 3000;

criarApp().listen(porta, () => {
  console.log(`VaultGabe rodando em http://localhost:${porta}`);
});
