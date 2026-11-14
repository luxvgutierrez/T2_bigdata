"""
Generador de datos sintéticos escalables para el data lake.

Toma los CSV reales de `ETL/raw` y produce un dataset del mismo esquema pero
con N veces más volumen, preservando la integridad referencial del modelo:

  - Las dimensiones crecen (más productos, clientes, proveedores, trabajadores)
    con claves surrogate y de negocio nuevas.
  - Los hechos crecen proporcionalmente y SIEMPRE referencian claves válidas.
  - El snapshot se genera como producto cartesiano producto x día (su grano).
  - Opcionalmente inyecta errores CONOCIDOS (y registra la verdad en
    `_verdad_errores.csv`) para medir la detección de las reglas de calidad.

Uso:
    python generador_sintetico.py --escalas 1,5,10
    python generador_sintetico.py --escala 50 --errores 0.02
"""
import argparse
import json
import shutil
from pathlib import Path

import numpy as np
import pandas as pd

import config_spark as cfg

SEMILLA = 42

NOMBRES = ['María', 'José', 'Luis', 'Ana', 'Carlos', 'Rosa', 'Jorge', 'Lucía',
           'Pedro', 'Carmen', 'Miguel', 'Elena', 'Raúl', 'Sofía', 'Diego',
           'Patricia', 'Fernando', 'Claudia', 'Ricardo', 'Verónica']
APELLIDOS = ['Quispe', 'Rojas', 'Chávez', 'Ramírez', 'Flores', 'Vargas',
             'Huamán', 'Castro', 'Mendoza', 'Salazar', 'Paredes', 'Torres',
             'Gutiérrez', 'Sánchez', 'Ríos', 'Cárdenas', 'Ponce', 'Aguilar']

CATEGORIAS = [
    ('Arroz', 'ABARR', 4.50, 'kg'), ('Azúcar', 'ABARR', 4.20, 'kg'),
    ('Aceite', 'ABARR', 8.90, 'L'), ('Fideos', 'ABARR', 3.80, 'paq'),
    ('Atún', 'ABARR', 5.60, 'lata'), ('Leche', 'LACTEOS', 4.30, 'L'),
    ('Queso', 'LACTEOS', 12.50, 'kg'), ('Yogur', 'LACTEOS', 2.80, 'vaso'),
    ('Detergente', 'LIMPIEZA', 9.90, 'kg'), ('Jabón', 'LIMPIEZA', 2.50, 'unid'),
    ('Lejía', 'LIMPIEZA', 3.20, 'L'), ('Papel higiénico', 'LIMPIEZA', 6.40, 'paq'),
    ('Galletas', 'SNACKS', 1.80, 'paq'), ('Chocolate', 'SNACKS', 3.50, 'unid'),
    ('Gaseosa', 'BEBIDAS', 3.00, 'L'), ('Agua', 'BEBIDAS', 1.50, 'L'),
    ('Café', 'BEBIDAS', 11.20, 'kg'), ('Jugo', 'BEBIDAS', 4.70, 'L'),
]
MARCAS = ['Costeño', 'Primor', 'Alicorp', 'Gloria', 'Laive', 'Bolívar',
          'Nestlé', 'San Fernando', 'Backus', 'Coca-Cola']
TIPOS_CLIENTE = ['Minorista', 'Mayorista', 'Bodega', 'Restaurante']
TIPOS_PAGO = ['Crédito 7 días', 'Crédito 15 días', 'Contado', 'Crédito 30 días']
ESTADOS_CREDITO = ['Aprobado', 'Aprobado', 'Aprobado', 'Observado']
CAT_LABORAL = ['Ventas', 'Almacén', 'Caja', 'Administración']
TIPO_TRABAJADOR = ['Cajero', 'Vendedor', 'Almacenero', 'Supervisor']


# --------------------------------------------------------------------------
# Lectura del dataset real
# --------------------------------------------------------------------------
def leer_reales(ruta_raw: Path) -> dict:
    """Lee los CSV reales como texto (conserva '000001' y 'T00001')."""
    datos = {}
    for tabla in cfg.TABLAS:
        ruta = ruta_raw / f'{tabla}.csv'
        if ruta.exists():
            datos[tabla] = pd.read_csv(
                ruta, dtype=str, keep_default_na=False, na_values=[''])
    return datos


