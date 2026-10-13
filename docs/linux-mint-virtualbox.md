# Linux Mint no VirtualBox — conexão ao Zabbix

## Configuração utilizada

Este guia descreve o primeiro caminho de coleta, direto do Mint para o server.
A ampliação com Proxy nativo, permissões, MySQL e Windows está no
[guia completo do curso](curso-mint.md).

| Componente | Configuração |
|---|---|
| VM no VirtualBox | `Linux Mint` |
| Adaptador de rede | NAT padrão do VirtualBox |
| Agente | Zabbix Agent 2, série 7.0 |
| Nome técnico no Zabbix | `linux-mint` |
| Nome visível no painel | `Linux Mint (VirtualBox)` |
| Grupos | `Linux servers`, `NOC/Linux` |
| Template | `Linux by Zabbix agent active` |
| Destino do agente | `192.168.0.9:10051` (IP LAN do Windows nesta instalação) |

```text
VM Linux Mint -> NAT VirtualBox -> Windows -> porta publicada Docker -> Zabbix server
  Agent 2                         192.168.0.9         TCP 10051
```

O alias NAT `10.0.2.2` apresentou falhas intermitentes nesta instalação. O destino
foi migrado para o IP LAN do Windows, com recuperação confirmada da coleta.
A VM permanece em NAT e o agente inicia as conexões. Se o IP do Windows mudar,
atualize o destino; não é necessário encaminhar a porta 10050 para dentro da VM.

## Parte A — executar dentro da VM Linux Mint

Estes passos já foram aplicados pelo usuário. São mantidos aqui para reprodução.

### 1. Instalar o agente 7.0

Ligue a VM e abra um terminal Bash no Mint:

```bash
# Obtém a versão Ubuntu que serve de base ao Linux Mint.
source /etc/upstream-release/lsb-release
echo "$DISTRIB_RELEASE"

wget -O /tmp/zabbix-release.deb \
"https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu${DISTRIB_RELEASE}_all.deb"

sudo dpkg -i /tmp/zabbix-release.deb
sudo apt update
sudo apt install -y zabbix-agent2
```

Execute os comandos na ordem e resolva qualquer erro antes de prosseguir. O método
acima é para Linux Mint baseado em Ubuntu, não para Linux Mint Debian Edition.

### 2. Configurar a comunicação

```bash
sudo nano /etc/zabbix/zabbix_agent2.conf
```

Ajuste as linhas existentes, sem duplicar parâmetros:

```ini
Server=127.0.0.1
ServerActive=192.168.0.9:10051
Hostname=linux-mint
```

- `Server` restringe consultas passivas ao próprio Mint.
- `ServerActive` define o destino para buscar checks ativos e enviar os resultados.
- `Hostname` precisa coincidir exatamente com o nome técnico cadastrado no Zabbix.

No Nano, salve com Ctrl+O, Enter e saia com Ctrl+X.

### 3. Habilitar e iniciar

```bash
sudo systemctl enable zabbix-agent2
sudo systemctl restart zabbix-agent2
sudo systemctl status zabbix-agent2 --no-pager
```

O status esperado é `active (running)`. Isso confirma o processo; a coleta deve
ser confirmada também no painel.

## Parte B — executar no Windows / painel Zabbix

### 1. Iniciar o laboratório

Abra o Docker Desktop em modo Linux containers. No PowerShell, dentro de
`lab-zabbix-7`:

```powershell
.\start.ps1
.\healthcheck.ps1
```

O frontend deve responder HTTP 200 em http://localhost:8080 e a porta TCP 10051
deve estar acessível. Os serviços ficam em modo desacoplado.

### 2. Cadastrar o host

**Já realizado via API nesta instalação.** Para recriar depois de apagar o banco,
entre no painel com `Admin` / `zabbix` e abra
**Data collection > Hosts > Create host**:

- Host name: `linux-mint`
- Visible name: `Linux Mint (VirtualBox)`
- Host groups: `Linux servers`
- Templates: `Linux by Zabbix agent active`
- Enabled: marcado
- Interfaces: não é necessário adicionar interface Agent para esse template ativo.

O script `configure-hosts.ps1` da stack configura `Zabbix server` e `linux-lab`.
O novo `complete-lab.ps1` também cadastra a VM externa e os demais objetos do curso.

### 3. Confirmar dados

Abra **Monitoring > Latest data** e filtre por **Linux Mint (VirtualBox)**.
Aguarde alguns minutos após iniciar o agente. Confira o horário de atualização,
`agent.ping=1`, CPU, memória e uptime. Itens têm intervalos diferentes de coleta.

Na última verificação, a API confirmou disponibilidade ativa e dados recentes
nessas métricas, sem itens habilitados não suportados para `linux-mint`.

## Diagnóstico, se a coleta parar

**Na VM:**

```bash
sudo systemctl status zabbix-agent2 --no-pager
sudo tail -n 50 /var/log/zabbix/zabbix_agent2.log
sudo journalctl -u zabbix-agent2 -n 50 --no-pager
timeout 5 bash -c 'exec 3<>/dev/tcp/192.168.0.9/10051' && echo 'TCP 10051 acessivel'
```

Se o log indicar host desconhecido, confira `Hostname=linux-mint`, cadastro
habilitado e template ativo. Se houver timeout de conexão, confira NAT, Docker
Desktop em execução, publicação da porta 10051 e regras do firewall Windows.
Não é preciso desabilitar o firewall; uma eventual regra deve permitir apenas
o tráfego necessário. A conexão já foi validada na configuração atual.

**No Windows**, dentro de `lab-zabbix-7`:

```powershell
.\healthcheck.ps1
docker compose ps
docker compose logs --tail=100 zabbix-server
```

`zabbix_get` executado pelo server não é a validação apropriada para esta VM:
ela está configurada para checks ativos e aceita checks passivos somente locais.
Mantenha Windows, Docker Desktop e VM ligados para a coleta continuar.

## O que essa configuração monitora

- `linux-mint`: o sistema Linux Mint da VM VirtualBox.
- `linux-lab`: o Ubuntu simulado em container.
- `Zabbix server`: saúde do server, Docker e métricas do ambiente Linux do Docker Desktop.

O Windows principal agora tem o serviço **Zabbix Agent** clássico instalado via
MSI e envia dados ao host `windows-host`, com template Windows ativo.
