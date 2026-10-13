# Curso NOC adaptado ao Linux Mint

## 1. Topologia pronta

```text
Windows / Docker Desktop
  http://localhost:8080 -> frontend -> MySQL
  Windows Agent (MSI) -------------> server:10051
  Agent 2 Docker <------------------ server (passivo)
      -> MySQL mysql:3306 (plugin)
  linux-lab <-> lab-proxy SQLite ---> server
  http://localhost:8081/setup-mint.sh (somente arquivos de pratica)

VirtualBox / Linux Mint / NAT
  Agent 2 linux-mint --------------> 192.168.0.9:10051 -> server
  mint-proxy SQLite ---------------> 192.168.0.9:10051 -> server
      -> consulta Agent 2 em 127.0.0.1:10050 como host linux-mint-proxy
```

Os dois hosts Mint mostram o mesmo sistema por caminhos distintos: coleta ativa
direta e passiva através do proxy nativo. Isso permite comparar os modos do curso.
O proxy Docker já fornece um cenário completo mesmo antes da instalação na VM.

## 2. O que fazer no Windows

Dentro de `lab-zabbix-7`:

```powershell
.\start.ps1
.\complete-lab.ps1
.\verify-lab.ps1
```

Se houver bloqueio da política de execução, use
`powershell -NoProfile -ExecutionPolicy Bypass -File .\NOME-DO-SCRIPT.ps1`.

O agente Windows foi instalado e validado com `install-windows-agent.ps1`, usando
o MSI oficial assinado, versão 7.0.31. O serviço **Zabbix Agent** inicia
automaticamente. Configuração:

```ini
Hostname=windows-host
Server=127.0.0.1
ServerActive=127.0.0.1:10051
```

Arquivo: `C:\Program Files\Zabbix Agent\zabbix_agentd.conf`.
Template: `Windows by Zabbix agent active`. Para esta coleta ativa, não foi
necessário expor a porta 10050 para a rede. Logs da instalação estão em
`windows-install.log` e `windows-msi.log`.

## 3. O que fazer dentro da VM Mint

**Ajuste de rede após a auditoria:** o alias NAT `10.0.2.2:10051` apresentou
3/10 falhas, enquanto o IP LAN do Windows `192.168.0.9:10051` passou nas dez
amostras. O instalador passou a usar esse IP LAN como destino padrão.
Para uma instalação já existente, aplique a migração com backup:

```bash
curl -fsS http://192.168.0.9:8081/use-windows-ip.sh -o /tmp/use-windows-ip.sh
sudo bash /tmp/use-windows-ip.sh 192.168.0.9
```

Migração aplicada e coleta revalidada em 09/10/2026 às 07:20 (-03).
Confira o IP do Windows quando mudar de rede; a VM continua em NAT.

Execute no terminal da VM:

```bash
curl -fsS http://192.168.0.9:8081/setup-mint.sh -o /tmp/setup-mint.sh
sudo bash /tmp/setup-mint.sh
```

O script:

- Identifica a versão Ubuntu de base do Mint e usa o repositório oficial 7.0.
- Instala Agent 2, Proxy SQLite, `zabbix_get` e `sqlite3` via `apt`.
- Salva as configurações anteriores em `/var/backups/zabbix-noc/`.
- Configura `mint-proxy`, com banco `/var/lib/zabbix/mint-proxy.db`.
- Mantém o Agent 2 como `linux-mint` com checks ativos diretos.
- Adiciona chaves didáticas e regras `AllowKey`/`DenyKey`.
- Habilita e reinicia os serviços `zabbix-agent2` e `zabbix-proxy`.

Valide dentro do Mint:

```bash
systemctl status zabbix-agent2 zabbix-proxy --no-pager
sudo tail -n 50 /var/log/zabbix/zabbix_proxy.log
zabbix_get -s 127.0.0.1 -k agent.ping
```

Depois, no Windows, execute `verify-lab.ps1 -RequireMintProxy` e confira o host
**Linux Mint via Proxy** em Latest data. Nesta instalação o script já foi
executado pelo usuário e a comunicação/coleta do proxy nativo foi confirmada.

## 4. Credenciais e permissões — Módulo 5

O login principal continua sendo `Admin` / `zabbix`.
As senhas aleatórias das contas abaixo estão em **`credentials.local.json`**.

