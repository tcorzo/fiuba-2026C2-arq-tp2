#import "../plantilla.typ": *

// Cada táctica vive en su propio archivo, `tacticas/<táctica>.typ`, con un
// único `#tactica(...)`, y se incluye acá. El enunciado pide una o dos:
// las adicionales no suman nota y no se leen.

= Tácticas superadoras

#include "tacticas/terminacion-tls.typ"
#include "tacticas/tope-de-conexiones.typ"
