# pr-reviewer — design

Data: 2026-10-31
Status: rascunho para aprovação

## Intenção

Um bot de revisão de PR **pessoal**, rodando no Mac do Jean, sem infraestrutura de produção (sem Docker, sem frota de contas, sem pipeline de vários agentes, sem rodar os testes do projeto).

O fluxo: Jean (ou alguém de confiança) comenta `/jeanjacintho-review` (PR inteiro) ou `/jeanjacintho-update-review` (só o que mudou desde a última revisão) num PR → o bot percebe em até ~2 min → revisa com o Codex procurando **falhas reais** (bugs que atravessam arquivos, não implicância de estilo) → posta **um** comentário com os achados ranqueados e um veredito. Com o tempo ele aprende: `/jeanjacintho-memorize <lição>` vira uma regra que entra em todas as revisões seguintes.

O porquê: ter "o meu bot de revisão", com as minhas regras, usando a conta do Codex que Jean já tem.

## Metas

- Disparo por comando em comentário de PR, só de pessoas configuradas.
- Só repositórios configurados.
- Revisão que busca falhas reais com caminho de falha citado (`arquivo:linha`), ranqueada por gravidade, com veredito.
- Aprendizado explícito via `/jeanjacintho-memorize`, guardado num arquivo legível e editável à mão.
- Roda sozinho no Mac (launchd), a cada 2 minutos.

## Não-metas

- Docker, múltiplas contas Codex, workers paralelos.
- Pipeline de vários especialistas + critic + agregador. **Uma** chamada Codex por revisão.
- Rodar testes de PRs cujo autor não é confiável.
- Aprender sozinho por heurística (só aprende quando mandado).
- Aprovar PR pelo bot.
- Webhooks / servidor público / GitHub App.

## Anti-metas (falha mesmo se "funcionar")

- **Gastar tokens do Codex no polling.** O ciclo de 2 min é 100% script (`gh` + `jq`). Codex só roda quando existe um comando válido, de pessoa confiável, ainda não tratado.
- Postar comentários duplicados (dois reviews para o mesmo comando, ou spam em loop de erro).
- Reagir a comandos de quem não está na lista.
- Disparar em comandos antigos na primeira execução.
- Executar código de PR de autor não confiável na máquina do Jean.
- Deixar conteúdo do PR (diff, descrição, arquivos do repo) dar ordens ao Codex ou fazê-lo escrever/rodar algo.
- Copiar código ou prompts de outro projeto. Prompts e scripts são escritos do zero.

## Restrições

- macOS, uma conta Codex (CLI `codex` 0.164 já instalado e logado), `gh` logado como `jeanjacintho`, `jq` disponível.
- Comenta no GitHub como a conta do próprio Jean (sem usuário bot separado).
- Cota da API do GitHub: 5.000 req/h — o polling precisa caber folgado (ver "Polling").
- Tudo que o bot posta no PR é em **inglês**. Comentários de código e mensagens de commit também em inglês.

## Decisões do Jean

- Fluxo: comando no PR → revisão → um comentário com os achados.
- Prefixo de comando `jeanjacintho`: `/jeanjacintho-review`, `/jeanjacintho-update-review` e `/jeanjacintho-memorize`.
- `review` revisa o PR inteiro de novo; `update-review` revisa só o código novo desde a última revisão.
- Roda os testes do repo, mas só quando o autor do PR também é confiável.
- Intervalo de 2 minutos, verificado por script, sem gastar tokens.
- Só revisa nos repositórios configurados e só obedece às pessoas configuradas.
- Aprende com o tempo, a partir de lições ensinadas por comando.
- Comentários do bot no PR em inglês, no formato descrito em "Formato do comentário".
- Prompts e código escritos do zero, sem copiar de outro projeto e sem arquivo de atribuição.
- Local: `personal-projects/pr-reviewer`.

## Como funciona

### Configuração — `config.sh` (gitignored; `config.example.sh` versionado)