# --------------------------------------------------------------------------
# Expansión de dimensiones
# --------------------------------------------------------------------------
def expandir_productos(productos: pd.DataFrame, rng, escala: int) -> pd.DataFrame:
    """Agrega (escala-1)*80 productos nuevos con precios por categoría."""
    nuevos = []
    sk_base = int(pd.to_numeric(productos['sk_producto']).max()) + 1
    cod_base = 900001
    faltan = 80 * (escala - 1)
    for i in range(faltan):
        categoria, cod_tipo, precio, unidad = CATEGORIAS[i % len(CATEGORIAS)]
        marca = MARCAS[(i * 7) % len(MARCAS)]
        nuevos.append({
            'sk_producto': str(sk_base + i),
            'cod_producto': f'{cod_base + i:06d}',
            'descripcion': f'{categoria} {marca} {1 + (i % 5)} {unidad}',
            'cod_tipo_producto': cod_tipo,
            'tipo_producto': categoria,
            'estado_producto': 'Activo',
            'precio_lista': f'{precio * (0.85 + 0.30 * rng.random()):.2f}',
            'fecha_inicio': '2025-01-01',
            'fecha_fin': '',
            'es_vigente': 'True',
        })
    if not nuevos:
        return productos
    return pd.concat([productos, pd.DataFrame(nuevos)], ignore_index=True)


def expandir_clientes(clientes: pd.DataFrame, rng, escala: int) -> pd.DataFrame:
    """Agrega (escala-1)*300 clientes nuevos."""
    nuevos = []
    sk_base = int(pd.to_numeric(clientes['sk_cliente']).max()) + 1
    faltan = 300 * (escala - 1)
    for i in range(faltan):
        nombre = NOMBRES[int(rng.integers(0, len(NOMBRES)))]
        apellido = APELLIDOS[int(rng.integers(0, len(APELLIDOS)))]
        nuevos.append({
            'sk_cliente': str(sk_base + i),
            'id_cliente': f'{900001 + i:06d}',
            'dni': f'{40000000 + i:08d}',
            'nombres': f'{nombre} {APELLIDOS[(i + 3) % len(APELLIDOS)]}',
            'apellidos': apellido,
            'fecha_nacimiento': f'{1960 + (i % 45):04d}-{(i % 12) + 1:02d}-{(i % 27) + 1:02d}',
            'correo': f'cliente{i + 1}@correo-demo.pe',
            'telefono': f'9{10000000 + i:08d}',
            'tipo_cliente': TIPOS_CLIENTE[i % len(TIPOS_CLIENTE)],
            'direccion': f'Lima Norte - Zona {(i % 20) + 1}',
            'fecha_inicio': '2025-01-01',
            'fecha_fin': '',
            'es_vigente': 'True',
        })
    if not nuevos:
        return clientes
    return pd.concat([clientes, pd.DataFrame(nuevos)], ignore_index=True)


def expandir_proveedores(proveedores: pd.DataFrame, rng, escala: int) -> pd.DataFrame:
    nuevos = []
    sk_base = int(pd.to_numeric(proveedores['sk_proveedor']).max()) + 1
    for i in range(20 * (escala - 1)):
        categoria, cod_tipo, _, _ = CATEGORIAS[i % len(CATEGORIAS)]
        nuevos.append({
            'sk_proveedor': str(sk_base + i),
            'id_provedor': f'{900001 + i:06d}',
            'nombre_proveedor': f'Distribuidora {categoria} {i + 1}',
            'cod_tipo_provedor': cod_tipo,
            'tipo_proveedor': categoria,
            'limite_credito': f'{5000 + 500 * (i % 20):.2f}',
            'plazo_pago_dias': str([7, 15, 30][i % 3]),
            'tipo_pago': TIPOS_PAGO[i % len(TIPOS_PAGO)],
            'estado_credito': ESTADOS_CREDITO[i % len(ESTADOS_CREDITO)],
            'tiene_delivery': 'True' if i % 4 else 'False',
            'telefono': f'01-640-{1000 + i}',
            'fecha_inicio': '2024-01-01',
            'fecha_fin': '',
            'es_vigente': 'True',
        })
    if not nuevos:
        return proveedores
    return pd.concat([proveedores, pd.DataFrame(nuevos)], ignore_index=True)


