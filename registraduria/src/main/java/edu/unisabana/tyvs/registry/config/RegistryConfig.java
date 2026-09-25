package edu.unisabana.tyvs.registry.config;

import edu.unisabana.tyvs.registry.application.port.out.RegistryRepositoryPort;
import edu.unisabana.tyvs.registry.application.usecase.Registry;
import edu.unisabana.tyvs.registry.infrastructure.persistence.RegistryRepository;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Cableado de la aplicacion (composition root).
 *
 * La URL JDBC se lee de una propiedad, con un valor por defecto, en vez de
 * estar escrita en el codigo. No es cosmetico: permite que cada prueba de
 * integracion use su propia base en memoria y no contamine a las demas, y
 * evita tener que declarar beans alternativos en la prueba.
 *
 * Ese ultimo punto tiene una trampa que costo un build en rojo: si una prueba
 * declara un @TestConfiguration con un @Bean llamado igual que uno de aqui
 * (el nombre del bean es el nombre del METODO), Spring aborta el arranque con
 * BeanDefinitionOverrideException. Parametrizar la URL hace innecesarios esos
 * beans duplicados.
 */
@Configuration
public class RegistryConfig {

    /**
     * Pool de conexiones (HikariCP). Reemplaza el DriverManager por operacion.
     * Tamano configurable sin recompilar: registry.pool.max-size (por defecto 20).
     *
     * OJO: NO se conecta MeterRegistry aqui a mano. Spring Boot detecta
     * automaticamente cualquier bean HikariDataSource y le engancha
     * hikaricp_connections_* por su cuenta (DataSourcePoolMetricsAutoConfiguration).
     * Intentar cablearlo manualmente crea una referencia circular: el DataSource
     * pide el MeterRegistry para configurarse, y el MeterRegistry pide el
     * DataSource para poder registrar sus metricas.
     */
    @Bean(destroyMethod = "close")
    public HikariDataSource registryDataSource(
            @Value("${registry.jdbc-url:jdbc:h2:mem:regdb;DB_CLOSE_DELAY=-1}") String jdbcUrl,
            @Value("${registry.pool.max-size:20}") int maxPoolSize) {
        HikariConfig cfg = new HikariConfig();
        cfg.setPoolName("registry-pool");
        cfg.setJdbcUrl(jdbcUrl);
        cfg.setUsername("");
        cfg.setPassword("");
        cfg.setMaximumPoolSize(maxPoolSize);
        cfg.setMinimumIdle(maxPoolSize); // pool de tamano fijo
        return new HikariDataSource(cfg);
    }

    @Bean
    public RegistryRepositoryPort registryRepositoryPort(HikariDataSource dataSource)
            throws Exception {
        RegistryRepository repo = new RegistryRepository(dataSource);
        repo.initSchema();
        return repo;
    }

    @Bean
    public Registry registry(RegistryRepositoryPort port) {
        return new Registry(port);
    }
}