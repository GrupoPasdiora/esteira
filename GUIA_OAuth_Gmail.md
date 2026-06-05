# Guia rápido — criar as credenciais OAuth do Gmail

O Claude Code precisa de `GMAIL_CLIENT_ID` e `GMAIL_CLIENT_SECRET` para o botão "Conectar Gmail" funcionar. Quem cria isso é você, no Google Cloud (uma vez). Leva ~10 minutos.

## Passo a passo
1. Acesse **console.cloud.google.com** e crie um projeto (ex.: "Agencia Newsroom").
2. Menu → **APIs e serviços → Biblioteca** → busque **Gmail API** → **Ativar**.
3. Menu → **APIs e serviços → Tela de consentimento OAuth**:
   - Tipo: **Externo** (ou Interno, se a conta for Google Workspace da agência).
   - Preencha nome do app, e-mail de suporte e e-mail do desenvolvedor.
   - Em **Escopos**, adicione: `.../auth/gmail.readonly` (só leitura — o sistema lê, não envia).
   - Em **Usuários de teste**, adicione o e-mail da agência que vai conectar.
4. Menu → **Credenciais → Criar credenciais → ID do cliente OAuth**:
   - Tipo: **Aplicativo da Web**.
   - **URIs de redirecionamento autorizados:** cole exatamente
     `https://SEU_DOMINIO/api/newsroom/oauth/gmail/callback`
     (o mesmo valor de `GMAIL_REDIRECT_URI` no `.env`).
5. Copie o **Client ID** e o **Client Secret** para o `.env`.

## Observações
- Escopo **readonly** é suficiente e mais seguro: o sistema só precisa ler os e-mails-fonte.
- Enquanto a tela de consentimento estiver em "Teste", só os e-mails listados como usuários de teste conseguem conectar — perfeito para o piloto. Para uso amplo, publique o app.
- Para contas que **não** são Gmail, use o caminho IMAP (`IMAP_HOST/USER/PASSWORD` no `.env`) com uma senha de app.
