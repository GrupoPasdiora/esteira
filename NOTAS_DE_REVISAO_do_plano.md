# Notas de revisão do plano do Claude Code

Revisão do plano do módulo "Newsroom". No geral: **aprovado, plano sólido** — modular, reaproveita BullMQ/Redis e o `audit_logs` existentes, mantém o disparo intocado como downstream e segue a ordem de fases certa. Abaixo, ajustes e acréscimos para ele incorporar **antes de codar**.

---

## 1. Os 6 prompts JÁ estão prontos — não redigir de novo
O plano diz: "Eu redijo os 3 prompts faltantes (classificação/manchetes/QA) como rascunho editável." **Não precisa.** Os **6 prompts** finalizados já estão em `prompts/prompts.md` (classificação, extração de fatos, reescrita, manchete, QA, similaridade), com o modelo recomendado por etapa. Para evitar duas versões divergentes: **use exatamente esses como seed da tabela `newsroom_config`** e deixe-os editáveis no dashboard. Se quiser melhorar algum, edite o arquivo — fonte única de verdade.

## 2. ⚠️ Direitos de IMAGEM — lacuna importante (resolver na Fase 2)
O texto está protegido (reescrita a partir de fatos + checagem de similaridade). Mas a **foto** de outro jornal **não** tem a defesa de "fatos não são protegidos" — reutilizar a imagem do concorrente é o risco jurídico **maior** de todos. Regra para o sistema:

- **NUNCA anexar automaticamente a imagem capturada de outro jornal** à matéria publicada.
- A imagem da matéria deve vir de: (a) **banco próprio da agência**, (b) **imagens oficiais** de release de governo/prefeitura (em geral liberadas), (c) **banco livre/gerada por IA**, ou (d) ficar **em branco com pendência "adicionar imagem"** para o editor resolver na fila.
- Adicionar `image_policy` na config e um flag `precisa_imagem` na `Story`. A imagem de origem pode ser guardada **só para referência interna** do editor, igual à URL — nunca publicada.

## 3. Feeds RSS — resultado da validação (eu testei)
Validei os feeds do seed. Conclusões úteis para você não perder tempo:

| Fonte | Situação | Ação |
|---|---|---|
| Rondoniagora | feed responde com conteúdo grande | provável OK — confirmar com parser real |
| Rondônia ao Vivo | feed responde com conteúdo grande | provável OK — confirmar com parser real |
| **Portal Rondônia** | **`/feed` REDIRECIONA para a home (sem RSS)** | **já mudei para `jornal_html` no seed; definir seletores** |
| Diário da Amazônia, Tudo Rondônia, News Rondônia, Rondo Notícias, Ji-Paraná Notícias, Rondônia Dinâmica | inconclusivo na minha ferramenta (ela renderiza HTML, não XML cru) | **validar 1 a 1 com parser RSS real a partir da VPS** |
| G1 Rondônia | bloqueado na minha ferramenta, mas o endpoint RSS do G1 é válido | usar `https://g1.globo.com/rss/g1/ro/rondonia/` da VPS |

Ou seja: a validação definitiva tem que ser feita **com um parser de RSS de verdade rodando na VPS** (como você já planejou). Minha ferramenta web não serve como validador de XML — não confie no "vazio" dela como "feed inexistente", exceto no caso do Portal Rondônia, que comprovadamente redireciona.

## 4. Dedup deve ser semântico, não só hash
O `SeenItem` por hash resolve a duplicata **da mesma fonte**. Mas o mesmo fato vem de **fontes diferentes** com títulos diferentes (e do e-mail/WhatsApp também). O agrupamento de `Card` precisa de uma camada **semântica** (similaridade de assunto + janela de tempo), senão o mesmo acontecimento vira 5 matérias nos 19 portais. Pode ser uma checagem barata de IA (Haiku) ou embedding — registre como item da Fase 2.

## 5. Trava de custo de IA
Já incluí `IA_LIMITE_DIARIO_USD` no `.env.example`. Implemente um **teto diário** de gasto com a API: ao atingir, a fila para de gerar e avisa no dashboard, em vez de gastar sem limite num dia de pico. Classificação/extração em alto volume → usar **Batch API** (mais barata) quando não for urgente.

## 6. Idempotência na publicação
No `approve`, garanta que **clicar duas vezes não publica duas vezes** (chave de idempotência por `Story.id`) e que falha no WordPress faça **retry com backoff** sem duplicar o post. Vale também para o webhook do disparo na Fase 3.

## 7. Pequenos reforços
- **WhatsApp na Fase 1:** a "ponte por e-mail" é só configurar a `CAPTACAO_EMAIL` (já no `.env`) como uma `Source` do tipo email com filtro — bom, mantém tudo no mesmo pipeline.
- **Editoria sensível:** marcar `Política/Polícia/Justiça` para usar **Sonnet no QA** e ligar a verificação cruzada já na entrada dessas (Fase 3), pelo risco de herdar erro do concorrente.

---

## Decisões que dependem de você (Elaine), não do Claude Code
1. **Portal-piloto da Fase 1:** qual site? Ele precisa da **URL da API REST** (`/wp-json/wp/v2`) e de um **Application Password** de um usuário editor. (Campos `WP_PILOTO_*` no `.env.example`.)
2. **Prompts:** confirmar que ele deve usar os de `prompts/prompts.md` (recomendado) em vez de redigir novos.
3. **Divisão editorial** "Nova Brasilândia d'Oeste → Zona da Mata": é decisão sua; confirme direto com ele.
4. **Política de imagem** (item 2): qual a preferência — banco próprio, imagem oficial, gerada por IA, ou sempre o editor adiciona?

## Arquivos de apoio que já deixei prontos no pacote
- `.env.example` — todas as chaves (Anthropic, Gmail, WordPress, webhook, trava de custo).
- `docker-compose.example.yml` — referência de deploy (web + worker + postgres + redis).
- `GUIA_OAuth_Gmail.md` — passo a passo para você gerar as credenciais do Gmail.
