<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Icono de la aplicación Triwarden">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  Un gestor de contraseñas nativo para Mac compatible con <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> y Bitwarden.<br>
  Creado con Swift y SwiftUI para macOS 26.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.zh-HK.md">粵語</a> · <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> · Español
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg"><img src="https://img.shields.io/badge/Descargar-para%20macOS-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="Descargar el DMG más reciente de Triwarden para macOS"></a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml"><img src="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="Licencia: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 o posterior">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="promo/public/shots/vault-dark.png" width="820" alt="La bóveda de Triwarden en tema oscuro">
</p>

> Esta traducción se sincronizó con el [README en inglés](README.md) el 6 de noviembre de 2026. La versión inglesa mantiene la lista completa de funciones y detalles técnicos.

> **Estado:** Triwarden aún está en sus primeras versiones (0.x). Funciona con cuentas reales de Vaultwarden y Bitwarden
> y se prueba con ambos servicios, pero recomendamos mantener tu cliente habitual hasta la versión 1.0. Las capturas usan la bóveda de demostración incluida.

## Instalación

Requiere macOS 26 (Tahoe) o posterior.

```bash
brew install --cask sinhong2011/tap/triwarden
```

El botón superior descarga directamente el DMG más reciente, firmado y notarizado. Puedes buscar actualizaciones firmadas en «Ajustes › Acerca de»; la comprobación e instalación automáticas son opcionales.

## Primeros pasos

1. Abre Triwarden, elige tu servidor de Vaultwarden, Bitwarden US o Bitwarden EU e inicia sesión con tu cuenta existente.
2. Activa Triwarden en «Ajustes del Sistema › General › Autorrelleno y contraseñas» para completar contraseñas, llaves de acceso y códigos de verificación.
3. Usa **⌘F** para buscar en la bóveda o **⇧⌘Espacio** para abrir la paleta de comandos desde cualquier aplicación.
   La escritura automática necesita permiso de Accesibilidad para **Triwarden Auto-Type**. La extensión del navegador es opcional y se conecta desde Ajustes.

**Sin conexión:** puedes desbloquear y consultar la bóveda cifrada guardada en este Mac. Crear, editar, importar y eliminar elementos requiere conexión con el servidor; los cambios no quedan en espera para enviarse después.

**Compilaciones oficiales y licencia de pago:** todas las funciones siguen siendo gratuitas y sin límite de tiempo para uso personal. Usar una compilación oficial con cuentas de trabajo requiere una licencia de pago único por persona, válida en todos sus Mac. Consulta las [condiciones de la licencia de pago](docs/LICENSE-TERMS.md).

## Funciones

**Tu bóveda, nativa en Mac**

- Gestiona inicios de sesión, notas seguras, tarjetas, identidades y claves SSH, además de carpetas, favoritos, campos personalizados, archivos adjuntos, archivo y papelera.
- Usa varias cuentas de Vaultwarden o Bitwarden a la vez, incluidas bóvedas compartidas y colecciones, con sincronización en directo mediante WebSocket. Admite inicio de sesión con contraseña, verificación en dos pasos y SSO.
- Busca en todas las bóvedas y filtra por tipo, carpeta, favorito, código de un solo uso, llave de acceso o problema de Watchtower.
- Añade, descarga o elimina archivos adjuntos desde el editor. Al crear un inicio de sesión desde la pestaña activa, los datos del sitio se rellenan automáticamente.

**Acceso rápido**

- Usa la paleta de comandos desde cualquier aplicación para buscar un elemento, copiarlo o escribir automáticamente el nombre de usuario y la contraseña.
- Configura atajos globales y usa la barra de menús para acceder a inicios de sesión relacionados, códigos de un solo uso y el generador.
- Las extensiones de Safari, Chrome, Edge, Brave y Firefox rellenan y guardan inicios de sesión después de aprobarlos en la aplicación. Las llaves de acceso usan el autorrelleno del sistema de macOS; la extensión del navegador aún no gestiona el inicio con llaves de acceso.

**Integración con macOS y herramientas de seguridad**

- El autorrelleno del sistema admite contraseñas, llaves de acceso y códigos de un solo uso. Desbloquea con Touch ID o PIN.
- Los secretos copiados se borran automáticamente del portapapeles. El agente SSH puede firmar commits de Git con las claves SSH de la bóveda.
- Triwarden puede ocultarse de capturas, grabaciones y pantalla compartida. Los servidores autohospedados pueden usar una CA privada y encabezados adicionales como los de Cloudflare Access.
- Watchtower detecta contraseñas débiles, reutilizadas, filtradas o inseguras, y sitios donde aún no has activado la verificación en dos pasos.
- Verificación en dos pasos, gestión de dispositivos, acceso de emergencia, Send, generadores de contraseñas y nombres de usuario, y numerosos formatos de importación y exportación.

Consulta el [README en inglés](README.md) y la [hoja de ruta](docs/ROADMAP.md) para ver todas las funciones y limitaciones.

## Línea de comandos y claves API locales

Activa **Answer the tw command** en «Ajustes › Desarrollador» e instala `tw` mediante **Terminal Helper Setup…**.

```bash
tw get github | pbcopy
tw code github
tw status
tw run
tw tools list
tw generate --length 32
tw lock
```

Las claves API locales están ocultas de forma predeterminada. Activa «Ajustes › Desarrollador › Show Secrets» para seguir el recorrido guiado: guardar una clave → proporcionarla a una herramienta o proyecto → revisar la autorización → volver a usarla. Consulta la [guía de inicio](docs/local-api-keys-getting-started.md).
Cada clave API muestra qué herramientas la utilizan. «Access › Permissions» y «Access › History» muestran los permisos activos y las decisiones anteriores.

## Compilar desde el código fuente

Requiere macOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.js y pnpm.

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run
```

Ejecuta `make` para ver todos los comandos. Los más habituales son `make test`, `make selftest`, `make uitest` y `make snapshots`.

## Seguridad, accesibilidad e idiomas

Tu contraseña maestra y tus claves nunca salen del Mac; el servidor solo recibe datos cifrados. Consulta [SECURITY.md](SECURITY.md) para conocer los detalles y cómo informar de una vulnerabilidad de forma privada.

Triwarden incluye etiquetas de VoiceOver, atajos de teclado y compatibilidad con Aumentar contraste y Reducir movimiento. La aplicación está disponible en English, 繁體中文, 粵語, 简体中文, 日本語, 한국어, Français, Español y ไทย. Las limitaciones conocidas están documentadas en [ACCESSIBILITY.md](ACCESSIBILITY.md).

## Soporte y contribuciones

Para preguntas sobre compras o el producto, escribe a [support@triwarden.cc](mailto:support@triwarden.cc). Para errores y sugerencias, abre una [incidencia en GitHub](https://github.com/sinhong2011/triwarden/issues). Aceptamos issues y pull requests; consulta [docs/RELEASING.md](docs/RELEASING.md) para conocer el proceso de publicación.

## Licencia

Triwarden es software libre publicado bajo la [GNU General Public License v3.0](LICENSE). La licencia del código no incluye el nombre «Triwarden» ni el icono de la aplicación; las versiones modificadas deben usar su propio nombre e icono. Triwarden no está afiliado con Bitwarden, Inc. ni con el proyecto Vaultwarden.
