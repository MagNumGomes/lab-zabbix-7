# Laboratório Zabbix 7.0 LTS

Ambiente prático completo de monitoramento corporativo baseado em **Zabbix 7.0 LTS**, configurado em arquitetura híbrida com **Docker (Compose v2)**, integração com o **Host Windows local** e suporte a **Máquinas Virtuais externas (Linux Mint / Ubuntu no VirtualBox)**.

O laboratório implementa cenários reais de monitoramento de infraestrutura e NOC (Network Operations Center): múltiplos métodos de coleta (agente clássico passivo/ativo, Agent 2, monitoramento nativo de MySQL e Docker daemon), proxies Zabbix (Docker SQLite e proxy nativo), controle de acesso granular baseado em perfis (RBAC), autenticação multifator (MFA TOTP), esteira automatizada de alertas com escalonamento em múltiplos níveis e webhooks, janelas programadas de manutenção, dashboards executivos e gestão de SLA de serviços de TI.

---

## Sumário

- [Arquitetura e Topologia](#arquitetura-e-topologia)
- [Portas e Credenciais de Acesso](#portas-e-credenciais-de-acesso)
- [Tutorial de Uso (Passo a Passo)](#tutorial-de-uso-passo-a-passo)
  - [1. Pré-requisitos](#1-pré-requisitos)
  - [2. Inicializar a Stack Docker](#2-inicializar-a-stack-docker)
  - [3. Provisionar o Laboratório via API](#3-provisionar-o-laboratório-via-api)
  - [4. Provisionar Cenários e Regras de Monitoramento](#4-provisionar-cenários-e-regras-de-monitoramento)
  - [5. Instalar o Agente no Host Windows (Opcional)](#5-instalar-o-agente-no-host-windows-opcional)
  - [6. Integrar VM Linux Mint / VirtualBox (Opcional)](#6-integrar-vm-linux-mint--virtualbox-opcional)
  - [7. Validar o Laboratório e Executar Testes](#7-validar-o-laboratório-e-executar-testes)
- [Inventário de Hosts e Modos de Coleta](#inventário-de-hosts-e-modos-de-coleta)
- [Cenários e Recursos Configurados no Laboratório](#cenários-e-recursos-configurados-no-laboratório)
- [Scripts e Automações Disponíveis](#scripts-e-automações-disponíveis)
- [Operação, Diagnóstico e Troubleshooting](#operação-diagnóstico-e-troubleshooting)

---

## Arquitetura e Topologia

O ambiente integra containers Docker na rede interna `zabbix-net`, serviços locais no Windows e máquinas virtuais na rede local:

```text
                                  +------------------------------------+
                                  |         Navegador Web Local        |
                                  +------------------------------------+
                                             |              |
                                    HTTP 8080|     HTTP 8081| (scripts/arquivos)
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
1. **`mysql`**: MySQL 8.0 com charset `utf8mb4_bin` e volume persistente `mysql-data`.
2. **`zabbix-server`**: Zabbix Server 7.0 Alpine expondo a porta `10051`.
3. **`zabbix-web`**: Frontend Zabbix 7.0 Nginx/PHP na porta `8080`.
4. **`zabbix-agent2`**: Agente 2 oficial com monitoramento do Docker daemon local e `/host/root`.
5. **`zabbix-proxy`** (`lab-proxy`): Proxy SQLite3 na porta `10052` coletando o container `linux-lab`.
6. **`lab-files`**: Servidor Nginx estático na porta `8081` para entrega de scripts e pacotes.
7. **`linux-lab`**: Container Ubuntu 22.04 com Agente Zabbix clássico simulando servidor monitorado.

---

## Portas e Credenciais de Acesso

### Interfaces e Portas

| Serviço | Destino / Porta | Descrição |
|---|---|---|
| **Frontend Zabbix** | `http://localhost:8080` | Interface gráfica de gerenciamento do Zabbix 7.0 |
| **Servidor de Arquivos do Lab** | `http://localhost:8081` | Distribuição HTTP de scripts e pacotes para hosts/VMs |
| **Zabbix Server Trapper** | `localhost:10051` | Porta padrão para Agentes Ativos e Zabbix Sender |
| **Docker Zabbix Proxy** | `localhost:10052` | Porta para encaminhamento de coleta via `lab-proxy` |
| **MySQL Database** | Interno (`mysql:3306`) | Conexão de server e frontend ao MySQL |

### Credenciais Principais

| Conta / Contexto | Usuário | Senha | Função / Permissões |
|---|---|---|---|
| **Zabbix Super Admin** | `Admin` | `zabbix` | Acesso administrativo completo à interface |
| **Zabbix Banco MySQL** | `zabbix` | Definida em `.env` (`MYSQL_PASSWORD`) | Conexão interna do Server e Frontend |
| **MySQL Root** | `root` | Definida em `.env` (`MYSQL_ROOT_PASSWORD`) | Administração do container MySQL |
| **MySQL Monitor** | `zbx_monitor` | Armazenada em `credentials.local.json` | Coleta de métricas pelo plugin MySQL do Agent 2 |
| **Contas de Operação** | `lab.user`, `lab.admin`, `lab.super`, `lab.noc`, `lab.operator`, `lab.mfa` | Geradas e salvas em `credentials.local.json` | Perfis para testes de papéis (RBAC) e MFA |

> [!NOTE]
> As senhas randômicas das contas de serviço e da conta SQL de monitoramento ficam salvas localmente no arquivo [`credentials.local.json`](credentials.local.json) (gerado automaticamente no provisionamento e ignorado pelo Git).

---

## Tutorial de Uso (Passo a Passo)

### 1. Pré-requisitos

- **Windows 10/11** com **Docker Desktop** (Engine em modo Linux containers com integração WSL2).
- Mínimo de **4 GB de RAM** e **10 GB de disco** livres.
- **PowerShell 5.1+** com permissão para execução de scripts (`ExecutionPolicy Bypass`).

---

### 2. Inicializar a Stack Docker

Abra um terminal PowerShell na pasta raiz do projeto:

```powershell
.\start.ps1
```

*(Ou no Linux/macOS via Bash: `bash start.sh`)*

Para validar que os containers subiram corretamente e estão com status `healthy`:

```powershell
.\healthcheck.ps1
```

Acesse o painel web em seu navegador:
- **URL:** [http://localhost:8080](http://localhost:8080)
- **Usuário padrão:** `Admin`
- **Senha padrão:** `zabbix`

---

### 3. Provisionar o Laboratório via API

Execute o provisionamento automatizado da infraestrutura através da Zabbix API:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\complete-lab.ps1
```

Esse script executa automaticamente:
- Criação dos proxies no Zabbix (`lab-proxy` e `mint-proxy`).
- Cadastro dos hosts principais (`windows-host`, `mysql-lab`, `linux-mint`).
- Configuração de grupos de hosts e grupos de templates.
- Configuração do usuário e permissões do MySQL para o Zabbix Agent 2.
- Cadastro dos perfis de usuário (RBAC) e configuração do método MFA TOTP.
- Armazenamento seguro de credenciais geradas em `credentials.local.json`.

---

### 4. Provisionar Cenários e Regras de Monitoramento

Crie as regras de negócio, triggers com dependência, escalonamentos e dashboards operacionais:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\create-noc-examples.ps1
```

Esse comando configura:
- **Template `NOC Linux practice`**: Itens simulados de serviço, contadores de erro e diretiva `AllowKey`.
- **Triggers com Dependência**: Disparo correlacionado para evitar tempestade de alarmes quando um serviço cai.
- **Esteira de Alertas**: Ação de alerta com filtro por tag, escalonamento em múltiplos passos e webhook de registro.
- **Governança**: Janela programada de manutenção com supressão de alarmes.
- **Visão de Negócio**: Dashboard operacional, mapeamento de serviço de TI e monitoramento de SLA (99,9%).

---

### 5. Instalar o Agente no Host Windows (Opcional)

Para monitorar a máquina física local Windows no laboratório:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows-agent.ps1
```

O script baixa o instalador oficial do Zabbix Agent (`.msi`), configura o serviço apontando para `localhost:10051` com o hostname `windows-host` e inicia o serviço no Windows.

---

### 6. Integrar VM Linux Mint / VirtualBox (Opcional)

Se desejar testar a coleta de uma VM externa na rede local:

1. Na VM Linux Mint/Ubuntu, baixe e execute o script de instalação rápida disponibilizado pelo servidor HTTP do laboratório:
   ```bash
   curl -s http://<IP_DO_WINDOWS>:8081/setup-mint.sh | sudo bash
   ```
   *(Ou execute diretamente o arquivo [`mint/setup-mint.sh`](mint/setup-mint.sh))*

2. Para atualizar o IP de destino caso a máquina Windows mude de endereço de rede:
   ```bash
   sudo bash mint/use-windows-ip.sh <NOVO_IP_WINDOWS>
   ```

3. Para testar conectividade e integridade dos serviços dentro da VM:
   ```bash
   sudo bash mint/diagnose-mint.sh
   ```

---

### 7. Validar o Laboratório e Executar Testes

O laboratório conta com rotinas de teste automatizadas para auditar e demonstrar o funcionamento dos componentes:

#### A. Auditoria geral de infraestrutura
Valida containers, serviços do agente, comunicação com proxies, frescor da coleta de dados e testes de autenticação RBAC/MFA:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-lab.ps1
```

#### B. Auditoria das regras e cenários configurados
Verifica a existência e a consistência das roles, ações de alerta, triggers de dependência, janelas de manutenção, dashboards e SLA:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-examples.ps1
```

#### C. Teste de incidente em tempo real (Simulação de Alerta e Webhook)
Simula uma parada não programada do serviço no container `linux-lab`, aguarda o acionamento da trigger, valida o disparo do webhook de notificação e limpa a falha gerando o evento de recuperação (*recovery*):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test-alert-live.ps1
```

#### D. Simulação de triggers e testes de dependência
Gera valores de teste no container para acionar triggers pontuais e demonstrar a supressão de alarmes dependentes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\practice-triggers.ps1
```

---

## Inventário de Hosts e Modos de Coleta

| Nome do Host no Zabbix | Ambiente | Modo de Coleta | Rota / Conexão | Templates Vinculados |
|---|---|---|---|---|
| `Zabbix server` | Container Docker | Agent 2 (Passivo 10050) | Conexão direta interna | `Linux by Zabbix agent`, `Zabbix server health`, `Docker by Zabbix agent 2` |
| `linux-lab` | Container Docker | Clássico (Passivo/Ativo) | Coletado via Proxy `lab-proxy` | `Linux by Zabbix agent`, `NOC Linux practice` |
| `windows-host` | Máquina Local Windows | Clássico 7.0.31 (Ativo) | Direto para `localhost:10051` | `Windows by Zabbix agent active` |
| `mysql-lab` | Container MySQL | Agent 2 (Passivo) | Agent 2 consulta MySQL | `MySQL by Zabbix agent 2` |
| `linux-mint` | VM VirtualBox | Agent 2 (Ativo) | Direto para IP LAN:10051 | `Linux by Zabbix agent active` |
| `linux-mint-proxy` | VM VirtualBox | Agent 2 (Passivo) | Via proxy nativo `mint-proxy` | `Linux by Zabbix agent` |

---

## Cenários e Recursos Configurados no Laboratório

### 1. Template `NOC Linux practice`
- **Métricas simuladas:**
  - `lab.service.up`: Status da aplicação simulada (0 = Parado, 1 = Em execução).
  - `lab.service.errors`: Contador de erros da aplicação.
  - `lab.key.allowed`: Demonstração da diretiva `AllowKey` retornando `1`.
  - `vfs.file.size[/etc/hostname]`: Exemplo de verificação ativa de arquivo.
- **Triggers com dependência:**
  - `NOC: Service is down` (Severidade High, trigger pai).
  - `NOC: Too many service errors` (Severidade Warning, trigger filha dependente do pai). Se o serviço principal cair, o alarme secundário de erros é suprimido automaticamente, evitando notificações redundantes.
- **Macros de usuário:** `{$NOC.ERRORS.MAX} = 5`.
- **Value Mapping:** Mapeamento `NOC service state` (0 ➔ Parado, 1 ➔ Em execução).

### 2. Controle de Acesso Baseado em Perfis (RBAC)
- **`NOC read only`**: Permissão restrita de somente leitura ao grupo `NOC/Linux`, sem acesso administrativo e com bloqueio de métodos de escrita na API.
- **`NOC Operator`**: Permissão de visualização operacional (Dashboard, Problemas, Dados recentes, Mapas) com direito de reconhecer (*Acknowledge*), comentar, suprimir e fechar incidentes.
- **`NOC Maintenance admin`**: Perfil administrativo direcionado à gestão de períodos de manutenção, sem permissão para gerenciar contas de usuários ou regras globais de alerta.

### 3. Autenticação e MFA (TOTP)
- Método `NOC TOTP` configurado no Zabbix 7.0.
- Usuário `lab.mfa` preparado para validação de fluxo de segundo fator com aplicativos autenticadores (Google Authenticator, Microsoft Authenticator, 2FAS, etc.).

### 4. Ações de Alerta, Escalonamento e Webhook
- **Ação:** `NOC: avisa queda do servico didatico`.
- **Filtro:** Dispara para problemas associados à tag `curso:noc` no grupo `NOC/Linux` com severidade `Warning` ou superior.
- **Escalonamento em 2 níveis:**
  - **Passo 1 (imediato):** Dispara notificação inicial para os operadores (`NOC Operators`).
  - **Passo 2 (após 5 minutos sem resolução):** Escala o chamado notificando a gerência/administração (`NOC Administrators`).
  - **Recuperação automática:** Envia aviso de restabelecimento assim que o serviço retorna ao estado normal.
- **Media Type Webhook:** Webhook JavaScript embutido (`NOC Registro em log (exemplo)`) que confirma entrega e logging real sem dependência de serviços externos.

### 5. Janela de Manutenção
- **`NOC Exemplo - janela de manutencao`**: Período de manutenção programado aos domingos (05:00–07:00) para o host `linux-lab`, mantendo a coleta de métricas ativa porém suprimindo alarmes e notificações durante a janela.

### 6. Dashboards, Serviços de TI e Gestão de SLA
- **Dashboard Operacional**: Visão consolidada com widgets de Problemas Ativos, Disponibilidade de Hosts e Métricas do Servidor.
- **Serviço de TI (`NOC Servico didatico`)**: Mapeado na árvore de serviços através da tag `servico:lab-demo`.
- **SLA (`NOC SLA exemplo`)**: Cálculo de nível de serviço semanal com meta de disponibilidade estabelecida em **99,9%**.

---

## Scripts e Automações Disponíveis

Todos os scripts PowerShell foram desenvolvidos com foco em **idempotência** (podem ser reexecutados sem duplicar objetos ou causar inconsistências):

| Script | Finalidade | Como Executar |
|---|---|---|
| [`start.ps1`](start.ps1) | Inicializa os containers Docker com verificação `--wait` | `.\start.ps1` |
| [`healthcheck.ps1`](healthcheck.ps1) | Testa respostas HTTP 200 (8080) e porta TCP 10051 | `.\healthcheck.ps1` |
| [`configure-hosts.ps1`](configure-hosts.ps1) | Cadastra hosts iniciais via Zabbix API | `.\configure-hosts.ps1` |
| [`complete-lab.ps1`](complete-lab.ps1) | Provisiona a infraestrutura completa do laboratório via API | `powershell -ExecutionPolicy Bypass -File .\complete-lab.ps1` |
| [`create-noc-examples.ps1`](create-noc-examples.ps1) | Cria templates, triggers, escalonamentos, SLA e dashboards | `powershell -ExecutionPolicy Bypass -File .\create-noc-examples.ps1` |
| [`install-windows-agent.ps1`](install-windows-agent.ps1) | Baixa e instala o serviço do Zabbix Agent no Windows | `powershell -ExecutionPolicy Bypass -File .\install-windows-agent.ps1` |
| [`verify-lab.ps1`](verify-lab.ps1) | Auditoria técnica de containers, agentes, banco e RBAC | `powershell -ExecutionPolicy Bypass -File .\verify-lab.ps1` |
| [`verify-examples.ps1`](verify-examples.ps1) | Validação automatizada de regras, alertas e configurações | `powershell -ExecutionPolicy Bypass -File .\verify-examples.ps1` |
| [`test-alert-live.ps1`](test-alert-live.ps1) | Teste de incidente em tempo real com webhook e recovery | `powershell -ExecutionPolicy Bypass -File .\test-alert-live.ps1` |
| [`practice-triggers.ps1`](practice-triggers.ps1) | Simula disparo de triggers e dependências no container | `powershell -ExecutionPolicy Bypass -File .\practice-triggers.ps1` |
| [`practice-agent-root.sh`](practice-agent-root.sh) | Valida execução do agente Zabbix em container | Executado em container Linux |

### Scripts para VM Linux Mint ([`mint/`](mint/))
- [`mint/setup-mint.sh`](mint/setup-mint.sh): Instala o Zabbix Agent 2 e Proxy nativo SQLite no Linux Mint.
- [`mint/use-windows-ip.sh`](mint/use-windows-ip.sh): Configura o IP do host Windows para comunicação na rede local.
- [`mint/diagnose-mint.sh`](mint/diagnose-mint.sh): Diagnóstico de rede, portas e status dos serviços Zabbix na VM.
- [`mint/recover-mint.sh`](mint/recover-mint.sh): Recupera serviços e reestabelece a comunicação da VM.

---

## Operação, Diagnóstico e Troubleshooting

### Comandos Essenciais do Docker Compose

```powershell
# Verificar o status de todos os containers
docker compose ps

# Visualizar logs em tempo real
docker compose logs -f zabbix-server
docker compose logs -f zabbix-proxy
docker compose logs -f zabbix-web

# Parar os serviços mantendo os volumes de dados
docker compose stop

# Retomar os serviços parados
docker compose start

# Destruir containers preservando os volumes do banco e proxies
docker compose down

# ATENÇÃO: Destruir containers e ZERAR banco de dados e histórico
docker compose down -v
```

> [!WARNING]
> O comando `docker compose down -v` apaga os volumes persistentes (`mysql-data` e `proxy-data`). Utilize-o apenas caso deseje reiniciar o laboratório do zero absoluto. Caso faça isso, execute novamente `start.ps1`, `complete-lab.ps1` e `create-noc-examples.ps1`.

### Diagnóstico de Coleta de Métricas (`zabbix_get`)

Para testar consultas diretas a partir do servidor Zabbix:

```powershell
# Teste de conectividade com o agente do container linux-lab
docker compose exec zabbix-server zabbix_get -s linux-lab -k agent.ping

# Teste de conectividade com o Agent 2 do host
docker compose exec zabbix-server zabbix_get -s zabbix-agent2 -k agent.ping

# Teste de coleta no plugin Docker
docker compose exec zabbix-server zabbix_get -s zabbix-agent2 -k docker.ping
```

### Resolução de Problemas Frequentes

1. **Porta 8080, 8081 ou 10051 em uso:**
   - Verifique quais processos estão ocupando a porta com `Get-NetTCPConnection -LocalPort 8080, 8081, 10051` e encerre-os antes de iniciar o laboratório.

2. **Política de Execução de Scripts do PowerShell:**
   - Caso receba mensagem de bloqueio (`Script Execution Restricted`), adicione o parâmetro `-ExecutionPolicy Bypass`:
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File .\<script>.ps1
     ```

3. **Autenticação TOTP / Código Inválido no Login MFA:**
   - O algoritmo TOTP baseia-se em timestamps UNIX precisos. Certifique-se de que o relógio do Windows e o relógio do seu smartphone/dispositivo autenticador estejam sincronizados via NTP.
