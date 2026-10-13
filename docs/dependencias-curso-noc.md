# Dependências do curso Zabbix 7 — NOC

## Base desta análise

Grade fornecida: `C:\Users\joaog\Downloads\grade_do_curso_zabbix.md`.
Comparação com os arquivos do laboratório e as verificações registradas nesta
sessão. Os títulos permitem identificar os pré-requisitos principais; versões
exatas de pacotes, recursos de VM e exercícios definidos pelo instrutor devem ser
conferidos no material das aulas. Esta é uma análise técnica, não uma lista
oficial de requisitos da NOC.

**Atualização após autorização do usuário:** o ambiente foi ampliado e adaptado
para **Mint/Ubuntu**, com Proxy Docker, script de Proxy nativo no Mint, agente
Windows, monitoramento MySQL, objetos didáticos, permissões e TOTP. A execução
do script dentro da VM e o vínculo do autenticador precisam da ação do usuário.
Veja o [guia de execução](curso-mint.md). Não é necessário substituir o Mint
pelo Oracle Linux para as práticas funcionais preparadas.

## Mapeamento de dependências

| Aulas | Pré-requisitos para a prática | Situação no laboratório |
|---|---|---|
| M00–M02 | Plataforma do curso, conceitos de monitoração, arquitetura e terminologia | Sem infraestrutura adicional identificada pelos títulos |
| M03A01–A05 | Linux, rede, banco, estimativa de itens/intervalos/retenção para dimensionamento | Stack disponível; o dimensionamento é um exercício próprio, não comprovado pelo simples funcionamento |
| M03A06 | Linux, acesso sudo/root, repositório Zabbix 7.0, MySQL compatível, server, frontend, servidor web/PHP e schema | Equivalente funcional em Docker; comandos de pacotes adaptados ao Mint no guia. Segunda instalação nativa all-in-one não aplicada |
| M03A07 | Acesso ao arquivo do frontend e entendimento da conexão com BD/server | Disponível no container web, gerenciado pelo entrypoint e pelas variáveis do Compose |
| M03A08 | VirtualBox e uma VM com rede configurada | VirtualBox e Mint já utilizados |
| M04A01–A03 | Frontend, conta administrativa e hosts/itens de exemplo | Disponíveis; exercícios de cada tipo de item podem exigir alvos específicos |
| M04A04–A10 | Agente instalado, configuração, hostgroup e comunicação passiva/ativa | Agente clássico no Ubuntu container e Agent 2 no Mint/Docker disponíveis; Mint validado em modo ativo |
| M04A11 | Agente Linux e acesso administrativo para praticar execução como root | Exercício temporário validado com `practice-agent-root.sh`: agente clássico retornou UID 0 |
| M04A12–A19 | Host, itens com dados, value maps, triggers e macros; duas triggers para dependência | Template NOC, macro, value map e duas triggers preparados; problema, recuperação e dependência testados |
| M04A20 e A20-1 | Server em execução, acesso a configuração/logs/cache e mudanças no frontend | Disponível no container server |
| M04A21–A23 | Binários `zabbix_server`, `zabbix_agentd` e `zabbix_get`; acesso ao processo/configuração | Disponíveis nos containers; consultar `--help` de cada binário, pois Agent 2 e clássico têm comandos diferentes |
| M04A24–A25 | Objetos de origem, host de destino, grupos de templates e permissões para editar | Template próprio criado e vinculado; disponível como origem para praticar clonagem/cópia |
| M04A26–A28 | Zabbix Proxy 7.0, SQLite3, armazenamento próprio, registro no server e host associado ao proxy | Proxy Docker coletando; proxy Mint registrado e instalador apt entregue para execução na VM |
| M04A29–A30 | Windows, privilégio de administrador, MSI do agente 7.0, serviço configurado, host e template Windows | Agente clássico instalado via MSI, serviço automático e coleta ativa validados |
| M04A31–A32 | Agent 2 e repositório correspondente ao sistema | Agent 2 instalado no Mint; instalador adaptado para apt e base Ubuntu |
| M04A33 | MySQL acessível pelo Agent 2, plugin MySQL, conta de monitoramento, template e macros | Host mysql-lab, conta dedicada e coleta validados; cálculo de uma hora aguarda histórico |
| M04A34 | Agente, acesso ao arquivo de configuração e chaves para testar `AllowKey`/`DenyKey` | Chave permitida e bloqueada configuradas e testadas no linux-lab; incluídas no instalador Mint |
| M05A01 e A03–A07 | Hostgroups com dados, usuários/grupos de teste, roles e sessões separadas para validar permissões | Contas User/Admin/Super admin/NOC/Operator criadas; roles NOC, Operator e Maintenance admin; direitos e bloqueios testados por API e login real |
| M05A02 | Autenticação interna; diretório/IdP somente se houver prática LDAP/SAML | Interna disponível; o título não comprova necessidade de AD, LDAP ou SAML externo |
| M05A08 | Método MFA, grupo/usuário associado; para TOTP, aplicativo autenticador e relógios sincronizados | NOC TOTP configurado, autenticador de lab.mfa confirmado e login interativo concluído pelo usuário |

