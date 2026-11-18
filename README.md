# Scrap Book Liquibase

O changelog inicial da F01 instala as 24 tabelas de aplicação no schema `scrapbook`. A execução usa PostgreSQL 18, com suíte local fixada em 18.6, e Liquibase 4.33.0. As versões da suíte estão em [config/versions.json](config/versions.json).

## Estrutura e acesso

- [config/bootstrap.sql](config/bootstrap.sql) prepara o schema e as roles. O operador executa esse passo administrativo no banco novo, antes da primeira conexão do Liquibase. Configure credenciais de login por mecanismo privado.
- `scrapbook_owner` é a proprietária sem login. `scrapbook_migrator` autentica separadamente e assume a proprietária no banco provisionado. As tabelas de controle usam o schema `scrapbook`.
- `scrapbook_app` tem USAGE no schema, leitura e inserção nas tabelas de aplicação comuns e UPDATE nas tabelas mutáveis. A auditoria permite somente INSERT à aplicação. A leitura de auditoria usa a role separada `scrapbook_audit_reader`. O controle do Liquibase é restrito à proprietária e à sessão de migração.
- [db.changelog-master.yaml](db.changelog-master.yaml) inclui uma migração transacional. Os arquivos SQL criam tabelas e índices, adicionam as FKs depois das chaves candidatas, aplicam privilégios e registram uma assinatura do catálogo.

## Aplicar em laboratório

Em um PostgreSQL novo e descartável, configure o serviço de conexão administrativo e a configuração privada do Liquibase. Use a identidade migradora no Liquibase e preencha a URL JDBC do mesmo alvo preparado. Este fluxo é para o laboratório.

```sh
psql service=scrapbook_local_admin -X -v ON_ERROR_STOP=1 -f config/bootstrap.sql
liquibase --liquibase-schema-name=scrapbook validate --changelog-file=db.changelog-master.yaml --default-schema-name=scrapbook
liquibase --liquibase-schema-name=scrapbook update --changelog-file=db.changelog-master.yaml --default-schema-name=scrapbook
liquibase --liquibase-schema-name=scrapbook status --changelog-file=db.changelog-master.yaml --default-schema-name=scrapbook
```

A reaplicação verifica o estado conhecido do catálogo e preserva o histórico. Em base nova, objetos preexistentes precisam de transição explícita. Revisar o alvo, ownership, histórico e catálogo quando o Liquibase recusar o estado.

## Reverter no laboratório

Com o estado inicial como único changeset aplicado, a suíte usa `rollback-count --count=1` para exercitar a própria reversão. Conferir histórico e alvo antes de qualquer execução manual. O rollback bloqueia as tabelas durante a verificação, exige a assinatura esperada e recusa dados, objetos estranhos e dependências externas. O schema preparado, suas roles e as tabelas de controle permanecem após a reversão. Para homologação e produção, seguir o workflow manual de recuperação quando ele estiver disponível.

## Validar

```sh
python3 tests/test_baseline.py
```

A suíte cria um contêiner PostgreSQL exclusivo, publica uma porta aleatória em loopback, gera credenciais sintéticas e remove o contêiner ao final. Exercita instalação, drift, histórico, privilégios, unicidade e rollback. Usar a CLI Liquibase 4.33.0 e o Docker local.
