import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;

public final class MigrationPreflight {
    public static void main(String[] args) throws IOException {
        var properties = new Properties();
        properties.setProperty("user", "scrapbook_migrator");
        var password = System.getenv("LIQUIBASE_COMMAND_PASSWORD");
        if (password != null) {
            properties.setProperty("password", password);
        }

        try (var connection = DriverManager.getConnection(System.getenv("LIQUIBASE_COMMAND_URL"), properties)) {
            connection.setReadOnly(true);
            connection.setAutoCommit(false);
            try (var statement = connection.createStatement()) {
                statement.execute(Files.readString(Path.of(args[0])));
            }
            if (args.length == 2) {
                assertGeneration(connection, args[1]);
            }
        } catch (SQLException error) {
            if ("P0001".equals(error.getSQLState())) {
                System.err.println(error.getMessage().lines().findFirst().orElse("Pré-validação recusada."));
            } else {
                System.err.println("Falha na pré-validação JDBC (SQLSTATE " + error.getSQLState() + ").");
            }
            System.exit(1);
        }
    }

    private static void assertGeneration(Connection connection, String expectedGeneration) throws SQLException {
        try (var statement = connection.prepareStatement("""
            SELECT checkpoint->>'generation' = ?
                AND checkpoint->'signatures'->>(checkpoint->>'generation') = scrapbook.foundation_signature()
            FROM (
                SELECT obj_description('scrapbook.foundation_signature()'::regprocedure, 'pg_proc')::jsonb AS checkpoint
            ) AS catalog
            """)) {
            statement.setString(1, expectedGeneration);
            try (var result = statement.executeQuery()) {
                if (!result.next() || !result.getBoolean(1)) {
                    throw new SQLException("A geração ativa difere do catálogo esperado.", "P0001");
                }
            }
        }
    }
}
