CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE billing_period AS ENUM ('monthly', 'annual');

CREATE TYPE subscription_status AS ENUM ('trial', 'active', 'suspended', 'cancelled', 'expired'); 

CREATE TYPE payment_method AS ENUM ('credit_card','debit_card', 'bank_transfer', 'paypal', 'cash', 'google_pay', 'gtripe', 'other');

CREATE TYPE bill_status AS ENUM ('paid', 'pending', 'overdue', 'cancelled');

CREATE TYPE platform_users AS ENUM ('anthony','superadmin', 'admin', 'tecnico', 'soporte');
CREATE TYPE gas_unit AS ENUM ('galones', 'litros');
CREATE TYPE modules AS ENUM ('rutas','inventario','transporte','ventas', 'entregas', 'transferencias');
-- =====================================================
-- NIVEL PLATAFORMA (SIN empresa_id)
-- =====================================================

-- Tabla: planes_suscripcion
-- Planes disponibles en la plataforma
CREATE TABLE planes_suscripcion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    precio_mensual DECIMAL(10,2) NOT NULL,
    precio_anual DECIMAL(10,2),
    -- Límites del plan
    max_sucursales INTEGER,
    max_vehiculos INTEGER,
    max_usuarios INTEGER,
    max_storage_mb INTEGER,
    retencion_historico_dias INTEGER, -- NULL = ilimitado
    -- Características
    permite_multisucursal BOOLEAN DEFAULT TRUE,
    permite_api_access BOOLEAN DEFAULT FALSE,
    permite_exportacion_masiva BOOLEAN DEFAULT TRUE,
    permite_reportes_avanzados BOOLEAN DEFAULT FALSE,
    soporte_prioritario BOOLEAN DEFAULT FALSE,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE planes_suscripcion IS 'Planes de suscripción disponibles en la plataforma';



