# Estado verificado e pendências

Atualizado após a ampliação do laboratório para a grade NOC em 09/10/2026.
Este registro é um retrato das verificações, não um indicador em tempo real.

**Revalidação de 09/10/2026 às 07:31 (-03):** consulte o
[relatório detalhado](auditoria-requisitos.md). MFA vinculado e confirmado.
O atraso do Mint direto reapareceu; o caminho via Proxy continua com dados recentes.

## Funcionamento confirmado

| Componente | Resultado |
|---|---|
| MySQL, server, frontend, Agent 2, Ubuntu, Proxy e servidor de arquivos | Sete containers `healthy` |
| Frontend | HTTP 200 em `http://localhost:8080` |
| Server | TCP 10051 acessível |
| Banco | `utf8mb4` / `utf8mb4_bin`, schema inicializado |
| `linux-mint` | Uptime com 303 segundos de atraso; falha de frescor, sem itens habilitados marcados como não suportados |
| `linux-lab` | `agent.ping=1`, CPU, memória e uptime recentes; 0 itens habilitados não suportados |
| `Zabbix server` | `agent.ping=1`, `docker.ping=1`, CPU, memória e uptime com coleta |
| `windows-host` | Agente clássico 7.0.31 instalado via MSI, serviço automático e uptime recente |
| `mysql-lab` | Coleta de uptime e demais métricas via Agent 2; conta SQL dedicada |
| `lab-proxy` | Comunicação recente com server, SQLite persistente e coleta de `linux-lab` |
| `mint-proxy` | Comunicação recente; uptime atualizado há 5 segundos e nenhum item habilitado não suportado |
| Permissões | Logins reais com User/Admin/Super admin/NOC, limites de visibilidade e bloqueios de escrita/API confirmados |
| MFA | `lab.mfa` com autenticador confirmado e login concluído pelo usuário |
| Prática de triggers | Problema, recuperação, dependência pai/filha e retorno ao normal testados |
| Agente clássico root | Instância temporária confirmou `lab.uid=0` e foi encerrada |
| AllowKey/DenyKey | Chave permitida retornou 1; chave bloqueada foi recusada |

As métricas Linux principais tinham atualização inferior a um minuto na
verificação. O último `docker.ping` tinha aproximadamente cinco minutos,
coerente com seu intervalo de coleta. Os dois scripts de healthcheck passaram.

## Monitoramento do Windows

O laboratório funciona no Windows via Docker Desktop. O Agent 2 em container
observa o ambiente Linux do Docker Desktop e a API Docker; ele não equivale a
um agente nativo Windows. O mount `/host/root` também não representa o disco Windows.

**Resolvido:** o serviço nativo **Zabbix Agent** (clássico, conforme a aula MSI)
foi instalado separadamente no Windows, com template ativo e host `windows-host`.
O Agent 2 Docker continua responsável pelo Linux do Docker Desktop e pelo MySQL.

## Histórico: 13 itens não suportados em `Zabbix server`

**Ajuste aplicado:** os 13 itens abaixo foram desabilitados somente nesse host.
Os templates oficiais continuam disponíveis para outros hosts. A verificação
posterior confirmou ausência de erros de coleta habilitados nesse host.

| Chave do item | Motivo observado |
|---|---|
| `zabbix[process,ipmi poller,avg,busy]` | Processo IPMI poller não iniciado |
| `zabbix[process,ipmi manager,avg,busy]` | Processo IPMI manager não iniciado |
| `zabbix[process,java poller,avg,busy]` | Processo Java poller não iniciado |
| `zabbix[process,snmp trapper,avg,busy]` | Processo SNMP trapper não iniciado |
| `zabbix[process,vmware collector,avg,busy]` | Processo VMware collector não iniciado |
| `zabbix[vmware,buffer,pused]` | Coletor VMware não iniciado |
| `zabbix[process,report writer,avg,busy]` | Processo de escrita de relatórios não iniciado |
| `zabbix[process,report manager,avg,busy]` | Processo de gerenciamento de relatórios não iniciado |
| `zabbix[connector_queue]` | Conectores não inicializados; parâmetro `StartConnectors` |
| `zabbix[process,connector manager,avg,busy]` | Processo connector manager não iniciado |
| `zabbix[process,connector worker,avg,busy]` | Processo connector worker não iniciado |
| `system.sw.packages.get` | Agente não conseguiu obter informações dos pacotes no container |
| `docker.kernel_mem.enabled` | Pré-processamento busca `$.KernelMemory`, ausente na resposta Docker |

Esses erros não impediram a coleta principal comprovada acima. Eles também
significam que o conjunto completo de itens vinculados ainda não está validado.

### Tratamento aplicado

1. Itens de recursos opcionais desativados foram desabilitados nesse host.
2. Inventário de pacotes incompatível com esse container foi desabilitado.
3. O item de `KernelMemory`, ausente na resposta Docker, foi desabilitado.

No Windows também foi desabilitado somente o item de metadado `net.if.type` do
adaptador **OpenVPN Connect DCO Adapter**, cujo `AdapterTypeId` não é fornecido
na consulta WMI. As demais métricas de rede permanecem disponíveis.

## Etapas restantes e histórico inicial

- **Mint:** agente e proxy usam `192.168.0.9:10051`, mas o atraso na coleta ativa
  direta reapareceu. A causa adicional precisa ser investigada; o proxy mantém coleta recente.
- **MFA concluído:** método, associação à conta e vínculo pessoal confirmados;
  o usuário completou a autenticação e acessou o dashboard.
- **Histórico MySQL:** a espera inicial de uma hora já foi superada; nenhum
  item habilitado não suportado desse host foi encontrado na auditoria posterior.
- **Instalação all-in-one por pacotes no Mint:** a stack Docker fornece a
  arquitetura funcional; uma segunda instalação nativa de server/frontend/BD
  não foi executada na VM. Consulte a adaptação de instalação no guia do curso.

Os scripts e passos estão no [guia do curso adaptado ao Mint](curso-mint.md).

## Como repetir a verificação

No PowerShell, dentro de `lab-zabbix-7`:

```powershell
docker compose ps
.\healthcheck.ps1
.\verify-lab.ps1
docker compose exec zabbix-server zabbix_get -s linux-lab -k agent.ping
docker compose exec zabbix-server zabbix_get -s zabbix-agent2 -k agent.ping
docker compose exec zabbix-server zabbix_get -s zabbix-agent2 -k docker.ping
```

No painel:

- **Monitoring > Latest data:** confira valores e horários nos três hosts.
- **Data collection > Hosts > Items:** em cada host, filtre itens habilitados
  e estado **Not supported** para consultar os erros.
- **Monitoring > Problems:** confira os problemas detectados pelas triggers.

Para o Mint, siga também o [diagnóstico na VM e no Windows](linux-mint-virtualbox.md).