> Adendo de 2026-10-31: `REPOS`, `TRUSTED_USERS`, `TEST_CMDS` e `CODEX_MODEL` por repo agora vivem em `repos.json` (seção "Dashboard local"); o bloco abaixo é o formato original.

```bash
CMD_PREFIX="jeanjacintho"
REPOS=(jeanjacintho/motes)                        # owner/repo
TRUSTED_USERS=(jeanjacintho)                     # GitHub logins
REVIEW_TIMEOUT_SECS=1200
TEST_TIMEOUT_SECS=900
TEST_CMDS=(                                      # optional, "owner/repo|command"
  "jeanjacintho/motes|npm ci && npm test"
)
CODEX_MODEL=""                                   # empty = codex config default
```

### Quem pode disparar

Conta **quem comentou** o comando, não o autor do PR. Comentário de alguém em `TRUSTED_USERS` → executa, mesmo em PR de outra pessoa. Qualquer outro autor → ignorado em silêncio (só log local).

### Gramática do comando

Só **comentários de conversa do PR** (os de nível superior, os mesmos do `gh pr comment`) contam. Texto de review submetido e comentários inline em linhas de código não disparam nada na v1.

O comando precisa ser a **primeira linha não vazia** do comentário (para que citar o comando num exemplo não dispare): `^\s*/jeanjacintho-(review|update-review|memorize)(\s|$)`, sem diferenciar maiúsculas.

- `review` / `update-review`: o resto do comentário (se houver) é um foco opcional ("focus on the migration path") que entra no prompt como contexto.
- `memorize`: a lição é o resto da primeira linha + as linhas seguintes.

### Polling (`poll.sh`, launchd a cada 120 s)

1. Lock (`mkdir state/poll.lock`) — se outro ciclo ainda está rodando (ex.: revisão longa), sai. Lock com mais de `REVIEW_TIMEOUT_SECS` + margem é considerado órfão e removido.
2. Para cada repo: **uma** consulta GraphQL que traz os PRs abertos com os últimos ~30 comentários de cada (id, autor, corpo, data) e o `headRefOid`. Com poucos repos isso fica em ~1 req por repo por ciclo → ~30 req/h por repo.
3. Filtra só em `jq`: comentários com comando válido, autor confiável, criados depois da marca d'água, cujo id não está em `state/seen.json`.
4. Para cada um, em ordem cronológica: marca como visto **antes** de agir (garante no máximo uma execução por comentário, mesmo se der erro no meio) e chama `review.sh` (com o modo `full` ou `update`) ou `memorize.sh`.

**Marca d'água / primeira execução:** `state/started-at` guarda o instante da instalação; comentários anteriores nunca disparam.

### Os dois modos de revisão

| | `/jeanjacintho-review` (`full`) | `/jeanjacintho-update-review` (`update`) |
|---|---|---|
| Diff revisado | PR inteiro contra a base | só `último SHA revisado..head` |
| Mesmo SHA já revisado | revisa de novo (pedido explícito) | responde "No new commits since last review." e para (zero Codex) |
| Revisão anterior | entra como contexto, para não repetir em outra forma o que já foi respondido | entra como contexto; o bot diz quais achados antigos foram resolvidos e quais continuam (com `arquivo:linha` atual) |
| Sem revisão anterior ou SHA antigo sumiu (force-push) | — | cai para `full` e avisa na primeira linha do comentário |

No `update`, o diff completo do PR também vai como contexto de leitura (para checar se um achado antigo foi mesmo resolvido), mas só o diff incremental é o escopo de achados novos.

### Testes

