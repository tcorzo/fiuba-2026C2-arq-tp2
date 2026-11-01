# Manejo de errores del servicio

**Todo error de un request pasa por un único middleware: `error-handler.js`.**
Si agregás o modificás un endpoint, tus errores se lanzan con `throw`; nunca se
responden a mano con `res.status(4xx/5xx).json(...)`.

Existe por H-01: un `TypeError` dentro de un handler `async` terminaba el
proceso, porque Express 4 no captura el rechazo de una promesa.

## Las piezas

| Archivo | Qué es |
|---|---|
| `errors.js` | El vocabulario: `AppError` y sus subclases. Cada una fija el status HTTP y el `code` que recibe el cliente. |
| `error-handler.js` | `asyncHandler`, `notFoundHandler` y `errorHandler`. Es el único lugar donde un error se convierte en una respuesta. |
| `metrics.js` | `countHandledError(code)`, que cuenta cada error respondido en `exchange.<w>.http.errors.<code>`. |

## Reglas para agregar un endpoint

1. Envolvé el handler en `asyncHandler(...)`, sea `async` o no.
2. Ante un error del cliente, `throw` de una subclase de `AppError`.
3. No captures un error para responder con `res.status(...)`. Si tenés que
   capturarlo, relanzalo (`throw`) o pasalo a `next(err)`.
4. Si ninguna subclase describe tu error, creá una en `errors.js` con su status y
   su `code`. No lo resuelvas dentro del endpoint.
5. `errorHandler` tiene que seguir siendo el último `app.use(...)` de `createApp` (`http.js`), y
   `notFoundHandler` el anterior.

## Qué responde cada error

Todas las respuestas de error tienen la forma `{ "error": <mensaje>, "code": <código>, "details": <opcional> }`.

| Origen | Status | `code` |
|---|---|---|
| `ValidationError`: faltan campos o el request está mal formado | 400 | `VALIDATION_ERROR` |
| Body que no es JSON (lo produce `express.json`) | 400 | `INVALID_JSON` |
| Body demasiado grande (lo produce `express.json`) | 413 | `PAYLOAD_TOO_LARGE` |
| Otro 4xx de Express o de un middleware | el mismo | `BAD_REQUEST` |
| `UnknownCurrencyError`: moneda para la que el servicio no tiene una cuenta interna | 422 | `UNKNOWN_CURRENCY` |
| `UnsupportedPairError`: las dos monedas existen pero `getRate` no encuentra tasa entre ellas (ni guardada ni derivada) | 422 | `UNSUPPORTED_PAIR` |
| `NotFoundError`: ruta que ningún endpoint atiende, o cuenta que no existe | 404 | `NOT_FOUND` |
| `ExchangeFailedError`: el cambio se ejecutó y la cuenta interna no tiene fondos | 409 | `INSUFFICIENT_INTERNAL_FUNDS` |
| `ExchangeFailedError`: la cuenta del cliente rechazó el retiro | 422 | `WITHDRAW_REJECTED` |
| `ExchangeFailedError`: la dependencia de transferencias no acreditó al cliente | 502 | `DEPOSIT_FAILED` |
| `ExchangeFailedError`: con una causa que no está en la tabla de `errors.js` | 500 | `EXCHANGE_FAILED` |
| Cualquier otra cosa: un defecto nuestro | 500 | `INTERNAL_ERROR` |

Un 500 es siempre un defecto del servicio, nunca una entrada inválida. El
cliente recibe un mensaje genérico; el detalle y el stack quedan en el log del
container. Los 4xx no se loguean (un cliente podría llenar el log), pero se
cuentan por `code`.

## Qué cambió para los clientes respecto del caso base

- Un error ya no corta la conexión ni devuelve el HTML de error de Express: es
  siempre un JSON con `error` y `code`.
- Los `400` llevan `code`. H-07 citó en su commit medido el cuerpo sin `code`
  (`{"error":"baseAmount must be a positive number"}`); esa cita sigue valiendo
  para ese commit, pero hoy el mismo request devuelve además
  `"code":"VALIDATION_ERROR"`.
- Una moneda o un par inexistentes responden `422`, no un `502` de nginx.
- Actualizar el saldo de una cuenta que no existe responde `404`, no un `200`
  que no hizo nada.
- Un cambio rechazado ya no responde `500` con el resultado como cuerpo (H-34):
  responde `409`, `422` o `502` según la causa, con la forma de error de arriba.
  El resultado completo, con su `id` y el campo nuevo `failure`, viaja en
  `details`.
- Los campos numéricos se validan por tipo y rango, con las funciones de
  `validation.js` (H-31, H-44). `balance` tiene que ser un número mayor o
  igual a `0`: el `0` ahora se acepta. `rate` y `baseAmount` tienen que ser
  números mayores que `0`. Un número enviado como texto (`"1000"`) responde
  `400`. El `0` en `rate` y en `baseAmount` sigue respondiendo `400`, pero con
  el mensaje de la regla en lugar de `Malformed request`.

## Cómo se verifica que se cumplan las reglas

- `app/test/error-handling.test.js` recorre el router y falla si alguna ruta no está
  envuelta en `asyncHandler`, o si `errorHandler` deja de ser el último
  middleware. `npm test --prefix app` lo corre sin docker.

## Qué no cubre

- Solo cubre los requests. Un `setInterval` no tiene una ruta a la que entregar
  su error: `state.js` captura y loguea el de cada guardado periódico, y
  cualquier temporizador nuevo tiene que hacer lo mismo.
- No deshace estados parciales. Si un error ocurre entre las dos transferencias de
  `exchange()`, el handler evita la caída pero el estado queda como esté (H-06).
- Una causa de rechazo nueva en `exchange()` tiene que agregarse también a
  `EXCHANGE_FAILURES` en `errors.js`. Si falta, el cambio rechazado responde
  `500` con `code` `EXCHANGE_FAILED`, sin ningún otro aviso.
