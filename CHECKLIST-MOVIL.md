# Checklist — App móvil Dexi (`dexi_movil`)

Qué tiene la app frente a lo que ya existe en la web. Cada sección sigue la
numeración de `../CHECKLIST-DEXI.md`.

**Leyenda:** `[x]` hecho en la app · `[ ]` falta · 🖥️ solo web, a propósito
(tareas de escritorio que no tienen sentido en el teléfono).
**API:** lo que hay que agregar en `dexi-web/routes/api.php` para cada pendiente
(✅ = ya existe). Regla de la arquitectura: la app nunca decide permisos; el
servidor revalida todo y responde 403 con un código (`permission_denied`,
`plan_module_missing`, `subscription_inactive`…).

**Servidor:** producción `https://dexi.sczsoft.net/api/v1`; en desarrollo se
cambia con `--dart-define=API_URL=…`. Identificador `net.sczsoft.dexi`.
Referencia: `../../vexi/vexi_movil` (misma arquitectura; se porta y se adapta a odontología).

Última revisión: 17/11/2026 · 19 tests de la app (`flutter test`), `flutter analyze` sin avisos.

---

## Base técnica

- [x] Proyecto Flutter, `.gitignore`, identificador `net.sczsoft.dexi`, nombre «Dexi»
- [x] Ícono (diente sin el texto, adaptable en Android) y pantalla de arranque con el logo
- [x] Login con token Sanctum (`POST /auth/login`) — API ✅
- [x] Token en almacenamiento seguro; sesión vencida → vuelve al login con aviso
- [x] Selector de clínica (`X-Company-Id`) y cambio desde el menú o el perfil — API ✅ (`GET /me`)
- [x] Menú según `permissions` y `plan.features` de `GET /me` (lo que no se puede, no se muestra)
- [x] Errores con código y mensaje en español (sin permiso, módulo fuera del plan, suscripción vencida o en solo lectura)
- [x] Sin conexión → pantalla de reintento (no cierra la sesión)
- [x] Barra inferior: Inicio · Agenda · Pacientes · Menú; menú lateral con las secciones agrupadas y con los colores de la web (Ventas y Cuentas por cobrar, con el módulo de ventas)
- [x] Tema con la paleta de Dexi (turquesa `#0E9F9A`, Inter), modo claro
- [x] Logo en el login; el de la clínica (o el diente de Dexi) en el menú
- [x] Servidor configurable para desarrollo (`--dart-define=API_URL`)
- [ ] Modo sin conexión (ver lo ya cargado sin internet)
- [ ] Compilación de producción firmada (Play Store / App Store)
- [x] Permisos de Android para producción: internet (sin él, la versión publicada no se conectaba) y cámara

## 1. Inicio

- [x] Saludo y agenda de hoy: lo que sigue abierto (en atención y en espera primero) — API: `GET /dashboard`
- [x] Pendientes del día: WhatsApp por enviar, cumpleaños, laboratorio atrasado, insumos bajo el mínimo — API: `GET /dashboard`
- [x] Para el dueño: cobrado hoy y en el mes, por cobrar — API ✅ `GET /dashboard`
- [x] Accesos rápidos: nueva cita, nuevo paciente, cobrar

## 2. Pacientes

- [x] Buscar pacientes (nombre, documento, teléfono, historia) — API ✅ `GET /patients`
- [x] Ficha: Resumen (alertas médicas en rojo, datos, anamnesis) y Citas (próximas y anteriores)
- [x] Ficha en pestañas: Resumen · Odontograma · Historia (consultas anteriores) · Citas · Documentos (según plan y rol)
- [x] Ficha: pestaña Pagos (lo que debe, lo pendiente de cobro, cobrar, abonar y sus ventas)
- [ ] Ficha: pestaña Plan (llega con la fase de planes)
- [x] Llamar y WhatsApp desde la ficha
- [x] Registrar y editar paciente, con anamnesis y alertas — API ✅ `POST/PUT /patients`
- [x] Documentos y fotos: ver, y subir desde la cámara (radiografías, fotos intraorales) — API ✅ `GET/POST /patients/{id}/documents`
- [x] Odontograma en la ficha (hallazgos en rojo, tratamientos en azul); en el teléfono se parte en cuadrantes para que cada diente se pueda tocar — API ✅ `GET /patients/{id}/odontogram`

## 3. Agenda