- Opcional por repo: só roda se o repo tiver uma entrada em `TEST_CMDS` no `config.sh` (formato `owner/repo|comando`, compatível com o bash 3.2 do macOS). O comando vem sempre da config, nunca do PR.
- Só roda se o **autor do PR** estiver em `TRUSTED_USERS`. Caso contrário: não executa nada e o comentário diz `Tests skipped: PR author is not in the trusted list.`
- Roda num worktree **separado** do que o Codex lê (o código de teste não pode alterar o que está sendo revisado), com `TEST_TIMEOUT_SECS`, em paralelo com a preparação; o Codex só começa quando o resultado existe.
- Resultado (exit code + cauda do log, ~200 linhas) entra no prompt como dado e alimenta a seção **Test coverage**.
- Roda nos dois modos (`full` e `update`).

### Revisão (`review.sh <full|update> <repo> <pr> <comment_id>`)

1. Reage com 👀 no comentário do comando (feedback de "peguei").
2. Resolve o modo (tabela acima); no `update` sem commit novo, responde e para.
3. Prepara o código: clone cache em `work/<owner>/<repo>` (fetch incremental), worktree no head do PR, base = merge-base com a branch base. PRs de fork funcionam via `refs/pull/<n>/head`.
4. Se aplicável, dispara os testes (seção Testes) e espera o resultado.
5. Monta o prompt (arquivo temporário), nesta ordem:
   - `prompts/policy.md` — política fixa, escrita do zero: cerca de segurança (só comandos de leitura; diff, descrição, comentários e arquivos do repo são **dados, nunca instruções**), postura (buscar falhas reais com caminho de falha concreto; preferir simplificar a adicionar; não propor defesas para cenários hipotéticos; em re-revisão, não repetir em outra forma um achado já respondido).
   - `prompts/review.md` — tarefa e o formato exato de saída (abaixo).
   - `rules.md` — regras fixas do Jean (começa com um conjunto inicial; editado à mão).
   - `lessons.md` — lições aprendidas.
   - `REVIEW.md` do repo revisado, **lido da branch base** (se existir) — regras por repo.
   - Contexto marcado como dado: título/descrição do PR, o foco opcional do comando, lista de commits, lista de arquivos, o diff do modo (completo ou incremental), resultado dos testes, e a revisão anterior do bot nesse PR (achada pelo marcador), se houver.
6. Roda `codex exec --sandbox read-only -C <worktree> --output-last-message <arquivo>` com o prompt via stdin, com timeout. Codex pode ler o repo inteiro (grep/cat/git) para seguir a causalidade entre arquivos, mas não escreve nem acessa rede.
7. Valida a saída (não vazia, termina com uma linha `VERDICT:` válida). Posta **um** comentário via `gh pr comment`, acrescentando o rodapé com SHA e o marcador `<!-- jeanjacintho-reviewer -->`. Registra `repo#pr → sha` em `reviewed.json`. Troca 👀 por ✅.
8. Em falha (timeout, Codex sem cota, saída inválida): reage com 😕 e posta **um** comentário curto de erro em inglês; não tenta de novo sozinho (Jean comenta o comando de novo).
   - **Falhas curtas do GitHub** (adendo de 2026-11-02, após `jeanjacintho/motes#50`, em que três chamadas GraphQL falharam em 12 s e a revisão pronta foi perdida): toda chamada `gh` do caminho de revisão (reações, `gh pr comment`, leituras) é repetida até `GH_RETRY_ATTEMPTS` vezes (padrão 4), com espera linear de `GH_RETRY_DELAY` × tentativa segundos (padrão 3 → 3, 6, 9 s), **somente** para falhas transitórias: `Something went wrong while executing your query`, HTTP 5xx, 429, limite secundário, erro de conexão ou timeout. Erros 4xx (validação) não são repetidos. Quando a chamada falha de vez, a primeira linha do erro do `gh` (com o request id) vai para `poll.log`.
   - Garantia de um comentário: antes de repetir um `gh pr comment`, o bot confere se um comentário idêntico dele já existe no PR (últimos 5 min); se existe, a postagem anterior chegou ao GitHub e não posta de novo. O texto da revisão **não** é guardado entre polls; se todas as tentativas falham, vale a regra acima (Jean comenta o comando de novo).

### Formato do comentário (inglês)