| Usuário | Tipo / finalidade | Acesso preparado |
|---|---|---|
| `lab.user` | User | Leitura de `NOC/Linux` |
| `lab.admin` | Admin | Escrita em Linux, Windows e Databases do curso; templates em `Templates/NOC` |
| `lab.super` | Super admin | Administração global |
| `lab.noc` | User com role customizada | Dashboard, problemas, hosts e Latest data; API limitada |
| `lab.operator` | User com role **NOC Operator** | Leitura de `NOC/Linux`, reconhece/fecha problemas, mídias email + webhook de exemplo |
| `lab.mfa` | User com TOTP | Leitura de Linux e login com segundo fator |

Os direitos sobre hosts vêm dos grupos de usuários. A role restringe menus,
ações e métodos de API. Teste cada conta em uma janela privada do navegador.
O script de verificação faz logins reais e confirma leitura, limites de grupos,
proibição de escrita pelo User e restrição de API do NOC.

### Concluir o MFA no seu aplicativo

**Concluído nesta instalação em 09/10/2026:** autenticador confirmado para
`lab.mfa` e login realizado pelo usuário. Os passos a seguir ficam como referência.

1. Abra uma janela privada em http://localhost:8080.
2. Entre com `lab.mfa` e sua senha em `credentials.local.json`.
3. Cadastre o QR code no aplicativo autenticador TOTP.
4. Informe o código de seis dígitos e confirme o login.
5. Saia e entre novamente para testar o segundo fator.

O método **NOC TOTP** e o grupo **NOC MFA** estão configurados, com autenticador
vinculado e login interativo concluído nesta instalação. Os demais grupos
do laboratório estão com MFA desabilitado. LDAP/AD, SAML e Duo dependem de serviços
externos e não são necessários para estes exercícios de autenticação interna/TOTP.

## 5. Práticas de itens, macros, triggers e templates

Template criado: **NOC Linux practice**, vinculado a `linux-lab` e `linux-mint-proxy`.

| Objeto | Configuração |
|---|---|
| Item | `lab.service.up`, intervalo 10s, 1 normal / 0 indisponível |
| Item | `lab.service.errors`, intervalo 10s, 0 normal / 10 com arquivo de teste |
| Item | `lab.key.allowed`, permitido por AllowKey |
| Value map | `NOC service state`: 0 → Down; 1 → Up |
| Macro | `{$NOC.ERRORS.MAX}=5` |
| Trigger pai | `NOC: Service is down` |
| Trigger dependente | `NOC: Too many service errors`, depende da trigger pai |
| Item ativo em linux-lab | `vfs.file.size[/etc/hostname]`, enviado através de lab-proxy |

Exercício manual no Windows:

```powershell
# Gera erro, abre problema; remove erro, recupera.
docker compose exec linux-lab touch /tmp/lab-service-errors
docker compose exec linux-lab rm /tmp/lab-service-errors

# Testa a causa principal; aguarde o problema antes de gerar o erro dependente.
docker compose exec linux-lab touch /tmp/lab-service-down
docker compose exec linux-lab touch /tmp/lab-service-errors
# Limpeza:
docker compose exec linux-lab rm -f /tmp/lab-service-down /tmp/lab-service-errors
```

Para executar e validar automaticamente toda a sequência, use
`powershell -ExecutionPolicy Bypass -File .\practice-triggers.ps1`.
No Mint, após instalar o script, os mesmos arquivos em `/tmp` exercitam o host
**Linux Mint via Proxy**.

Para M04A24–A25, abra **Data collection > Templates**, selecione o template NOC,
pratique clonagem/cópia e vincule a cópia a um host de teste. Não vincule ao mesmo
host duas versões que definam chaves de item iguais.

## 6. AllowKey / DenyKey e execução como root

No Windows:

```powershell
docker compose exec zabbix-proxy zabbix_get -s linux-lab -k lab.key.allowed
docker compose exec zabbix-proxy zabbix_get -s linux-lab -k lab.key.blocked
```

Resultados esperados: `1` e `ZBX_NOTSUPPORTED: Unsupported item key.`
Essa recusa é intencional e não existe item habilitado no painel solicitando a chave bloqueada.

Para a aula do agente clássico como root:

```powershell
Get-Content -Raw .\practice-agent-root.sh | docker compose exec -T -u root linux-lab bash -s
```

O exercício inicia uma instância temporária do agente clássico em
`127.0.0.1:10060`, com `AllowRoot=1` e `User=root`, consulta `lab.uid=0` e encerra
a instância. O agente habitual do container continua como usuário `zabbix`.

## 7. Configuration syncer e utilitários

No Windows:

