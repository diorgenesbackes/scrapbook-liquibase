import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
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
        } catch (SQLException error) {
            if ("P0001".equals(error.getSQLState())) {
                System.err.println(error.getMessage().lines().findFirst().orElse("Pré-validação recusada."));
            } else {
                System.err.println("Falha na pré-validação JDBC (SQLSTATE " + error.getSQLState() + ").");
            }
            System.exit(1);
        }
    }
}