Estrutura fixa, pensada para ser lida por humanos e também por agentes de código (Codex, Claude Code, Cursor) que vão corrigir o PR:

```
_It appears @<author> is working towards <user-facing outcome> — reviewing against that goal._

(update mode only) **Since last review (abc1234 → def5678)** — resolved: #2, #4 · still open: #1 (now `path:line`).

**Overview** — 2–3 sentences on what the PR does.

**Strengths** — non-obvious things done right. (omitted if none)

**Findings**

1. [blocking] [bug] <declarative outcome: input → where it breaks → observable result>. Files: `path:line`, …. Edit: <concrete change>.
2. [medium] [simplification] <…>. Files: `path:line`. Edit: <…>.
3. [open] [contract] **Q: <question in 5–10 words>** — <full question>. If yes, <edit>. If no, <cost of leaving it>.
4. [low] [tests] <…>.

**Security** — one sentence on the most severe security-relevant finding, or `None`.

**Test coverage** — one sentence: test result (passed / failed / skipped and why / not configured) plus the most severe `[tests]` finding, if any.

**For AI authors** — Findings above are load-bearing. Answer each `[open]` item directly or revisit the design; do not absorb a finding by adding defensive code. Prefer deletions over new guards.

VERDICT: APPROVE | APPROVE — pending: <low items> | COMMENT

---

**Full review** at `def5678` · comment `/jeanjacintho-update-review` after your next push · `/jeanjacintho-memorize <lesson>` to teach me

🤖 This review was written by @jeanjacintho's PR review bot, not typed by hand.
<!-- jeanjacintho-reviewer -->
```

Regras do formato:

- **Rodapé** (adendo de 2026-10-31, pedido do Jean): no mesmo tamanho do texto (sem `<sub>`), separado por uma linha, e assinado pelo bot com o login da conta que posta (`gh api user`); se o login não puder ser lido, diz "a PR review bot". Revisões antigas com o rodapé `<sub>` continuam reconhecidas como revisão anterior.
- **Primeira linha:** intenção inferida do PR, em itálico — o objetivo do ponto de vista do usuário final, não a lista de mudanças.
- **Gravidades:** `blocking` > `medium` > `low` > `nit`; `[open]` é uma pergunta cuja resposta decide se é problema. Ordenados por gravidade; dentro da mesma faixa, `bug` antes de `contract`/`shape` antes de `simplification`.
- **Classes:** `bug`, `security`, `data-integrity`, `contract` (quebra de contrato com quem chama/consome), `simplification` (duplicação, código morto, complexidade desnecessária), `tests`.
- `blocking` exige caminho de falha concreto citando `arquivo:linha`; sem isso vira `[open]`.
- Achados de simplificação (duplicação, código morto, excesso de defesa) são valorizados, não rebaixados a nit.
- Alvo de 300–500 palavras; até ~1000 só se o conteúdo justificar.
- **Veredito:** `APPROVE` sem achados ou só `low`/`nit`; `APPROVE — pending: …` aprovável com notas; `COMMENT` se houver qualquer `medium`, `blocking` ou `[open]` que importe.
- Sem achados: Findings diz `None — no load-bearing issues found.` e veredito `APPROVE`.

### Aprendizado (`memorize.sh <repo> <pr> <comment_id>`)

1. Extrai a lição do comentário. Lição vazia → responde em inglês pedindo o texto.
2. Chama Codex (sem acesso ao repo, só texto) com: `lessons.md` atual + a lição nova + a última revisão do bot nesse PR (contexto do que motivou a lição). Pede de volta o `lessons.md` inteiro, já com a lição reescrita como regra curta e acionável em inglês, mesclada sem duplicar, limitada a **40 regras**, cada uma com a origem (`repo#pr`).
3. Valida a saída (não vazia, formato de lista, ≤ 40 itens) antes de sobrescrever; guarda backup em `state/lessons.bak`.
4. Responde no PR: 👍 no comentário + "Learned: <resulting rule>".