- [x] Citas del día con flechas y calendario; filtro por profesional y «solo mis citas» — API ✅ `GET /appointments`
- [x] Detalle de la cita
- [x] Cambiar estado: confirmar, llegó, en atención, atendida, no asistió, cancelar — API ✅ `PATCH /appointments/{id}/status`
- [x] Agendar desde la agenda o la ficha: procedimiento con su duración, profesional, horarios libres — API ✅ `GET /appointments/slots`, `POST /appointments`
- [x] Reprogramar — API ✅ `PUT /appointments/{id}`
- [x] Sala de espera: llegados, tiempo esperando, en atención (se actualiza sola)
- [x] Recordatorio por WhatsApp con la plantilla de la clínica (y se registra el envío) — API: `POST /communications/send`
- [ ] Vista semanal

## 4. Atención clínica y odontograma

- [x] Iniciar consulta desde la cita («Atender»), la ficha («Nueva consulta») o «Por atender» en Consultas — API ✅ `POST /consultations`
- [x] Motivo, anamnesis, examen, plan, indicaciones y próxima visita (avisa si sales sin guardar) — API ✅ `PUT /consultations/{id}`
- [x] Diagnósticos con el catálogo (CIE-10) y pieza — API ✅ `POST/DELETE /consultations/{id}/diagnoses`
- [x] Procedimientos realizados (pieza y caras) con «marcar en el odontograma» — API ✅ `POST/DELETE /consultations/{id}/procedures`
- [x] «Hecho hoy» de un ítem del plan de tratamiento — API ✅ `POST /consultations/{id}/plan-items/{item}`
- [x] Odontograma interactivo: tocar una pieza, elegir caras y hallazgo o tratamiento; quitar lo registrado; historia de la pieza — API ✅ `POST /patients/{id}/odontogram`, `.../resolve`, `.../teeth/{pieza}`
- [x] Cerrar la consulta (firmada) y nota de adenda — API ✅ `POST /consultations/{id}/close`, `/addendum`
- [x] Indicaciones al paciente por WhatsApp (texto de la consulta)
- [ ] Receta en PDF para compartir por WhatsApp — API: `GET /consultations/{id}/prescription.pdf` (hoy solo en la web)
- [x] Fotos clínicas desde la consulta (pestaña Fotos: cámara o galería, van a Documentos del paciente)

## 5. Planes de tratamiento

- [ ] Ver los planes del paciente con su avance y lo cobrado — API: `GET /patients/{id}/treatment-plans`
- [ ] Presupuesto en PDF para enviar al paciente — API: `GET /treatment-plans/{id}/pdf`
- [ ] Marcar presentado / aprobado (con nombre de quien aprueba)
- 🖥️ Armar el presupuesto ítem por ítem (más cómodo en pantalla grande)

## 6. Ventas y cobros

- [x] Cuentas por cobrar: quién debe, vencido primero, buscar, recordatorio por WhatsApp (queda registrado) — API ✅ `GET /receivables`
- [x] Registrar un abono (método, referencia, caja abierta), a la cuenta del paciente o a una venta, con recibo por WhatsApp — API ✅ `POST /receivables/{patient}/pay`, `POST /sales/{id}/payments`
- [x] Cobrar lo pendiente de un paciente (lo realizado viene marcado; el plan, por adelantado), lo suelto del tarifario, descuento, vuelto y saldo con fecha — API ✅ `GET /sales/options`, `GET /patients/{id}/pending`, `POST /sales`; también desde la consulta («Cobrar»)
- [x] Anular una venta con motivo y devolución — API ✅ `POST /sales/{id}/cancel`
- [ ] Vender productos (con el módulo de inventario; hoy solo en la web)
- [x] Ventas del día, del mes, con saldo y anuladas; lo cobrado hoy por método; detalle y recibo por WhatsApp — API ✅ `GET /sales`, `GET /sales/{id}`
- 🖥️ Caja: apertura, arqueo y cierre (la app cobra en la caja que esté abierta)

## 7. Finanzas

- [x] Gastos en pestañas (Generales · Proveedores · Personal · Servicios · Todos) por mes, con el origen del dinero (caja abierta o cuenta), foto del comprobante (se ve en la app) y anulación — API ✅ `/finance/options`, `/finance/expenses`, `/finance/expenses/{id}/receipt`
- [x] Control del mes de servicios básicos, con «Pagar» en lo pendiente — API ✅ `GET /finance/basics?month=`
- [x] Cuentas con su extracto (saldo después de cada movimiento), ingreso / egreso y transferencia — API ✅ `/finance/accounts`

## 8. Inventario y compras

