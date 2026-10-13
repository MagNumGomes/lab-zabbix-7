# Auditoria de requisitos — 09/10/2026

## Resultado

**Última execução: 09/10/2026 às 07:31:46 (-03), com uma falha.**
O autenticador de `lab.mfa` foi vinculado e confirmado (`status=1`), e o navegador
chegou ao dashboard após a autenticação do usuário. MFA passou no teste estrito.
Entretanto, a coleta ativa direta de `linux-mint` voltou a apresentar atraso de
**303 segundos**. `linux-mint-proxy` estava atualizado há **5 segundos**, e os
demais testes passaram. Portanto, a recuperação anterior ainda não demonstra
estabilidade contínua da coleta ativa direta.

A pendência operacional atual é investigar essa recorrência. O diagnóstico
de rede anterior continua válido, mas a migração para o IP LAN, sozinha, não
resolveu definitivamente o atraso. Nenhuma causa adicional foi comprovada.

### Revalidação após a troca de destino

- Agente: `ServerActive=192.168.0.9:10051`; Proxy Mint: `Server=192.168.0.9`.
- Backup informado pelo instalador:
  `/var/backups/zabbix-noc/network-20261009-071940.oIzfXH`.
- Uptime do Mint direto e via proxy atualizado há **24 e 26 segundos** no teste.
- Nenhum item habilitado não suportado nos seis hosts verificados.
- Na confirmação adicional de CPU, `user` e `guest_nice` tinham amostras com
  idade entre **26 e 62 segundos**, nos dois caminhos de coleta.
- A primeira rodada local após reiniciar retornou vazia; as duas seguintes
  responderam numericamente. O usuário `zabbix` também conseguiu ler `/proc/stat`.
- Windows, MySQL, Proxy Docker, itens didáticos e testes de permissões passaram.

Isso comprova a recuperação nas amostras observadas; a instalação nativa
all-in-one e os exercícios manuais mantêm os limites de cobertura descritos
na seção 4. As seções de falhas abaixo preservam o histórico do diagnóstico.

