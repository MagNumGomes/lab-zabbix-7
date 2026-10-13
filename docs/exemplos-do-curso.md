# Exemplos práticos por tema do curso (M01–M05 + alertas)

Criados em 09/10/2026 via `create-noc-examples.ps1`, validados por
`verify-examples.ps1` (28 verificações, todas OK) e por um teste real de
alerta (`test-alert-live.ps1`: problema gerado, alerta **enviado** via webhook
e recuperação confirmada). Os scripts são reexecutáveis: rodar de novo não
duplica objetos.

```powershell
.\create-noc-examples.ps1   # cria/atualiza os exemplos
.\verify-examples.ps1        # valida os exemplos
.\test-alert-live.ps1        # prova de fogo do alerta (gera e limpa uma falha real)
```

Senha do novo usuário `lab.operator`: `credentials.local.json` (não versionado).

## Renomeação JLCP → NOC (09/10/2026)

Todos os objetos e arquivos usavam o prefixo `JLCP` e foram migrados para
`NOC`. Renomeados:
hostgroups `NOC/*`, grupo de templates, template `NOC Linux practice` (com
reescrita e validação das expressões das triggers), value map, macro
`{$NOC.ERRORS.MAX}`, triggers, itens (só nomes de exibição), grupos de
usuários, as três roles, método TOTP, nome de exibição dos usuários `lab.*`,
ação (nome + filtro), media type (nome + assuntos), manutenção, dashboard
(+ widget), serviço, SLA, tags `curso:noc` e `sendto` da mídia do operador.
Preservados de propósito: chaves dos itens (`lab.*`), usuários `lab.*`,
proxies e arquivos já implantados na VM (`noc-lab.conf` passa a valer em
reinstalações). Após a migração: `verify-examples.ps1` 28/28 OK e
`test-alert-live.ps1` com alerta entregue e recuperação confirmada.

## Mapa exemplo → aula

| Aula(s) | Exemplo criado | Onde ver no painel |
|---|---|---|
| M01 (pilares/disponibilidade) | Serviço `NOC Servico didatico` (tag `servico:lab-demo`) + SLA `NOC SLA exemplo` 99,9% semanal | Services > Services; Services > SLA |
| M04A08 (hostgroup) | Grupos `NOC/Linux`, `NOC/Windows`, `NOC/Databases` (já existiam) + grupo de usuários `NOC Operators` | Data collection > Host groups |
| M04A12–A15 (itens, value map) | Template `NOC Linux practice`: `lab.service.up`, `lab.service.errors`, `lab.key.allowed`, value map `NOC service state` (já existiam) | Data collection > Templates |
| M04A16–A18 (triggers, dependência) | Triggers `NOC: Service is down` (pai) e `NOC: Too many service errors` (filha), agora com tags `curso:noc` + `servico:lab-demo` | Mesmo template > Triggers |
| M04A19 (macros) | `{$NOC.ERRORS.MAX}=5` no template (já existia) | Mesmo template > Macros |
| M04A24–A25 (cópia, templates) | Template NOC serve de origem para praticar clone/vínculo (passo manual abaixo) | Data collection > Templates |
| M04A26–A28 (proxy) | `lab-proxy` (Docker) e `mint-proxy` (nativo no Mint) + hosts associados (já existiam) | Administration > Proxies |
| M04A29–A30 (Windows) | Host `windows-host` via MSI (já existia) | Monitoring > Hosts |
| M04A31–A33 (Agent 2, MySQL) | Host `mysql-lab` com conta `zbx_monitor` (já existia) | Monitoring > Latest data |
| M04A34 (AllowKey/DenyKey) | `lab.key.allowed` retorna 1; `lab.key.blocked` é recusada (já existia) | Idem + `practice-triggers.ps1` |
| M05A01, A03–A06 (permissões, usuários) | Grupo `NOC Operators` (leitura `NOC/Linux`) + usuário `lab.operator` (role Operator, com mídia de email e webhook) | Users > Users / User groups |
| M05A07 (role customizada) | `NOC NOC read only` (já existia) + **`NOC Operator`** (User: reconhece/fecha/suprime problemas, API com `event.acknowledge`) + **`NOC Maintenance admin`** (Admin: foco em manutenção, sem gerir trigger actions/usuários) | Users > User roles |
| M05A08 (MFA) | Método `NOC TOTP` + `lab.mfa` com autenticador vinculado (já existia) | Users > Authentication |
| Alertas (prática extra) | Media type webhook **`NOC Registro em log (exemplo)`** (habilitado, script `return 'OK'`, com modelos de mensagem problema/recuperação/atualização) + ação **`NOC: avisa queda do servico didatico`** (habilitada, filtro grupo+nome+severidade, escalonamento em 5 min: passo 1 → Operators, passo 2 → Administrators, + notificação de recovery) | Alerts > Media types / Actions |
| Manutenção (prática extra) | **`NOC Exemplo - janela de manutencao`**: 2h todo domingo 05:00–07:00 (horário de Brasília), só `linux-lab`, com coleta. Criada no futuro (11/10/2026) para não suprimir nada agora | Data collection > Maintenance |
| Dashboard (prática extra) | **`NOC Visao do curso`**: widgets Problemas, Disponibilidade dos hosts e Info do servidor | Dashboards |

## Como testar cada exemplo (passo a passo)

1. **Roles e permissões** — entre numa janela privada como `lab.operator`:
   Monitoring liberado (Dashboard, Problems, Hosts, Latest data, Maps) e, num
   problema ativo, o botão *Acknowledge* funciona; como `lab.noc`, o mesmo botão
   é negado. Como `lab.mfa`, o login pede o código TOTP.
2. **Alerta de ponta a ponta** — rode `.\test-alert-live.ps1` ou, manualmente:
   `docker compose exec linux-lab touch /tmp/lab-service-down` → em ~1 min o
   problema `NOC: Service is down` abre e **Reports > Action log** mostra o envio
   via webhook `NOC Registro em log (exemplo)` com status *Sent*; remova o
   arquivo e a notificação de *recovery* aparece. O passo 2 do escalonamento
   (Administrators após 5 min) só dispara se o problema persistir.
3. **Manutenção** — Data collection > Maintenance: a janela aparece agendada para
   domingo; durante a janela, problemas de `linux-lab` seriam suprimidos.
4. **Dashboard** — Dashboards > `NOC Visao do curso`: problemas e
   disponibilidade visíveis; widgets editáveis pelo Operator? Não — edição de
   dashboards é negada às roles NOC (só Admin/Maintenance do curso não têm essa
   ação; o Admin padrão tem).
5. **Serviço/SLA** — Services > Services mostra `NOC Servico didatico`;
   Services > SLA acompanha os 99,9% semanais.
6. **Clone de template (M04A24–A25)** — Data collection > Templates > marque
   `NOC Linux practice` > *Clone*, salve com outro nome e vincule a um host de
   teste. Não vincule duas cópias com as mesmas chaves ao mesmo host.

## Limites conhecidos (não são falhas dos exemplos)

- O Email (HTML) do `lab.operator` falha com *Media type disabled*: não há relay
  SMTP no laboratório. O caminho real de entrega demonstrado é o webhook.
- A manutenção de exemplo é propositalmente futura; não espere supressão hoje.
- O SLA semanal precisa de histórico para percentuais estáveis.
- Em 09/10/2026 o teste estrito principal (`verify-lab.ps1`) ainda registra o
  atraso recorrente da coleta ativa direta do Mint; os exemplos acima não
  dependem desse caminho (o host de teste é `linux-lab` via proxy Docker).