As lições são **globais** (valem para todos os repos). Regras específicas de um repo vão no `REVIEW.md` daquele repo.

### Instalação / operação

- `install.sh`: cria `config.sh` a partir do exemplo se não existir, grava `state/started-at`, gera e carrega o plist do launchd (`~/Library/LaunchAgents/com.jeanjacintho.pr-reviewer.plist`, `StartInterval 120`, PATH com `/opt/homebrew/bin`). Idempotente.
- `uninstall.sh`: descarrega o launchd.
- Log em `state/poll.log` (uma linha por evento, com rotação simples por tamanho).
- `state/` e `work/` gitignored.

## Dashboard local (adendo de 2026-10-31)

Uma página web **só no Mac do Jean** para configurar o bot sem editar arquivos à mão.

### Configuração por repositório — `repos.json` (gitignored; `repos.example.json` versionado)

```json
{"repos":[{"repo":"jeanjacintho/motes","enabled":true,"trusted_users":["jeanjacintho","alice"],"model":"","test_cmd":"npm ci && npm test"}]}
```

- Substitui `REPOS`, `TRUSTED_USERS`, `TEST_CMDS` e `CODEX_MODEL` do `config.sh`; este fica só com `CMD_PREFIX` e os timeouts. `CODEX_MODEL` global continua como padrão quando `model` do repo está vazio.
- **Confiança é por repositório.** `trusted_users` de um repo decide (a) quem pode disparar comandos nele e (b) se o código do PR roda `test_cmd`: só quando o **autor do PR** está na mesma lista. Confiar em alguém é, portanto, aceitar que o código dessa pessoa rode `test_cmd` na máquina.
- `enabled: false` mantém o repo na lista sem consultá-lo.
- O `poll.sh` relê o arquivo a cada ciclo; mudanças valem no ciclo seguinte, sem reiniciar. `repos.json` é lido com `jq`; o dashboard nunca gera código shell.
- Escrita atômica (arquivo temporário + `mv`), e entradas validadas na borda: `repo` casa `owner/name`, login casa um login do GitHub, `model` casa `[A-Za-z0-9._:-]{0,64}`. `test_cmd` é texto livre e é executado como hoje no `config.sh` (decisão de quem configura).

### Servidor

- Node, **sem dependências** (`http` embutido, front em HTML/JS puro), em `dashboard/`. Escuta só em `127.0.0.1` (porta `DASHBOARD_PORT`, padrão 4777).
- Sem login. Como defesa contra páginas abertas no navegador, rejeita requisições cujo `Host` ou `Origin` não sejam o do próprio dashboard.
- Mostra e edita `repos.json`; mostra leitura de `reviewed.json`, cauda de `poll.log` e o estado do launchd. Não dispara revisões nem altera `seen.json`.
- Roda como segundo serviço launchd (`com.jeanjacintho.pr-reviewer-dashboard`), a partir da instalação fora de Documents.
- Se o dashboard cair, o bot continua: o Bash só lê `repos.json`.

## Motor de revisão por repositório (adendo de 2026-10-31, aprovado pelo Jean)

Substitui "uma chamada Codex por revisão" por "uma chamada ao motor escolhido para o repositório". Continua **uma** chamada por revisão, sem pipeline, na profundidade `quick`. A `deep` está no adendo "Revisão profunda em etapas".

