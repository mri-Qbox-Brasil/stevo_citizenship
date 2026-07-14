# mri_Qwhitelist — Manual

Whitelist por exame de cidadania: o jogador entra isolado em um routing bucket próprio e só é liberado para o mundo depois de acertar o percentual mínimo de um questionário de múltipla escolha.

---

## Sumário

1. [Dependências](#dependências)
2. [Instalação](#instalação)
3. [Configuração](#configuração)
4. [Fluxo do jogador](#fluxo-do-jogador)
5. [Perguntas do exame](#perguntas-do-exame)
6. [Perguntas pré-exame e webhook do Discord](#perguntas-pré-exame-e-webhook-do-discord)
7. [Menu de gerenciamento](#menu-de-gerenciamento)
8. [Banco de dados](#banco-de-dados)
9. [Integrações](#integrações)
10. [Entrypoints para outros recursos](#entrypoints-para-outros-recursos)
11. [Estrutura de arquivos](#estrutura-de-arquivos)

---

## Dependências

| Recurso | Obrigatório | Observação |
|---|---|---|
| `qbx_core` | Sim | `GetPlayer`, `GetPlayerByCitizenId`, `SetPlayerBucket` |
| `ox_lib` | Sim | Diálogos (`inputDialog`, `alertDialog`), context menus, zonas, callbacks e notificações |
| `oxmysql` | Sim | Persistência da whitelist e da configuração |
| `ox_target` | Não | Apenas se `Config.Interaction.Type = "target"` |
| `mri_Qbox` | Não | Registra o menu de gerenciamento e fornece `GetRayCoords` para capturar coordenadas |

O `fxmanifest.lua` também exige `/server:4500` como versão mínima do FXServer.

---

## Instalação

1. Copie a pasta `mri_Qwhitelist` para `resources/`.
2. Copie `server/config.sample.lua` para `server/config.lua` e ajuste as opções. **Renomeie ou remova o `config.sample.lua` depois de copiar** — o `fxmanifest` carrega `server/*.lua`, então os dois arquivos entram no bundle e a tabela `Config` do sample pode sobrescrever a sua.
3. Adicione ao `server.cfg`:
   ```
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core
   ensure mri_Qwhitelist
   ```
4. As tabelas MySQL são criadas automaticamente no primeiro start — não há `.sql` para importar.

---

## Configuração

Arquivo: `server/config.lua` (modelo em `server/config.sample.lua`).

Importante: depois do primeiro start, o recurso passa a ler a configuração da tabela `mri_qwhitelistcfg`. Se essa tabela tiver um registro, ele **sobrescreve** o arquivo Lua. Qualquer alteração feita pelo menu de gerenciamento é gravada lá.

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `Config.Enabled` | bool | Sim | `false` desativa a whitelist — `CheckCitizenship` retorna `true` para todos |
| `Config.Debug` | bool | Não | Desenha a `citizenZone` no mundo (passado como `debug` para a zona do ox_lib) |
| `Config.Percent` | number | Sim | Percentual mínimo de acertos para liberar o jogador |
| `Config.TimerTimeout` | number (ms) | Não | Intervalo do loop que verifica se o jogador saiu da zona. Padrão interno: `5000` |
| `Config.loadNotify` | string | Não | Notificação exibida ao carregar sem cidadania |
| `Config.escapeNotify` | string | Não | Notificação exibida ao tentar sair da zona do exame |
| `Config.StartExamLabel` | string | Não | Rótulo genérico do início do exame |
| `Config.StartExamHeader` | string | Não | Título do diálogo de confirmação antes do exame |
| `Config.StartExamContent` | string | Não | Texto do diálogo de confirmação antes do exame |
| `Config.SuccessHeader` | string | Não | Título do diálogo de aprovação |
| `Config.SuccessContent` | string | Não | Texto do diálogo de aprovação |
| `Config.FailedHeader` | string | Não | Título do diálogo de reprovação |
| `Config.FailedContent` | string | Não | Texto do diálogo de reprovação |
| `Config.PassingScore` | number | Não | Campo presente no config de exemplo. O código usa `Config.Percent`, não este valor |
| `Config.NotifyType` | string | Não | Campo presente no config de exemplo. O código sempre usa `lib.notify` |
| `Config.Interaction.Type` | string | Sim | `"target"`, `"marker"` ou `"3dtext"` — define como o jogador inicia o exame |
| `Config.Interaction.MarkerLabel` | string | Não | Texto exibido no marker / texto 3D |
| `Config.Interaction.MarkerType` | number | Não | ID do marker do GTA V |
| `Config.Interaction.MarkerColor` | `{r,g,b}` | Não | Cor do marker |
| `Config.Interaction.MarkerSize` | `{x,y,z}` | Não | Escala do marker |
| `Config.Interaction.MarkerOnFloor` | bool | Não | Fixa o marker no chão |
| `Config.Interaction.TargetIcon` | string | Não | Ícone FontAwesome da opção do ox_target |
| `Config.Interaction.TargetLabel` | string | Não | Rótulo da opção do ox_target |
| `Config.Interaction.TargetRadius` | vector3 | Não | Tamanho da box zone do ox_target |
| `Config.Interaction.TargetDistance` | number | Não | Distância máxima de interação |
| `Config.SpawnCoords` | vec4 | Sim | Onde o jogador sem cidadania nasce e para onde volta se tentar fugir |
| `Config.ExamCoords` | vec3 | Sim | Ponto da interação que inicia o exame |
| `Config.CompletionCoords` | vec4 | Sim | Para onde o jogador é teleportado após ser aprovado |
| `Config.citizenZone.coords` | vec3 | Sim | Centro da zona de confinamento |
| `Config.citizenZone.size` | vec3 | Sim | Dimensões da box zone |
| `Config.citizenZone.rotation` | number | Sim | Rotação da box zone |
| `Config.Questions` | tabela | Sim | Lista de perguntas — ver seção abaixo |
| `Config.PreExamQuestions` | tabela | Não | Formulário opcional antes do exame — ver seção abaixo |

---

## Fluxo do jogador

1. No `QBCore:Client:OnPlayerLoaded`, o client pede a configuração ao servidor e chama `mri_Qwhitelist:Server:CheckCitizenship`.
2. Se o jogador **não** está na whitelist, o servidor o move para o routing bucket `1000 + source` (isolado dos demais) e retorna `false`.
3. O client teleporta o jogador para `Config.SpawnCoords`, cria a interação de exame (target, marker ou texto 3D) e a box zone `citizenZone`.
4. Um loop a cada `Config.TimerTimeout` ms verifica se o jogador está dentro da zona. Se sair, ele é teleportado de volta ao spawn com a notificação `escapeNotify`.
5. Ao interagir, o jogador responde as perguntas (opcionalmente precedidas do formulário pré-exame). As perguntas e as alternativas são embaralhadas a cada tentativa.
6. Se o percentual de acertos atingir `Config.Percent`, o servidor grava o `citizenid` na tabela `mri_qwhitelist`, move o jogador para o bucket `0` e o client o teleporta para `Config.CompletionCoords`, removendo a zona.
7. Se reprovar, o diálogo de falha é exibido e o jogador pode tentar de novo pela mesma interação.

---

## Perguntas do exame

Cada entrada de `Config.Questions` é uma pergunta com uma lista de alternativas. A alternativa correta tem `value = true`.

```lua
Config.Questions = {
    {
        question = "O que é Meta Gaming?",
        options = {
            { label = "Uso de informação que o personagem não aprendeu no RP.", value = true },
            { label = "Alternativa errada.", value = false },
            { label = "Eu não sei.", value = false }
        }
    },
}
```

A ordem das perguntas e das alternativas é embaralhada em runtime. Nada impede marcar mais de uma alternativa como correta, mas o jogador só escolhe uma.

---

## Perguntas pré-exame e webhook do Discord

Quando `Config.PreExamQuestions.Enabled = true`, um `lib.inputDialog` é exibido antes do exame. As respostas são enviadas ao servidor, que as encaminha para o webhook configurado como um embed do Discord com o nome, o `citizenid` e o nome do personagem.

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `Enabled` | bool | Sim | Liga/desliga o formulário |
| `FormatPhone` | bool | Não | Converte campos com `kind = "phone"` em link `https://wa.me/55<numero>` no embed |
| `WebHook` | string | Sim (se `Enabled`) | URL do webhook do Discord. Sem ela, o envio é abortado com aviso no console |
| `label` | string | Não | Título do diálogo |
| `information` | tabela | Sim | Campos do `lib.inputDialog`. Cada campo aceita `type`, `label`, `placeholder`, `required`, `min`, `max` e `kind` |

O `kind` é usado para formatar o valor no embed (por exemplo `kind = "phone"`) e não é uma validação do ox_lib.

---

## Menu de gerenciamento

O recurso não registra comandos de chat. O acesso ao gerenciamento é feito de duas formas:

- **Com `mri_Qbox` iniciado** — o menu "Gerenciar Whitelist" é adicionado automaticamente ao menu gerencial do `mri_Qbox` via `exports['mri_Qbox']:AddManageMenu`.
- **Sem `mri_Qbox`** — o client registra o callback `mri_Qwhitelist:Client:ManageWhitelistMenu`, que outro recurso pode disparar para abrir o menu.

O menu permite:

- Ativar/desativar a whitelist.
- Definir o local de spawn e o local do exame usando a mira (`exports.mri_Qbox:GetRayCoords`). A opção "Zona de Exame" existe mas está desabilitada no código.
- Ajustar o percentual de acertos.
- Criar, editar e remover perguntas e alternativas, e marcar qual alternativa é correta.
- Liberar ou revogar a whitelist de um jogador, informando o `citizenid` ou o `source`.

Toda saída do menu (`onExit`) grava a configuração atual na tabela `mri_qwhitelistcfg`.

---

## Banco de dados

Ambas as tabelas são criadas automaticamente no `onResourceStart` se não existirem.

### `mri_qwhitelist`

| Coluna | Tipo | Descrição |
|---|---|---|
| `id` | INT AUTO_INCREMENT | Chave primária |
| `citizen` | VARCHAR(50) UNIQUE | `citizenid` do personagem liberado |

### `mri_qwhitelistcfg`

| Coluna | Tipo | Descrição |
|---|---|---|
| `id` | INT AUTO_INCREMENT | Chave primária (o recurso sempre usa `id = 1`) |
| `config` | LONGTEXT | Tabela `Config` serializada em JSON |

Para forçar o recurso a voltar a usar o `server/config.lua`, apague a linha da tabela `mri_qwhitelistcfg`.

---

## Integrações

### mri_Qbox

Se o `mri_Qbox` estiver iniciado, o menu de gerenciamento é registrado no menu gerencial central e as opções de captura de coordenadas passam a usar `exports.mri_Qbox:GetRayCoords()`.

---

## Entrypoints para outros recursos

Todos os entrypoints são callbacks do `ox_lib`.

### Callbacks do servidor

```lua
-- Retorna a tabela Config atual
local config = lib.callback.await('mri_Qwhitelist:Server:GetConfig', false)

-- Salva a configuração (persiste em mri_qwhitelistcfg)
lib.callback.await('mri_Qwhitelist:Server:SaveConfig', false, config)

-- true se o jogador tem cidadania (ou se a whitelist está desativada).
-- Efeito colateral: move o jogador para o bucket isolado quando não tem.
local ok = lib.callback.await('mri_Qwhitelist:Server:CheckCitizenship', false)

-- Libera um jogador. `identifier` aceita citizenid (string) ou source (number).
-- Omitido, usa o próprio source.
lib.callback.await('mri_Qwhitelist:Server:AddCitizenship', false, identifier)

-- Revoga a whitelist e devolve o jogador ao bucket isolado.
lib.callback.await('mri_Qwhitelist:Server:RemoveCitizenship', false, identifier)

-- Envia um formulário pré-exame ao webhook configurado.
lib.callback.await('mri_Qwhitelist:Server:SendPreExamData', false, data)
```

### Callbacks do client

```lua
-- Marca o exame como concluído, remove a zona e teleporta para CompletionCoords
lib.callback.await('mri_Qwhitelist:Client:AddCitizenship', playerSource, false)

-- Recria a zona de confinamento e devolve o jogador ao spawn
lib.callback.await('mri_Qwhitelist:Client:RemoveCitizenship', playerSource, false)

-- Abre o menu de gerenciamento (registrado apenas quando mri_Qbox não está iniciado)
lib.callback.await('mri_Qwhitelist:Client:ManageWhitelistMenu', playerSource, false)
```

---

## Estrutura de arquivos

```
mri_Qwhitelist/
├── client/
│   ├── main.lua              — fluxo do exame, teleportes, zona de confinamento
│   └── creator.lua           — menus ox_lib de gerenciamento (perguntas, locais, liberar/revogar)
├── server/
│   ├── main.lua              — callbacks, MySQL, routing buckets, webhook do Discord
│   └── config.sample.lua     — configuração modelo (copiar para config.lua)
├── interactions/
│   ├── target.lua            — interação via ox_target
│   ├── marker.lua            — interação via marker 3D
│   ├── text.lua              — interação via texto 3D
│   └── zone.lua              — wrapper da box zone do ox_lib
└── fxmanifest.lua
```