def expandir_trabajadores(trabajadores: pd.DataFrame, rng, escala: int) -> pd.DataFrame:
    nuevos = []
    sk_base = int(pd.to_numeric(trabajadores['sk_trabajador']).max()) + 1
    for i in range(20 * (escala - 1)):
        nombre = NOMBRES[int(rng.integers(0, len(NOMBRES)))]
        nuevos.append({
            'sk_trabajador': str(sk_base + i),
            'id_trabajador': f'T{90001 + i:05d}',
            'dni': f'{71000000 + i:08d}',
            'nombres': nombre,
            'apellidos': APELLIDOS[(i + 5) % len(APELLIDOS)],
            'fecha_nacimiento': f'{1980 + (i % 25):04d}-{(i % 12) + 1:02d}-{(i % 27) + 1:02d}',
            'tipo_trabajador': TIPO_TRABAJADOR[i % len(TIPO_TRABAJADOR)],
            'cat_laboral': CAT_LABORAL[i % len(CAT_LABORAL)],
            'fecha_inicio': '2024-01-10',
            'fecha_fin': '',
            'es_vigente': 'True',
        })
    if not nuevos:
        return trabajadores
    return pd.concat([trabajadores, pd.DataFrame(nuevos)], ignore_index=True)


# --------------------------------------------------------------------------
# Generación de hechos
# --------------------------------------------------------------------------
def generar_ventas(dims: dict, rng, escala: int) -> pd.DataFrame:
    """Bootstrap de ventas reales + ruido de negocio, con FKs siempre válidas."""
    base = dims['Fact_Ventas']
    n = 5000 * escala
    idx = rng.integers(0, len(base), n)

    tiempos = pd.to_numeric(dims['Dim_Tiempo']['sk_tiempo']).to_numpy()
    clientes = pd.to_numeric(dims['Dim_Cliente']['sk_cliente']).to_numpy()
    trabajadores = pd.to_numeric(dims['Dim_Trabajador']['sk_trabajador']).to_numpy()
    productos = dims['Dim_Producto']
    sk_productos = pd.to_numeric(productos['sk_producto']).to_numpy()
    precios = pd.to_numeric(productos['precio_lista']).to_numpy()

    cantidad = rng.integers(1, 13, n)
    pos_producto = rng.integers(0, len(sk_productos), n)
    precio = np.round(precios[pos_producto] * rng.uniform(0.90, 1.10, n), 2)

    return pd.DataFrame({
        'sk_fact_venta': np.arange(1, n + 1),
        'sk_tiempo': rng.choice(tiempos, n),
        'sk_cliente': rng.choice(clientes, n),
        'sk_trabajador': rng.choice(trabajadores, n),
        'sk_producto': sk_productos[pos_producto],
        'sk_condicion_venta': rng.integers(1, 5, n),
        'nro_comprobante': 100001 + np.arange(n),
        'id_detalle': [f'{i:06d}' for i in range(1, n + 1)],
        'cantidad': cantidad,
        'importe_total': np.round(cantidad * precio, 2),
        'precio_unitario': precio,
    })