- `repos.json` ganha `engine` (`codex` ou `claude`; ausente = `codex`) e `effort` (vazio = padrão da CLI). `model` vazio continua sendo o padrão da CLI.
- **Codex:** como antes, mais `-c model_reasoning_effort="<effort>"` quando `effort` não está vazio. O nível `ultra` (delegação automática) não é oferecido, porque multi-agente fica desligado por segurança.
- **Claude Code:** `claude -p --restricted --tools "Read,Grep,Glob" --permission-mode dontAsk --strict-mcp-config --disable-slash-commands --no-session-persistence --output-format text`, prompt via stdin, rodando dentro do worktree, com `--model`/`--effort` quando definidos. `--restricted` tira shell, código e rede, ignora configurações de usuário/projeto e confina a leitura ao diretório. No `memorize`, sem ferramentas (`--tools ""`). Verificado à mão em 2026-10-31: não cria arquivo, não roda shell, não lê fora da pasta, não acessa a rede.
- Motor desconhecido ou não instalado: a revisão falha com o comentário de erro de sempre; nunca cai para outro motor sem avisar.
- O dashboard lista só as CLIs instaladas (no PATH do serviço). Modelos e níveis do Codex vêm de `~/.codex/models_cache.json` (só `visibility: "list"`), e o padrão de `~/.codex/config.toml`. Do Claude Code: apelidos `fable`, `opus`, `sonnet` e níveis `low`…`max`; aceita também um nome de modelo digitado.
- Revisões com Claude Code gastam o plano do Claude do Jean; Codex continua o padrão.
- Activity também por repositório: a página de cada repo mostra as revisões e as linhas de log daquele repo; a página geral tem filtro por repo.

## Revisão profunda em etapas (adendo de 2026-11-01, pedido do Jean)

**Problema.** A revisão de uma chamada só deixa passar bugs reais que o Jean achou depois. Um prompt único divide a atenção entre todos os ângulos, nada obriga o modelo a seguir o código alterado para fora do diff, e nenhum achado é conferido antes de ir para o comentário.

**Ideia.** Cada repositório escolhe a profundidade: `quick` (a revisão de uma chamada de hoje) ou `deep`. Na `deep`, a revisão vira um pipeline de etapas pequenas. Cada etapa tem um único trabalho e entrega para a próxima um texto num formato fixo, que o Bash valida.

```
intenção ──┬─ ângulo 1 → verificação ─┐
           ├─ ângulo 2 → verificação ─┤
           ├─ …                       ├─→ redação → comentário (formato de sempre)
           └─ ângulo 5 → verificação ─┘
```

1. **Intenção** (1 chamada) — deduz, em uma ou duas frases, o resultado que o PR quer entregar ao usuário final. Roda enquanto os testes rodam. Se falhar, as outras etapas seguem sem ela.
2. **Ângulos** (1 chamada cada, em paralelo depois dos testes) — cada um procura problemas de um só tipo, lendo o repositório inteiro e não só o diff:
   - `correctness` — segue quem chama e quem consome cada símbolo alterado, inclusive arquivos fora do diff (listas de build, entrypoints, config, migrations);
   - `security` — segurança e integridade de dados;
   - `contracts` — contratos com quem chama, uso de APIs externas e fakes ou testes que concordam com o bug em vez de com a API real;
   - `tests` — lê o resultado dos testes e procura caminhos de falha sem cobertura;
   - `simplification` — duplicação, código morto, complexidade e defesas desnecessárias.

   A saída não é uma revisão: são **hipóteses** (no máximo 6 por ângulo) num bloco fixo com id, gravidade, classe, afirmação de uma frase, `arquivo:linha` e o caminho de falha. Também pode ser exatamente `NO HYPOTHESES`.
3. **Verificação** (1 chamada por ângulo que tenha hipóteses, logo depois dele) — tenta provar ou derrubar cada hipótese lendo o código, e responde `yes`, `no` ou `unknown` com uma evidência em `arquivo:linha`. Nunca cria hipóteses novas. O Bash descarta as `no`. Uma `unknown` só segue se for `blocking` ou `medium`, e então só pode virar item `[open]`.
4. **Redação** (1 chamada) — recebe as hipóteses confirmadas de todos os ângulos, junta duplicadas, ordena e escreve o comentário no **mesmo formato** de sempre, com a mesma validação, o mesmo rodapé e o mesmo `update-review`. Não inventa achado que não veio das etapas anteriores, mas lê o código para escrever a correção concreta.

**Regras.**