Comando executado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-lab.ps1 -RequireMintProxy -RequireMfaEnrollment
```

Evidência estruturada: `validation.local.json`, com horário, métricas e falhas.
O arquivo é atualizado a cada execução do teste. Este documento registra a
auditoria realizada, não o estado em tempo real.

## 1. Stack e requisitos de instalação

| Requisito | Resultado e evidência |
|---|---|
| Docker Compose desacoplado | Sete serviços em execução e `healthy` |
| Rede bridge comum | `zabbix-net`, driver `bridge` |
| MySQL 8.0 | Versão efetiva 8.0.46 |
| Charset e collation | Servidor e banco `zabbix`: `utf8mb4` / `utf8mb4_bin` |
| Senhas centralizadas e consistentes | Senha de banco com 64 caracteres; root diferente; server/frontend usam a mesma senha da conta SQL |
| Persistência MySQL | Volume montado em `/var/lib/mysql` |
| Dependência saudável | Server depende do MySQL com `service_healthy` |
| Frontend e server | HTTP 200 em 8080; TCP 10051 acessível, verificados por Bash e PowerShell |
| Timezone | `PHP_TZ=America/Sao_Paulo` no Compose |
| Agent 2 e mounts | Socket Docker e `/host/root` efetivamente montados com `RW=false` |
| Host Linux simulado | Ubuntu com agente clássico e coleta via proxy |
| Proxy Docker | Série 7.0.31, comunicação recente; volume em `/var/lib/zabbix/db_data` |
| Agente Windows | Serviço `Zabbix Agent` em execução e inicialização automática; coleta ativa recente |
| Proxy Mint | `mint-proxy` 7.0.31 registrado e comunicando; host `linux-mint-proxy` associado corretamente |

As imagens Zabbix usam tags oficiais com prefixo de distribuição, conforme o
ajuste já documentado. Persistência foi verificada pelos mounts; esta auditoria
não apagou nem recriou bancos para testar recuperação destrutiva.

## 2. Coleta e práticas do Módulo 4

| Prática | Resultado |
|---|---|
| Coleta dos hosts base e Windows | Uptime recente em `Zabbix server`, `linux-lab`, `windows-host` |
| MySQL via Agent 2 | Uptime recente e nenhum item habilitado não suportado na verificação |
| Privilégios da conta SQL | `PROCESS`, `SHOW DATABASES`, `REPLICATION CLIENT`, `SHOW VIEW`, confirmados por `SHOW GRANTS` |
| Histórico MySQL de uma hora | A espera inicial já deixou de aparecer como pendência |
| Checks ativos via Proxy Docker | Item `vfs.file.size[/etc/hostname]` com coleta recente |
| Itens didáticos passivos | `lab.service.up`, `lab.service.errors`, `lab.key.allowed` com coleta recente em `linux-lab` |
| Macro/trigger | Erro acima do limite gerou problema e a remoção gerou recuperação |
| Dependência de triggers | Problema pai impediu abertura do problema dependente; teste terminou com recuperação |
| Agente clássico root | Instância temporária retornou `lab.uid=0` e foi encerrada |
| AllowKey/DenyKey | Chave permitida retornou 1; bloqueada retornou `ZBX_NOTSUPPORTED`, como esperado |
| Utilitários/runtime | `agent.ping` local retornou 1; server e proxy aceitaram `config_cache_reload` |
| Templates | Template didático criado e vinculado; clonagem/cópia manual permanece exercício do aluno |

### Histórico da falha A — coleta ativa direta do Mint atrasada

- Host: `linux-mint`.
- `system.uptime` tem intervalo configurado de **30 segundos**.
- Em três amostras ao longo de um minuto, o dado ficou **326, 356 e 326 segundos**
  atrás do relógio do server; o limite de frescor do teste é 180 segundos.
- Os valores continuam chegando, mas com atraso aproximadamente constante.
- A disponibilidade ativa aparece como disponível; isso não comprova dados atuais.

### Histórico da falha B — timeout de CPU no caminho via Proxy Mint

- Host: `linux-mint-proxy`.
- Item: `system.cpu.util[,guest_nice]`.
- Erro: `Timeout while waiting for item in queue.`
- O erro persistiu nas três amostras. Uptime, memória e itens didáticos desse
  mesmo host continuaram recebendo dados recentes.

Ainda não foi determinada a causa dos dois problemas. Precisamos conferir
hora/sincronização, parâmetros de buffer e fila e logs do agente dentro da VM.
Não foram alterados limiares ou desabilitados esses itens para fazer o teste passar.

### Diagnóstico enviado pelo usuário às 07:07

- Relógio do Mint e cabeçalho HTTP do server coincidiram; NTP ativo/sincronizado.
- Mint tinha aproximadamente 2,2 GiB de memória disponível e 105 GiB de disco livre.
- `zabbix_get` local para `system.cpu.util[,guest_nice]` também expirou; `agent.ping`
  e `system.uptime` responderam. Isso localiza uma falha na coleta/atendimento de
  CPU do Agent 2, independentemente do caminho VirtualBox → Windows.
- Logs do agente e do proxy registraram timeouts TCP intermitentes ao destino
  `10.0.2.2:10051`, seguidos de recuperação. A origem exata dessa intermitência
  ainda não foi isolada entre rede, encaminhamento e host.
- No server, trappers e history syncers estavam com ocupação média inferior a 1%
  na consulta; não apareceu indício de saturação sustentada desses processos.
- O item de CPU voltou a ser suportado às 07:08:49, mas o atraso da coleta ativa
  persistia na consulta seguinte. Recuperação pontual não comprova estabilidade.

Foi disponibilizado `mint/recover-mint.sh`: valida a configuração, reinicia uma
vez o Agent 2, testa as chaves localmente e compara dez conexões TCP pelo NAT e
pelo IP LAN do Windows (`192.168.0.9` nesta instalação). O script é uma tentativa
controlada de recuperação e diagnóstico, não uma correção definitiva comprovada.
Pode-se definir `ZABBIX_WINDOWS_IP` se o IP do Windows mudar.

### Resultado da recuperação enviado às 07:15

- Reinício do Agent 2 precisou encerrar o processo anterior com SIGKILL após o
  timeout de parada do serviço. O novo processo iniciou e validou a configuração.
- `agent.ping` e uptime responderam; as primeiras consultas de CPU retornaram
  resposta vazia. A mensagem de `zabbix_get` sugere permissões genericamente, mas
  não prova que esse seja o motivo. O plugin de CPU também pode retornar vazio
  antes de reunir suas primeiras amostras após ativação.
- Comparação simultânea: `10.0.2.2:10051` falhou **3/10** vezes;
  `192.168.0.9:10051` teve **0/10** falhas.
- O IP LAN do Windows foi reconfirmado por aqui como `192.168.0.9`. As mesmas
  chaves de CPU funcionaram no Agent 2 do Docker; o problema restante requer
  validação no agente da VM.

Com essa evidência foi preparado `mint/use-windows-ip.sh`, que troca `ServerActive`
do agente e `Server` do proxy para o IP LAN do Windows, com backup e restauração
em caso de falha de validação/reinício. A VM continua em NAT. O script repete as
consultas de CPU para não classificar a primeira amostra vazia como falha definitiva.
Aplicação e validação final dependem da execução dentro do Mint.

```bash
curl -fsS http://192.168.0.9:8081/use-windows-ip.sh -o /tmp/use-windows-ip.sh
sudo bash /tmp/use-windows-ip.sh 192.168.0.9
```

O destino LAN depende do endereço do Windows: se ele mudar por DHCP, o destino
do agente e do proxy deve ser atualizado. A amostragem inicial de dez conexões
não garante estabilidade contínua; a coleta recente deve ser revalidada no server.

## 3. Permissões e MFA — Módulo 5

| Requisito | Resultado |
|---|---|
| User com leitura | Login real; enxerga Linux e é impedido de alterar host |
| Admin restrito aos grupos do curso | Linux/Windows/Databases editáveis; infraestrutura fora do acesso |
| Super admin | Acesso à infraestrutura confirmado |
| Role NOC customizada | Visibilidade de Linux; métodos de API fora da lista são recusados |
| Associação MFA | Método TOTP SHA-1/6 dígitos, grupo e conta `lab.mfa` corretamente associados |
| Vínculo e login MFA | **Concluído:** um registro TOTP confirmado para `lab.mfa`; usuário autenticou e navegador chegou ao dashboard |

A consulta do estado MFA leu somente existência e confirmação do cadastro;
nenhuma chave secreta TOTP foi consultada. Configurar o método não equivale a
validar um login com segundo fator.

## 4. Cobertura da grade e limites da comprovação

- **M00–M02:** conceitos e estudos; testes de infraestrutura não comprovam aprendizado.
- **M03:** arquitetura funcional disponível em Docker. A instalação all-in-one
  por pacotes dentro do Mint não foi executada. O dimensionamento do banco e a
  reprodução do procedimento de instalação são exercícios que não se comprovam
  apenas pela stack estar saudável.
- **M04:** agentes clássico/2, Windows, proxies, MySQL e objetos didáticos
  disponíveis. A recorrência do atraso no Mint direto impede aprovar integralmente a coleta.
- **M05:** permissões testadas; vínculo MFA confirmado e login concluído pelo usuário.
- Oracle Linux foi adaptado para Mint/Ubuntu conforme solicitado. Procedimentos
  específicos de RPM/SELinux não são executados no Mint.
- LDAP/AD, SAML e Duo não foram instalados: a grade fornecida não define uma
  prática obrigatória específica desses provedores. Autenticação interna e TOTP
  são os cenários preparados.
- Os 13 itens incompatíveis com a infraestrutura Docker continuam desabilitados;
  essa é uma adaptação explícita do laboratório, não comprovação desses coletores.

## 5. Próximos passos para aprovar o que está pendente

### Dentro do Mint: coletar diagnóstico

```bash
curl -fsS http://10.0.2.2:8081/diagnose-mint.sh -o /tmp/diagnose-mint.sh
sudo bash /tmp/diagnose-mint.sh | tee ~/diagnostico-zabbix.txt
```

O script é somente leitura: mostra horário, recursos, estado dos serviços,
parâmetros de buffer/timeout, consultas locais e logs recentes. Envie o arquivo
`~/diagnostico-zabbix.txt` para investigar os dois erros sem adivinhar a causa.

Após o diagnóstico já recebido, execute a etapa controlada no Mint:

```bash
curl -fsS http://10.0.2.2:8081/recover-mint.sh -o /tmp/recover-mint.sh
sudo bash /tmp/recover-mint.sh | tee ~/recuperacao-zabbix.txt
```

Envie `~/recuperacao-zabbix.txt` para comparar os testes locais e os dois destinos.

### No painel: concluir MFA

**Etapa já concluída nesta instalação.** Os passos abaixo servem para reprodução:

Entre com `lab.mfa` usando a senha em `credentials.local.json`, vincule o QR code
ao autenticador TOTP e confirme o login. Depois saia e teste um novo login.

### No Windows: repetir o teste estrito após as correções

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-lab.ps1 -RequireMintProxy -RequireMfaEnrollment
```

O verificador foi reforçado nesta auditoria para detectar hosts ausentes,
validar a associação do Proxy Mint, exigir dados recentes também nos itens
didáticos e distinguir MFA configurado de autenticador efetivamente confirmado.
