# Evolution API + n8n + Chatwoot - Instalación Automática

Script de autoinstalación para crear un stack completo con Evolution API, n8n y Chatwoot, configurado y listo para usar en minutos. Ideal para crear un entorno de automatización y gestión de WhatsApp profesional.

## 🚀 Características

- **Instalación 100% automatizada** de Evolution API, n8n y Chatwoot
- **Certificados SSL automáticos** con Let's Encrypt
- **Integración preconfigurada** entre los servicios
- **Generación segura** de todas las contraseñas y tokens
- **Herramientas de monitoreo** y mantenimiento incluidas
- **Respaldos automáticos** programados
- **Protección con rkhunter y chkrootkit** para mayor seguridad

## 📋 Requisitos

- Servidor Ubuntu/Debian limpio (recomendado Ubuntu 20.04 LTS o superior)
- Dominio con registros DNS correctamente configurados apuntando al servidor:
  - `n8n.tudominio.com`
  - `evoapi.tudominio.com`
  - `chat.tudominio.com`
- Acceso root al servidor
- Puertos 80 y 443 abiertos
- Correo electrónico Gmail y contraseña de aplicación (se explica abajo)

## 🔑 Cómo crear una contraseña de aplicación en Google

Antes de iniciar la instalación, necesitarás crear una contraseña de aplicación en Google para que Chatwoot pueda enviar correos:

1. Ve a tu [Cuenta de Google](https://myaccount.google.com/)
2. En el panel de navegación, selecciona **Seguridad**
3. Bajo "Iniciar sesión en Google", selecciona **Verificación en dos pasos** (debes tenerla activada)
4. En la parte inferior, selecciona **Contraseñas de aplicaciones**
5. Selecciona **Otra (nombre personalizado)** del menú desplegable
6. Escribe "Chatwoot" y haz clic en **Generar**
7. Google mostrará una contraseña de 16 caracteres. **Cópiala**, la necesitarás durante la instalación
8. Haz clic en **Listo**

## ⚡ Instalación rápida (Un solo comando)

```bash
sh <(curl https://raw.githubusercontent.com/men2985/evolution-n8n-installer/main/install.sh || wget -O - https://raw.githubusercontent.com/men2985/evolution-n8n-installer/main/install.sh)
```

## 📥 Instalación manual

Si prefieres revisar el script antes de ejecutarlo:

1. Descarga el script:
   ```bash
   wget https://raw.githubusercontent.com/men2985/evolution-n8n-installer/main/install.sh
   ```

2. Dale permisos de ejecución:
   ```bash
   chmod +x install.sh
   ```

3. Ejecútalo:
   ```bash
   sudo ./install.sh
   ```

## 🔧 Proceso de instalación

Durante la instalación, se te solicitará:

1. Tu dominio principal (ej: `ejemplo.com`)
2. Tu correo electrónico (para los certificados SSL y notificaciones)
3. Tu contraseña de aplicación de Google (para envío de correos desde Chatwoot)

El script se encargará de todo lo demás, incluyendo:
- Instalación de dependencias
- Configuración de Docker y redes
- Creación de todos los contenedores
- Configuración de Nginx y SSL
- Configuración de respaldos automáticos
- Instalación de herramientas de seguridad

## 🖥️ Configuración post-instalación

Una vez finalizada la instalación, deberás realizar algunos pasos adicionales para completar la configuración:

### Para Chatwoot:

1. Visita `https://chat.tudominio.com` y crea una cuenta de super admin
2. Anota el ID de cuenta (visible en la URL después de iniciar sesión, ej: `/app/accounts/1/...`)
3. Ve a Perfil → Configuración → Tokens de acceso API y crea un nuevo token
4. Ejecuta el siguiente comando en el servidor:
   ```bash
   configure-chatwoot-integration <ID_DE_CUENTA> <TOKEN_API>
   ```
5. Configura un canal de WhatsApp en Chatwoot:
   - Ve a Ajustes → Canales de entrada → Añadir canal → API WhatsApp
   - Configura la URL de la API: `https://evoapi.tudominio.com`
   - Usa la API Key que se muestra en el resumen de instalación

### Para n8n:

1. Visita `https://n8n.tudominio.com` y completa la configuración inicial
2. Crea flujos de trabajo que se conecten con Evolution API para automatizar tareas

### Para Evolution API:

1. Visita `https://evoapi.tudominio.com/api-docs` para acceder a la documentación de la API
2. Usa la API Key generada automáticamente (mostrada al final de la instalación)

## 🛠️ Herramientas de mantenimiento

El script instala varias herramientas útiles:

- **check-services**: Muestra el estado de todos los servicios instalados
- **configure-chatwoot-integration**: Configura la integración entre Evolution API y Chatwoot
- Respaldos automáticos diarios en `/opt/backups`
- Escaneos de seguridad semanales con rkhunter y chkrootkit

## 📂 Estructura de directorios

- **n8n**: `/home/docker/n8n`
- **Evolution API**: `/home/docker/evolution`
- **Chatwoot**: `/home/docker/chatwoot`
- **Respaldos**: `/opt/backups`
- **Credenciales**: `/opt/backups/credentials.txt` (¡guarda este archivo en un lugar seguro!)

## 📝 Solución de problemas

Si encuentras algún problema:

1. Ejecuta `check-services` para verificar el estado de todos los servicios
2. Revisa los logs de Docker: `docker logs app_n8n_service` (reemplaza el nombre del servicio según necesites)
3. Revisa los logs de Nginx: `/var/log/nginx/n8n.error.log` (o evolution.error.log, chatwoot.error.log)
4. Si necesitas reiniciar algún servicio:
   ```bash
   cd /home/docker/n8n && docker-compose restart
   cd /home/docker/evolution && docker-compose restart
   cd /home/docker/chatwoot && docker-compose restart
   ```

## 🆙 Actualizaciones

Para actualizar los servicios:

```bash
# Para n8n
cd /home/docker/n8n && docker-compose pull && docker-compose up -d

# Para Evolution API
cd /home/docker/evolution && docker-compose pull && docker-compose up -d

# Para Chatwoot
cd /home/docker/chatwoot && docker-compose pull && docker-compose up -d
```

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Si deseas mejorar este script:

1. Haz un fork del repositorio
2. Crea una rama para tu feature (`git checkout -b feature/nueva-caracteristica`)
3. Haz commit de tus cambios (`git commit -am 'Añade nueva característica'`)
4. Haz push a la rama (`git push origin feature/nueva-caracteristica`)
5. Crea un nuevo Pull Request

## 📄 Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para más detalles.

## 👥 Créditos

Este instalador es posible gracias a:
- [Evolution API](https://github.com/EvolutionAPI/evolution-api)
- [n8n](https://n8n.io/)
- [Chatwoot](https://www.chatwoot.com/)

---

⭐ Si este proyecto te ha sido útil, considera darle una estrella en GitHub ⭐