CREATE TABLE empresa (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Información básica
    nombre VARCHAR(200) NOT NULL,
    razon_social VARCHAR(300),
    rfc_nit VARCHAR(50),
    subdominio VARCHAR(100) UNIQUE NOT NULL,
    -- Contacto
    email_contacto VARCHAR(255) NOT NULL,
    telefono_contacto VARCHAR(50),
    -- Branding
    logo_url TEXT,
    color_primario VARCHAR(7), -- Hex color
    color_secundario VARCHAR(7),
    color_acento VARCHAR(7),
    -- Configuración
    zona_horaria VARCHAR(50) DEFAULT 'America/Guatemala',
    idioma VARCHAR(10) DEFAULT 'es',
    moneda VARCHAR(10) DEFAULT 'GTQ',
    -- Suscripción actual
    plan_id UUID REFERENCES planes_suscripcion(id),
    fecha_inicio_suscripcion DATE,
    fecha_fin_suscripcion DATE,
    estado_suscripcion VARCHAR(50) DEFAULT 'trial', -- trial, active, suspended, cancelled
    -- Autenticación
    requiere_2fa BOOLEAN DEFAULT FALSE,
    permite_login_google BOOLEAN DEFAULT FALSE,
    permite_login_microsoft BOOLEAN DEFAULT FALSE,
    -- Límites de uso actuales
    uso_sucursales INTEGER DEFAULT 0,
    uso_vehiculos INTEGER DEFAULT 0,
    uso_usuarios INTEGER DEFAULT 0,
    uso_storage_mb DECIMAL(10,2) DEFAULT 0,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    bloqueado BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE empresa IS 'Empresas registradas en la plataforma';
CREATE INDEX idx_empresa_subdominio ON empresa(subdominio) WHERE deleted_at IS NULL;
CREATE INDEX idx_empresa_activo ON empresa(activo, deleted_at) WHERE deleted_at IS NULL;

CREATE TABLE bloqueo(
    id SERIAL PRIMARY KEY,
    empresa_id UUID REFERENCES empresa(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    motivo TEXT

)



-- Tabla: suscripciones
-- Historial de suscripciones de cada empresa
CREATE TABLE suscripcion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES planes_suscripcion(id),
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE,
    precio_pagado DECIMAL(10,2) NOT NULL,
    periodo_facturacion billing_period NOT NULL, -- monthly, annual
    estado  subscription_status, -- active, expired, cancelled
    -- Información de pago
    metodo_pago payment_method,-- credit_card, bank_transfer, paypal
    referencia_pago VARCHAR(200),
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE suscripcion IS 'Historial de suscripciones de empresas';
CREATE INDEX idx_suscripciones_empresa ON suscripcion(empresa_id, estado);
CREATE INDEX idx_suscripciones_fechas ON suscripcion(fecha_inicio, fecha_fin);

CREATE TABLE facturacion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    suscripcion_id UUID REFERENCES suscripcion(id),
    numero_factura VARCHAR(100) UNIQUE NOT NULL,
    fecha_emision DATE NOT NULL,
    fecha_vencimiento DATE NOT NULL,
    -- Montos
    subtotal DECIMAL(10,2) NOT NULL,
    impuestos DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    -- Estado
    estado bill_status DEFAULT 'pending', -- pending, paid, overdue, cancelled
    fecha_pago TIMESTAMP,
    metodo_pago VARCHAR(50),
    referencia_pago VARCHAR(200),
    -- Archivo
    pdf_url TEXT,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE facturacion IS 'Facturas emitidas a empresas';
CREATE INDEX idx_facturacion_empresa ON facturacion(empresa_id, estado);
CREATE INDEX idx_facturacion_estado ON facturacion(estado, fecha_vencimiento);


CREATE TABLE usuario_plataforma (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre_completo VARCHAR(200) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    rol platform_users NOT NULL, -- superadmin, admin, tecnico, soporte
    -- Permisos específicos
    puede_ver_todas_empresas BOOLEAN DEFAULT FALSE,
    puede_modificar_planes BOOLEAN DEFAULT FALSE,
    puede_acceder_base_datos BOOLEAN DEFAULT FALSE,
    puede_gestionar_facturacion BOOLEAN DEFAULT FALSE,
    -- Seguridad
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret TEXT,
    ultimo_acceso TIMESTAMP,
    ip_ultimo_acceso INET,
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE usuario_plataforma IS 'Usuarios del equipo de la plataforma';
CREATE INDEX idx_usuarios_plataforma_email ON usuario_plataforma(email) WHERE deleted_at IS NULL;

CREATE TABLE asignaciones_soporte (
    id SERIAL PRIMARY KEY,
    usuario_plataforma_id UUID NOT NULL REFERENCES usuario_plataforma(id) ON DELETE CASCADE,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    fecha_asignacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_fin TIMESTAMP,
    activo BOOLEAN DEFAULT TRUE,
    UNIQUE(usuario_plataforma_id, empresa_id, activo)
);


COMMENT ON TABLE asignaciones_soporte IS 'Asignación de técnicos a empresas específicas';
CREATE INDEX idx_asignaciones_empresa ON asignaciones_soporte(empresa_id, activo);
CREATE INDEX idx_asignaciones_usuario ON asignaciones_soporte(usuario_plataforma_id, activo);




CREATE TABLE logs_acceso_plataforma (
    id BIGSERIAL PRIMARY KEY,
    usuario_plataforma_id UUID REFERENCES usuario_plataforma(id),
    empresa_accedida_id UUID REFERENCES empresa(id),
    accion VARCHAR(200) NOT NULL,
    detalles JSONB,
    ip_address INET,
    user_agent TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


COMMENT ON TABLE logs_acceso_plataforma IS 'Auditoría de accesos del equipo de plataforma';
CREATE INDEX idx_logs_plataforma_usuario ON logs_acceso_plataforma(usuario_plataforma_id, timestamp DESC);
CREATE INDEX idx_logs_plataforma_empresa ON logs_acceso_plataforma(empresa_accedida_id, timestamp DESC);

CREATE TABLE onboarding_empresa (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    -- Pasos completados
    paso_registro_completado BOOLEAN DEFAULT TRUE,
    paso_configuracion_basica BOOLEAN DEFAULT FALSE,
    paso_primera_sucursal BOOLEAN DEFAULT FALSE,
    paso_primer_vehiculo BOOLEAN DEFAULT FALSE,
    paso_primer_usuario BOOLEAN DEFAULT FALSE,
    paso_primer_producto BOOLEAN DEFAULT FALSE,
    paso_primera_ruta BOOLEAN DEFAULT FALSE,
    paso_tour_completado BOOLEAN DEFAULT FALSE,
    -- Fechas de completado
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_config_basica TIMESTAMP,
    fecha_primera_sucursal TIMESTAMP,
    fecha_primer_vehiculo TIMESTAMP,
    fecha_primer_usuario TIMESTAMP,
    fecha_primer_producto TIMESTAMP,
    fecha_primera_ruta TIMESTAMP,
    fecha_tour_completado TIMESTAMP,
    -- Estado general
    onboarding_completado BOOLEAN DEFAULT FALSE,
    fecha_completado TIMESTAMP,
    -- Asistencia
    requiere_asistencia BOOLEAN DEFAULT FALSE,
    notas_asistencia TEXT,
    asignado_a UUID REFERENCES usuario_plataforma(id),
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id)
);

COMMENT ON TABLE onboarding_empresa IS 'Seguimiento del proceso de onboarding de nuevas empresas';
CREATE INDEX idx_onboarding_incompleto ON onboarding_empresa(empresa_id) WHERE onboarding_completado = FALSE;

CREATE TABLE tipos_vehiculos_predefinidos (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    capacidad_peso_kg_sugerida DECIMAL(10,2),
    capacidad_volumen_m3_sugerida DECIMAL(10,2),
    icono_url TEXT,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE tipos_vehiculos_predefinidos IS 'Catálogo base de tipos de vehículos';

CREATE TABLE categorias_productos_predefinidas (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    icono_url TEXT,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE categorias_productos_predefinidas IS 'Catálogo base de categorías de productos';

CREATE TABLE motivos_justificacion_predefinidos (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    tipo VARCHAR(50) NOT NULL, -- parada_omitida, desviacion, retraso, cambio_inventario
    requiere_foto BOOLEAN DEFAULT FALSE,
    requiere_descripcion BOOLEAN DEFAULT TRUE,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE motivos_justificacion_predefinidos IS 'Catálogo base de motivos de justificación';

CREATE TABLE configuraciones_empresa (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    -- Configuración de tracking GPS
    frecuencia_gps_vehiculo_pequeno_segundos INTEGER DEFAULT 30,
    frecuencia_gps_vehiculo_mediano_segundos INTEGER DEFAULT 60,
    frecuencia_gps_vehiculo_grande_segundos INTEGER DEFAULT 120,
    -- Configuración de alertas
    distancia_desviacion_metros DECIMAL(10,2) DEFAULT 10,
    --define a que distancia del destino se envia la notificación de proximidad al conductor
    distancia_proximidad_parada_metros DECIMAL(10,2) DEFAULT 100,
    --define el margen que tiene el conductor en minutos para comenzar su viaje.
    margen_inicio_ruta_minutos INTEGER DEFAULT 30,
    --define el margen que tiene el conductor en minutos para terminar su viaje.
    margen_fin_ruta_minutos INTEGER DEFAULT 30,
    -- Configuración de devoluciones
    dias_limite_devolucion INTEGER DEFAULT 7,
    requiere_foto_devolucion BOOLEAN DEFAULT TRUE,
    requiere_justificacion_devolucion BOOLEAN DEFAULT TRUE,
    -- Configuración de inventario
    alerta_productos_vencimiento_dias INTEGER DEFAULT 14,
    permite_ventas_parciales BOOLEAN DEFAULT TRUE,
    -- Configuración de combustible
    tipo_medida_combustible gas_unit DEFAULT 'galones', -- galones, litros
    -- Módulos activos
    modulo_ventas_activo BOOLEAN DEFAULT TRUE,
    modulo_entregas_activo BOOLEAN DEFAULT TRUE,
    modulo_exploracion_activo BOOLEAN DEFAULT TRUE,
    modulo_transferencias_activo BOOLEAN DEFAULT TRUE,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id)
);

COMMENT ON TABLE configuraciones_empresa IS 'Configuraciones específicas por empresa';


CREATE TABLE nivel_jerarquico (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE nivel_jerarquico IS 'Niveles jerarquicos contemplados para las distintas empresas';

CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    nivel_jerarquico_id INTEGER REFERENCES nivel_jerarquico(id) NOT NULL, -- 1=Dueño, 2=Admin, 3=Supervisor, 4=Conductor, 5=Ayudante
    es_rol_sistema BOOLEAN DEFAULT FALSE, -- No se puede eliminar
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, nombre)
);

COMMENT ON TABLE roles IS 'Roles configurables por empresa';
CREATE INDEX idx_roles_empresa ON roles(empresa_id, activo) WHERE deleted_at IS NULL;



CREATE TABLE permisos (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(100) NOT NULL UNIQUE,
    nombre VARCHAR(200) NOT NULL,
    descripcion TEXT,
    modulo modules NOT NULL, -- rutas, inventario, usuarios, reportes, etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE permisos IS 'Catálogo de permisos del sistema';

CREATE TABLE roles_permisos (
    id SERIAL PRIMARY KEY,
    rol_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permiso_id INTEGER NOT NULL REFERENCES permisos(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(rol_id, permiso_id)
);

COMMENT ON TABLE roles_permisos IS 'Permisos asignados a roles';
CREATE INDEX idx_roles_permisos_rol ON roles_permisos(rol_id);


CREATE TABLE usuario (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    rol_id INTEGER NOT NULL REFERENCES roles(id),
    -- Información personal
    nombre_completo VARCHAR(200) NOT NULL,
    email VARCHAR(255) NOT NULL,
    telefono VARCHAR(20),
    fecha_nacimiento DATE,
    -- Autenticación
    password_hash TEXT NOT NULL,
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret TEXT,
    backup_codes JSONB,
    -- Información laboral
    numero_empleado VARCHAR(50),
    fecha_contratacion DATE,
    licencia_conducir VARCHAR(100),
    fecha_vencimiento_licencia DATE,
    -- Asignación
    sucursal_principal_id INTEGER, -- Se referencia después
    -- Configuración personal
    preferencias JSONB DEFAULT '{}',
    -- Seguridad
    ultimo_acceso TIMESTAMP,
    ip_ultimo_acceso INET,
    intentos_fallidos_login INTEGER DEFAULT 0,
    bloqueado_hasta TIMESTAMP,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, email)
);