- Todas as etapas usam o motor, o modelo e o effort do repositório, as mesmas regras de leitura (`policy.md`), `rules.md`, `lessons.md` e o `REVIEW.md` da base. Cada etapa só recebe o resultado da anterior pelo prompt, como dado. Nenhuma etapa escreve arquivos no worktree.
- No `update`, os ângulos só levantam hipóteses no diff incremental, com o diff completo como contexto. A redação monta o "Since last review" a partir da revisão anterior.
- **Paralelismo:** no máximo `DEEP_PARALLEL` chamadas ao mesmo tempo (padrão 3). Cada etapa tem o seu timeout, `STAGE_TIMEOUT_SECS` (padrão 600). O lock do poll passa a considerar o pior caso da revisão profunda.
- **Falha parcial:** um ângulo, ou a verificação dele, que falhe, estoure o tempo ou devolva formato inválido fica de fora. O comentário começa com `Partial review: the <angles> check(s) did not finish.` Se todos os ângulos falharem, ou se a redação falhar, a revisão falha com o comentário de erro de sempre.
- Cada etapa registra no `poll.log` quanto tempo levou, e o Activity do dashboard mostra isso.
- **Custo:** até 12 chamadas por revisão em vez de 1, e alguns minutos a mais. Por isso a profundidade é escolhida por repositório.
- **`repos.json`** ganha `depth` (`quick` ou `deep`). Se o campo faltar, vale `quick`, então as entradas antigas continuam como estão. O dashboard escolhe a profundidade por repositório, e um repositório novo adicionado por ele começa em `deep`.
- **`tools/try-review <repo> <pr> [quick|deep]`** roda a revisão contra o head do PR e imprime o comentário sem escrever nada no GitHub (sem reação, sem comentário e sem estado). Serve para comparar `quick` e `deep` nos PRs em que o Jean já sabe qual bug passou.

## Decisões minhas (o Jean pode mudar)

- **Bash + `gh` + `jq` + `codex exec`**. Sem Node/Python no bot. Exceção única: o dashboard local usa Node sem dependências.
- Configuração num `config.sh` sourceado, no próprio repo.
- Lições globais, não por repo; teto de 40.
- Reações (👀/✅/😕) como sinal de status.
- Texto extra após o comando de revisão vira foco da revisão.
- Revisões rodam em série dentro do ciclo do poll (lock evita sobreposição). Só as etapas de uma mesma revisão profunda rodam em paralelo.
- `/jeanjacintho-memorize` aceito em qualquer PR dos repos configurados, não só depois de uma revisão do bot.
- Sem suporte a org inteira na v1; só `owner/repo` explícito.
- Só comentários de conversa do PR disparam comandos (nada de review body nem inline).
- Qualquer repo que o `gh` do Jean acesse pode entrar em `REPOS`, inclusive de orgs. Se pode ou não mandar código de uma org pela conta pessoal do Codex é decisão de quem configura, não do código. O exemplo usa só repo pessoal.
- `update-review` cai para revisão completa quando não há base anterior utilizável, em vez de recusar.
- Testes só com entrada em `TEST_CMDS` por repo; sem isso a seção diz `not configured`.
- Cauda de ~200 linhas do log de teste no prompt.

## Deixado para quem construir

- Texto exato de `prompts/policy.md`, `prompts/review.md` e o `rules.md` inicial.
- Formato interno dos arquivos de estado.
- Tratamento de diffs muito grandes (truncar e avisar no comentário é aceitável).
- Estratégia de testes: no mínimo testes de script (ex.: `bats` ou um `test.sh` com fixtures JSON) para a gramática do comando, o filtro de confiança/marca d'água/visto, a escolha do modo (`update` sem commit novo / fallback para `full`), o portão de autor confiável dos testes e a validação da linha `VERDICT:` — as partes que, se erradas, gastam tokens ou geram spam.
- Detalhes de flags do `codex exec` e de timeout no macOS (confirmar contra a versão instalada).
