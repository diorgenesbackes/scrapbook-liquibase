FROM eclipse-temurin:21-jdk-jammy@sha256:b2711c65970c1227197c29c46e669bfdbb137524e9da0e664703a140ec25a040 AS compiler
WORKDIR /src
COPY scripts/MigrationPreflight.java .
RUN javac --release 21 -d /out MigrationPreflight.java
RUN mkdir -m 0755 /certs
ADD --chmod=0444 --checksum=sha256:b1711d12bae51838581281e23b6cb97b1074016873b4dafc80ed14002462dd77 https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem /certs/rds-us-east-1.pem

FROM liquibase/liquibase:4.33.0@sha256:e116c935ba22b59a22165207f65c268e363269de30bb1fedacff3755c2abaa8c
WORKDIR /opt/scrapbook
COPY --from=compiler /out/ ./classes/
COPY db.changelog-master.yaml ./
COPY changelogs/ ./changelogs/
COPY config/preflight.sql config/catalog-generation.txt ./config/
COPY config/rollback-preflight.sql config/rollback-verify.sql ./config/
COPY --chmod=0555 scripts/run_fargate.sh ./run_fargate.sh
COPY --from=compiler /certs/ ./certs/
ENTRYPOINT ["/opt/scrapbook/run_fargate.sh"]
CMD []