- [x] Buscar productos e insumos (nombre, marca, código); existencia por consultorio, lotes y últimos movimientos — API ✅ `GET /products`, `GET /products/{id}`
- [x] Bajo el mínimo y por vencer (con su cuenta)
- [x] Escáner de código de barras con la cámara (linterna y «escribir el código»); entrada (con lote y vencimiento), salida (el lote que vence primero) y conteo físico — API ✅ `GET /products/scan/{código}`, `POST /stock-movements`
- 🖥️ Traslados entre consultorios
- [x] Recibir mercadería de una compra (lo que llegó, lote y vencimiento; el escáner ubica el producto) — API ✅ `GET /purchases/pending`, `POST /purchases/{id}/receive`
- 🖥️ Alta de productos, compras completas, cuentas por pagar

## 9. Equipo y comisiones

- [x] Mis comisiones (cada odontólogo, lo suyo, mes a mes; lo que le deben de cualquier fecha) — API ✅ `GET /me/commissions`
- [x] Comisiones por pagar (por profesional, desde cuándo) y pagar la liquidación desde la caja o una cuenta (queda como gasto de personal) — API ✅ `/commissions/pending`, `/commissions/{personal}`, `POST /commissions/{personal}/settle`
- 🖥️ Reglas de comisión, personal, cargos y permisos

## 10. Laboratorio

- [x] Trabajos en curso, atrasados (en rojo), por instalar, instalados y todos — API ✅ `GET /lab-orders`
- [x] Avanzar el estado (llegó, instalado, devolver para ajuste con el motivo, cancelar) y su recorrido — API ✅ `GET /lab-orders/{id}`, `POST /lab-orders/{id}/status`
- [x] Nueva orden desde la ficha o la lista (laboratorio de siempre, trabajo, pieza, material, color VITA, entrega, ítem del plan) — API ✅ `GET /lab-orders/options`, `POST /lab-orders`
- 🖥️ Pagar al laboratorio (agrupado por laboratorio)

## 11. Comunicaciones

- [x] «Para enviar hoy»: recordatorios (citas de mañana o de hoy), cumpleaños, controles, inasistencias y saldos, con el mensaje de la plantilla; «Enviar» abre WhatsApp y registra; lo ya enviado se marca — API ✅ `GET /communications/queue`, `POST /communications/send`
- [x] Programar un control desde la ficha o al cerrar la consulta (motivos sugeridos, «en 6 meses» o fecha) — API ✅ `POST /patients/{id}/followups`
- [x] Controles: pendientes (vencidos en rojo), hechos y descartados; marcar hecho o descartar — API ✅ `GET /followups`, `POST /followups/{id}/status`
- [x] Historial de lo enviado (API ✅ `GET /communications/history`; en la app, el «Enviado» de cada mensaje)
- 🖥️ Editar las plantillas de los mensajes

## 12. Reportes

- [x] Resumen para el dueño («Cómo va la clínica»): utilidad estimada comparada con el período anterior, cobrado, costos y gastos, barras de lo que entra y sale, «Para revisar hoy» (lleva a cada pantalla), lo más importante, cobrado por método, deudas y producción por profesional — API ✅ `GET /reports/summary?preset=`
- [x] Reportes por sección, como en la web (Ingresos y egresos · Ventas · Pacientes y citas · Profesionales · Inventario), con período y consultorio: indicadores con comparación, gráfico y rankings. Respeta los permisos: cada rol ve solo sus secciones y sin `reports.finance` no llegan cifras de dinero (lo decide el servidor) — API ✅ `GET /reports`, `GET /reports/{sección}`
- 🖥️ Exportación a Excel

## 13. Perfil y suscripción

- [x] Datos del usuario, clínica, plan y cerrar sesión
- [x] Cambiar la contraseña (pide la actual; cierra las sesiones de otros teléfonos) — API ✅ `PUT /me/password`
- [x] Plan y estado de la suscripción; aviso de solo lectura cuando venció
- [ ] Notificaciones push (llegó el paciente, trabajo de laboratorio listo) — API: `POST /devices`
- 🖥️ Configuración de la clínica, usuarios, roles y panel de la plataforma

---

## Prioridad sugerida

1. ~~**Base técnica + Inicio + Agenda + Pacientes**~~ ✅ (17/11/2026)
2. ~~**Atención clínica en el sillón:** consulta, odontograma interactivo y fotos~~ ✅ (17/11/2026) — falta la receta en PDF.
3. ~~**Cobros:** cuentas por cobrar, abonos con recibo por WhatsApp y cobrar lo pendiente~~ ✅ (17/11/2026)
4. ~~**Comunicaciones:** «Para enviar hoy» desde el teléfono (es donde está WhatsApp)~~ ✅ (17/11/2026)
5. ~~**Laboratorio, inventario con escáner y finanzas.**~~ ✅ (18/11/2026)
6. ~~**Para el dueño:** resumen de reportes y comisiones~~ ✅ (18/11/2026)
7. **Publicación:** firma, Play Store y App Store; notificaciones push.
