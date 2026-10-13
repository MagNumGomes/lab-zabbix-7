# Laboratório Zabbix 7.0 LTS — Apoio ao Curso NOC

Ambiente prático completo de monitoramento baseado em **Zabbix 7.0 LTS**, adaptado para arquitetura híbrida com **Docker (Compose v2) + Windows (Host local) + Linux Mint/Ubuntu (VM VirtualBox)**.

O laboratório implementa cenários reais de NOC: múltiplos métodos de coleta (agente passivo/ativo, Agent 2, MySQL), proxies Zabbix (Docker e nativo), controle estrito de acesso baseado em funções (RBAC), autenticação de dois fatores (MFA TOTP), esteira de alertas com escalonamento e webhooks, janelas de manutenção, dashboards executivos e gestão de SLA de serviços de TI.

---

## Sumário

- [Guias Complementares](#guias-complementares)
- [Arquitetura e Topologia](#arquitetura-e-topologia)
- [Portas e Credenciais de Acesso](#portas-e-credenciais-de-acesso)
- [Início Rápido (Quick Start)](#início-rápido-quick-start)
- [Inventário de Hosts e Coleta](#inventário-de-hosts-e-coleta)
- [Objetos e Práticas do Curso NOC](#objetos-e-práticas-do-curso-noc)
- [Automação e Scripts Disponíveis](#automação-e-scripts-disponíveis)
- [Testes e Validação do Laboratório](#testes-e-validação-do-laboratório)
- [Operação, Diagnóstico e Troubleshooting](#operação-diagnóstico-e-troubleshooting)

---

## Guias Complementares

Documentação técnica detalhada mantida na pasta [`docs/`](docs/):

- [Exemplos práticos por tema do curso](docs/exemplos-do-curso.md) — Roles, alertas, escalonamento, manutenção, dashboard e SLA.
- [Dependências por aula da grade NOC](docs/dependencias-curso-noc.md) — Relação dos módulos M00 a M05 e correspondência com a infraestrutura.
- [Auditoria dos requisitos e testes](docs/auditoria-requisitos.md) — Relatório de conformidade dos 7 containers, agentes, banco e segurança.
- [Guia do curso adaptado ao Linux Mint](docs/curso-mint.md) — Procedimentos passo a passo com comandos `.deb`/`apt` e configuração da VM.
- [VM Linux Mint no VirtualBox](docs/linux-mint-virtualbox.md) — Configuração de rede, integração com o host Windows e scripts de apoio.
- [Registro de estado e histórico de coleta](docs/estado-e-pendencias.md) — Histórico de verificação, itens corrigidos e observações de latência.

---

## Arquitetura e Topologia

O ambiente integra containers, serviços locais do Windows e máquinas virtuais em rede local:

```text
                                  +------------------------------------+
                                  |         Navegador Web Local        |
                                  +------------------------------------+
                                             |              |
                                    HTTP 8080|     HTTP 8081| (scripts/deb)
                                             v              v
+----------------------------- DOCKER COMPOSE (zabbix-net) ------------------------------+
|                                                                                       |
|  +--------------------+       +---------------------+        +---------------------+  |
|  |     zabbix-web     | ----> |    zabbix-server    | <----> |        mysql        |  |
|  | (Nginx/PHP-FPM 7.0)|       | (Server 7.0 / 10051)|        | (MySQL 8.0 utf8mb4) |  |
|  +--------------------+       +---------------------+        +---------------------+  |
|                                     |             ^                     ^             |
|                                     |             |                     |             |
|                  +------------------+             |               Agent 2 plugin      |
|                  |                                |                     |             |
|                  v                                |                     v             |
|        +--------------------+          +--------------------+  +--------------------+ |
|        |     lab-proxy      |          |   zabbix-agent2    |  |     mysql-lab      | |
|        | (SQLite3 / 10052)  |          | (Host Docker/Sock) |  | (Conta zbx_monitor)| |
|        +--------------------+          +--------------------+  +--------------------+ |
|                  |                                                                    |
|                  v                                                                    |
|        +--------------------+                                                         |
|        |     linux-lab      |                                                         |
|        | (Ubuntu clássico)  |                                                         |
|        +--------------------+                                                         |
+---------------------------------------------------------------------------------------+
            ^                                       ^
            | TCP 10052 (Proxy)                     | TCP 10051 (Server)
            |                                       |
+--------------------------+            +--------------------------+
|  VM Externa (Linux Mint) |            |   Host Local (Windows)   |
|  - zabbix-agent2 (ativo) |            |  - Zabbix Agent clássico |
|  - mint-proxy (nativo)   |            |    MSI 7.0.31 (Serviço)  |
|  - linux-mint-proxy      |            |  - Host: windows-host    |
+--------------------------+            +--------------------------+
```

### Componentes da Stack Docker (7 serviços)
1. **`mysql`**: MySQL 8.0 com `utf8mb4_bin` e volume persistente `mysql-data`.
2. **`zabbix-server`**: Zabbix Server 7.0 Alpine expondo a porta `10051`.
3. **`zabbix-web`**: Interface Web Zabbix 7.0 Nginx/PHP na porta `8080`.
4. **`zabbix-agent2`**: Agente 2 oficial com monitoramento do Docker daemon e `/host/root`.
5. **`zabbix-proxy`** (`lab-proxy`): Proxy SQLite3 na porta `10052` coletando o container `linux-lab`.
6. **`lab-files`**: Servidor Nginx estático na porta `8081` para entrega de scripts à VM Mint.
7. **`linux-lab`**: Container Ubuntu 22.04 com Agente Zabbix clássico simulando servidor monitorado.

---

## Portas e Credenciais de Acesso

### Interfaces e Portas

| Serviço | Destino / Porta | Descrição |
|---|---|---|
| **Frontend Zabbix** | `http://localhost:8080` | Interface gráfica web do Zabbix 7.0 |
| **Servidor de Scripts/Arquivos** | `http://localhost:8081` | Distribuição local de scripts para a VM Mint |
| **Zabbix Server Trapper** | `localhost:10051` | Porta padrão para Agentes Ativos e Zabbix Sender |
| **Docker Zabbix Proxy** | `localhost:10052` | Porta para encaminhamento de coleta via `lab-proxy` |
| **MySQL Database** | Interno (`mysql:3306`) | Acesso interno no container (usuário `zabbix`) |

### Credenciais Principais

| Conta / Contexto | Usuário | Senha | Função / Permissões |
|---|---|---|---|
| **Zabbix Super Admin** | `Admin` | `zabbix` | Administrador total da plataforma Zabbix |
| **Zabbix Banco MySQL** | `zabbix` | Definida em `.env` (`MYSQL_PASSWORD`) | Conexão de server e frontend ao MySQL |
| **MySQL Root** | `root` | Definida em `.env` (`MYSQL_ROOT_PASSWORD`) | Administração do container MySQL |
| **MySQL Monitor** | `zbx_monitor` | Armazenada em `credentials.local.json` | Leitura de métricas pelo Zabbix Agent 2 |
| **Contas do Curso** | `lab.user`, `lab.admin`, `lab.super`, `lab.noc`, `lab.operator`, `lab.mfa` | Geradas e salvas em `credentials.local.json` | Contas didáticas para prática de perfis e segurança |

> [!NOTE]
> As senhas randômicas das contas do laboratório e da conta SQL de monitoramento ficam salvas localmente no arquivo [`credentials.local.json`](credentials.local.json) (ignorado pelo Git por segurança).

---

## Início Rápido (Quick Start)

### Pré-requisitos
- **Windows 10/11** com **Docker Desktop** (Engine em modo Linux containers com integração WSL2).
- Mínimo de **4 GB de memória RAM** e **10 GB de disco** livres.
- **PowerShell 5.1+** executado com privilégios adequados.

### 1. Inicializar a stack Docker

No PowerShell, dentro da pasta do projeto:

```powershell
.\start.ps1
```

*(Ou via Bash: `bash start.sh`)*

### 2. Provisionar o ambiente completo do laboratório

Execute o provisionamento automatizado via Zabbix API:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\complete-lab.ps1
```

Esse script cria os proxies, hosts adicionais (`windows-host`, `mysql-lab`, `linux-mint`), grupos, templates, contas de usuário e ativa o MFA TOTP.

### 3. Provisionar os exemplos práticos NOC

Crie todos os cenários práticos (ações de alerta, webhook, escalonamento, roles customizadas, SLA, janela de manutenção e dashboards):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\create-noc-examples.ps1
```

### 4. Validar o ambiente

Execute os testes automatizados para verificar se tudo está saudável:

```powershell
# Testa infraestrutura, containers, agentes e permissões
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-lab.ps1

# Valida os 28 critérios dos exemplos didáticos NOC
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-examples.ps1

# Teste de fogo real do alerta via webhook e escalonamento
powershell -NoProfile -ExecutionPolicy Bypass -File .\test-alert-live.ps1
```

---

## Inventário de Hosts e Coleta

| Nome do Host no Zabbix | Tipo de Ambiente | Modo de Coleta | Rota de Rede | Templates Vinculados |
|---|---|---|---|---|
| `Zabbix server` | Container Docker | Agent 2 (Passivo 10050) | Conexão direta interna | `Linux by Zabbix agent`, `Zabbix server health`, `Docker by Zabbix agent 2` |
| `linux-lab` | Container Docker | Clássico (Passivo/Ativo) | Coletado via Proxy `lab-proxy` | `Linux by Zabbix agent`, `NOC Linux practice` |
| `windows-host` | Máquina Local Windows | Clássico 7.0.31 (Ativo) | Direto para `localhost:10051` | `Windows by Zabbix agent active` |
| `mysql-lab` | Container MySQL | Agent 2 (Passivo) | Agent 2 consulta MySQL | `MySQL by Zabbix agent 2` |
| `linux-mint` | VM VirtualBox | Agent 2 (Ativo) | Direto para IP LAN:10051 | `Linux by Zabbix agent active` |
| `linux-mint-proxy` | VM VirtualBox | Agent 2 (Passivo) | Via proxy nativo `mint-proxy` | `Linux by Zabbix agent` |

---

## Objetos e Práticas do Curso NOC

### 1. Template `NOC Linux practice`
- **Itens de serviço simulados:**
  - `lab.service.up`: Estado do serviço didático (0 = Down, 1 = Up).
  - `lab.service.errors`: Contador de erros da aplicação.
  - `lab.key.allowed`: Demonstração da diretiva `AllowKey` retornando `1`.
  - `vfs.file.size[/etc/hostname]`: Exemplo de verificação ativa.
- **Triggers com dependência:**
  - `NOC: Service is down` (Severidade High, pai).
  - `NOC: Too many service errors` (Severidade Warning, filha dependente do pai). Se o serviço cair, a trigger de erros é suprimida automaticamente.
- **Macros de usuário:** `{$NOC.ERRORS.MAX} = 5`.
- **Value Mapping:** Mapeamento `NOC service state` (0 ➔ Parado, 1 ➔ Em execução).

### 2. Controle de Acesso e Roles (RBAC)
- **`NOC read only`**: Permissão somente leitura no grupo `NOC/Linux`, sem acesso administrativo e bloqueio restritivo de métodos da API.
- **`NOC Operator`**: Permissão de monitoramento operacional (Dashboard, Problems, Latest Data, Maps) com direito de reconhecer (*Acknowledge*), comentar, suprimir e fechar problemas.
- **`NOC Maintenance admin`**: Perfil de administrador focado na gestão de períodos de manutenção, sem permissão para alterar usuários ou ações de alerta.

### 3. Autenticação e MFA (TOTP)
- Método `NOC TOTP` configurado no Zabbix 7.0.
- Grupo `NOC MFA` vinculado ao método TOTP.
- Usuário `lab.mfa` com fluxo de segundo fator ativo para aplicativos autenticadores (Google Authenticator, Microsoft Authenticator, etc.).

### 4. Ações de Alerta e Escalonamento
- **Ação:** `NOC: avisa queda do servico didatico`.
- **Filtro:** Dispara para problemas com tag `curso:noc` no grupo `NOC/Linux` com severidade `Warning` ou superior.
- **Escalonamento em 2 etapas:**
  - **Passo 1 (imediato):** Notifica os operadores (`NOC Operators`).
  - **Passo 2 (após 5 minutos sem resolução):** Notifica a gerência/administração (`NOC Administrators`).
  - **Notificação de Recuperação (Recovery):** Notifica automaticamente quando a falha é resolvida.
- **Media Type Webhook:** `NOC Registro em log (exemplo)` (código JavaScript auto-contido que confirma entrega real sem depender de servidor externo).

### 5. Janela de Manutenção
- **`NOC Exemplo - janela de manutencao`**: Janela programada para todo domingo (05:00–07:00 horário de Brasília) associada ao host `linux-lab`, com coleta contínua de dados mas supressão de alarmes.

### 6. Dashboards, Serviços de TI e SLA
- **Dashboard `NOC Visao do curso`**: Widgets de Problemas Ativos, Disponibilidade de Hosts e Informações de Sistema.
- **Serviço de TI `NOC Servico didatico`**: Mapeado na árvore de serviços pela tag `servico:lab-demo`.
- **SLA `NOC SLA exemplo`**: Cálculo semanal com meta estabelecida de **99,9%**.

---

## Automação e Scripts Disponíveis

Todos os scripts PowerShell foram desenvolvidos com foco em **idempotência** (podem ser executados repetidamente sem corromper o estado do laboratório):

| Script | Finalidade | Como Executar |
|---|---|---|
| [`start.ps1`](start.ps1) | Sobe todos os 7 containers com `--wait` | `.\start.ps1` |
| [`healthcheck.ps1`](healthcheck.ps1) | Valida respostas HTTP 200 (8080) e TCP (10051) | `.\healthcheck.ps1` |
| [`configure-hosts.ps1`](configure-hosts.ps1) | Cadastra hosts iniciais via Zabbix API | `.\configure-hosts.ps1` |
| [`install-windows-agent.ps1`](install-windows-agent.ps1) | Baixa e instala o MSI do Zabbix Agent no Windows | `powershell -ExecutionPolicy Bypass -File .\install-windows-agent.ps1` |
| [`complete-lab.ps1`](complete-lab.ps1) | Provisiona a infraestrutura completa do laboratório | `powershell -ExecutionPolicy Bypass -File .\complete-lab.ps1` |
| [`create-noc-examples.ps1`](create-noc-examples.ps1) | Cria templates, triggers, ações, SLA, roles e dashboards | `powershell -ExecutionPolicy Bypass -File .\create-noc-examples.ps1` |
| [`verify-lab.ps1`](verify-lab.ps1) | Auditoria técnica de containers, agentes, banco e RBAC | `powershell -ExecutionPolicy Bypass -File .\verify-lab.ps1` |
| [`verify-examples.ps1`](verify-examples.ps1) | Validação automatizada de 28 itens dos exemplos NOC | `powershell -ExecutionPolicy Bypass -File .\verify-examples.ps1` |
| [`test-alert-live.ps1`](test-alert-live.ps1) | Teste ao vivo de incidente, webhook e recovery | `powershell -ExecutionPolicy Bypass -File .\test-alert-live.ps1` |
| [`practice-triggers.ps1`](practice-triggers.ps1) | Simula disparo de triggers e dependências | `powershell -ExecutionPolicy Bypass -File .\practice-triggers.ps1` |
| [`practice-agent-root.sh`](practice-agent-root.sh) | Valida execução do agente como root em container | Executado dentro de container Linux |

### Scripts para VM Linux Mint ([`mint/`](mint/))
- [`mint/setup-mint.sh`](mint/setup-mint.sh): Script de instalação do Zabbix Agent 2 e Proxy nativo SQLite no Mint.
- [`mint/use-windows-ip.sh`](mint/use-windows-ip.sh): Configura o IP do host Windows para comunicação na rede local.
- [`mint/diagnose-mint.sh`](mint/diagnose-mint.sh): Diagnóstico de rede, portas e status dos serviços Zabbix na VM.
- [`mint/recover-mint.sh`](mint/recover-mint.sh): Recupera serviços e reconfigura comunicação da VM.

---

## Testes e Validação do Laboratório

### 1. Teste de Infraestrutura Geral (`verify-lab.ps1`)
Valida:
- Integridade dos 7 containers Docker (`healthy`).
- Serviço do Zabbix Agent em execução no Windows.
- Registro e comunicação recente de ambos os proxies (`lab-proxy` e `mint-proxy`).
- Coleta recente de uptime nos 6 hosts.
- Vínculo e ativação de TOTP para `lab.mfa`.
- Teste real de permissões efetuando login com `lab.user`, `lab.admin`, `lab.super` e `lab.noc`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-lab.ps1
```

Os resultados detalhados ficam registrados em [`validation.local.json`](validation.local.json).

### 2. Teste dos Cenários de NOC (`verify-examples.ps1`)
Audita os 28 pontos exigidos: existência das roles, capacidades de acknowledge, grupo de operadores, login do operador, ação de alerta com escalonamento, webhook, agendamento da manutenção, dashboard, serviço e SLA de 99,9%.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-examples.ps1
```

### 3. Teste Real de Alerta e Escalonamento (`test-alert-live.ps1`)
Simula uma falha operacional gerando um arquivo de flag no container `linux-lab`:
1. Cria `/tmp/lab-service-down` no container.
2. Aguarda a trigger `NOC: Service is down` disparar.
3. Confirma o envio real do evento para a mídia webhook.
4. Remove o arquivo e valida o fechamento do problema e o envio do aviso de recuperação.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test-alert-live.ps1
```

---

## Operação, Diagnóstico e Troubleshooting

### Comandos Úteis do Docker Compose

```powershell
# Ver status e saúde de todos os serviços
docker compose ps

# Visualizar logs em tempo real
docker compose logs -f zabbix-server
docker compose logs -f zabbix-proxy
docker compose logs -f zabbix-web

# Parar os serviços mantendo os dados
docker compose stop

# Retomar serviços parados
docker compose start

# Destruir containers preservando volumes do banco e proxy
docker compose down

# ATENÇÃO: Destruir containers E APAGAR O BANCO/HISTÓRICO
docker compose down -v
```

> [!WARNING]
> O comando `docker compose down -v` remove os volumes persistentes (`mysql-data` e `proxy-data`). Use apenas se quiser recomeçar o laboratório do zero. Após esse comando, execute novamente `start.ps1`, `complete-lab.ps1` e `create-noc-examples.ps1`.

### Diagnóstico de Coleta de Métricas (`zabbix_get`)
Para testar consultas diretas a partir do servidor Zabbix:

```powershell
# Teste de ping no agente do linux-lab
docker compose exec zabbix-server zabbix_get -s linux-lab -k agent.ping

# Teste de ping no agente 2 do host
docker compose exec zabbix-server zabbix_get -s zabbix-agent2 -k agent.ping

# Teste de ping no plugin Docker
docker compose exec zabbix-server zabbix_get -s zabbix-agent2 -k docker.ping
```

### Resolução de Problemas Frequentes

1. **Porta 8080, 8081 ou 10051 já em uso:**
   - Verifique com `Get-NetTCPConnection -LocalPort 8080, 8081, 10051` quais processos estão utilizando a porta e encerre-os antes de executar `.\start.ps1`.

2. **Atraso na Coleta Ativa da VM Linux Mint:**
   - Agentes ativos enviam métricas com base no intervalo do item e no parâmetro `RefreshActiveChecks` (padrão de 120s). Se o relógio da VM estiver desincronizado ou o IP do Windows mudar, utilize `mint/use-windows-ip.sh` dentro da VM.

3. **Política de Execução do PowerShell:**
   - Se ocorrer erro de política de execução (`Script Execution Restricted`), utilize sempre o parâmetro `-ExecutionPolicy Bypass`:
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File .\<script>.ps1
     ```

4. **Autenticação TOTP / Código Inválido:**
   - O algoritmo TOTP depende de relógios sincronizados. Certifique-se de que o relógio do Windows e do smartphone/dispositivo estejam sincronizados via NTP antes de validar o token de `lab.mfa`.