def generar_compras(dims: dict, rng, escala: int) -> pd.DataFrame:
    base = dims['Fact_Compras']
    n = 1500 * escala
    idx = rng.integers(0, len(base), n)

    tiempos = pd.to_numeric(dims['Dim_Tiempo']['sk_tiempo']).to_numpy()
    proveedores = pd.to_numeric(dims['Dim_Proveedor']['sk_proveedor']).to_numpy()
    trabajadores = pd.to_numeric(dims['Dim_Trabajador']['sk_trabajador']).to_numpy()
    productos = dims['Dim_Producto']
    sk_productos = pd.to_numeric(productos['sk_producto']).to_numpy()
    costos = pd.to_numeric(productos['precio_lista']).to_numpy()

    cantidad = rng.integers(5, 60, n)
    pos_producto = rng.integers(0, len(sk_productos), n)
    precio = np.round(costos[pos_producto] * rng.uniform(0.45, 0.75, n), 2)

    return pd.DataFrame({
        'sk_fact_compra': np.arange(1, n + 1),
        'sk_tiempo': rng.choice(tiempos, n),
        'sk_proveedor': rng.choice(proveedores, n),
        'sk_trabajador': rng.choice(trabajadores, n),
        'sk_producto': sk_productos[pos_producto],
        'sk_documento_ingreso': rng.integers(1, 5, n),
        'id_ingreso': [f'{i:06d}' for i in range(1, n + 1)],
        'id_detalle_ingreso': [f'{i:06d}' for i in range(1, n + 1)],
        'nro_documento': [f'F{800001 + i}' for i in range(n)],
        'cantidad': cantidad,
        'precio_unitario': precio,
        'subtotal': np.round(cantidad * precio, 2),
    })


def generar_snapshot(dims: dict, rng) -> pd.DataFrame:
    """Producto x día (grano del snapshot), con stock aleatorio realista."""
    productos = pd.to_numeric(dims['Dim_Producto']['sk_producto']).to_numpy()
    tiempos = pd.to_numeric(dims['Dim_Tiempo']['sk_tiempo']).to_numpy()
    producto, tiempo = np.meshgrid(productos, tiempos)
    n = producto.size
    stock = np.clip(rng.normal(45, 18, n).round(), 0, 250).astype(int)
    return pd.DataFrame({
        'sk_tiempo': tiempo.ravel(),
        'sk_producto': producto.ravel(),
        'stock_cantidad': stock,
    })


# --------------------------------------------------------------------------
# Inyección de errores con verdad conocida
# --------------------------------------------------------------------------
TIPOS_ERROR = ['nulo_clave', 'negativo', 'importe_incoherente', 'huerfano',
               'fecha_invalida', 'texto_en_numero']


def inyectar_errores(ventas: pd.DataFrame, rng, fraccion: float):
    """
    Corrompe una fracción de las ventas y devuelve (df_corrupto, verdad).
    La verdad permite calcular recall/precisión de las reglas de calidad.
    """
    if fraccion <= 0:
        return ventas, pd.DataFrame(columns=['tabla', 'id_fila', 'tipo_error'])

    ventas = ventas.copy()
    # pandas 3 no permite meter texto en una columna int64 y asignar None la
    # convertiría a float (79 -> 79.0). Se usa object para ambos casos.
    for columna in ('cantidad', 'sk_cliente'):
        ventas[columna] = ventas[columna].astype('object')
    n = max(1, int(len(ventas) * fraccion))
    idx = rng.choice(ventas.index.to_numpy(), n, replace=False)
    tipos = rng.choice(TIPOS_ERROR, n)

    for fila, tipo in zip(idx, tipos):
        if tipo == 'nulo_clave':
            ventas.at[fila, 'sk_cliente'] = None
        elif tipo == 'negativo':
            ventas.at[fila, 'cantidad'] = -int(ventas.at[fila, 'cantidad'])
        elif tipo == 'importe_incoherente':
            ventas.at[fila, 'importe_total'] = round(
                float(ventas.at[fila, 'importe_total']) * 1.5 + 10, 2)
        elif tipo == 'huerfano':
            ventas.at[fila, 'sk_producto'] = 999999
        elif tipo == 'fecha_invalida':
            ventas.at[fila, 'sk_tiempo'] = 0
        elif tipo == 'texto_en_numero':
            ventas.at[fila, 'cantidad'] = 'ABC'

    verdad = pd.DataFrame({
        'tabla': 'Fact_Ventas',
        'id_fila': ventas.loc[idx, 'sk_fact_venta'].to_numpy(),
        'tipo_error': tipos,
    })

    # Duplicados: se copian filas ya existentes (misma PK) -> viola unicidad
    n_dup = max(1, int(len(ventas) * fraccion / 2))
    idx_dup = rng.choice(ventas.index.to_numpy(), n_dup, replace=False)
    duplicadas = ventas.loc[idx_dup].copy()
    ventas = pd.concat([ventas, duplicadas], ignore_index=True)
    verdad = pd.concat([verdad, pd.DataFrame({
        'tabla': 'Fact_Ventas',
        'id_fila': duplicadas['sk_fact_venta'].to_numpy(),
        'tipo_error': 'duplicado',
    })], ignore_index=True)

    return ventas, verdad