## Dependências e adaptações aplicadas

### 1. Adaptação do sistema usado pelo instrutor

As aulas citam **Oracle Linux**, o sistema operacional; o banco da instalação
all-in-one continua sendo **MySQL**, não Oracle Database.

O usuário optou por manter Linux Mint. Foram usados o repositório Zabbix para a
base Ubuntu correspondente e pacotes `.deb`. A correspondência de comandos está
no guia do curso. Oracle Linux 8/9 só seria necessário para reproduzir literalmente
os detalhes específicos de RPM/SELinux apresentados pelo instrutor.

Mint usa pacotes Debian/Ubuntu (`apt`); Oracle Linux usa a família RPM (`dnf`),
com diferenças de repositórios, serviços, firewall e SELinux. Docker fornece a
arquitetura funcional, mas não exercita automaticamente esses procedimentos.

### 2. Proxy com SQLite — M04A26–A28

Necessário:

- Proxy da série 7.0 e banco SQLite em arquivo persistente próprio.
- Nome do proxy igual no arquivo de configuração e no cadastro do server.
- Conectividade entre proxy e server e entre proxy e os hosts que ele monitora.
- Associar um host ao proxy e confirmar que os dados chegam por ele.
- Se o host usar checks ativos, apontar `ServerActive` para o proxy; se usar
  passivos, permitir o proxy no parâmetro `Server` do agente.

O SQLite do proxy é separado do MySQL do server. Se o proxy for colocado em um
container, pode compartilhar a bridge Docker; uma porta publicada adicional
precisa ser diferente da 10051 do server (ex.: 10052 no Windows → 10051 no proxy).
Essa adaptação cobre a função do proxy; o script Mint fornece também a prática
de instalação nativa equivalente, usando apt em vez de RPM.

### 3. Agente Windows — M04A29–A30

O Windows principal pode ser o alvo da prática. A grade menciona MSI do Zabbix
Agent antes da introdução ao Agent 2; confirme na aula qual variante é instalada.

- Instalar o MSI correspondente e configurar o serviço com permissões administrativas.
- Definir um nome de host e cadastrá-lo com template Windows adequado ao modo de coleta.
- Para checks ativos no Windows que hospeda a stack, o destino pode ser
  `127.0.0.1:10051`, pois a porta do server está publicada no próprio Windows.
- Para checks passivos, o server em container deve acessar o Windows, por exemplo
  via `host.docker.internal:10050`, com `Server` e firewall permitindo a origem real.

`10.0.2.2` é o endereço usado **dentro do Mint em NAT VirtualBox**; não deve ser
copiado automaticamente para a configuração do agente Windows.

### 4. Monitorar MySQL via Agent 2 — M04A33

O MySQL já usado pela stack pode ser o alvo. O Agent 2 na mesma bridge consegue
alcançar `mysql:3306`, sem publicar o banco no Windows.

Preparação conforme o template oficial `MySQL by Zabbix agent 2`:

