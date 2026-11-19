# Scrap Book Liquibase

O changelog inicial da F01 instala as 24 tabelas de aplicação no schema `scrapbook`. A execução usa PostgreSQL 18, com suíte local fixada em 18.6, e Liquibase 4.33.0. As versões da suíte estão em [config/versions.json](config/versions.json).

## Estrutura e acesso

- [config/bootstrap.sql](config/bootstrap.sql) prepara o schema e as roles. O operador executa esse passo administrativo no banco novo, antes da primeira conexão do Liquibase. Configure credenciais de login por mecanismo privado. O preparo recusa associações de roles e privilégios padrão incompatíveis, inclusive defaults no schema ou para PUBLIC.
- `scrapbook_owner` é a proprietária sem login. `scrapbook_migrator` autentica separadamente e assume a proprietária no banco provisionado. As tabelas de controle usam o schema `scrapbook`.
- `scrapbook_app` tem USAGE no schema, leitura e inserção nas tabelas de aplicação comuns e UPDATE nas tabelas mutáveis. A auditoria permite somente INSERT à aplicação. A leitura de auditoria usa a role separada `scrapbook_audit_reader`. A sessão de migração acessa os controles como proprietária. A pré-validação recusa grants de tabela ou coluna nesses controles para outros beneficiários, inclusive PUBLIC.
- [scripts/migrate.py](scripts/migrate.py) verifica o alvo, os defaults e os controles preexistentes por JDBC antes de iniciar a CLI. A pré-validação usa uma conexão somente leitura e o JDK e driver PostgreSQL da instalação do Liquibase. Se a detecção por `liquibase --version` não informar os caminhos, forneça `JAVA_HOME` e `LIQUIBASE_HOME`.
- [db.changelog-master.yaml](db.changelog-master.yaml) inclui uma migração transacional. Os arquivos SQL criam tabelas e índices, adicionam as FKs depois das chaves candidatas, aplicam privilégios e registram uma assinatura do catálogo.

## Aplicar em laboratório

Em um PostgreSQL novo e descartável, configure o serviço de conexão administrativo. Defina `LIQUIBASE_COMMAND_URL` com a URL JDBC sem credenciais e `LIQUIBASE_COMMAND_PASSWORD` com o segredo da identidade migradora, usando configuração privada. Mantenha o provisionamento de roles e os comandos de migração na mesma janela de operação, sem alterações concorrentes de privilégios.

```sh
psql service=scrapbook_local_admin -X -v ON_ERROR_STOP=1 -f config/bootstrap.sql
python3 scripts/migrate.py validate
python3 scripts/migrate.py update-sql
python3 scripts/migrate.py update
python3 scripts/migrate.py status
```

A instalação inicial exige histórico vazio nos controles do Liquibase e ausência de objetos de aplicação no schema. Um catálogo ou histórico preexistente exige uma transição explícita. A reaplicação verifica o estado conhecido do catálogo e preserva o histórico. Revisar o alvo, ownership, histórico e catálogo quando o Liquibase recusar o estado.

## Evoluir o catálogo

Cada changeset que altera o catálogo deve terminar com `SELECT scrapbook.checkpoint_catalog('id-anterior', 'id-do-changeset')` na mesma transação do DDL. Use IDs de geração únicos e registrados pelo autor `scrapbook`. A função preserva a assinatura original de cada geração e confere os privilégios efetivos de runtime. O `update` valida o catálogo efetivo contra a assinatura da geração ativa e verifica se ela consta no histórico.

No rollback de uma evolução, confira primeiro se a geração e a assinatura correspondem ao changeset que será revertido. Desfaça o DDL e chame `scrapbook.checkpoint_catalog('id-do-changeset', 'id-anterior', TRUE)` na mesma transação. A chamada exige a assinatura histórica da geração de destino e recusa uma reversão incompleta. A assinatura cobre a persistência das relações e os parâmetros de definição das sequências `IDENTITY`, como incremento e limites. O avanço normal da sequência na inserção é independente dessa comparação.

## Reverter no laboratório

Com o estado inicial como único changeset aplicado, a suíte usa `python3 scripts/migrate.py rollback-count --count=1` para exercitar a própria reversão. Conferir histórico e alvo antes de qualquer execução manual. O rollback bloqueia as tabelas durante a verificação, exige a assinatura esperada e recusa dados, objetos estranhos e dependências externas. O schema preparado, suas roles e as tabelas de controle permanecem após a reversão. Para homologação e produção, seguir o workflow manual de recuperação quando ele estiver disponível.

## Validar

```sh
python3 tests/test_baseline.py
```

A suíte cria um contêiner PostgreSQL exclusivo, publica uma porta aleatória em loopback, gera credenciais sintéticas e remove o contêiner ao final. Exercita instalação, drift, histórico, privilégios, unicidade e rollback. Usar a CLI Liquibase 4.33.0 e o Docker local.