# --------------------------------------------------------------------------
# Construcción de un dataset
# --------------------------------------------------------------------------
def construir_dataset(escala: int, ruta_salida: Path, fraccion_errores: float = 0.0,
                      semilla: int = SEMILLA, ruta_raw: Path = None) -> dict:
    rng = np.random.default_rng(semilla + escala)
    reales = leer_reales(Path(ruta_raw) if ruta_raw else cfg.RUTA_RAW)
    if not reales:
        raise SystemExit(f'No hay CSV en {ruta_raw or cfg.RUTA_RAW}')

    dims = dict(reales)
    dims['Dim_Producto'] = expandir_productos(reales['Dim_Producto'], rng, escala)
    dims['Dim_Cliente'] = expandir_clientes(reales['Dim_Cliente'], rng, escala)
    dims['Dim_Proveedor'] = expandir_proveedores(reales['Dim_Proveedor'], rng, escala)
    dims['Dim_Trabajador'] = expandir_trabajadores(reales['Dim_Trabajador'], rng, escala)

    if escala == 1:
        hechos = {t: reales[t] for t in cfg.HECHOS}
    else:
        hechos = {
            'Fact_Ventas': generar_ventas(dims, rng, escala),
            'Fact_Compras': generar_compras(dims, rng, escala),
            'Fact_Inventario_Snapshot': generar_snapshot(dims, rng),
        }

    verdad = pd.DataFrame(columns=['tabla', 'id_fila', 'tipo_error'])
    if fraccion_errores > 0:
        hechos['Fact_Ventas'], verdad = inyectar_errores(
            hechos['Fact_Ventas'], rng, fraccion_errores)

    ruta_salida.mkdir(parents=True, exist_ok=True)
    filas = {}
    for tabla, df in {**dims, **hechos}.items():
        df.to_csv(ruta_salida / f'{tabla}.csv', index=False, encoding='utf-8',
                  na_rep='')
        filas[tabla] = int(len(df))

    verdad.to_csv(ruta_salida / '_verdad_errores.csv', index=False, encoding='utf-8')

    manifiesto = {
        'escala': escala,
        'semilla': semilla,
        'fraccion_errores': fraccion_errores,
        'filas': filas,
        'filas_totales': int(sum(filas.values())),
        'filas_hechos': int(sum(filas[t] for t in cfg.HECHOS)),
    }
    (ruta_salida / '_manifiesto.json').write_text(
        json.dumps(manifiesto, indent=2, ensure_ascii=False), encoding='utf-8')
    return manifiesto


def main():
    parser = argparse.ArgumentParser(description='Generador de datos sintéticos')
    parser.add_argument('--escalas', default='1,5,10',
                        help='Escalas separadas por coma (1 = datos reales)')
    parser.add_argument('--escala', type=int, help='Una sola escala')
    parser.add_argument('--errores', type=float, default=0.0,
                        help='Fracción de ventas a corromper (0.01 = 1%%)')
    parser.add_argument('--salida', default=str(cfg.RUTA_DATOS))
    args = parser.parse_args()

    escalas = [args.escala] if args.escala else [
        int(e) for e in args.escalas.split(',') if e.strip()]

    for escala in escalas:
        destino = Path(args.salida) / f'escala_{escala}x'
        if destino.exists():
            shutil.rmtree(destino)
        manifiesto = construir_dataset(escala, destino, args.errores)
        print(f"[OK] escala {escala}x -> {destino} | "
              f"{manifiesto['filas_totales']:,} filas "
              f"({manifiesto['filas_hechos']:,} en hechos) | "
              f"errores inyectados: {manifiesto['fraccion_errores']:.1%}")


if __name__ == '__main__':
    main()
