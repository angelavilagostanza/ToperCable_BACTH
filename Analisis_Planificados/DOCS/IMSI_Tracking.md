# Trazabilidad de IMSI en el Pipeline de Alineamiento Planificado

**Fecha:** 2026-09-02  
**Autor:** angel.avila@masmovil.com

---

## Descripcion

Se ha añadido trazabilidad del campo IMSI entre los tres sistemas que lo gestionan:
**Salesforce (SF)**, **Xena** y **MSA (HLR)**. El objetivo es detectar desalineamientos
de IMSI entre sistemas y reportarlos como `ERROR_IMSI` en el resultado del match.

---

## Campos en BD

Tabla: `topercable.alineamiento_planificado_detalle`

| Campo      | Sistema origen | Descripcion                        |
|------------|----------------|------------------------------------|
| `imsi_sf`  | Salesforce     | IMSI extraido del asset SIM_OT     |
| `imsi_xena`| Xena           | IMSI extraido desde Xena           |
| `imsi_msa` | MSA (HLR)      | IMSI extraido via API REST HLR     |

### Convencion de valores

| Valor  | Significado                                      |
|--------|--------------------------------------------------|
| `'0'`  | No procesado (pendiente de extraccion)           |
| `''`   | Procesado, MSISDN no encontrado en el sistema    |
| valor  | IMSI real extraido del sistema                   |

---

## Pipeline de extraccion

El IMSI se extrae en tres pasos independientes, cada uno con su propio script:

```
Analisis_Salesforce.pl          -> imsi_sf   (via SOQL sobre asset SIM_OT)
Extraccion_Datos_Xena.pl        -> imsi_xena (via API Xena)
Extraccion_Datos_MSA.pl         -> imsi_msa  (via API REST HLR GET /msisdns/{msisdn}/hlr)
```

Despues de los tres, se ejecuta `Match_Sistemas.pl`.

---

## Comportamiento ante MSISDN no encontrado (HTTP 400 en MSA)

Cuando la API de MSA devuelve HTTP 400, significa que el MSISDN no existe en el sistema.
No es un error de comportamiento.

- **Log en libreria:** `NO EXISTE el MSISDN en MSA: <msisdn>`
- **Log en script:**   `NO_EXISTE Get_MSA_MSISDN_Data (<msisdn>): [MSA.NoExiste]`
- **Valor guardado en BD:** `imsi_msa = ''` (procesado sin datos)

Errores reales (HTTP 500 u otros) se siguen registrando como `ERROR HTTP <code>` y guardan
`imsi_msa = '[Error.MSA.HTTP.<code>]'` para trazabilidad.

---

## Logica ERROR_IMSI en Match_Sistemas

**Fuente de verdad:** `imsi_msa`

**Condicion de disparo:**
- `imsi_msa` tiene valor real (no vacio)
- `imsi_sf != imsi_msa` O `imsi_xena != imsi_msa`

**Posicion en la cadena de prioridad** (cada regla posterior sobreescribe a la anterior):

```
ERROR_INV
ERROR_TAR / ERROR_BCO / ERROR_PRO
ERROR_CODSF
ERROR_IMSI      <- aqui
ERROR_CIF       <- sobreescribe IMSI si ambos aplican
ERROR_COD
ERROR_AST
ERROR_MSA       <- maxima prioridad
```

Si `imsi_msa = ''` (MSISDN no encontrado en MSA), la comprobacion se omite.

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `MSA/Lib/LIB_ToperCable_MSA.pm` | HTTP 400 -> `[MSA.NoExiste]` en lugar de `ERROR HTTP 400` |
| `MSA/Extraccion_Datos_MSA.pl` | Prefijo log `NO_EXISTE` vs `ERROR`; HTTP 400 -> `imsi_msa = ''` |
| `Match_Sistemas/Lib/LIB_ToperCable_Match.pm` | `ERROR_IMSI` reposicionado y condicion corregida a `$IMSI_MSA ne ''` |

---

## Commits

| Hash | Descripcion |
|------|-------------|
| `07a2fb8` | fix: diferenciar HTTP 400 (no existe) de errores reales en Get_MSA_MSISDN_Data |
| `9e93077` | fix: imsi_msa = '' cuando MSISDN no existe en MSA (HTTP 400) |
| `b455f7f` | feat: añadir ERROR_IMSI en Match_Sistemas antes de ERROR_CIF |
