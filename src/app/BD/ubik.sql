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

CREATE TYPE fuel_type AS ENUM ('gasolina','diesel','electrico', 'hibrido_gasolina', 'hibrido_diesel');
-- =====================================================
-- NIVEL PLATAFORMA (SIN empresa_id)
-- =====================================================

-- Tabla: planes_suscripcion
-- Planes disponibles en la plataforma
--1
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


--2
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

--3
CREATE TABLE bloqueo(
    id SERIAL PRIMARY KEY,
    empresa_id UUID REFERENCES empresa(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    motivo TEXT

)



-- Tabla: suscripciones
-- Historial de suscripciones de cada empresa
--4
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
--5
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

--6
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
--7
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



--8
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

--8
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

--9
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

--10
CREATE TABLE categorias_productos_predefinidas (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    icono_url TEXT,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE categorias_productos_predefinidas IS 'Catálogo base de categorías de productos';

--11
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

--12
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

--13
CREATE TABLE nivel_jerarquico (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE nivel_jerarquico IS 'Niveles jerarquicos contemplados para las distintas empresas';
--14
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


--15
CREATE TABLE permisos (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(100) NOT NULL UNIQUE,
    nombre VARCHAR(200) NOT NULL,
    descripcion TEXT,
    modulo modules NOT NULL, -- rutas, inventario, usuarios, reportes, etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE permisos IS 'Catálogo de permisos del sistema';

--16
CREATE TABLE roles_permisos (
    id SERIAL PRIMARY KEY,
    rol_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permiso_id INTEGER NOT NULL REFERENCES permisos(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(rol_id, permiso_id)
);

COMMENT ON TABLE roles_permisos IS 'Permisos asignados a roles';
CREATE INDEX idx_roles_permisos_rol ON roles_permisos(rol_id);

--17
CREATE TABLE usuario (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
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
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    deleted_by_usuario INTEGER REFERENCES usuario(id),
    deleted_by_plataforma UUID REFERENCES usuario_plataforma(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, email)
);

COMMENT ON TABLE usuario IS 'Usuarios de empresas (conductores, supervisores, admins)';
CREATE INDEX idx_usuarios_empresa ON usuario(empresa_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_usuarios_email ON usuario(empresa_id, email) WHERE deleted_at IS NULL;
CREATE INDEX idx_usuarios_rol ON usuario(rol_id, activo) WHERE deleted_at IS NULL;

--18
CREATE TABLE tipos_vehiculos (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    basado_en_predefinido_id INTEGER REFERENCES tipos_vehiculos_predefinidos(id),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    capacidad_peso_kg DECIMAL(10,2),
    capacidad_volumen_m3 DECIMAL(10,2),
    icono_url TEXT,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, nombre)
);


COMMENT ON TABLE tipos_vehiculos IS 'Tipos de vehículos configurables por empresa';
CREATE INDEX idx_tipos_vehiculos_empresa ON tipos_vehiculos(empresa_id, activo) WHERE deleted_at IS NULL;

--19
CREATE TABLE categorias_productos (
    id BIGSERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    basado_en_predefinido_id INTEGER REFERENCES categorias_productos_predefinidas(id),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    icono_url TEXT,
    padre_id INTEGER REFERENCES categorias_productos(id), -- Para subcategorías
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_by_usuario INTEGER REFERENCES usuario(id),
    deleted_by_plataforma UUID REFERENCES usuario_plataforma(id),
    UNIQUE(empresa_id, nombre)
);

COMMENT ON TABLE categorias_productos IS 'Categorías de productos configurables por empresa';
CREATE INDEX idx_categorias_empresa ON categorias_productos(empresa_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_categorias_padre ON categorias_productos(padre_id);


--20
CREATE TABLE motivo_justificacion (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    basado_en_predefinido_id INTEGER REFERENCES motivos_justificacion_predefinidos(id),
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    tipo VARCHAR(50) NOT NULL, -- parada_omitida, desviacion, retraso, cambio_inventario, etc.
    requiere_foto BOOLEAN DEFAULT FALSE,
    requiere_descripcion BOOLEAN DEFAULT TRUE,
    requiere_autorizacion BOOLEAN DEFAULT FALSE, -- Si requiere aprobación de supervisor/admin
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, nombre, tipo)
);


COMMENT ON TABLE motivo_justificacion IS 'Motivos de justificación configurables por empresa';
CREATE INDEX idx_motivos_empresa ON motivo_justificacion(empresa_id, tipo, activo) WHERE deleted_at IS NULL;



--21

-- Tabla: tipos_rutas
-- Tipos de rutas configurables por empresa
CREATE TABLE tipo_ruta (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    codigo VARCHAR(50) NOT NULL, -- exploracion, entrega, venta, mixta, reabastecimiento
    permite_ventas BOOLEAN DEFAULT TRUE,
    permite_entregas BOOLEAN DEFAULT TRUE,
    permite_exploracion BOOLEAN DEFAULT FALSE,
    requiere_inventario_inicial BOOLEAN DEFAULT TRUE,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, codigo),
    created_by_usuario INTEGER REFERENCES usuario(id),
    deleted_by_usuario INTEGER REFERENCES usuario(id),
    deleted_by_plataforma UUID REFERENCES usuario_plataforma(id)
);
COMMENT ON TABLE tipo_ruta IS 'Tipos de rutas configurables por empresa';
CREATE INDEX idx_tipos_rutas_empresa ON tipo_ruta(empresa_id, activo) WHERE deleted_at IS NULL;

-- =====================================================
-- NIVEL EMPRESA - ESTRUCTURA ORGANIZACIONAL
-- =====================================================

-- Tabla: sucursales

--22
CREATE TABLE pais(
    id BIGINT PRIMARY KEY,
    codigo_iso_alfa2 CHAR(2), --US, MX, GT
    codigo_iso_alfa3 CHAR(3),-- USA, MEX, ESP
    nombre_es VARCHAR(100),
    nombre_en VARCHAR(100),
    codigo_telefonico VARCHAR (10),
    codigo_moneda CHAR(3),
    activo BOOLEAN

);

--23
 
CREATE TABLE departamento (
    id SERIAL PRIMARY KEY,
    pais_id INTEGER REFERENCES pais(id) NOT NULL,
    nombre TEXT NOT NULL
);

--24
CREATE TABLE municipio (
    id SERIAL PRIMARY KEY,
    departamento_id INTEGER REFERENCES departamento(ID) NOT NULL,
    nombre TEXT NOT NULL,
    codigo_postal VARCHAR(10) NOT NULL
);

--25
CREATE TABLE sucursal (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    nombre VARCHAR(200) NOT NULL,
    codigo VARCHAR(50) NOT NULL,
    -- Ubicación
    direccion TEXT,
    municipio_id INTEGER REFERENCES municipio(id),
    codigo_postal VARCHAR(20),
    ubicacion GEOGRAPHY(POINT, 4326),
    area_cobertura GEOGRAPHY(POLYGON, 4326), -- Área que cubre esta sucursal
    -- Contacto
    telefono VARCHAR(50),
    email VARCHAR(255),
    -- Configuración
    es_casa_matriz BOOLEAN DEFAULT FALSE,
    es_bodega BOOLEAN DEFAULT FALSE, -- Almacén intermedio
    -- Horarios (JSONB flexible)
    horarios JSONB, -- {lunes: {abre: "08:00", cierra: "18:00"}, ...}
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, codigo)
);

COMMENT ON TABLE sucursales IS 'Sucursales y bodegas de cada empresa';
CREATE INDEX idx_sucursales_empresa ON sucursales(empresa_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_sucursales_ubicacion ON sucursales USING GIST(ubicacion) WHERE deleted_at IS NULL;
CREATE INDEX idx_sucursales_area ON sucursales USING GIST(area_cobertura) WHERE deleted_at IS NULL AND area_cobertura IS NOT NULL;

-- Agregar FK a usuarios que faltaba
ALTER TABLE usuarios ADD CONSTRAINT fk_usuarios_sucursal 
    FOREIGN KEY (sucursal_principal_id) REFERENCES sucursales(id);


---######### HORARIOS #######

-- 1. Catálogo Maestro de Festivos (Nivel Plataforma)
-- Sirve para copiar festivos a las empresas automáticamente
--26
CREATE TABLE plantillas_festivos_globales (
    id SERIAL PRIMARY KEY,
    pais_id BIGINT REFERENCES pais(id) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    dia INTEGER NOT NULL CHECK (dia BETWEEN 1 AND 31),
    mes INTEGER NOT NULL CHECK (mes BETWEEN 1 AND 12),
    es_irrenunciable BOOLEAN DEFAULT TRUE,
    activo BOOLEAN DEFAULT TRUE,
    UNIQUE(pais_id, mes, dia)
);

-- 2. Festivos por Empresa (Instancia Local)
-- Aquí se copian los globales y la empresa agrega los suyos
--27
CREATE TABLE dias_festivos (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL,
    fecha DATE NOT NULL,
    es_laborable BOOLEAN DEFAULT FALSE, -- Si es TRUE, se paga extra pero se trabaja
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, fecha)
);

-- 3. Definición de Turnos (Bloques de tiempo)
-- Define CÓMO es un turno, no CUÁNDO oc-- 3. Turnos (Mejorado para detectar cruce de día)
--28
CREATE TABLE turnos_trabajo (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    -- Si hora_fin < hora_inicio, el sistema asume que cruza medianoche
    minutos_descanso INTEGER DEFAULT 60,
    margen_entrada_minutos INTEGER DEFAULT 15,
    color_identificador VARCHAR(7),
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Cabecera del Patrón de Horario
-- Ej: "Horario Administrativo (Lun-Vie)" o "Rotación Guardias (Mensual)"
--29
CREATE TABLE patrones_horarios (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    nombre VARCHAR(150) NOT NULL,
    tipo_ciclo VARCHAR(20) NOT NULL CHECK (tipo_ciclo IN ('semanal', 'mensual', 'dias_n')),    
    cantidad_dias_ciclo INTEGER, 
    fecha_base_rotacion DATE, 
    descripcion TEXT,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. Detalles del Patrón (La repetición)
-- Define qué turno toca cada día del ciclo
-- 5. Detalles Patrón (CORREGIDO: Límite de días eliminado)

--30
CREATE TABLE detalles_patron_horario (
    id SERIAL PRIMARY KEY,
    patron_horario_id INTEGER NOT NULL REFERENCES patrones_horarios(id) ON DELETE CASCADE,
    turno_trabajo_id INTEGER REFERENCES turnos_trabajo(id),
    
    -- CORRECCIÓN: Quitamos el límite de 31 para soportar rotaciones largas (dias_n)
    dia_numero INTEGER NOT NULL CHECK (dia_numero > 0),
    
    es_descanso BOOLEAN DEFAULT FALSE,
    UNIQUE(patron_horario_id, dia_numero)
);

--31
CREATE TABLE asignaciones_horario_usuario (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    usuario_id INTEGER NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    patron_horario_id INTEGER NOT NULL REFERENCES patrones_horarios(id),
    
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE, 
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
    
    -- CORRECCIÓN PRO: Evita que asignes 2 horarios al mismo usuario el mismo día
    EXCLUDE USING GIST (
        usuario_id WITH =, 
        DATERANGE(fecha_inicio, COALESCE(fecha_fin, '2999-12-31'), '[]') WITH &&
    )
);
CREATE INDEX idx_asignacion_usuario ON asignaciones_horario_usuario(usuario_id, fecha_inicio);

-- 7. Excepciones de Horario (Overrides)
-- Para días específicos que se salen del patrón (cambio de turno, permiso, falta)

--32
CREATE TABLE excepciones_horario (
    id SERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    usuario_id INTEGER NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    fecha DATE NOT NULL,
    
    tipo VARCHAR(50) NOT NULL, 
    turno_temporal_id INTEGER REFERENCES turnos_trabajo(id),
    
    -- CORRECCIÓN PRO: Permisos por horas (llegadas tarde, citas médicas)
    es_parcial BOOLEAN DEFAULT FALSE,
    horas_a_descontar DECIMAL(5,2) DEFAULT 0,
    es_con_goce_sueldo BOOLEAN DEFAULT FALSE,
    
    observaciones TEXT,
    aprobado_por INTEGER REFERENCES usuario(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(usuario_id, fecha)
);

-- 8. Registro de Asistencia (Time Tracking)
-- El fichaje real

--33
CREATE TABLE registro_asistencia (
    id BIGSERIAL PRIMARY KEY,
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    usuario_id INTEGER NOT NULL REFERENCES usuario(id),
    
    -- CORRECCIÓN: Fecha contable para separar el día de pago del día real
    fecha_contable DATE NOT NULL, 
    turno_asignado_id INTEGER REFERENCES turnos_trabajo(id),
    
    entrada_real TIMESTAMP,
    salida_real TIMESTAMP,
    
    -- CORRECCIÓN PRO: JSONB para múltiples descansos (esencial para choferes)
    -- Estructura: [{"inicio": "10:00", "fin": "10:15", "tipo": "baño"}, {"inicio": "13:00", "fin": "14:00", "tipo": "comida"}]
    descansos_log JSONB DEFAULT '[]',
    total_minutos_descanso INTEGER DEFAULT 0,
    
    ubicacion_entrada GEOGRAPHY(POINT, 4326),
    ubicacion_salida GEOGRAPHY(POINT, 4326),
    
    horas_normales DECIMAL(5,2),
    horas_extras DECIMAL(5,2),
    horas_nocturnas DECIMAL(5,2), -- Importante para pago diferencial
    minutos_tardia INTEGER,
    
    estado VARCHAR(20) DEFAULT 'abierto',
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
--#####FIN SECCION HORARIOS#######
-- Tabla: vehiculos
--34
CREATE TABLE vehiculos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    sucursal_actual_id UUID REFERENCES sucursales(id), -- Corregido a plural según tu esquema anterior
    tipo_vehiculo_id INTEGER NOT NULL REFERENCES tipos_vehiculos(id),
    
    -- Identificación
    placa VARCHAR(20) NOT NULL, -- 50 es mucho para placa
    marca VARCHAR(100),
    modelo VARCHAR(100),
    anio INTEGER,
    color VARCHAR(50),
    numero_economico VARCHAR(50), -- ID interno de la empresa (Ej: "Unidad-05")
    vin VARCHAR(100), -- Número de serie del chasis (importante para seguros/taller)

    -- Capacidades (Vital para el algoritmo de rutas)
    capacidad_peso_kg DECIMAL(10,2) NOT NULL,
    capacidad_volumen_m3 DECIMAL(10,2) NOT NULL,
    
    -- Combustible
    capacidad_tanque_galones DECIMAL(10,2),
    rendimiento_teorico_km_galon DECIMAL(10,2), -- Lo que dice el manual
    rendimiento_real_km_galon DECIMAL(10,2), -- Promedio histórico calculado
    tipo_combustible fuel_type DEFAULT 'diesel',
    
    -- Tracking & Telemetría
    dispositivo_gps_id VARCHAR(100),
    proveedor_gps VARCHAR(100),
    frecuencia_actualizacion_segundos INTEGER DEFAULT 60,
    
    -- Estado Actual (Snapshot)
    estado estado_vehiculo_enum DEFAULT 'disponible',
    ubicacion_actual GEOGRAPHY(POINT, 4326),
    ultima_actualizacion_gps TIMESTAMP,
    velocidad_actual_kmh DECIMAL(5,2),
    
    -- Mantenimiento y Odómetro
    ultimo_mantenimiento DATE,
    proximo_mantenimiento DATE,
    kilometraje_actual DECIMAL(12,2), -- DECIMAL(10,2) se queda corto para camiones viejos (99,999.99)
    horas_motor DECIMAL(10,2), -- Para maquinaria o camiones, a veces cuentan horas, no KM
    
    -- Control Administrativo
    activo BOOLEAN DEFAULT TRUE, -- TRUE = En flota activa, FALSE = Baja administrativa (sin seguro, etc)
    deleted_at TIMESTAMP, -- Soft Delete (Vendido, chatarra)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(empresa_id, placa),
    UNIQUE(empresa_id, numero_economico)
);

CREATE INDEX idx_vehiculos_estado ON vehiculos(empresa_id, estado);
CREATE INDEX idx_vehiculos_ubicacion ON vehiculos USING GIST(ubicacion_actual);

COMMENT ON TABLE vehiculos IS 'Vehículos de la flota de cada empresa';
CREATE INDEX idx_vehiculos_empresa ON vehiculos(empresa_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_vehiculos_sucursal ON vehiculos(sucursal_actual_id, estado) WHERE deleted_at IS NULL;
CREATE INDEX idx_vehiculos_estado ON vehiculos(empresa_id, estado) WHERE deleted_at IS NULL;
CREATE INDEX idx_vehiculos_ubicacion ON vehiculos USING GIST(ubicacion_actual) WHERE deleted_at IS NULL;

-- Tabla: mantenimientos
CREATE TABLE mantenimientos (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    vehiculo_id INTEGER NOT NULL REFERENCES vehiculos(id) ON DELETE CASCADE,
    tipo VARCHAR(100) NOT NULL, -- preventivo, correctivo, revision
    descripcion TEXT NOT NULL,
    -- Fechas
    fecha_inicio DATE NOT NULL,
    fecha_fin_estimada DATE,
    fecha_fin_real DATE,
    -- Costos
    costo_estimado DECIMAL(10,2),
    costo_real DECIMAL(10,2),
    -- Proveedor
    proveedor VARCHAR(200),
    numero_factura VARCHAR(100),
    -- Estado
    estado VARCHAR(50) DEFAULT 'programado', -- programado, en_proceso, completado, cancelado
    -- Archivos
    fotos_urls JSONB, -- URLs de fotos de facturas/trabajo
    -- Control
    registrado_por INTEGER REFERENCES usuarios(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE mantenimientos IS 'Historial de mantenimientos de vehículos';
CREATE INDEX idx_mantenimientos_vehiculo ON mantenimientos(vehiculo_id, fecha_inicio DESC);
CREATE INDEX idx_mantenimientos_estado ON mantenimientos(empresa_id, estado, fecha_fin_estimada);

-- =====================================================
-- NIVEL EMPRESA - PRODUCTOS E INVENTARIO
-- =====================================================

-- Tabla: productos
CREATE TABLE productos (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    categoria_id INTEGER REFERENCES categorias_productos(id),
    -- Información básica
    codigo_sku VARCHAR(100) NOT NULL,
    nombre VARCHAR(200) NOT NULL,
    descripcion TEXT,
    -- Presentación
    es_perecedero BOOLEAN DEFAULT FALSE,
    dias_vida_util INTEGER, -- Para perecederos
    -- Empaque
    unidades_por_caja INTEGER NOT NULL DEFAULT 1,
    peso_caja_kg DECIMAL(10,2) NOT NULL,
    largo_caja_cm DECIMAL(10,2),
    ancho_caja_cm DECIMAL(10,2),
    alto_caja_cm DECIMAL(10,2),
    volumen_caja_m3 DECIMAL(10,4), -- Calculado automáticamente
    -- Precios base (pueden variar por sucursal)
    precio_unitario_base DECIMAL(10,2) NOT NULL,
    precio_caja_base DECIMAL(10,2) NOT NULL,
    precio_lote_base DECIMAL(10,2),
    unidades_por_lote INTEGER,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, codigo_sku)
);

COMMENT ON TABLE productos IS 'Catálogo de productos de cada empresa';
CREATE INDEX idx_productos_empresa ON productos(empresa_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_productos_categoria ON productos(categoria_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_productos_sku ON productos(empresa_id, codigo_sku) WHERE deleted_at IS NULL;

-- Tabla: precios_productos
-- Historial de precios y precios por sucursal
CREATE TABLE precios_productos (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    sucursal_id INTEGER REFERENCES sucursales(id), -- NULL = precio general
    -- Precios
    precio_unitario DECIMAL(10,2) NOT NULL,
    precio_caja DECIMAL(10,2) NOT NULL,
    precio_lote DECIMAL(10,2),
    -- Vigencia
    fecha_inicio DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin DATE,
    -- Control
    es_promocion BOOLEAN DEFAULT FALSE,
    descripcion_promocion TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by INTEGER REFERENCES usuarios(id)
);

COMMENT ON TABLE precios_productos IS 'Historial de precios de productos (general y por sucursal)';
CREATE INDEX idx_precios_producto ON precios_productos(producto_id, fecha_inicio DESC);
CREATE INDEX idx_precios_sucursal ON precios_productos(sucursal_id, fecha_inicio DESC) WHERE sucursal_id IS NOT NULL;
CREATE INDEX idx_precios_vigentes ON precios_productos(producto_id, sucursal_id) 
    WHERE fecha_fin IS NULL OR fecha_fin >= CURRENT_DATE;

-- Tabla: cajas_fisicas
-- Cajas físicas que deben trackearse individualmente
CREATE TABLE cajas_fisicas (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    codigo_caja VARCHAR(100) NOT NULL UNIQUE,
    tipo VARCHAR(50) NOT NULL, -- retornable, especial, peligrosa
    descripcion TEXT,
    -- Dimensiones
    peso_kg DECIMAL(10,2),
    largo_cm DECIMAL(10,2),
    ancho_cm DECIMAL(10,2),
    alto_cm DECIMAL(10,2),
    -- Estado
    estado VARCHAR(50) DEFAULT 'disponible', -- disponible, en_uso, perdida, danada
    ubicacion_actual VARCHAR(100), -- sucursal, vehiculo, cliente
    ubicacion_id INTEGER, -- ID de la ubicación actual
    ultimo_movimiento TIMESTAMP,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE cajas_fisicas IS 'Cajas físicas que requieren tracking individual';
CREATE INDEX idx_cajas_empresa ON cajas_fisicas(empresa_id, estado) WHERE deleted_at IS NULL;
CREATE INDEX idx_cajas_codigo ON cajas_fisicas(codigo_caja) WHERE deleted_at IS NULL;
CREATE INDEX idx_cajas_ubicacion ON cajas_fisicas(ubicacion_actual, ubicacion_id);

-- Tabla: movimientos_cajas
-- Historial de movimientos de cajas físicas
CREATE TABLE movimientos_cajas (
    id BIGSERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    caja_fisica_id INTEGER NOT NULL REFERENCES cajas_fisicas(id) ON DELETE CASCADE,
    tipo_movimiento VARCHAR(50) NOT NULL, -- carga, descarga, transferencia, perdida
    ubicacion_origen VARCHAR(100),
    ubicacion_origen_id INTEGER,
    ubicacion_destino VARCHAR(100),
    ubicacion_destino_id INTEGER,
    fecha_movimiento TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    registrado_por INTEGER REFERENCES usuarios(id),
    notas TEXT
);

COMMENT ON TABLE movimientos_cajas IS 'Historial de movimientos de cajas físicas';
CREATE INDEX idx_movimientos_cajas_caja ON movimientos_cajas(caja_fisica_id, fecha_movimiento DESC);
CREATE INDEX idx_movimientos_cajas_fecha ON movimientos_cajas(empresa_id, fecha_movimiento DESC);

-- Tabla: inventario_sucursal
-- Inventario por sucursal
CREATE TABLE inventario_sucursal (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_id INTEGER NOT NULL REFERENCES sucursales(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    -- Cantidades
    cantidad_cajas DECIMAL(10,2) NOT NULL DEFAULT 0,
    cantidad_unidades DECIMAL(10,2) NOT NULL DEFAULT 0,
    -- Para perecederos
    fecha_vencimiento DATE,
    lote VARCHAR(100),
    -- Control
    peso_total_kg DECIMAL(10,2),
    volumen_total_m3 DECIMAL(10,4),
    ultima_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sucursal_id, producto_id, lote, fecha_vencimiento)
);

COMMENT ON TABLE inventario_sucursal IS 'Inventario de productos por sucursal';
CREATE INDEX idx_inventario_sucursal ON inventario_sucursal(sucursal_id, producto_id);
CREATE INDEX idx_inventario_producto ON inventario_sucursal(producto_id, sucursal_id);
CREATE INDEX idx_inventario_vencimiento ON inventario_sucursal(sucursal_id, fecha_vencimiento) 
    WHERE fecha_vencimiento IS NOT NULL;

-- Tabla: inventario_vehiculo
-- Inventario cargado en vehículos
CREATE TABLE inventario_vehiculo (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    vehiculo_id INTEGER NOT NULL REFERENCES vehiculos(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    ruta_id INTEGER, -- Se referencia después
    -- Cantidades
    cantidad_cajas DECIMAL(10,2) NOT NULL DEFAULT 0,
    cantidad_unidades DECIMAL(10,2) NOT NULL DEFAULT 0,
    -- Para perecederos
    fecha_vencimiento DATE,
    lote VARCHAR(100),
    -- Control
    peso_total_kg DECIMAL(10,2),
    volumen_total_m3 DECIMAL(10,4),
    ultima_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(vehiculo_id, producto_id, lote, fecha_vencimiento)
);

COMMENT ON TABLE inventario_vehiculo IS 'Inventario cargado en vehículos';
CREATE INDEX idx_inventario_vehiculo ON inventario_vehiculo(vehiculo_id, producto_id);
CREATE INDEX idx_inventario_vehiculo_ruta ON inventario_vehiculo(ruta_id) WHERE ruta_id IS NOT NULL;

-- Tabla: inventario_desechos
-- Productos devueltos o dañados pendientes de revisión
CREATE TABLE inventario_desechos (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_id INTEGER NOT NULL REFERENCES sucursales(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    -- Origen
    origen VARCHAR(50) NOT NULL, -- devolucion, danado, vencido
    ruta_id INTEGER, -- Si viene de una ruta
    devolucion_id INTEGER, -- Si viene de una devolución
    -- Cantidades
    cantidad_cajas DECIMAL(10,2) NOT NULL,
    cantidad_unidades DECIMAL(10,2) NOT NULL,
    -- Estado
    estado VARCHAR(50) DEFAULT 'pendiente_revision', -- pendiente_revision, inspeccionado, recuperable, descarte
    inspeccionado_por INTEGER REFERENCES usuarios(id),
    fecha_inspeccion TIMESTAMP,
    decision TEXT,
    -- Reintegro
    reintegrado_inventario BOOLEAN DEFAULT FALSE,
    fecha_reintegro TIMESTAMP,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE inventario_desechos IS 'Productos devueltos o dañados pendientes de revisión';
CREATE INDEX idx_desechos_sucursal ON inventario_desechos(sucursal_id, estado);
CREATE INDEX idx_desechos_producto ON inventario_desechos(producto_id, estado);
CREATE INDEX idx_desechos_pendientes ON inventario_desechos(empresa_id, estado) 
    WHERE estado = 'pendiente_revision';

-- =====================================================
-- NIVEL EMPRESA - CLIENTES
-- =====================================================

-- Tabla: clientes
CREATE TABLE clientes (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_principal_id INTEGER REFERENCES sucursales(id),
    -- Información básica
    codigo_cliente VARCHAR(100),
    nombre VARCHAR(200) NOT NULL,
    razon_social VARCHAR(300),
    rfc_nit VARCHAR(50),
    -- Contacto
    telefono VARCHAR(50),
    email VARCHAR(255),
    -- Clasificación
    tipo VARCHAR(50) DEFAULT 'minorista', -- minorista, mayorista, distribuidor
    segmento VARCHAR(50), -- A, B, C (configurable por empresa)
    -- Crédito
    limite_credito DECIMAL(10,2) DEFAULT 0,
    dias_credito INTEGER DEFAULT 0,
    saldo_pendiente DECIMAL(10,2) DEFAULT 0,
    -- Estadísticas
    total_compras DECIMAL(10,2) DEFAULT 0,
    total_pedidos INTEGER DEFAULT 0,
    fecha_primera_compra DATE,
    fecha_ultima_compra DATE,
    ticket_promedio DECIMAL(10,2),
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, codigo_cliente)
);

COMMENT ON TABLE clientes IS 'Clientes de cada empresa';
CREATE INDEX idx_clientes_empresa ON clientes(empresa_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_clientes_sucursal ON clientes(sucursal_principal_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_clientes_codigo ON clientes(empresa_id, codigo_cliente) WHERE deleted_at IS NULL;

-- Tabla: direcciones_clientes
-- Múltiples direcciones de entrega por cliente
CREATE TABLE direcciones_clientes (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    cliente_id INTEGER NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
    alias VARCHAR(100), -- "Casa", "Negocio", "Bodega"
    direccion TEXT NOT NULL,
    ciudad VARCHAR(100),
    estado_departamento VARCHAR(100),
    codigo_postal VARCHAR(20),
    ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
    -- Configuración
    es_principal BOOLEAN DEFAULT FALSE,
    requiere_cita BOOLEAN DEFAULT FALSE,
    notas_entrega TEXT,
    -- Horarios de recepción
    horarios_recepcion JSONB,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE direcciones_clientes IS 'Direcciones de entrega de clientes';
CREATE INDEX idx_direcciones_cliente ON direcciones_clientes(cliente_id, activo);
CREATE INDEX idx_direcciones_ubicacion ON direcciones_clientes USING GIST(ubicacion) WHERE activo = TRUE;
CREATE INDEX idx_direcciones_principal ON direcciones_clientes(cliente_id) WHERE es_principal = TRUE;

-- Tabla: clientes_potenciales
-- Prospectos marcados por conductores
CREATE TABLE clientes_potenciales (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    ruta_id INTEGER, -- Se referencia después
    registrado_por INTEGER NOT NULL REFERENCES usuarios(id),
    -- Información básica
    nombre VARCHAR(200),
    telefono VARCHAR(50),
    email VARCHAR(255),
    -- Ubicación
    direccion TEXT,
    ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
    -- Detalles
    tipo_negocio VARCHAR(100),
    productos_interes TEXT,
    notas TEXT,
    -- Estado
    estado VARCHAR(50) DEFAULT 'nuevo', -- nuevo, contactado, interesado, convertido, descartado
    revisado_por INTEGER REFERENCES usuarios(id),
    fecha_revision TIMESTAMP,
    -- Conversión
    convertido_a_cliente_id INTEGER REFERENCES clientes(id),
    fecha_conversion TIMESTAMP,
    -- Archivado automático
    fecha_expiracion DATE DEFAULT (CURRENT_DATE + INTERVAL '30 days'),
    archivado BOOLEAN DEFAULT FALSE,
    fecha_archivado TIMESTAMP,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE clientes_potenciales IS 'Clientes potenciales registrados por conductores (auto-archivado 30 días)';
CREATE INDEX idx_clientes_potenciales_empresa ON clientes_potenciales(empresa_id, estado) WHERE archivado = FALSE;
CREATE INDEX idx_clientes_potenciales_ubicacion ON clientes_potenciales USING GIST(ubicacion) WHERE archivado = FALSE;
CREATE INDEX idx_clientes_potenciales_expiracion ON clientes_potenciales(fecha_expiracion) 
    WHERE archivado = FALSE AND estado = 'nuevo';

-- =====================================================
-- NIVEL EMPRESA - RUTAS Y TRACKING
-- =====================================================

-- Tabla: plantillas_rutas
-- Rutas predefinidas (plantillas)
CREATE TABLE plantillas_rutas (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_id INTEGER NOT NULL REFERENCES sucursales(id) ON DELETE CASCADE,
    tipo_ruta_id INTEGER NOT NULL REFERENCES tipos_rutas(id),
    -- Información básica
    nombre VARCHAR(200) NOT NULL,
    codigo VARCHAR(50),
    descripcion TEXT,
    -- Geometría
    geometria_planificada GEOGRAPHY(LINESTRING, 4326),
    distancia_planificada_km DECIMAL(10,2),
    -- Tiempos estimados
    duracion_estimada_minutos INTEGER,
    duracion_promedio_real_minutos INTEGER, -- Calculado con el tiempo
    -- Área de exploración (si aplica)
    area_exploracion GEOGRAPHY(POLYGON, 4326),
    -- Configuración
    permite_desviaciones BOOLEAN DEFAULT TRUE,
    requiere_autorizacion_desviaciones BOOLEAN DEFAULT FALSE,
    distancia_maxima_desviacion_metros DECIMAL(10,2),
    -- Horarios
    hora_inicio_sugerida TIME,
    hora_fin_estimada TIME,
    margen_inicio_minutos INTEGER,
    margen_fin_minutos INTEGER,
    -- Estadísticas históricas
    total_veces_usada INTEGER DEFAULT 0,
    adherencia_promedio DECIMAL(5,2), -- Porcentaje
    tasa_completado DECIMAL(5,2),
    -- Origen
    creada_desde_recorrido_id INTEGER, -- Si fue convertida de un recorrido real
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(empresa_id, codigo)
);

COMMENT ON TABLE plantillas_rutas IS 'Plantillas de rutas predefinidas';
CREATE INDEX idx_plantillas_empresa ON plantillas_rutas(empresa_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_plantillas_sucursal ON plantillas_rutas(sucursal_id, activo) WHERE deleted_at IS NULL;
CREATE INDEX idx_plantillas_geometria ON plantillas_rutas USING GIST(geometria_planificada) WHERE deleted_at IS NULL;

-- Tabla: paradas_plantilla
-- Paradas predefinidas en plantillas de rutas
CREATE TABLE paradas_plantilla (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    plantilla_ruta_id INTEGER NOT NULL REFERENCES plantillas_rutas(id) ON DELETE CASCADE,
    -- Información
    orden INTEGER NOT NULL,
    nombre VARCHAR(200) NOT NULL,
    ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
    -- Cliente asociado (si aplica)
    cliente_id INTEGER REFERENCES clientes(id),
    direccion_cliente_id INTEGER REFERENCES direcciones_clientes(id),
    -- Configuración
    es_obligatoria BOOLEAN DEFAULT TRUE,
    tiempo_estimado_minutos INTEGER,
    -- Radio de proximidad
    radio_proximidad_metros DECIMAL(10,2) DEFAULT 100,
    -- Notificaciones
    notificar_llegada BOOLEAN DEFAULT TRUE,
    -- Control
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE paradas_plantilla IS 'Paradas predefinidas en plantillas de rutas';
CREATE INDEX idx_paradas_plantilla ON paradas_plantilla(plantilla_ruta_id, orden);
CREATE INDEX idx_paradas_plantilla_ubicacion ON paradas_plantilla USING GIST(ubicacion);
CREATE INDEX idx_paradas_plantilla_cliente ON paradas_plantilla(cliente_id) WHERE cliente_id IS NOT NULL;

-- Tabla: rutas
-- Rutas activas/históricas (instancias de plantillas o rutas nuevas)
CREATE TABLE rutas (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_id INTEGER NOT NULL REFERENCES sucursales(id) ON DELETE CASCADE,
    plantilla_ruta_id INTEGER REFERENCES plantillas_rutas(id),
    tipo_ruta_id INTEGER NOT NULL REFERENCES tipos_rutas(id),
    -- Asignación
    vehiculo_id INTEGER NOT NULL REFERENCES vehiculos(id),
    conductor_id INTEGER NOT NULL REFERENCES usuarios(id),
    supervisor_id INTEGER REFERENCES usuarios(id), -- Quien planificó/supervisa
    -- Información
    numero_ruta VARCHAR(100) UNIQUE NOT NULL,
    nombre VARCHAR(200),
    descripcion TEXT,
    -- Geometrías
    geometria_planificada GEOGRAPHY(LINESTRING, 4326),
    geometria_recorrida GEOGRAPHY(LINESTRING, 4326), -- Se construye con tracking GPS
    -- Fechas y tiempos
    fecha_planificada DATE NOT NULL,
    hora_inicio_planificada TIME,
    hora_fin_estimada TIME,
    hora_inicio_real TIMESTAMP,
    hora_fin_real TIMESTAMP,
    duracion_real_minutos INTEGER,
    -- Tracking activo
    tracking_activo BOOLEAN DEFAULT FALSE, -- Si se está dibujando la ruta en tiempo real
    -- Estado
    estado VARCHAR(50) DEFAULT 'planificada', -- planificada, en_progreso, completada, cancelada
    -- Métricas (calculadas al completar)
    distancia_planificada_km DECIMAL(10,2),
    distancia_recorrida_km DECIMAL(10,2),
    adherencia_porcentaje DECIMAL(5,2),
    metros_desviacion_acumulados DECIMAL(10,2),
    tiempo_perdido_desviaciones_minutos INTEGER,
    -- Inventario
    inicio_sin_inventario BOOLEAN DEFAULT FALSE,
    peso_inicial_kg DECIMAL(10,2),
    volumen_inicial_m3 DECIMAL(10,4),
    -- Combustible
    combustible_inicial_galones DECIMAL(10,2),
    combustible_gastado_galones DECIMAL(10,2),
    costo_combustible DECIMAL(10,2),
    -- Tripulación adicional
    tripulacion_adicional JSONB, -- [{usuario_id, rol, funciones}]
    -- Control
    cancelada_por INTEGER REFERENCES usuarios(id),
    motivo_cancelacion TEXT,
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE rutas IS 'Rutas activas e históricas (instancias de ejecución)';
CREATE INDEX idx_rutas_empresa ON rutas(empresa_id, estado, fecha_planificada DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_rutas_sucursal ON rutas(sucursal_id, estado) WHERE deleted_at IS NULL;
CREATE INDEX idx_rutas_conductor ON rutas(conductor_id, fecha_planificada DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_rutas_vehiculo ON rutas(vehiculo_id, fecha_planificada DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_rutas_activas ON rutas(empresa_id, estado) WHERE estado = 'en_progreso';
CREATE INDEX idx_rutas_geometria_plan ON rutas USING GIST(geometria_planificada) WHERE deleted_at IS NULL;
CREATE INDEX idx_rutas_geometria_real ON rutas USING GIST(geometria_recorrida) WHERE geometria_recorrida IS NOT NULL;

-- Agregar FK faltante a inventario_vehiculo
ALTER TABLE inventario_vehiculo ADD CONSTRAINT fk_inventario_ruta 
    FOREIGN KEY (ruta_id) REFERENCES rutas(id);

-- Agregar FK faltante a clientes_potenciales
ALTER TABLE clientes_potenciales ADD CONSTRAINT fk_cliente_potencial_ruta 
    FOREIGN KEY (ruta_id) REFERENCES rutas(id);

-- Tabla: paradas_ruta
-- Paradas de una ruta específica (copiadas de plantilla o nuevas)
CREATE TABLE paradas_ruta (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    ruta_id INTEGER NOT NULL REFERENCES rutas(id) ON DELETE CASCADE,
    parada_plantilla_id INTEGER REFERENCES paradas_plantilla(id),
    -- Información
    orden INTEGER NOT NULL,
    nombre VARCHAR(200) NOT NULL,
    ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
    -- Cliente asociado
    cliente_id INTEGER REFERENCES clientes(id),
    direccion_cliente_id INTEGER REFERENCES direcciones_clientes(id),
    -- Tipo de parada
    tipo VARCHAR(50) NOT NULL, -- planificada, emergente, bodega
    es_obligatoria BOOLEAN DEFAULT TRUE,
    tiempo_estimado_minutos INTEGER,
    -- Estado
    estado VARCHAR(50) DEFAULT 'pendiente', -- pendiente, notificada, visitada, omitida, completada
    -- Tiempos reales
    hora_llegada TIMESTAMP,
    hora_salida TIMESTAMP,
    duracion_real_minutos INTEGER,
    -- Proximidad
    radio_proximidad_metros DECIMAL(10,2) DEFAULT 100,
    notificacion_proximidad_enviada BOOLEAN DEFAULT FALSE,
    -- Omisión
    omitida BOOLEAN DEFAULT FALSE,
    motivo_omision_id INTEGER REFERENCES motivos_justificacion(id),
    justificacion_omision TEXT,
    requiere_autorizacion BOOLEAN DEFAULT FALSE,
    autorizada BOOLEAN DEFAULT FALSE,
    autorizada_por INTEGER REFERENCES usuarios(id),
    fecha_autorizacion TIMESTAMP,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE paradas_ruta IS 'Paradas de rutas específicas (planificadas y emergentes)';
CREATE INDEX idx_paradas_ruta ON paradas_ruta(ruta_id, orden);
CREATE INDEX idx_paradas_ruta_ubicacion ON paradas_ruta USING GIST(ubicacion);
CREATE INDEX idx_paradas_ruta_estado ON paradas_ruta(ruta_id, estado);
CREATE INDEX idx_paradas_ruta_cliente ON paradas_ruta(cliente_id) WHERE cliente_id IS NOT NULL;

-- Tabla: tracking_gps
-- Puntos GPS registrados durante las rutas
CREATE TABLE tracking_gps (
    id BIGSERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    ruta_id INTEGER NOT NULL REFERENCES rutas(id) ON DELETE CASCADE,
    vehiculo_id INTEGER NOT NULL REFERENCES vehiculos(id),
    -- Ubicación
    ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
    altitud DECIMAL(10,2),
    precision_metros DECIMAL(10,2),
    -- Movimiento
    velocidad_kmh DECIMAL(10,2),
    direccion_grados DECIMAL(5,2), -- 0-360
    -- Desviación
    distancia_desviacion_metros DECIMAL(10,2), -- Distancia perpendicular a ruta planificada
    esta_desviado BOOLEAN DEFAULT FALSE,
    -- Timestamp
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE tracking_gps IS 'Puntos GPS registrados durante rutas (particionado mensual recomendado)';
CREATE INDEX idx_tracking_ruta ON tracking_gps(ruta_id, timestamp DESC);
CREATE INDEX idx_tracking_vehiculo ON tracking_gps(vehiculo_id, timestamp DESC);
CREATE INDEX idx_tracking_ubicacion ON tracking_gps USING GIST(ubicacion);
CREATE INDEX idx_tracking_desviaciones ON tracking_gps(ruta_id) WHERE esta_desviado = TRUE;

-- Tabla: puntos_interes
-- Puntos marcados por conductores durante rutas
CREATE TABLE puntos_interes (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    ruta_id INTEGER NOT NULL REFERENCES rutas(id) ON DELETE CASCADE,
    registrado_por INTEGER NOT NULL REFERENCES usuarios(id),
    -- Tipo
    tipo VARCHAR(50) NOT NULL, -- bache, bloqueo, competencia, oportunidad, peligro
    nombre VARCHAR(200),
    descripcion TEXT,
    -- Ubicación
    ubicacion GEOGRAPHY(POINT, 4326) NOT NULL,
    -- Archivos
    fotos_urls JSONB,
    -- Estado
    revisado BOOLEAN DEFAULT FALSE,
    revisado_por INTEGER REFERENCES usuarios(id),
    fecha_revision TIMESTAMP,
    accion_tomada TEXT,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE puntos_interes IS 'Puntos de interés marcados por conductores';
CREATE INDEX idx_puntos_interes_empresa ON puntos_interes(empresa_id, tipo);
CREATE INDEX idx_puntos_interes_ruta ON puntos_interes(ruta_id);
CREATE INDEX idx_puntos_interes_ubicacion ON puntos_interes USING GIST(ubicacion);
CREATE INDEX idx_puntos_interes_revision ON puntos_interes(empresa_id) WHERE revisado = FALSE;

-- =====================================================
-- NIVEL EMPRESA - VENTAS Y PEDIDOS
-- =====================================================

-- Tabla: pedidos
-- Pedidos confirmados antes de salir a ruta
CREATE TABLE pedidos (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_id INTEGER NOT NULL REFERENCES sucursales(id) ON DELETE CASCADE,
    cliente_id INTEGER NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
    direccion_entrega_id INTEGER NOT NULL REFERENCES direcciones_clientes(id),
    -- Numeración
    numero_pedido VARCHAR(100) UNIQUE NOT NULL,
    -- Asignación a ruta
    ruta_id INTEGER REFERENCES rutas(id),
    parada_ruta_id INTEGER REFERENCES paradas_ruta(id),
    -- Fechas
    fecha_pedido DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_entrega_programada DATE,
    fecha_entrega_real DATE,
    -- Montos
    subtotal DECIMAL(10,2) NOT NULL,
    descuento DECIMAL(10,2) DEFAULT 0,
    impuestos DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    -- Pago
    metodo_pago VARCHAR(50), -- efectivo, transferencia, credito, adelantado
    estado_pago VARCHAR(50) DEFAULT 'pendiente', -- pendiente, pagado, credito
    monto_pagado DECIMAL(10,2) DEFAULT 0,
    -- Estado
    estado VARCHAR(50) DEFAULT 'confirmado', -- confirmado, asignado, en_ruta, entregado, cancelado
    -- Control
    registrado_por INTEGER NOT NULL REFERENCES usuarios(id),
    entregado_por INTEGER REFERENCES usuarios(id),
    cancelado_por INTEGER REFERENCES usuarios(id),
    motivo_cancelacion TEXT,
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE pedidos IS 'Pedidos confirmados (ventas pre-aseguradas)';
CREATE INDEX idx_pedidos_empresa ON pedidos(empresa_id, fecha_pedido DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_pedidos_cliente ON pedidos(cliente_id, fecha_pedido DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_pedidos_ruta ON pedidos(ruta_id, estado) WHERE ruta_id IS NOT NULL;
CREATE INDEX idx_pedidos_estado ON pedidos(empresa_id, estado, fecha_entrega_programada);

-- Tabla: detalles_pedido
CREATE TABLE detalles_pedido (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    pedido_id INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id),
    -- Cantidades solicitadas
    cantidad_cajas DECIMAL(10,2) NOT NULL,
    cantidad_unidades DECIMAL(10,2) NOT NULL,
    -- Cantidades entregadas (puede diferir)
    cantidad_cajas_entregadas DECIMAL(10,2) DEFAULT 0,
    cantidad_unidades_entregadas DECIMAL(10,2) DEFAULT 0,
    -- Precios
    precio_unitario DECIMAL(10,2) NOT NULL,
    precio_caja DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    descuento DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE detalles_pedido IS 'Detalle de productos en pedidos';
CREATE INDEX idx_detalles_pedido ON detalles_pedido(pedido_id);
CREATE INDEX idx_detalles_producto ON detalles_pedido(producto_id);

-- Tabla: ventas
-- Ventas registradas durante la ruta
CREATE TABLE ventas (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_id INTEGER NOT NULL REFERENCES sucursales(id) ON DELETE CASCADE,
    ruta_id INTEGER NOT NULL REFERENCES rutas(id) ON DELETE CASCADE,
    parada_ruta_id INTEGER REFERENCES paradas_ruta(id),
    -- Cliente
    cliente_id INTEGER NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
    direccion_entrega_id INTEGER REFERENCES direcciones_clientes(id),
    -- Numeración
    numero_venta VARCHAR(100) UNIQUE NOT NULL,
    -- Tipo
    es_venta_emergente BOOLEAN DEFAULT FALSE, -- No estaba planificada
    pedido_original_id INTEGER REFERENCES pedidos(id), -- Si corresponde a un pedido
    -- Fechas
    fecha_venta TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Montos
    subtotal DECIMAL(10,2) NOT NULL,
    descuento DECIMAL(10,2) DEFAULT 0,
    impuestos DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    -- Pago
    metodo_pago VARCHAR(50) NOT NULL, -- efectivo, transferencia, tarjeta, credito
    estado_pago VARCHAR(50) DEFAULT 'pendiente', -- pendiente, pagado, credito
    monto_pagado DECIMAL(10,2) DEFAULT 0,
    monto_pendiente DECIMAL(10,2) DEFAULT 0,
    -- Recibo/comprobante
    numero_comprobante VARCHAR(100),
    foto_comprobante_url TEXT,
    -- Control
    registrado_por INTEGER NOT NULL REFERENCES usuarios(id),
    deleted_at TIMESTAMP,
    deleted_by INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE ventas IS 'Ventas registradas durante rutas (planificadas y emergentes)';
CREATE INDEX idx_ventas_empresa ON ventas(empresa_id, fecha_venta DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_ventas_ruta ON ventas(ruta_id, fecha_venta DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_ventas_cliente ON ventas(cliente_id, fecha_venta DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_ventas_emergentes ON ventas(ruta_id) WHERE es_venta_emergente = TRUE;

-- Tabla: detalles_venta
CREATE TABLE detalles_venta (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    venta_id INTEGER NOT NULL REFERENCES ventas(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id),
    -- Cantidades
    cantidad_cajas DECIMAL(10,2) NOT NULL,
    cantidad_unidades DECIMAL(10,2) NOT NULL,
    -- Precios
    precio_unitario DECIMAL(10,2) NOT NULL,
    precio_caja DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    descuento DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    -- Lote/vencimiento
    lote VARCHAR(100),
    fecha_vencimiento DATE,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE detalles_venta IS 'Detalle de productos en ventas';
CREATE INDEX idx_detalles_venta ON detalles_venta(venta_id);
CREATE INDEX idx_detalles_venta_producto ON detalles_venta(producto_id);

-- Tabla: devoluciones
CREATE TABLE devoluciones (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_id INTEGER NOT NULL REFERENCES sucursales(id) ON DELETE CASCADE,
    ruta_id INTEGER NOT NULL REFERENCES rutas(id) ON DELETE CASCADE,
    -- Origen
    venta_id INTEGER REFERENCES ventas(id), -- Si es devolución de venta
    pedido_id INTEGER REFERENCES pedidos(id), -- Si es devolución de pedido
    cliente_id INTEGER NOT NULL REFERENCES clientes(id),
    -- Información
    numero_devolucion VARCHAR(100) UNIQUE NOT NULL,
    fecha_devolucion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Montos
    monto_total DECIMAL(10,2) NOT NULL,
    monto_reembolsado DECIMAL(10,2) DEFAULT 0,
    -- Motivo
    motivo_id INTEGER REFERENCES motivos_justificacion(id),
    descripcion TEXT,
    requiere_foto BOOLEAN DEFAULT TRUE,
    fotos_urls JSONB,
    -- Estado
    estado VARCHAR(50) DEFAULT 'registrada', -- registrada, en_revision, aprobada, rechazada
    revisado_por INTEGER REFERENCES usuarios(id),
    fecha_revision TIMESTAMP,
    decision TEXT,
    -- Control
    registrado_por INTEGER NOT NULL REFERENCES usuarios(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE devoluciones IS 'Devoluciones de productos';
CREATE INDEX idx_devoluciones_empresa ON devoluciones(empresa_id, fecha_devolucion DESC);
CREATE INDEX idx_devoluciones_ruta ON devoluciones(ruta_id);
CREATE INDEX idx_devoluciones_cliente ON devoluciones(cliente_id, fecha_devolucion DESC);
CREATE INDEX idx_devoluciones_estado ON devoluciones(empresa_id, estado);

-- Tabla: detalles_devolucion
CREATE TABLE detalles_devolucion (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    devolucion_id INTEGER NOT NULL REFERENCES devoluciones(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id),
    -- Cantidades
    cantidad_cajas DECIMAL(10,2) NOT NULL,
    cantidad_unidades DECIMAL(10,2) NOT NULL,
    -- Precios al momento de la venta
    precio_unitario DECIMAL(10,2) NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    -- Estado del producto
    estado_producto VARCHAR(50), -- danado, vencido, defectuoso, equivocado
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE detalles_devolucion IS 'Detalle de productos devueltos';
CREATE INDEX idx_detalles_devolucion ON detalles_devolucion(devolucion_id);
CREATE INDEX idx_detalles_devolucion_producto ON detalles_devolucion(producto_id);

-- Tabla: reclamos_clientes
CREATE TABLE reclamos_clientes (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    cliente_id INTEGER NOT NULL REFERENCES clientes(id),
    -- Origen del reclamo
    venta_id INTEGER REFERENCES ventas(id),
    pedido_id INTEGER REFERENCES pedidos(id),
    ruta_id INTEGER REFERENCES rutas(id),
    -- Información
    numero_reclamo VARCHAR(100) UNIQUE NOT NULL,
    fecha_reclamo TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo VARCHAR(50) NOT NULL, -- calidad, entrega, facturacion, servicio, otro
    prioridad VARCHAR(50) DEFAULT 'media', -- baja, media, alta, critica
    -- Descripción
    asunto VARCHAR(200) NOT NULL,
    descripcion TEXT NOT NULL,
    fotos_urls JSONB,
    -- Estado
    estado VARCHAR(50) DEFAULT 'nuevo', -- nuevo, en_revision, en_proceso, resuelto, cerrado
    -- Asignación
    asignado_a INTEGER REFERENCES usuarios(id),
    fecha_asignacion TIMESTAMP,
    -- Resolución
    resuelto_por INTEGER REFERENCES usuarios(id),
    fecha_resolucion TIMESTAMP,
    solucion TEXT,
    compensacion_otorgada DECIMAL(10,2),
    -- Satisfacción
    cliente_satisfecho BOOLEAN,
    calificacion INTEGER, -- 1-5
    comentario_cliente TEXT,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE reclamos_clientes IS 'Reclamos de clientes';
CREATE INDEX idx_reclamos_empresa ON reclamos_clientes(empresa_id, estado, fecha_reclamo DESC);
CREATE INDEX idx_reclamos_cliente ON reclamos_clientes(cliente_id, fecha_reclamo DESC);
CREATE INDEX idx_reclamos_prioridad ON reclamos_clientes(empresa_id, prioridad) WHERE estado != 'cerrado';
CREATE INDEX idx_reclamos_asignado ON reclamos_clientes(asignado_a, estado) WHERE asignado_a IS NOT NULL;

-- Tabla: pagos
-- Pagos recibidos (puede ser de varias fuentes)
CREATE TABLE pagos (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    cliente_id INTEGER NOT NULL REFERENCES clientes(id),
    -- Origen
    venta_id INTEGER REFERENCES ventas(id),
    pedido_id INTEGER REFERENCES pedidos(id),
    -- Información
    numero_pago VARCHAR(100) UNIQUE NOT NULL,
    fecha_pago TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monto DECIMAL(10,2) NOT NULL,
    metodo_pago VARCHAR(50) NOT NULL, -- efectivo, transferencia, tarjeta, cheque
    -- Detalles del pago
    referencia VARCHAR(200), -- Número de transferencia, cheque, etc.
    banco VARCHAR(100),
    numero_cuenta VARCHAR(50),
    -- Comprobante
    foto_comprobante_url TEXT,
    -- Estado
    estado VARCHAR(50) DEFAULT 'recibido', -- recibido, verificado, rechazado
    verificado_por INTEGER REFERENCES usuarios(id),
    fecha_verificacion TIMESTAMP,
    -- Control
    registrado_por INTEGER NOT NULL REFERENCES usuarios(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE pagos IS 'Pagos recibidos de clientes';
CREATE INDEX idx_pagos_empresa ON pagos(empresa_id, fecha_pago DESC);
CREATE INDEX idx_pagos_cliente ON pagos(cliente_id, fecha_pago DESC);
CREATE INDEX idx_pagos_estado ON pagos(empresa_id, estado);

-- =====================================================
-- NIVEL EMPRESA - TRANSFERENCIAS
-- =====================================================

-- Tabla: transferencias_sucursales
CREATE TABLE transferencias_sucursales (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    sucursal_origen_id INTEGER NOT NULL REFERENCES sucursales(id),
    sucursal_destino_id INTEGER NOT NULL REFERENCES sucursales(id),
    -- Numeración
    numero_transferencia VARCHAR(100) UNIQUE NOT NULL,
    -- Vehículo y conductor
    vehiculo_id INTEGER NOT NULL REFERENCES vehiculos(id),
    conductor_id INTEGER NOT NULL REFERENCES usuarios(id),
    ruta_id INTEGER REFERENCES rutas(id), -- Si se crea ruta para la transferencia
    -- Fechas
    fecha_solicitud DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_salida TIMESTAMP,
    fecha_llegada_estimada TIMESTAMP,
    fecha_llegada_real TIMESTAMP,
    -- Estado
    estado VARCHAR(50) DEFAULT 'solicitada', -- solicitada, aprobada, en_transito, recibida, cancelada
    -- Totales
    total_cajas DECIMAL(10,2),
    total_peso_kg DECIMAL(10,2),
    total_volumen_m3 DECIMAL(10,4),
    -- Discrepancias
    hay_discrepancias BOOLEAN DEFAULT FALSE,
    discrepancias_detalle TEXT,
    -- Control
    solicitado_por INTEGER NOT NULL REFERENCES usuarios(id),
    aprobado_por INTEGER REFERENCES usuarios(id),
    recibido_por INTEGER REFERENCES usuarios(id),
    cancelado_por INTEGER REFERENCES usuarios(id),
    motivo_cancelacion TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_sucursales_diferentes CHECK (sucursal_origen_id != sucursal_destino_id)
);

COMMENT ON TABLE transferencias_sucursales IS 'Transferencias de inventario entre sucursales';
CREATE INDEX idx_transferencias_empresa ON transferencias_sucursales(empresa_id, estado, fecha_solicitud DESC);
CREATE INDEX idx_transferencias_origen ON transferencias_sucursales(sucursal_origen_id, estado);
CREATE INDEX idx_transferencias_destino ON transferencias_sucursales(sucursal_destino_id, estado);
CREATE INDEX idx_transferencias_conductor ON transferencias_sucursales(conductor_id);

-- Tabla: detalles_transferencia
CREATE TABLE detalles_transferencia (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    transferencia_id INTEGER NOT NULL REFERENCES transferencias_sucursales(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id),
    -- Cantidades enviadas
    cantidad_cajas_enviada DECIMAL(10,2) NOT NULL,
    cantidad_unidades_enviada DECIMAL(10,2) NOT NULL,
    -- Cantidades recibidas
    cantidad_cajas_recibida DECIMAL(10,2),
    cantidad_unidades_recibida DECIMAL(10,2),
    -- Diferencia
    hay_diferencia BOOLEAN DEFAULT FALSE,
    cajas_faltantes DECIMAL(10,2),
    unidades_faltantes DECIMAL(10,2),
    -- Lote/vencimiento
    lote VARCHAR(100),
    fecha_vencimiento DATE,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE detalles_transferencia IS 'Detalle de productos en transferencias';
CREATE INDEX idx_detalles_transferencia ON detalles_transferencia(transferencia_id);
CREATE INDEX idx_detalles_transferencia_producto ON detalles_transferencia(producto_id);

-- =====================================================
-- NIVEL EMPRESA - COMBUSTIBLE
-- =====================================================

-- Tabla: cargas_combustible
CREATE TABLE cargas_combustible (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    vehiculo_id INTEGER NOT NULL REFERENCES vehiculos(id),
    ruta_id INTEGER REFERENCES rutas(id),
    -- Información
    fecha_carga TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gasolinera VARCHAR(200),
    ubicacion GEOGRAPHY(POINT, 4326),
    -- Cantidades
    galones_cargados DECIMAL(10,2) NOT NULL,
    precio_por_galon DECIMAL(10,2) NOT NULL,
    total_gastado DECIMAL(10,2) NOT NULL,
    -- Comprobante
    numero_factura VARCHAR(100),
    foto_factura_url TEXT,
    -- Control
    registrado_por INTEGER NOT NULL REFERENCES usuarios(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE cargas_combustible IS 'Cargas de combustible de vehículos';
CREATE INDEX idx_combustible_vehiculo ON cargas_combustible(vehiculo_id, fecha_carga DESC);
CREATE INDEX idx_combustible_ruta ON cargas_combustible(ruta_id) WHERE ruta_id IS NOT NULL;
CREATE INDEX idx_combustible_empresa ON cargas_combustible(empresa_id, fecha_carga DESC);

-- =====================================================
-- NIVEL EMPRESA - METAS
-- =====================================================

-- Tabla: metas
CREATE TABLE metas (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    -- Alcance
    tipo_alcance VARCHAR(50) NOT NULL, -- empresa, sucursal, conductor
    sucursal_id INTEGER REFERENCES sucursales(id),
    conductor_id INTEGER REFERENCES usuarios(id),
    -- Tipo de meta
    tipo_meta VARCHAR(50) NOT NULL, -- ventas_monto, ventas_cantidad, nuevos_clientes, rutas_completadas
    producto_id INTEGER REFERENCES productos(id), -- Si es meta de producto específico
    -- Valores
    nombre VARCHAR(200) NOT NULL,
    descripcion TEXT,
    valor_objetivo DECIMAL(10,2) NOT NULL,
    valor_actual DECIMAL(10,2) DEFAULT 0,
    unidad VARCHAR(50), -- GTQ, unidades, clientes, rutas
    -- Periodo
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    -- Estado
    estado VARCHAR(50) DEFAULT 'activa', -- activa, completada, vencida, cancelada
    porcentaje_completado DECIMAL(5,2) DEFAULT 0,
    fecha_completado TIMESTAMP,
    -- Recompensa
    tiene_recompensa BOOLEAN DEFAULT FALSE,
    descripcion_recompensa TEXT,
    monto_recompensa DECIMAL(10,2),
    -- Control
    creado_por INTEGER NOT NULL REFERENCES usuarios(id),
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE metas IS 'Metas de ventas y desempeño';
CREATE INDEX idx_metas_empresa ON metas(empresa_id, estado, fecha_fin) WHERE deleted_at IS NULL;
CREATE INDEX idx_metas_sucursal ON metas(sucursal_id, estado) WHERE sucursal_id IS NOT NULL;
CREATE INDEX idx_metas_conductor ON metas(conductor_id, estado) WHERE conductor_id IS NOT NULL;
CREATE INDEX idx_metas_activas ON metas(empresa_id, estado) WHERE estado = 'activa';

-- =====================================================
-- NIVEL EMPRESA - NOTIFICACIONES
-- =====================================================

-- Tabla: notificaciones
CREATE TABLE notificaciones (
    id BIGSERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    -- Destinatarios
    usuario_id INTEGER REFERENCES usuarios(id),
    rol_id INTEGER REFERENCES roles(id), -- Para enviar a todos de un rol
    -- Tipo y prioridad
    tipo VARCHAR(50) NOT NULL, -- inicio_ruta, fin_ruta, desviacion, parada_completada, venta_emergente, etc.
    prioridad VARCHAR(50) DEFAULT 'normal', -- baja, normal, alta, critica
    -- Contenido
    titulo VARCHAR(200) NOT NULL,
    mensaje TEXT NOT NULL,
    datos_adicionales JSONB, -- Data específica del evento
    -- Origen
    ruta_id INTEGER REFERENCES rutas(id),
    venta_id INTEGER REFERENCES ventas(id),
    pedido_id INTEGER REFERENCES pedidos(id),
    -- Estado
    leida BOOLEAN DEFAULT FALSE,
    fecha_lectura TIMESTAMP,
    archivada BOOLEAN DEFAULT FALSE,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE notificaciones IS 'Notificaciones del sistema';
CREATE INDEX idx_notificaciones_usuario ON notificaciones(usuario_id, leida, created_at DESC) WHERE usuario_id IS NOT NULL;
CREATE INDEX idx_notificaciones_rol ON notificaciones(rol_id, leida, created_at DESC) WHERE rol_id IS NOT NULL;
CREATE INDEX idx_notificaciones_tipo ON notificaciones(empresa_id, tipo, created_at DESC);
CREATE INDEX idx_notificaciones_ruta ON notificaciones(ruta_id) WHERE ruta_id IS NOT NULL;

-- =====================================================
-- NIVEL EMPRESA - ESTADÍSTICAS
-- =====================================================

-- Tabla: estadisticas_rutas
CREATE TABLE estadisticas_rutas (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    ruta_id INTEGER NOT NULL REFERENCES rutas(id) ON DELETE CASCADE,
    -- Ventas
    total_ventas DECIMAL(10,2) DEFAULT 0,
    total_entregas INTEGER DEFAULT 0,
    total_ventas_emergentes INTEGER DEFAULT 0,
    total_nuevos_clientes INTEGER DEFAULT 0,
    -- Paradas
    total_paradas_planificadas INTEGER DEFAULT 0,
    total_paradas_completadas INTEGER DEFAULT 0,
    total_paradas_omitidas INTEGER DEFAULT 0,
    total_paradas_emergentes INTEGER DEFAULT 0,
    -- Recorrido
    distancia_km DECIMAL(10,2) DEFAULT 0,
    duracion_minutos INTEGER DEFAULT 0,
    adherencia_porcentaje DECIMAL(5,2) DEFAULT 0,
    metros_desviacion DECIMAL(10,2) DEFAULT 0,
    -- Combustible
    eficiencia_km_por_galon DECIMAL(10,2),
    -- Puntos de interés
    total_puntos_interes INTEGER DEFAULT 0,
    total_clientes_potenciales INTEGER DEFAULT 0,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(ruta_id)
);

COMMENT ON TABLE estadisticas_rutas IS 'Estadísticas agregadas por ruta';
CREATE INDEX idx_estadisticas_rutas_empresa ON estadisticas_rutas(empresa_id);

-- Tabla: estadisticas_conductores
CREATE TABLE estadisticas_conductores (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    conductor_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    -- Periodo
    periodo VARCHAR(20) NOT NULL, -- dia, semana, mes, anio
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    -- Rutas
    total_rutas_completadas INTEGER DEFAULT 0,
    total_rutas_canceladas INTEGER DEFAULT 0,
    total_km_recorridos DECIMAL(10,2) DEFAULT 0,
    total_horas_ruta DECIMAL(10,2) DEFAULT 0,
    -- Ventas
    total_ventas DECIMAL(10,2) DEFAULT 0,
    total_ventas_emergentes DECIMAL(10,2) DEFAULT 0,
    total_pedidos_entregados INTEGER DEFAULT 0,
    -- Clientes
    total_nuevos_clientes INTEGER DEFAULT 0,
    total_clientes_atendidos INTEGER DEFAULT 0,
    -- Desempeño
    adherencia_promedio DECIMAL(5,2) DEFAULT 0,
    eficiencia_combustible_promedio DECIMAL(10,2),
    calificacion_promedio DECIMAL(3,2),
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(conductor_id, periodo, fecha_inicio)
);

COMMENT ON TABLE estadisticas_conductores IS 'Estadísticas agregadas por conductor y periodo';
CREATE INDEX idx_estadisticas_conductores ON estadisticas_conductores(conductor_id, periodo, fecha_inicio DESC);
CREATE INDEX idx_estadisticas_conductores_empresa ON estadisticas_conductores(empresa_id, periodo, fecha_inicio DESC);

-- Tabla: estadisticas_productos
CREATE TABLE estadisticas_productos (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    producto_id INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    sucursal_id INTEGER REFERENCES sucursales(id),
    -- Periodo
    periodo VARCHAR(20) NOT NULL, -- dia, semana, mes, anio
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    -- Ventas
    total_unidades_vendidas DECIMAL(10,2) DEFAULT 0,
    total_cajas_vendidas DECIMAL(10,2) DEFAULT 0,
    total_monto_ventas DECIMAL(10,2) DEFAULT 0,
    -- Devoluciones
    total_unidades_devueltas DECIMAL(10,2) DEFAULT 0,
    total_monto_devoluciones DECIMAL(10,2) DEFAULT 0,
    -- Inventario
    stock_inicial DECIMAL(10,2),
    stock_final DECIMAL(10,2),
    rotacion DECIMAL(10,2), -- Días de inventario
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(producto_id, sucursal_id, periodo, fecha_inicio)
);

COMMENT ON TABLE estadisticas_productos IS 'Estadísticas de ventas por producto y periodo';
CREATE INDEX idx_estadisticas_productos ON estadisticas_productos(producto_id, periodo, fecha_inicio DESC);
CREATE INDEX idx_estadisticas_productos_sucursal ON estadisticas_productos(sucursal_id, periodo, fecha_inicio DESC) WHERE sucursal_id IS NOT NULL;

-- Tabla: estadisticas_clientes
CREATE TABLE estadisticas_clientes (
    id SERIAL PRIMARY KEY,
    empresa_id INTEGER NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
    cliente_id INTEGER NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
    -- Periodo
    periodo VARCHAR(20) NOT NULL, -- dia, semana, mes, anio
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    -- Compras
    total_compras DECIMAL(10,2) DEFAULT 0,
    total_pedidos INTEGER DEFAULT 0,
    ticket_promedio DECIMAL(10,2) DEFAULT 0,
    -- Devoluciones
    total_devoluciones DECIMAL(10,2) DEFAULT 0,
    total_reclamos INTEGER DEFAULT 0,
    -- Control
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(cliente_id, periodo, fecha_inicio)
);

COMMENT ON TABLE estadisticas_clientes IS 'Estadísticas de compras por cliente y periodo';
CREATE INDEX idx_estadisticas_clientes ON estadisticas_clientes(cliente_id, periodo, fecha_inicio DESC);
CREATE INDEX idx_estadisticas_clientes_empresa ON estadisticas_clientes(empresa_id, periodo, fecha_inicio DESC);

-- =====================================================
-- NIVEL EMPRESA - AUDITORÍA
-- =====================================================

-- Tabla: auditoria
-- Registro de cambios en tablas críticas
CREATE TABLE auditoria (
    id BIGSERIAL PRIMARY KEY,
    empresa_id INTEGER REFERENCES empresas(id) ON DELETE CASCADE,
    -- Origen del cambio
    tabla VARCHAR(100) NOT NULL,
    registro_id INTEGER NOT NULL,
    operacion VARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE
    -- Usuario responsable
    usuario_id INTEGER REFERENCES usuarios(id),
    usuario_plataforma_id INTEGER REFERENCES usuarios_plataforma(id),
    -- Datos
    datos_anteriores JSONB,
    datos_nuevos JSONB,
    columnas_modificadas TEXT[],
    -- Contexto
    ip_address INET,
    user_agent TEXT,
    -- Control
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE auditoria IS 'Registro de auditoría de cambios (particionado mensual recomendado)';
CREATE INDEX idx_auditoria_empresa ON auditoria(empresa_id, timestamp DESC);
CREATE INDEX idx_auditoria_tabla ON auditoria(tabla, registro_id, timestamp DESC);
CREATE INDEX idx_auditoria_usuario ON auditoria(usuario_id, timestamp DESC) WHERE usuario_id IS NOT NULL;
CREATE INDEX idx_auditoria_plataforma ON auditoria(usuario_plataforma_id, timestamp DESC) WHERE usuario_plataforma_id IS NOT NULL;

-- =====================================================
-- ROW LEVEL SECURITY (RLS)
-- =====================================================

-- Habilitar RLS en todas las tablas de empresa
ALTER TABLE empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE configuraciones_empresa ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE tipos_vehiculos ENABLE ROW LEVEL SECURITY;
ALTER TABLE categorias_productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE motivos_justificacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE tipos_rutas ENABLE ROW LEVEL SECURITY;
ALTER TABLE sucursales ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehiculos ENABLE ROW LEVEL SECURITY;
ALTER TABLE mantenimientos ENABLE ROW LEVEL SECURITY;
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE precios_productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE cajas_fisicas ENABLE ROW LEVEL SECURITY;
ALTER TABLE movimientos_cajas ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario_sucursal ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario_vehiculo ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventario_desechos ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE direcciones_clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes_potenciales ENABLE ROW LEVEL SECURITY;
ALTER TABLE plantillas_rutas ENABLE ROW LEVEL SECURITY;
ALTER TABLE paradas_plantilla ENABLE ROW LEVEL SECURITY;
ALTER TABLE rutas ENABLE ROW LEVEL SECURITY;
ALTER TABLE paradas_ruta ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_gps ENABLE ROW LEVEL SECURITY;
ALTER TABLE puntos_interes ENABLE ROW LEVEL SECURITY;
ALTER TABLE pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE detalles_pedido ENABLE ROW LEVEL SECURITY;
ALTER TABLE ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE detalles_venta ENABLE ROW LEVEL SECURITY;
ALTER TABLE devoluciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE detalles_devolucion ENABLE ROW LEVEL SECURITY;
ALTER TABLE reclamos_clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagos ENABLE ROW LEVEL SECURITY;
ALTER TABLE transferencias_sucursales ENABLE ROW LEVEL SECURITY;
ALTER TABLE detalles_transferencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE cargas_combustible ENABLE ROW LEVEL SECURITY;
ALTER TABLE metas ENABLE ROW LEVEL SECURITY;
ALTER TABLE notificaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE estadisticas_rutas ENABLE ROW LEVEL SECURITY;
ALTER TABLE estadisticas_conductores ENABLE ROW LEVEL SECURITY;
ALTER TABLE estadisticas_productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE estadisticas_clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditoria ENABLE ROW LEVEL SECURITY;

-- Nota: Las políticas RLS específicas deben implementarse en el backend
-- basadas en el contexto del usuario autenticado (empresa_id)

-- =====================================================
-- DATOS INICIALES
-- =====================================================

-- Planes de suscripción
INSERT INTO planes_suscripcion (nombre, descripcion, precio_mensual, precio_anual, max_sucursales, max_vehiculos, max_usuarios, max_storage_mb, retencion_historico_dias, permite_multisucursal, permite_api_access, permite_reportes_avanzados, soporte_prioritario) VALUES
('Básico', 'Plan para pequeñas empresas', 49.99, 499.99, 2, 5, 10, 1024, 180, FALSE, FALSE, FALSE, FALSE),
('Profesional', 'Plan para empresas en crecimiento', 149.99, 1499.99, 10, 25, 50, 5120, 730, TRUE, TRUE, TRUE, FALSE),
('Enterprise', 'Plan para grandes empresas', 499.99, 4999.99, NULL, NULL, NULL, 51200, NULL, TRUE, TRUE, TRUE, TRUE);

-- Permisos del sistema
INSERT INTO permisos (codigo, nombre, descripcion, modulo) VALUES
-- Rutas
('rutas.ver', 'Ver rutas', 'Visualizar rutas propias o asignadas', 'rutas'),
('rutas.ver_todas', 'Ver todas las rutas', 'Visualizar todas las rutas de la empresa/sucursal', 'rutas'),
('rutas.crear', 'Crear rutas', 'Crear nuevas rutas', 'rutas'),
('rutas.editar', 'Editar rutas', 'Modificar rutas existentes', 'rutas'),
('rutas.eliminar', 'Eliminar rutas', 'Eliminar rutas', 'rutas'),
('rutas.iniciar', 'Iniciar rutas', 'Iniciar ejecución de rutas', 'rutas'),
('rutas.finalizar', 'Finalizar rutas', 'Finalizar rutas', 'rutas'),
('rutas.cancelar', 'Cancelar rutas', 'Cancelar rutas', 'rutas'),
('plantillas.crear', 'Crear plantillas', 'Crear plantillas de rutas', 'rutas'),
('plantillas.editar', 'Editar plantillas', 'Modificar plantillas', 'rutas'),
('plantillas.eliminar', 'Eliminar plantillas', 'Eliminar plantillas', 'rutas'),
-- Tracking
('tracking.ver', 'Ver tracking', 'Visualizar tracking GPS en tiempo real', 'tracking'),
('tracking.activar', 'Activar tracking', 'Activar/desactivar dibujo de ruta', 'tracking'),
('puntos_interes.crear', 'Marcar puntos de interés', 'Crear puntos de interés en el mapa', 'tracking'),
('puntos_interes.revisar', 'Revisar puntos de interés', 'Revisar y aprobar puntos de interés', 'tracking'),
-- Ventas
('ventas.ver', 'Ver ventas', 'Visualizar ventas propias', 'ventas'),
('ventas.ver_todas', 'Ver todas las ventas', 'Visualizar todas las ventas', 'ventas'),
('ventas.crear', 'Registrar ventas', 'Crear nuevas ventas', 'ventas'),
('ventas.editar', 'Editar ventas', 'Modificar ventas', 'ventas'),
('ventas.eliminar', 'Eliminar ventas', 'Eliminar ventas', 'ventas'),
('ventas.emergentes', 'Ventas emergentes', 'Registrar ventas no planificadas', 'ventas'),
-- Pedidos
('pedidos.ver', 'Ver pedidos', 'Visualizar pedidos', 'pedidos'),
('pedidos.crear', 'Crear pedidos', 'Crear nuevos pedidos', 'pedidos'),
('pedidos.editar', 'Editar pedidos', 'Modificar pedidos', 'pedidos'),
('pedidos.cancelar', 'Cancelar pedidos', 'Cancelar pedidos', 'pedidos'),
-- Clientes
('clientes.ver', 'Ver clientes', 'Visualizar clientes', 'clientes'),
('clientes.crear', 'Crear clientes', 'Registrar nuevos clientes', 'clientes'),
('clientes.editar', 'Editar clientes', 'Modificar información de clientes', 'clientes'),
('clientes.eliminar', 'Eliminar clientes', 'Eliminar clientes', 'clientes'),
('clientes_potenciales.crear', 'Registrar prospectos', 'Marcar clientes potenciales', 'clientes'),
('clientes_potenciales.revisar', 'Revisar prospectos', 'Revisar y convertir prospectos', 'clientes'),
-- Inventario
('inventario.ver', 'Ver inventario', 'Visualizar inventario', 'inventario'),
('inventario.editar', 'Editar inventario', 'Modificar inventario', 'inventario'),
('inventario.transferir', 'Transferir inventario', 'Crear transferencias entre sucursales', 'inventario'),
('inventario.aprobar_transferencia', 'Aprobar transferencias', 'Aprobar transferencias de inventario', 'inventario'),
('inventario.recibir', 'Recibir inventario', 'Recibir inventario transferido', 'inventario'),
-- Productos
('productos.ver', 'Ver productos', 'Visualizar catálogo de productos', 'productos'),
('productos.crear', 'Crear productos', 'Agregar nuevos productos', 'productos'),
('productos.editar', 'Editar productos', 'Modificar productos', 'productos'),
('productos.eliminar', 'Eliminar productos', 'Eliminar productos', 'productos'),
('precios.ver', 'Ver precios', 'Visualizar precios', 'productos'),
('precios.editar', 'Editar precios', 'Modificar precios', 'productos'),
-- Vehículos
('vehiculos.ver', 'Ver vehículos', 'Visualizar vehículos', 'vehiculos'),
('vehiculos.crear', 'Crear vehículos', 'Agregar nuevos vehículos', 'vehiculos'),
('vehiculos.editar', 'Editar vehículos', 'Modificar vehículos', 'vehiculos'),
('vehiculos.eliminar', 'Eliminar vehículos', 'Eliminar vehículos', 'vehiculos'),
('mantenimientos.ver', 'Ver mantenimientos', 'Visualizar mantenimientos', 'vehiculos'),
('mantenimientos.registrar', 'Registrar mantenimientos', 'Registrar mantenimientos', 'vehiculos'),
-- Usuarios
('usuarios.ver', 'Ver usuarios', 'Visualizar usuarios', 'usuarios'),
('usuarios.crear', 'Crear usuarios', 'Agregar nuevos usuarios', 'usuarios'),
('usuarios.editar', 'Editar usuarios', 'Modificar usuarios', 'usuarios'),
('usuarios.eliminar', 'Eliminar usuarios', 'Eliminar usuarios', 'usuarios'),
('usuarios.asignar_roles', 'Asignar roles', 'Asignar y modificar roles', 'usuarios'),
-- Sucursales
('sucursales.ver', 'Ver sucursales', 'Visualizar sucursales', 'sucursales'),
('sucursales.crear', 'Crear sucursales', 'Agregar nuevas sucursales', 'sucursales'),
('sucursales.editar', 'Editar sucursales', 'Modificar sucursales', 'sucursales'),
('sucursales.eliminar', 'Eliminar sucursales', 'Eliminar sucursales', 'sucursales'),
-- Reportes
('reportes.ventas', 'Reportes de ventas', 'Generar reportes de ventas', 'reportes'),
('reportes.rutas', 'Reportes de rutas', 'Generar reportes de rutas', 'reportes'),
('reportes.conductores', 'Reportes de conductores', 'Generar reportes de desempeño', 'reportes'),
('reportes.inventario', 'Reportes de inventario', 'Generar reportes de inventario', 'reportes'),
('reportes.financieros', 'Reportes financieros', 'Generar reportes financieros', 'reportes'),
('reportes.exportar', 'Exportar reportes', 'Exportar datos y reportes', 'reportes'),
-- Configuración
('configuracion.ver', 'Ver configuración', 'Visualizar configuración de empresa', 'configuracion'),
('configuracion.editar', 'Editar configuración', 'Modificar configuración', 'configuracion'),
('configuracion.roles', 'Gestionar roles', 'Crear y modificar roles', 'configuracion'),
('configuracion.permisos', 'Gestionar permisos', 'Asignar permisos a roles', 'configuracion'),
-- Devoluciones y reclamos
('devoluciones.ver', 'Ver devoluciones', 'Visualizar devoluciones', 'devoluciones'),
('devoluciones.registrar', 'Registrar devoluciones', 'Crear nuevas devoluciones', 'devoluciones'),
('devoluciones.revisar', 'Revisar devoluciones', 'Revisar y aprobar devoluciones', 'devoluciones'),
('reclamos.ver', 'Ver reclamos', 'Visualizar reclamos', 'reclamos'),
('reclamos.gestionar', 'Gestionar reclamos', 'Atender y resolver reclamos', 'reclamos'),
-- Notificaciones
('notificaciones.ver', 'Ver notificaciones', 'Recibir notificaciones', 'notificaciones'),
('notificaciones.enviar', 'Enviar notificaciones', 'Enviar notificaciones personalizadas', 'notificaciones'),
-- Metas
('metas.ver', 'Ver metas', 'Visualizar metas propias', 'metas'),
('metas.ver_todas', 'Ver todas las metas', 'Visualizar todas las metas', 'metas'),
('metas.crear', 'Crear metas', 'Crear nuevas metas', 'metas'),
('metas.editar', 'Editar metas', 'Modificar metas', 'metas'),
('metas.eliminar', 'Eliminar metas', 'Eliminar metas', 'metas'),
-- Autorización
('desviaciones.autorizar', 'Autorizar desviaciones', 'Autorizar desviaciones on-the-fly', 'rutas'),
('paradas.autorizar', 'Autorizar paradas', 'Autorizar paradas no planificadas', 'rutas');

-- Catálogos predefinidos de tipos de vehículos
INSERT INTO tipos_vehiculos_predefinidos (nombre, descripcion, capacidad_peso_kg_sugerida, capacidad_volumen_m3_sugerida) VALUES
('Motocicleta', 'Vehículo pequeño para entregas rápidas', 50, 0.2),
('Pick-up pequeña', 'Camioneta pickup compacta', 500, 2),
('Pick-up grande', 'Camioneta pickup de carga pesada', 1000, 4),
('Panel', 'Vehículo cerrado tipo van', 800, 6),
('Camión 3.5 ton', 'Camión ligero', 3500, 15),
('Camión 5 ton', 'Camión mediano', 5000, 25),
('Camión 8 ton', 'Camión pesado', 8000, 40),
('Tráiler', 'Camión articulado de largo recorrido', 20000, 80);

-- Catálogos predefinidos de categorías de productos
INSERT INTO categorias_productos_predefinidas (nombre, descripcion) VALUES
('Alimentos', 'Productos alimenticios'),
('Bebidas', 'Bebidas y líquidos'),
('Lácteos', 'Productos lácteos'),
('Panadería', 'Productos de panadería'),
('Carnes y embutidos', 'Productos cárnicos'),
('Frutas y verduras', 'Productos perecederos frescos'),
('Abarrotes', 'Productos de despensa'),
('Limpieza', 'Productos de limpieza'),
('Cuidado personal', 'Productos de higiene personal'),
('Juguetes', 'Juguetes y entretenimiento'),
('Ropa', 'Vestimenta y accesorios'),
('Electrónicos', 'Productos electrónicos'),
('Ferretería', 'Herramientas y materiales'),
('Papelería', 'Artículos de oficina'),
('Otros', 'Productos varios');

-- Catálogos predefinidos de motivos de justificación
INSERT INTO motivos_justificacion_predefinidos (nombre, descripcion, tipo, requiere_foto, requiere_descripcion) VALUES
-- Paradas omitidas
('Cliente cerrado', 'Local del cliente cerrado', 'parada_omitida', TRUE, TRUE),
('Cliente ausente', 'Cliente no se encontraba', 'parada_omitida', FALSE, TRUE),
('Dirección incorrecta', 'No se encontró la dirección', 'parada_omitida', TRUE, TRUE),
('Acceso bloqueado', 'No se pudo acceder a la ubicación', 'parada_omitida', TRUE, TRUE),
('Rechazó pedido', 'Cliente rechazó recibir el pedido', 'parada_omitida', FALSE, TRUE),
('Sin efectivo', 'Cliente no tenía forma de pagar', 'parada_omitida', FALSE, TRUE),
-- Desviaciones
('Bloqueo de vía', 'Calle bloqueada o cerrada', 'desviacion', TRUE, TRUE),
('Accidente en ruta', 'Accidente que impide paso', 'desviacion', TRUE, TRUE),
('Obras en la vía', 'Construcción o mantenimiento vial', 'desviacion', TRUE, FALSE),
('Tráfico excesivo', 'Congestión vehicular', 'desviacion', FALSE, TRUE),
('GPS incorrecto', 'Ruta GPS incorrecta', 'desviacion', FALSE, TRUE),
('Parada emergente', 'Venta o entrega no planificada', 'desviacion', FALSE, TRUE),
-- Retrasos
('Tráfico', 'Demora por tráfico vehicular', 'retraso', FALSE, FALSE),
('Clima adverso', 'Condiciones climáticas difíciles', 'retraso', TRUE, TRUE),
('Falla mecánica', 'Problema con el vehículo', 'retraso', TRUE, TRUE),
('Emergencia médica', 'Situación de emergencia médica', 'retraso', FALSE, TRUE),
('Cliente demoró', 'Cliente tardó en atender', 'retraso', FALSE, FALSE),
-- Cambios de inventario
('Producto dañado', 'Producto se dañó durante transporte', 'cambio_inventario', TRUE, TRUE),
('Producto vencido', 'Producto alcanzó fecha de vencimiento', 'cambio_inventario', TRUE, TRUE),
('Faltante en carga', 'No se cargó el producto solicitado', 'cambio_inventario', FALSE, TRUE),
('Error de conteo', 'Diferencia en inventario', 'cambio_inventario', FALSE, TRUE),
('Cambio solicitado', 'Cliente solicitó cambio de producto', 'cambio_inventario', FALSE, TRUE);

-- =====================================================
-- VISTAS ÚTILES
-- =====================================================

-- Vista: Inventario total por producto y empresa
CREATE VIEW vista_inventario_total AS
SELECT 
    p.empresa_id,
    p.id AS producto_id,
    p.codigo_sku,
    p.nombre AS producto_nombre,
    COALESCE(SUM(inv_suc.cantidad_cajas), 0) AS total_cajas_sucursales,
    COALESCE(SUM(inv_suc.cantidad_unidades), 0) AS total_unidades_sucursales,
    COALESCE(SUM(inv_veh.cantidad_cajas), 0) AS total_cajas_vehiculos,
    COALESCE(SUM(inv_veh.cantidad_unidades), 0) AS total_unidades_vehiculos,
    COALESCE(SUM(inv_suc.cantidad_cajas), 0) + COALESCE(SUM(inv_veh.cantidad_cajas), 0) AS total_cajas,
    COALESCE(SUM(inv_suc.cantidad_unidades), 0) + COALESCE(SUM(inv_veh.cantidad_unidades), 0) AS total_unidades
FROM productos p
LEFT JOIN inventario_sucursal inv_suc ON p.id = inv_suc.producto_id
LEFT JOIN inventario_vehiculo inv_veh ON p.id = inv_veh.producto_id
WHERE p.deleted_at IS NULL
GROUP BY p.empresa_id, p.id, p.codigo_sku, p.nombre;

COMMENT ON VIEW vista_inventario_total IS 'Vista consolidada de inventario total por producto';

-- Vista: Rutas activas con información completa
CREATE VIEW vista_rutas_activas AS
SELECT 
    r.id AS ruta_id,
    r.empresa_id,
    r.numero_ruta,
    r.estado,
    r.fecha_planificada,
    r.hora_inicio_real,
    r.tracking_activo,
    s.nombre AS sucursal_nombre,
    v.placa AS vehiculo_placa,
    v.ubicacion_actual AS vehiculo_ubicacion,
    c.nombre_completo AS conductor_nombre,
    c.telefono AS conductor_telefono,
    sup.nombre_completo AS supervisor_nombre,
    tr.nombre AS tipo_ruta_nombre,
    COUNT(DISTINCT pr.id) AS total_paradas,
    COUNT(DISTINCT CASE WHEN pr.estado = 'completada' THEN pr.id END) AS paradas_completadas,
    r.distancia_recorrida_km,
    r.adherencia_porcentaje
FROM rutas r
JOIN sucursales s ON r.sucursal_id = s.id
JOIN vehiculos v ON r.vehiculo_id = v.id
JOIN usuarios c ON r.conductor_id = c.id
LEFT JOIN usuarios sup ON r.supervisor_id = sup.id
JOIN tipos_rutas tr ON r.tipo_ruta_id = tr.id
LEFT JOIN paradas_ruta pr ON r.id = pr.ruta_id
WHERE r.estado IN ('planificada', 'en_progreso')
    AND r.deleted_at IS NULL
GROUP BY r.id, r.empresa_id, r.numero_ruta, r.estado, r.fecha_planificada, 
         r.hora_inicio_real, r.tracking_activo, s.nombre, v.placa, v.ubicacion_actual,
         c.nombre_completo, c.telefono, sup.nombre_completo, tr.nombre,
         r.distancia_recorrida_km, r.adherencia_porcentaje;

COMMENT ON VIEW vista_rutas_activas IS 'Vista de rutas activas con información consolidada';

-- Vista: Vehículos disponibles
CREATE VIEW vista_vehiculos_disponibles AS
SELECT 
    v.id AS vehiculo_id,
    v.empresa_id,
    v.placa,
    v.marca,
    v.modelo,
    tv.nombre AS tipo_vehiculo,
    v.capacidad_peso_kg,
    v.capacidad_volumen_m3,
    v.estado,
    s.nombre AS sucursal_actual,
    v.ubicacion_actual,
    v.ultimo_mantenimiento,
    v.proximo_mantenimiento,
    CASE 
        WHEN v.proximo_mantenimiento IS NOT NULL 
             AND v.proximo_mantenimiento <= CURRENT_DATE 
        THEN TRUE 
        ELSE FALSE 
    END AS requiere_mantenimiento
FROM vehiculos v
JOIN tipos_vehiculos tv ON v.tipo_vehiculo_id = tv.id
LEFT JOIN sucursales s ON v.sucursal_actual_id = s.id
WHERE v.estado = 'disponible'
    AND v.activo = TRUE
    AND v.deleted_at IS NULL;

COMMENT ON VIEW vista_vehiculos_disponibles IS 'Vista de vehículos disponibles para asignar';

-- Vista: Dashboard de conductores
CREATE VIEW vista_dashboard_conductor AS
SELECT 
    u.id AS conductor_id,
    u.empresa_id,
    u.nombre_completo,
    u.email,
    u.telefono,
    COUNT(DISTINCT r.id) FILTER (WHERE r.fecha_planificada >= CURRENT_DATE - INTERVAL '30 days') AS rutas_ultimo_mes,
    COUNT(DISTINCT r.id) FILTER (WHERE r.estado = 'completada' AND r.fecha_planificada >= CURRENT_DATE - INTERVAL '30 days') AS rutas_completadas_ultimo_mes,
    COALESCE(AVG(r.adherencia_porcentaje) FILTER (WHERE r.estado = 'completada' AND r.fecha_planificada >= CURRENT_DATE - INTERVAL '30 days'), 0) AS adherencia_promedio,
    COALESCE(SUM(v.total) FILTER (WHERE v.fecha_venta >= CURRENT_TIMESTAMP - INTERVAL '30 days'), 0) AS ventas_ultimo_mes,
    COUNT(DISTINCT v.id) FILTER (WHERE v.es_venta_emergente = TRUE AND v.fecha_venta >= CURRENT_TIMESTAMP - INTERVAL '30 days') AS ventas_emergentes_ultimo_mes,
    COUNT(DISTINCT cp.id) FILTER (WHERE cp.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days') AS clientes_potenciales_ultimo_mes
FROM usuarios u
LEFT JOIN rutas r ON u.id = r.conductor_id AND r.deleted_at IS NULL
LEFT JOIN ventas v ON r.id = v.ruta_id AND v.deleted_at IS NULL
LEFT JOIN clientes_potenciales cp ON u.id = cp.registrado_por AND cp.archivado = FALSE
WHERE u.deleted_at IS NULL
GROUP BY u.id, u.empresa_id, u.nombre_completo, u.email, u.telefono;

COMMENT ON VIEW vista_dashboard_conductor IS 'Vista de dashboard con métricas por conductor';

-- =====================================================
-- COMENTARIOS FINALES Y RECOMENDACIONES
-- =====================================================

COMMENT ON DATABASE postgres IS 'Sistema Multi-Tenant de Gestión de Rutas, Logística y Ventas';

-- =====================================================
-- LISTA DE TRIGGERS Y FUNCIONES A IMPLEMENTAR
-- =====================================================

/*
TRIGGERS Y FUNCIONES REQUERIDAS (A IMPLEMENTAR POR EL DESARROLLADOR):

=== CRÍTICO - IMPLEMENTAR PRIMERO ===

1. GENERACIÓN AUTOMÁTICA DE NÚMEROS
   - trigger_generar_numero_ruta() -> BEFORE INSERT ON rutas
   - trigger_generar_numero_venta() -> BEFORE INSERT ON ventas
   - trigger_generar_numero_pedido() -> BEFORE INSERT ON pedidos
   - trigger_generar_numero_transferencia() -> BEFORE INSERT ON transferencias_sucursales
   - trigger_generar_codigo_caja() -> BEFORE INSERT ON cajas_fisicas
   - trigger_generar_numero_devolucion() -> BEFORE INSERT ON devoluciones
   - trigger_generar_numero_reclamo() -> BEFORE INSERT ON reclamos_clientes
   - trigger_generar_numero_pago() -> BEFORE INSERT ON pagos

2. VALIDACIONES DE NEGOCIO
   - trigger_validar_vehiculo_disponible() -> BEFORE INSERT ON rutas
   - trigger_validar_conductor_disponible() -> BEFORE INSERT ON rutas
   - trigger_registrar_inicio_sin_inventario() -> AFTER INSERT ON rutas
   - trigger_alertar_productos_vencimiento() -> Función periódica + notificaciones
   - trigger_validar_limite_suscripcion() -> BEFORE INSERT en sucursales, vehiculos, usuarios

3. ACTUALIZACIÓN DE INVENTARIO
   - trigger_actualizar_inventario_venta() -> AFTER INSERT/UPDATE ON detalles_venta
   - trigger_actualizar_inventario_devolucion() -> AFTER INSERT ON detalles_devolucion
   - trigger_recalcular_peso_volumen_venta() -> AFTER INSERT/UPDATE ON detalles_venta
   - trigger_actualizar_inventario_carga_vehiculo() -> AFTER INSERT/UPDATE ON inventario_vehiculo
   - trigger_mover_desechos_a_inventario() -> AFTER UPDATE ON inventario_desechos

4. TRANSFERENCIAS ENTRE SUCURSALES
   - trigger_iniciar_transferencia() -> AFTER UPDATE ON transferencias_sucursales (estado='en_transito')
   - trigger_completar_transferencia() -> AFTER UPDATE ON transferencias_sucursales (estado='recibida')
   - trigger_detectar_discrepancias_transferencia() -> AFTER INSERT ON detalles_transferencia
   - trigger_notificar_discrepancia() -> Dentro de detectar_discrepancias

5. GEOMETRÍAS Y TRACKING GPS
   - funcion_construir_geometria_recorrida(ruta_id) -> Construye LineString desde puntos GPS
   - trigger_actualizar_geometria_tiempo_real() -> AFTER INSERT ON tracking_gps
   - trigger_detectar_desviacion() -> AFTER INSERT ON tracking_gps
   - trigger_notificar_proximidad_parada() -> AFTER INSERT ON tracking_gps
   - trigger_detectar_parada_emergente() -> AFTER INSERT ON tracking_gps (velocidad=0)
   - funcion_simplificar_geometria(geometria, tolerancia) -> ST_Simplify wrapper

6. MÉTRICAS Y ANÁLISIS DE RUTAS
   - funcion_calcular_metricas_ruta(ruta_id) -> Calcula adherencia, desviaciones, tiempo perdido
   - trigger_calcular_metricas_al_completar() -> AFTER UPDATE ON rutas (estado='completada')
   - funcion_convertir_recorrido_a_plantilla(ruta_id) -> Convierte ruta real en plantilla

=== ALTA PRIORIDAD ===

7. SISTEMA DE NOTIFICACIONES (11 tipos)
   - trigger_notificar_inicio_fuera_margen() -> AFTER UPDATE ON rutas (hora_inicio_real)
   - trigger_notificar_fin_fuera_margen() -> AFTER UPDATE ON rutas (hora_fin_real)
   - trigger_notificar_parada_completada() -> AFTER UPDATE ON paradas_ruta (estado='completada')
   - trigger_notificar_parada_omitida() -> AFTER UPDATE ON paradas_ruta (estado='omitida')
   - trigger_notificar_venta_emergente() -> AFTER INSERT ON ventas (es_venta_emergente=TRUE)
   - trigger_notificar_cliente_potencial() -> AFTER INSERT ON clientes_potenciales
   - trigger_notificar_devolucion() -> AFTER INSERT ON devoluciones
   - trigger_notificar_reclamo() -> AFTER INSERT ON reclamos_clientes
   - trigger_notificar_meta_alcanzada() -> AFTER UPDATE ON metas (porcentaje>=100)
   - funcion_agrupar_notificaciones_repetidas() -> Evita spam de notificaciones similares

8. ESTADÍSTICAS EN TIEMPO REAL
   - trigger_actualizar_estadisticas_ruta() -> AFTER UPDATE ON rutas (estado='completada')
   - trigger_actualizar_estadisticas_conductor() -> Después de actualizar_estadisticas_ruta
   - trigger_actualizar_estadisticas_producto_venta() -> AFTER INSERT ON detalles_venta
   - trigger_actualizar_estadisticas_producto_devolucion() -> AFTER INSERT ON detalles_devolucion
   - trigger_actualizar_estadisticas_cliente() -> AFTER INSERT ON ventas, pagos, devoluciones
   - funcion_recalcular_estadisticas_periodo() -> Recalculo manual de stats históricas

9. ANÁLISIS GEOESPACIAL
   - funcion_calcular_area_cobertura_sucursal(sucursal_id) -> Union de geometrías + buffer
   - funcion_detectar_gaps_cobertura(sucursal_id) -> Detecta zonas sin cobertura
   - funcion_identificar_solapamiento_rutas(sucursal_id) -> Detecta rutas que se solapan
   - funcion_clustering_clientes(sucursal_id, num_clusters) -> Agrupa clientes por proximidad
   - funcion_calcular_ruta_optima(paradas[]) -> TSP simplificado para optimizar orden

10. GESTIÓN DE CAJAS FÍSICAS
    - trigger_registrar_movimiento_caja() -> AFTER INSERT/UPDATE ON inventario_vehiculo
    - trigger_alertar_cajas_perdidas() -> Función periódica (cajas sin movimiento >30 días)
    - trigger_actualizar_estado_caja() -> AFTER INSERT ON movimientos_cajas

=== MEDIA PRIORIDAD ===

11. FUNCIONES DE DASHBOARD
    - funcion_get_rutas_activas_sucursal(sucursal_id) -> JSON de rutas en progreso
    - funcion_get_dashboard_conductor(conductor_id) -> JSON con métricas del conductor
    - funcion_get_dashboard_supervisor(supervisor_id) -> JSON con métricas de equipo
    - funcion_get_dashboard_admin(empresa_id) -> JSON con métricas globales

12. SISTEMA DE PERMISOS
    - funcion_verificar_permiso(usuario_id, permiso_codigo) -> Verifica si tiene permiso
    - funcion_autorizar_desviacion(ruta_id, usuario_id) -> Autoriza desviación on-the-fly

13. AUDITORÍA EXTENDIDA
    - trigger_auditoria_generico() -> Para todas las tablas críticas
      Aplicar a: clientes, inventario_sucursal, inventario_vehiculo, pedidos, ventas,
                 devoluciones, transferencias_sucursales, mantenimientos, usuarios, rutas

14. UTILIDADES Y MANTENIMIENTO
    - funcion_archivar_clientes_potenciales() -> Archiva prospectos >30 días
    - funcion_archivar_rutas_antiguas(dias) -> Mueve rutas antiguas a histórico
    - funcion_comprimir_tracking_gps(fecha_limite) -> Simplifica puntos GPS antiguos
    - funcion_limpiar_notificaciones_antiguas(dias) -> Limpia notificaciones leídas
    - funcion_validar_consistencia_inventarios() -> Detecta inconsistencias

15. ONBOARDING Y MÉTRICAS DE EMPRESA
    - trigger_actualizar_onboarding() -> AFTER INSERT en sucursales, vehiculos, productos, rutas
    - trigger_actualizar_uso_limites() -> AFTER INSERT/DELETE en sucursales, vehiculos, usuarios
    - trigger_alertar_limite_cercano() -> Cuando uso_x >= 80% de max_x

=== BAJA PRIORIDAD (OPTIMIZACIÓN) ===

16. OPTIMIZACIONES DE PERFORMANCE
    - Implementar particionamiento mensual en:
      * tracking_gps (por timestamp)
      * auditoria (por timestamp)
      * estadisticas_* (por periodo)
    - Crear índices compuestos adicionales según queries más frecuentes
    - Configurar materialización de vistas pesadas

17. FUNCIONES DE EXPORTACIÓN
    - funcion_exportar_datos_empresa(empresa_id) -> Exporta todos los datos en JSON/CSV
    - funcion_generar_backup_empresa(empresa_id) -> Backup completo de datos

18. WEBSOCKETS Y TIEMPO REAL
    - funcion_broadcast_actualizacion_ruta(ruta_id) -> Notifica cambios vía WebSocket
    - funcion_get_ultimos_puntos_gps(ruta_id, limite) -> Últimos N puntos GPS
    - trigger_notificar_cambio_tiempo_real() -> En tracking_gps, ventas, paradas_ruta

19. POLÍTICAS RLS (ROW LEVEL SECURITY)
    Implementar políticas para TODAS las tablas con empresa_id:
    
    CREATE POLICY politica_empresa_usuarios ON [tabla]
        USING (empresa_id = current_setting('app.current_empresa_id')::INTEGER);
    
    CREATE POLICY politica_plataforma_admin ON [tabla]
        USING (
            current_setting('app.es_usuario_plataforma')::BOOLEAN = TRUE
            AND current_setting('app.puede_ver_todas_empresas')::BOOLEAN = TRUE
        );
    
    CREATE POLICY politica_tecnico_asignado ON [tabla]
        USING (
            current_setting('app.es_usuario_plataforma')::BOOLEAN = TRUE
            AND empresa_id IN (
                SELECT empresa_id FROM asignaciones_soporte 
                WHERE usuario_plataforma_id = current_setting('app.usuario_plataforma_id')::INTEGER
                AND activo = TRUE
            )
        );

20. FUNCIONES DE CÁLCULO AUTOMÁTICO
    - trigger_calcular_volumen_caja() -> BEFORE INSERT/UPDATE ON productos (alto*ancho*largo)
    - trigger_calcular_totales_pedido() -> AFTER INSERT/UPDATE ON detalles_pedido
    - trigger_calcular_totales_venta() -> AFTER INSERT/UPDATE ON detalles_venta
    - trigger_calcular_saldo_cliente() -> AFTER INSERT/UPDATE ON ventas, pagos, devoluciones
    - trigger_actualizar_ticket_promedio() -> AFTER INSERT ON ventas
    - trigger_calcular_eficiencia_combustible() -> AFTER INSERT ON cargas_combustible
    - trigger_actualizar_ubicacion_vehiculo() -> AFTER INSERT ON tracking_gps

21. VALIDACIONES ADICIONALES
    - trigger_validar_fechas_transferencia() -> Fecha salida <= fecha llegada
    - trigger_validar_capacidad_vehiculo() -> Peso/volumen no excede capacidad
    - trigger_validar_stock_disponible() -> Antes de venta/pedido
    - trigger_validar_limite_credito_cliente() -> Antes de venta a crédito
    - trigger_validar_horario_parada() -> Verificar horarios de recepción

22. FUNCIONES DE CÁLCULO DE DISTANCIAS
    - funcion_calcular_distancia_entre_puntos(punto1, punto2) -> Distancia en km
    - funcion_calcular_distancia_a_ruta(punto, ruta) -> Distancia perpendicular
    - funcion_obtener_punto_mas_cercano_ruta(punto, ruta) -> Punto más cercano
    - funcion_verificar_punto_dentro_area(punto, area) -> Verifica si está dentro

23. INTEGRACIONES Y WEBHOOKS
    - funcion_enviar_webhook_evento(tipo_evento, datos) -> Envía webhooks a sistemas externos
    - trigger_webhook_ruta_completada() -> AFTER UPDATE ON rutas (estado='completada')
    - trigger_webhook_venta_nueva() -> AFTER INSERT ON ventas
    - trigger_webhook_cliente_nuevo() -> AFTER INSERT ON clientes

=== NOTAS IMPORTANTES ===

A. CONFIGURACIÓN DEL BACKEND (Set al iniciar sesión):
   
   SET app.current_empresa_id = [empresa_id];
   SET app.current_usuario_id = [usuario_id];
   SET app.es_usuario_plataforma = [true/false];
   SET app.puede_ver_todas_empresas = [true/false];
   SET app.usuario_plataforma_id = [id o NULL];

B. PARTICIONAMIENTO RECOMENDADO:
   
   tracking_gps: Particionar por RANGE(timestamp) mensual
   auditoria: Particionar por RANGE(timestamp) mensual
   notificaciones: Particionar por RANGE(created_at) trimestral

C. ÍNDICES ADICIONALES SEGÚN PATRONES DE USO:
   
   - Crear índices compuestos basados en queries más frecuentes del backend
   - Usar índices parciales para filtros comunes (estado='activo', deleted_at IS NULL)
   - Índices GIN en columnas JSONB si se consultan frecuentemente

D. VISTAS MATERIALIZADAS (REFRESH PERIÓDICO):
   
   CREATE MATERIALIZED VIEW mv_top_productos_vendidos AS
   SELECT producto_id, SUM(cantidad_unidades_vendidas) as total
   FROM estadisticas_productos
   WHERE periodo = 'mes' AND fecha_inicio >= CURRENT_DATE - INTERVAL '6 months'
   GROUP BY producto_id
   ORDER BY total DESC
   LIMIT 100;
   
   CREATE MATERIALIZED VIEW mv_top_conductores AS
   SELECT conductor_id, AVG(adherencia_promedio) as adherencia,
          SUM(total_ventas) as ventas
   FROM estadisticas_conductores
   WHERE periodo = 'mes' AND fecha_inicio >= CURRENT_DATE - INTERVAL '3 months'
   GROUP BY conductor_id
   ORDER BY adherencia DESC, ventas DESC
   LIMIT 50;

E. MANTENIMIENTO PERIÓDICO (CRON JOBS):
   
   - Diario: Archivar clientes_potenciales vencidos
   - Diario: Alertar productos por vencer
   - Diario: Alertar cajas perdidas
   - Semanal: Refresh vistas materializadas
   - Semanal: Comprimir tracking_gps antiguo (>6 meses)
   - Mensual: Archivar rutas antiguas (>1 año)
   - Mensual: Limpiar notificaciones leídas (>3 meses)
   - Mensual: Validar consistencia de inventarios

F. SOFT DELETES:
   
   Todas las tablas principales tienen deleted_at y deleted_by.
   NUNCA hacer DELETE físico, siempre UPDATE deleted_at = CURRENT_TIMESTAMP.
   Los índices deben incluir WHERE deleted_at IS NULL.

G. SEGURIDAD:
   
   - NUNCA almacenar passwords en texto plano (usar bcrypt/argon2)
   - Encriptar two_factor_secret con pgcrypto
   - Logs de auditoría para toda operación crítica
   - RLS habilitado en TODAS las tablas de empresa
   - Validar entrada en backend antes de INSERT/UPDATE

H. PERFORMANCE:
   
   - Usar EXPLAIN ANALYZE para optimizar queries lentas
   - Índices GIST en todas las columnas GEOGRAPHY
   - Índices B-tree en FKs y columnas de filtrado frecuente
   - Connection pooling en el backend (PgBouncer/HikariCP)
   - Limitar resultados con LIMIT y paginación

I. WEBSOCKETS (Eventos en tiempo real):
   
   Eventos a transmitir:
   - tracking_gps: Nueva posición de vehículo
   - paradas_ruta: Parada completada/omitida
   - ventas: Nueva venta registrada
   - notificaciones: Nueva notificación
   - rutas: Cambio de estado de ruta
   - desviaciones: Desviación detectada
   
   Usar canales de PostgreSQL LISTEN/NOTIFY o solución externa (Redis Pub/Sub)

J. MIGRACIONES:
   
   - Versionar todos los cambios de esquema
   - Usar herramientas como Flyway o Liquibase
   - Probar migraciones en ambiente de staging primero
   - Mantener backup antes de cada migración en producción

K. DATOS DE DEMOSTRACIÓN:
   
   Crear función: funcion_seed_empresa_demo(empresa_id)
   Que cree:
   - 3 sucursales
   - 10 vehículos
   - 20 usuarios (diferentes roles)
   - 50 productos
   - 100 clientes
   - 20 plantillas de rutas
   - 100 rutas históricas con tracking GPS
   - 500 ventas históricas
   - Estadísticas calculadas

L. MONITOREO:
   
   Métricas a monitorear:
   - Tamaño de tracking_gps (crecimiento diario)
   - Tamaño de auditoria (crecimiento diario)
   - Queries lentas (> 1 segundo)
   - Uso de disco por empresa
   - Rutas activas por empresa
   - Conexiones activas a la base de datos
   - Bloqueos (locks) de tablas

M. BACKUP Y RECUPERACIÓN:
   
   - Backup completo diario (pg_dump)
   - WAL archiving para point-in-time recovery
   - Backup de geometrías en formato GeoJSON
   - Probar recuperación mensualmente
   - Backup off-site/cloud

N. CONSIDERACIONES MULTI-TENANT:
   
   - NUNCA mezclar datos de diferentes empresas en queries
   - Siempre filtrar por empresa_id en WHERE
   - RLS como última línea de defensa (no como única)
   - Validar empresa_id en backend antes de operaciones
   - Logs de acceso cross-tenant para auditoría

O. LÍMITES Y QUOTAS:
   
   - Implementar límites de plan en el backend
   - Bloquear operaciones si se excede límite
   - Notificar al acercarse al límite (80%)
   - Ofrecer upgrade de plan automáticamente
   - Tracking de uso en tiempo real

P. CAMPOS CALCULADOS RECOMENDADOS:
   
   En rutas:
   - distancia_recorrida_km (calculado desde tracking_gps)
   - duracion_real_minutos (calculado)
   - adherencia_porcentaje (calculado)
   
   En clientes:
   - saldo_pendiente (calculado desde ventas/pagos)
   - ticket_promedio (calculado)
   
   En productos:
   - volumen_caja_m3 (calculado desde dimensiones)

Q. REPORTES FRECUENTES A OPTIMIZAR:
   
   1. Ventas diarias por sucursal
   2. Rutas completadas vs planificadas (por periodo)
   3. Top 10 productos más vendidos
   4. Top 10 conductores por desempeño
   5. Inventario actual por sucursal
   6. Clientes con saldo pendiente
   7. Vehículos con mantenimiento pendiente
   8. Metas por completar
   9. Clientes potenciales sin revisar
   10. Reclamos sin resolver

R. TESTING:
   
   - Unit tests para todas las funciones PL/pgSQL
   - Integration tests para triggers
   - Performance tests con datos de producción simulados
   - Security tests (SQL injection, RLS bypass)
   - Load testing (1000+ rutas simultáneas)

S. DOCUMENTACIÓN:
   
   - Documentar cada función con comentarios
   - Mantener ERD actualizado
   - Documentar decisiones de diseño
   - API docs para funciones públicas
   - Guía de troubleshooting común

========================================
FIN DE LISTA DE TRIGGERS Y FUNCIONES
========================================

RESUMEN FINAL:
- 70+ tablas creadas
- Multi-tenancy con empresa_id
- RLS habilitado
- Soft deletes implementados
- Índices optimizados (B-tree, GiST, GIN)
- Vistas útiles creadas
- Catálogos predefinidos poblados
- Sistema de permisos granular
- Soporte para suscripciones y facturación
- Onboarding tracking
- PostGIS para análisis geoespacial
- Auditoría completa
- Flexible y configurable por empresa

PRÓXIMOS PASOS:
1. Implementar triggers críticos (generación de números, validaciones)
2. Implementar RLS policies
3. Crear funciones de tracking GPS y geometrías
4. Implementar sistema de notificaciones
5. Crear funciones de estadísticas
6. Setup de particionamiento
7. Testing exhaustivo
8. Documentación de API
9. Migración inicial con datos demo
10. Monitoreo y optimización continua

*/