```powershell
docker compose exec zabbix-server zabbix_server --help
docker compose exec zabbix-server zabbix_server -R config_cache_reload
docker compose exec zabbix-proxy zabbix_proxy --help
docker compose exec zabbix-proxy zabbix_proxy -R config_cache_reload
docker compose exec linux-lab zabbix_agentd --help
docker compose exec linux-lab zabbix_agentd -t agent.ping -c /etc/zabbix/zabbix_agentd.conf
docker compose logs --tail=50 zabbix-server zabbix-proxy
```

No Mint, após instalar o proxy:

```bash
zabbix_agent2 --help
zabbix_proxy --help
sudo zabbix_proxy -R config_cache_reload -c /etc/zabbix/zabbix_proxy.conf
sudo journalctl -u zabbix-proxy -n 50 --no-pager
```

Use uma alteração de macro/intervalo e observe sincronização e logs. Nem todas
as opções de runtime do agente clássico existem no Agent 2 e vice-versa.

## 8. Tradução Oracle Linux → Mint

| Na aula Oracle Linux | Neste laboratório Mint/Ubuntu |
|---|---|
| Repositório RPM Zabbix | Pacote `.deb` correspondente à base Ubuntu do Mint |
| `dnf install` | `apt install` |
| Agent 2 via RPM | `zabbix-agent2` via repositório Ubuntu 7.0 |
| Proxy SQLite via RPM | `zabbix-proxy-sqlite3` via `apt` |
| `systemctl` / `journalctl` | Mesmos utilitários no Mint |
| `firewalld` / SELinux | Rede NAT atual; Mint pode usar UFW/AppArmor, com comandos diferentes |
| All-in-one nativo Oracle | Server + MySQL + Nginx/PHP disponíveis na stack Docker do Windows |

O objetivo funcional está disponível nesta topologia. A instalação all-in-one
por pacotes dentro do Mint é um exercício diferente: ela criaria outro server e
outro banco; não foi aplicada à VM por este script. Para estudar seus pacotes, os
equivalentes Ubuntu são `zabbix-server-mysql`, `zabbix-frontend-php`,
`zabbix-nginx-conf`, `zabbix-sql-scripts` e `mysql-server`, usando versões
compatíveis com a base Ubuntu identificada. Importação do schema, usuário do
banco, configuração PHP/Nginx e arquivos do server continuam sendo passos dessa
instalação. A VM atual já terá a porta 10051 ocupada pelo proxy nativo.

## 9. Monitoramento MySQL

Host **mysql-lab**, template **MySQL by Zabbix agent 2**, interface `zabbix-agent2`.
Macros: `{$MYSQL.DSN}=tcp://mysql:3306`, usuário `zbx_monitor` e senha do tipo secret.
Privilégios SQL: `REPLICATION CLIENT`, `PROCESS`, `SHOW DATABASES`, `SHOW VIEW`.
O banco permanece acessível pela rede Docker interna.

O timeout global do Agent 2 e do server foi ajustado para 30s para as consultas
de metadados neste ambiente local. CPU/disco e inicialização podem afetar as
primeiras amostras. O cálculo `mysql.innodb_log_file_size` consulta uma amostra de
uma hora atrás; até acumular esse histórico pode aparecer como não suportado.

## 10. Reprovisionamento e arquivos

- `complete-lab.ps1`: cria os objetos de forma reexecutável, mantendo credenciais
  geradas em `credentials.local.json`; as configurações declaradas da role NOC são reaplicadas.
- `verify-lab.ps1`: valida containers, coleta e permissões; registra `validation.local.json`.
- `verify-lab.ps1 -RequireMintProxy`: exige também comunicação e coleta do proxy nativo.
- Adicione `-RequireMfaEnrollment` para exigir o autenticador de `lab.mfa` confirmado.
- `mint/diagnose-mint.sh`: diagnóstico somente leitura da VM, servido em 8081.
- `mint/setup-mint.sh`: instalador da etapa Mint; servido em 8081.
- `practice-triggers.ps1` e `practice-agent-root.sh`: exercícios com validação.
- `create-noc-examples.ps1`: cria os exemplos por tema (roles, alerta com
  escalonamento, webhook, manutenção, dashboard, serviço/SLA); reexecutável.
- `verify-examples.ps1`: valida os 28 pontos dos exemplos.
- `test-alert-live.ps1`: gera uma falha real, confirma o alerta entregue e a
  recuperação; limpa os arquivos de teste ao final.

`docker compose down` preserva os volumes; `docker compose down -v` apaga os
bancos Docker. Após reset, reexecute `complete-lab.ps1` e vincule novamente o
autenticador da conta MFA. O SQLite do Mint fica na VM e é independente dos volumes Docker.