- Criar conta dedicada de monitoramento, por exemplo `zbx_monitor`.
- Conceder os privilégios documentados para MySQL:
  `REPLICATION CLIENT`, `PROCESS`, `SHOW DATABASES` e `SHOW VIEW`.
- Vincular o template ao host cuja interface aponta para o Agent 2 com acesso ao banco.
- Definir `{$MYSQL.DSN}=tcp://mysql:3306`, `{$MYSQL.USER}` e `{$MYSQL.PASSWORD}`,
  ou configurar uma sessão nomeada no plugin.
- Validar `mysql.ping`, versão, uptime e estatísticas no histórico.

Ter MySQL como banco do Zabbix não significa que essas métricas MySQL estejam
sendo coletadas. O healthcheck SQL do Compose também não substitui esse monitoramento.
O template oficial usa o plugin do Agent 2 e não exige scripts externos.

### 5. Permissões e MFA — M05

Para permissões, a stack atual já fornece os componentes necessários:

1. Criar hostgroups e usuários/grupos de teste.
2. Definir acesso de leitura/escrita aos grupos de hosts e, quando aplicável,
   aos grupos de templates.
3. Associar roles dos tipos User, Admin e Super admin; testar uma role customizada.
4. Entrar com cada usuário em sessões separadas e conferir acesso efetivo.

As roles controlam ações e recursos da interface/API; permissões sobre os objetos
são configuradas nos grupos de usuários. É necessário testar ambos.

Para MFA com **TOTP**, basta configurar o método no Zabbix, associá-lo ao grupo
de usuários, cadastrar o autenticador e testar o login. Relógios devem estar
sincronizados. Se a aula usar **Duo**, haverá dependência da conta/integração Duo.
O título da aula não especifica qual método o instrutor usa.

LDAP/AD e SAML exigem serviços externos apenas se esses métodos forem efetivamente
praticados em M05A02; não são pré-requisitos para permissões locais e TOTP.

## Ordem de dependências para estudar

```text
Conceitos M01–M02
  -> Arquitetura e instalação M03
     -> Hostgroups + agentes + coleta M04A04–A10
        -> Itens -> value maps / triggers -> dependências de triggers / macros
        -> Cópia de objetos -> templates M04A24–A25
           -> Proxy M04A26–A28
           -> Agente Windows + template M04A29–A30
           -> Agent 2 + MySQL M04A31–A33
        -> Restrição de chaves M04A34
     -> Grupos de hosts + usuários/grupos + roles M05A01–A07
        -> MFA M05A08
```

Proxy, Windows e MySQL são frentes que podem ser praticadas independentemente
depois da base de agentes/templates. **O Módulo 5 não depende de concluir o Proxy**:
as práticas de permissões locais podem começar com os hosts já existentes.

## Itens não suportados já encontrados

Os 13 itens não suportados no host `Zabbix server` estão detalhados em
[estado e pendências](estado-e-pendencias.md). IPMI, Java/JMX, traps SNMP,
coleta VMware, relatórios agendados e conectores não aparecem como práticas
obrigatórias explícitas nesta grade. A presença desses itens em templates não
torna a instalação desses componentes uma dependência do curso.

Os 13 itens foram desabilitados somente no host de infraestrutura na ampliação.
As dependências entre triggers da aula **M04A18** são relações configuradas entre
triggers para controlar problemas dependentes; não significam instalar mais serviços.

## Referências

- Grade enviada pelo usuário: `grade_do_curso_zabbix.md`.
- [Template oficial MySQL / Agent 2, série 7.0](https://github.com/zabbix/zabbix/blob/release/7.0/templates/db/mysql_agent2/README.md).
- [MFA no Zabbix 7.0: TOTP e Duo](https://www.zabbix.com/documentation/7.0/en/manual/web_interface/frontend_sections/users/authentication/mfa).
- Configuração local: `docker-compose.yml`, `linux-host/zabbix_agentd.conf` e
  [guia de conexão do Mint](linux-mint-virtualbox.md).
