# WAYLESS — TALENT CARDS & PROGRESSION RFC v1.0
**STATUS: PROPOSAL / NOT APPROVED / NOT IMPLEMENTED / NOT CANONICAL.**
**Fecha:** 2026-10-25  | **Área:** Game Design > Progression  | **Autoría:** propuesta asistida para evaluación de Magno y Kmz.
**Regla de gobernanza:** este documento NO autoriza implementación, cambios de datos, recompensas, monetización, promoción, merge ni QA como aprobado. Una decisión posterior explícita debe habilitar cualquier trabajo.

## 0. Propósito y límites
Diseñar un subsistema de cartas que complemente los ocho atributos, rasgos garantizados, maestría, técnicas, clan y sistemas de Character Life. Fuente prioritaria: PDF adjunto 'Wayless · Stats y Builds' (13 páginas, 24/10/2026). Referencias externas: Deepwoken Wiki y Bloodlines Trello como inspiración, NO autoridad sobre WAYLESS. No se copia nomenclatura específica ni assets protegidos.
**No incluye mantras/jutsus en manos de cartas.** Las técnicas y variantes de movimiento/sustitución existentes no pasan a cartas. Solo talento pasivo, modificación condicional de acciones existentes, ventajas de exploración/información y especializaciones mediante maestros. No crear barras, hotbar adicional ni poderes sin counter.

## 1. Datos bloqueados del diseño existente (PDF; NO reabrir automáticamente)
• Nivel máximo 100; 0 puntos al nivel 1; +3 por nivel => 297 al nivel 100; 8 atributos (Vitalidad, Chakra, Resistencia, Taijutsu, Ninjutsu, Genjutsu, Bukijutsu, Velocidad), máximo 100 cada uno; rendimientos 76–100 al 50%.
• Hitos 25/50/75/100 por atributo: 32 rasgos preexistentes automáticos; 8 rasgos híbridos a 40+40; una sola maestría permanente tras alcanzar 100 en algún stat; una sola variante equipada de dash y una de sustitución; variantes enseñadas/cambiadas por NPC maestro.
• Clan fijo por slot; naturalezas y sus counters definidos; finalidad de duelo entre iguales 45–90 s; cada ventaja importante necesita counter; PvE de dificultad fija, no escalado. Una reasignación de stats gratuita, después objeto raro o Robux (regla ya documentada; la monetización de talentos se desaconseja).
• CombatBalance reequilibrio base consta como implementado 2026-10-24 en PDF, aún pendiente QA; no asumir que cualquier fase ulterior está en vivo. Baselines Movement y Combat constan aprobados en Drive, Jutsu/Projectiles requieren autoridad/QA por sistema. Esta RFC no altera código.

## 2. Objetivos medibles y no objetivos
Objetivos: (a) dos personajes misma combinación de stats/clan/jutsus pueden tomar identidades diferentes, (b) elecciones interesantes sin inflación de poder, (c) conocer elegibilidad y consecuencias, (d) sin manos vacías, (e) no añadir efectos imposibles de contrarrestar, (f) ser viable en móvil y R6, (g) sobrevivir a desconexiones/permadeath de forma consistente.
No objetivos: replicar íntegramente Deepwoken, agregar mantras, importar Oaths sin rediseño, ofrecer talentos que solo sumen daño puro, abrir nuevas ranuras de skills, alterar economía o conceder compra directa de poder.

## 3. Modelo de progresión propuesto (todos estos valores son hipótesis)
• Las cartas NO gastan puntos de atributo ni reemplazan los rasgos a 25/50/75/100. Cada 5 niveles obtenidos (5,10,...,100) => una oportunidad; máximo 20 elecciones por vida; en cada oportunidad se muestran 3 cartas distintas elegibles y se elige 1.
• 12 oportunidades clasificadas 'base' (niveles 5–60), 6 'especializadas' (65–90), 2 'avanzadas' (95–100). Clasificación del sobre ≠ rareza de poder. Si un personaje no reúne avanzada elegible, ofrecer especializadas/base; jamás bloquear progreso.
• Las cartas se desbloquean por puntos actuales, por cartas previas, rasgos automáticos, hitos de mundo opcionales; el sistema no exige RNG para ganar una ventaja irremplazable. Oferta seeded por CharacterId+lifeId+milestone+revision, con ponderaciones anti-duplicados. El servidor calcula oferta y concede.
• Primer prototipo: 80 cartas de catálogo (48 mono-stat + 16 híbridas + 16 generales). Los 8 rasgos híbridos del PDF permanecen fuera de las cartas. Para el test, 15–20 cartas seleccionadas como vertical slice.
• Límite de 20 cartas adquiridas durante vida; recomendación de máximo 4 'potenciadores PvP proc' simultáneamente por presupuesto funcional, implementado mediante familias exclusivas, no desactivación silenciosa. Resto cosmético/lectura/economía menor.

## 4. Secuencia de concesión exacta
Al recibir un nivel: 1) progresión servidor confirma nuevo nivel y 3 puntos; 2) se actualiza valor 'UnspentStats'; 3) se evalúan umbrales automáticos del sistema vigente; 4) al múltiplo de 5 se crea token único (CharacterId, LifeId, Level) para elegir carta; 5) jugadores pueden invertir stats antes de abrir la mano, nunca después de emitir la oferta sin regenerar bajo token versionado; 6) generar 3 opciones distintas válidas; 7) persistir oferta y su checksum antes de mostrar; 8) cliente muestra; 9) elección validada y transacción idempotente; 10) persistir selección e invalidar oferta; 11) el resultado aplica por servidor.
Si hay pérdida de conexión: guardar pendingOffer; reabrir misma mano. Si nivel sube múltiple veces por XP masivo, encolar hitos pendientes y resolver en orden. Si ya existen 20 seleccionadas, nunca conceder duplicados. Al cambiar stats por respec, bloquearlo mientras haya oferta abierta; política de invalidación histórica definida en §9.

## 5. Elegibilidad, clasificación, aleatoriedad controlada
Toda carta se modela con id, version, displayName, description, category, minLevel, requiredStats, requiredAutoTraits, requiredCards, requiredWorldFlags, excludes, trigger, magnitude, duration, cooldown, procFamily, environment, stackingRule, counter, qaCases, status.
Para cada mano: excluir aprendidas, duplicadas, excluyentes, no cumplidas, deprecated y deshabilitadas. Priorizar al menos 1 opción que corresponda al stat mayor del jugador; mínimo 1 general segura en reserva. Las 3 cartas deben ser elegibles en el instante confirmado.
Reroll propuesto para decisión futura: 1 repetición GRATUITA por vida, no garantizada por slot ni comprada; 1 'reserve' para llevar una candidata a siguiente mano opcional; 'ban list' de máximo 2 cartas por vida. NO implementar sin ensayo UX/economía. Política de pity: si 2 manos consecutivas no ofrecen la disciplina principal, próxima ofrece al menos una si existe.
Distribución ponderada sugerida: primary 50%, secondary 30%, general 20% con muestreo sin reemplazo y fallback. No prometer porcentaje por usuario dado pool variable; registrar distribución real.

## 6. Presupuesto de poder y reglas de stacking
No sumar velocidad movimiento por encima del cap del PDF (+13%). No superar descuento total de chakra previsto si stats y rasgos ya alcanzan límites; provisional hard cap 25% desde fuentes de cartas + rasgos no firmemente canonizado; requiere revisión de Combate. Sin invulnerabilidad, anti-stun absoluto, inmortalidad extra, segundo reemplazo de sustitución ni clon real con daño.
Prioridad cálculo: source validation -> base stats -> rasgo automático -> variante equipada -> clan/element -> 1 carta principal por procFamily -> softcap por familia -> damage/status/guard. Donde las reglas del PDF ya fijan un máximo, ese máximo prevalece. ProcFamily ejemplo: staminaRefundOnBlock, chakraDiscountOnCast, postDashTempo, genjutsuResistOnBreak. Si dos cartas en misma familia compiten, aplicar mayor efecto válido, no suma; el selector debería impedir combinarlas cuando la diferencia resulte no visible.
Buffs solo con ventana explícita, cooldown mínimo y activación comprobable. Duración de combate target 45–90 s. Ninguna carta puede permitir infinitos loops de guardia, chakra o stamina. Todos los triggers y rechazos deben tener telemetría con muestreo limitado.

## 7. Catálogo maestro de 80 cartas (CANDIDATES; valores NO QA)
Formato: ID | nombre | requisito | efecto | función | counter. Todas las magnitudes se consideran puntos de partida para QA, no especificación balance final.

### Vitalidad — seis cartas
- **S01 Templanza** | Vitalidad 20 | Primer impacto de combo reduce 8% su empuje; no afecta stun obligatorio. | rol: anti-burst | counter: efectos de agarre.
- **S02 Reserva corporal** | Vitalidad 35 | Al salir de combate, recuperación natural de vida empieza 0.5 s antes; PvP tag la bloquea. | rol: recuperación | counter: persecución.
- **S03 Piel endurecida** | Vitalidad 45 | Tras recibir 3 M1 en 6 s, el siguiente M1 entrante reduce 5% daño; ICD 20 s. | rol: anti-combo | counter: jutsu.
- **S04 Último respiro táctico** | Vitalidad 55 | Con menos de 30% de vida, reducción 6% del daño de un golpe no letal; ICD 35 s. | rol: aguante | counter: presión sostenida.
- **S05 Dolor administrado** | Vitalidad 70 | Al salir de ragdoll, durante 1 s guardia recupera +10% velocidad, no bloquea auto. | rol: salida | counter: guardbreak.
- **S06 Persistencia** | Vitalidad 80 | Tras sobrevivir a un golpe que reduce vida por debajo de 20%, 6% velocidad de recuperación de stamina por 4 s, ICD 60 s. | rol: escape | counter: ataques de rango.

### Chakra — seis cartas
- **S07 Respiración medida** | Chakra 20 | Carga interrumpida conserva hasta 8 de chakra acumulado; ICD 15 s. | rol: economía | counter: presión.
- **S08 Pulso sereno** | Chakra 30 | Carga estacionaria 8% más eficiente después de 2 s sin daño; no acumulable con Control. | rol: economía | counter: rush.
- **S09 Flujo estabilizado** | Chakra 40 | Primer jutsu tras terminar carga obtiene 5% menos coste, ICD 25 s. | rol: eficiencia | counter: interrupción.
- **S10 Núcleo concentrado** | Chakra 50 | Al gastar 30% de chakra máximo en 8 s, recupera 10 chakra durante 5 s, ICD 35 s. | rol: reserva | counter: chakra drain.
- **S11 Reserva de marcha** | Chakra 65 | Sprinting sin jutsu permite 10% regen de chakra fuera de combate; no durante combate. | rol: viaje | counter: PvP sin efecto.
- **S12 Cierre de circuito** | Chakra 80 | Tras sustitución exitosa, carga siguiente comienza sin retardo adicional de animación, no aumenta carga; ICD 25 s. | rol: fluidez | counter: predicción.

### Resistencia — seis cartas
- **S13 Defensa medida** | Resistencia 25 | Block timed confirmado regenera 8 stamina; ICD 8 s; no activa en block sostenido. | rol: timing | counter: feints.
- **S14 Paso ahorrador** | Resistencia 20 | Saltos en suelo consumen 5% menos stamina si ninguna habilidad de salto está activa. | rol: movilidad | counter: persecución.
- **S15 Talón firme** | Resistencia 35 | Tras 1.5 s bloqueando, 5% menos knockback en impacto bloqueado; no evita break. | rol: posicionamiento | counter: guardbreak.
- **S16 Respiración en guardia** | Resistencia 45 | Bloqueo exitoso acelera un 8% el siguiente inicio de regeneración de stamina; ICD 15 s. | rol: sostenimiento | counter: grabs.
- **S17 Guardia paciente** | Resistencia 60 | Al salir de guardbreak, +10% regeneración de guardia durante 3 s; ICD 30 s. | rol: recuperación | counter: presión.
- **S18 Control de caída** | Resistencia 75 | Si aterriza tras lanzamiento y no está incapacitado, consume 5 menos stamina en el primer dash; ICD 20 s. | rol: escape | counter: ground pressure.

### Taijutsu — seis cartas
- **S19 Impacto medido** | Taijutsu 20 | Finisher de M1 bloqueado reduce 3 adicionales de guardia, ICD 12 s. | rol: guard pressure | counter: dodge.
- **S20 Cadencia** | Taijutsu 35 | Después de acertar segundo M1, siguiente golpe de la cadena obtiene +3% ventana de alineación; sin acelerar ataque. | rol: consistencia | counter: substitution.
- **S21 Ajuste de distancia** | Taijutsu 40 | Tras M1 esquivado por el rival, siguiente dash lateral gasta 2 menos stamina; ICD 18 s. | rol: reposicionamiento | counter: tracking.
- **S22 Puño prudente** | Taijutsu 55 | M1 fallado no inicia efecto; al bloquear ataque tras fallo, 5% menos desgaste de guardia, ICD 20 s. | rol: defensa | counter: grabs.
- **S23 Ritmo de combate** | Taijutsu 65 | Alternar M1 y block correcto reduce 5% retraso de recuperación normal, ICD 20 s. | rol: tempo | counter: ranged.
- **S24 Control de remate** | Taijutsu 80 | Finisher que conecta a enemigo fuera de guardia reduce 0.1 s tiempo para iniciar movimiento; no cancela locks. | rol: posicionamiento | counter: counter dash.

### Ninjutsu — seis cartas
- **S25 Sellos estables** | Ninjutsu 20 | Daño recibido en primer 0.15 s de sello no altera animación; la interrupción normal sigue vigente. | rol: consistencia | counter: interrupt fuerte.
- **S26 Mano preparada** | Ninjutsu 30 | Si no se usó jutsu 8 s, primer jutsu consume 3% menos chakra; ICD 25 s. | rol: economía | counter: pressure.
- **S27 Respiración del sello** | Ninjutsu 40 | Tras cancelar casteo voluntariamente, recupera hasta 5 chakra del coste reservado; ICD 20 s. | rol: cancel | counter: interrupción.
- **S28 Lectura elemental** | Ninjutsu 50 | Un impacto elemental acertado revela 1 s si el objetivo tiene resistencia al elemento; info, no daño. | rol: información | counter: ocultación.
- **S29 Sello compacto** | Ninjutsu 65 | En área segura fuera de combate, practicar sellos es 10% más rápido; no afecta PvP. | rol: training | counter: PvP n/a.
- **S30 Canal preciso** | Ninjutsu 80 | Tras jutsu fallado, siguiente carga fuera de combate inicia 0.3 s antes, ICD 30 s. | rol: economía | counter: persecución.

### Genjutsu — seis cartas
- **S31 Percepción velada** | Genjutsu 20 | Al observar una ilusión 1 s, muestra señal visual tenue de inconsistencia; no identifica automáticamente la fuente. | rol: información | counter: feint.
- **S32 Pensamiento claro** | Genjutsu 40 | Tras liberarse de efecto ilusorio, resistencia breve a repetición del mismo ID por 3 s; no apila. | rol: anti-loop | counter: variación.
- **S33 Eco engañoso** | Genjutsu 45 | Al romper Henge cerca de rival, sombra ilusoria no dañina dura 0.4 s; ICD 25 s. | rol: finta | counter: Byakugan.
- **S34 Umbral mental** | Genjutsu 55 | Si fue objetivo de genjutsu, la siguiente comprobación de señal es 8% más rápida; ICD 20 s. | rol: defensa | counter: presión física.
- **S35 Atención dividida** | Genjutsu 65 | Destruir clone ilusorio muestra una pista de origen de 0.5 s; ICD 15 s. | rol: detección | counter: multi-clones.
- **S36 Rastro falso** | Genjutsu 80 | Al terminar sustitución de cuervos, produce 0.4 s de sonido señuelo; ICD 30 s. | rol: engaño | counter: percepción.

### Bukijutsu — seis cartas
- **S37 Mango seguro** | Bukijutsu 20 | Tras parry fallido, primer block dentro de 2 s sufre 5% menos desgaste, ICD 25 s. | rol: consistencia | counter: guardbreak.
- **S38 Ojo de filo** | Bukijutsu 30 | Un impacto con herramienta revela 0.5 s una silueta breve del punto de impacto, no seguimiento. | rol: información | counter: cover.
- **S39 Recogida disciplinada** | Bukijutsu 40 | Fuera de combate, recuperación de herramientas arrojadas recuperables es 10% más rápida; sin duplicar stock. | rol: logística | counter: no combat.
- **S40 Precisión lateral** | Bukijutsu 50 | Después de sidestep, siguiente arrojadizo obtiene 5% menor dispersión, ICD 20 s. | rol: aim | counter: block.
- **S41 Acero oportuno** | Bukijutsu 65 | Tras parry real, siguiente golpe de arma genera 4 adicionales de daño de guardia; ICD 20 s. | rol: guard pressure | counter: bait.
- **S42 Mano ligera** | Bukijutsu 80 | Cambiar entre arma y herramienta reduce 0.08 s la espera de control si no está en combo; respeta locks. | rol: fluidez | counter: rush.

### Velocidad — seis cartas
- **S43 Paso silencioso** | Velocidad 20 | Después de 3 s caminando sin ataque, rango audible de pasos baja 20%, cesa al sprintar. | rol: stealth | counter: visión.
- **S44 Pisada limpia** | Velocidad 30 | Tras aterrizaje normal, primeros 0.5 s hacen menos ruido; no oculta partículas ni rastros. | rol: stealth | counter: Byakugan.
- **S45 Retirada medida** | Velocidad 40 | Tras dodge de ataque confirmado, siguiente dash lateral reduce coste 3 stamina; ICD 18 s. | rol: defensa | counter: read.
- **S46 Giro eficiente** | Velocidad 50 | Al invertir dirección corriendo, aceleración inicial aumenta 4% durante 0.3 s; respetar tope global. | rol: control | counter: AOE.
- **S47 Sombra fugaz** | Velocidad 65 | Después de dash, sonido de posición anterior persiste 0.3 s; sin clon ni invisibilidad. | rol: misdirection | counter: percepción.
- **S48 Ventana de escape** | Velocidad 80 | Al salir de un stun normal, siguiente dash gana 5% reducción de coste; ICD 30 s. | rol: escape | counter: prediction.

### Híbridas — 16 cartas
- **H01 Ruptura de ritmo** | Taijutsu+Velocidad 40/40 | Tras esquivar M1 cercano, siguiente M1 inicia 0.04 s antes; ICD 20 s; no anula telegraph. | counter: fintas.
- **H02 Remolino controlado** | Taijutsu+Velocidad 60/50 | Tras combo aéreo, caída consume 7 menos stamina si existe Estilo del remolino; ICD 20 s. | counter: anti-air.
- **H03 Filo conductor** | Bukijutsu+Ninjutsu 40/40 | Con Kenjutsu elemental, arma añade 5% duración de estado elemental; limitado por cap del estado. | counter: resistencia elemental.
- **H04 Contraflujo** | Bukijutsu+Ninjutsu 60/50 | Tras parry, siguiente aplicación elemental de arma reduce su coste de mantenimiento en 10%; ICD 25 s. | counter: proyectiles.
- **H05 Doble lectura** | Genjutsu+Ninjutsu 40/40 | Después de Jutsu fantasma, señal visual indica qué proyectil fue real al impactar, solo para usuario. | counter: percepción.
- **H06 Eco retardado** | Genjutsu+Ninjutsu 65/45 | Duplicado ilusorio persiste 0.25 s adicionales sin daño, ICD 18 s. | counter: Byakugan.
- **H07 Recuperación medida** | Chakra+Vitalidad 40/40 | Con Cuerpo de chakra, curación solo inicia tras 1 s de carga ininterrumpida; +0.1% vida/s exclusivamente fuera de combate. | counter: rush.
- **H08 Corazón centrado** | Chakra+Vitalidad 65/50 | Después de carga de 3 s fuera de combate, reduce 10% coste de la siguiente curación propia si existe; ICD 60 s. | counter: interrupción.
- **H09 Cambio firme** | Resistencia+Taijutsu 40/40 | Con Armadura de combate, el último M1 reduce 3 daño de guardia recibido durante su recuperación; ICD 20 s. | counter: dodge.
- **H10 Respuesta firme** | Resistencia+Taijutsu 65/50 | Después de Defensa medida, siguiente M1 aumenta 4 daño de guardia; ICD 20 s. | counter: feint.
- **H11 Flanco calculado** | Velocidad+Bukijutsu 40/40 | Tras movimiento lateral, primera arma acertada desde ángulo posterior revela acierto limpio sin más daño. | counter: defensa de espalda.
- **H12 Retirada del duelista** | Velocidad+Bukijutsu 65/50 | Tras parry, el primer dash a un lado cuesta 5 menos stamina; ICD 20 s. | counter: multi-hit.
- **H13 Ritmo incierto** | Genjutsu+Taijutsu 40/40 | Con Golpe hipnótico, primer M1 tras genjutsu exitoso reduce 4 desgaste de guardia propia al bloquear; ICD 20 s. | counter: anti-gen.
- **H14 Lectura falsa** | Genjutsu+Taijutsu 60/60 | Último M1 muestra afterimage no dañino de 0.25 s si no está bloqueado; ICD 25 s. | counter: sensor.
- **H15 Circuito estable** | Chakra+Ninjutsu 40/40 | Con Gran reserva, primer jutsu rango B tras cargar 2 s consume 3% menos chakra adicional; cap de descuento total 25%. | counter: silence.
- **H16 Pulso disciplinado** | Chakra+Ninjutsu 65/65 | Después de jutsu completo sin interrupción, siguiente inicio de carga gana 5% rapidez por 1 s; ICD 25 s. | counter: agresión.

### Generales y exploración — 16 cartas
- **G01 Mensajero del bosque** | n5+ | Fuera de combate, marcas manuales de ruta permanecen 20% más en mapa personal. | counter/alcance: n/a.
- **G02 Observador prudente** | n5+ | Tras ver un arrojadizo acertar terreno, muestra su clase durante 2 s, sin posición del rival. | counter/alcance: n/a.
- **G03 Aliento viajero** | n10+ | Fuera de combate, sprint intermitente reduce 3% consumo stamina en terreno normal. | counter/alcance: n/a.
- **G04 Percepción de sendero** | n10+ | Landmarks descubiertos generan indicación suave en mapa personal, sin revelar NPC secretos. | counter/alcance: n/a.
- **G05 Rutina shinobi** | n15+ | En zonas seguras, comenzar práctica de entrenamiento tarda 10% menos; sin XP extra. | counter/alcance: n/a.
- **G06 Oído entrenado** | n20+ | Efecto audio aumenta distinción de herramientas cercanas, opción accesible y sin bonus de distancia. | counter/alcance: n/a.
- **G07 Preparación ordenada** | n20+ | Fuera de combate, cambiar selección de herramientas en Ninja Bag tiene menor retardo visual; no altera servidor. | counter/alcance: n/a.
- **G08 Lectura del terreno** | n25+ | Al explorar, diferencia senda conocida en mapa sin aumentar visión real. | counter/alcance: n/a.
- **G09 Respeto del equipo** | n30+ | Estado de desgaste de armadura se visualiza con señal adicional accesible; sin buff. | counter/alcance: n/a.
- **G10 Punto de encuentro** | n35+ | Permite guardar una nota de referencia de región en mapa personal; sin teletransporte. | counter/alcance: n/a.
- **G11 Observación del clima** | n40+ | Predice tendencia del estado climático regional solo a partir de indicios visibles; sin precisión garantizada. | counter/alcance: n/a.
- **G12 Vigilancia lateral** | n45+ | Indicador de dirección de fuente de sonido existente mejora legibilidad, no alcance de detección. | counter/alcance: n/a.
- **G13 Memoria de misión** | n50+ | Registra en diario referencias de zonas visitadas; no resuelve objetivos automáticamente. | counter/alcance: n/a.
- **G14 Suministros contados** | n55+ | Indicador anticipa stock bajo por tipo de herramienta en UI; no aumenta capacidad. | counter/alcance: n/a.
- **G15 Compañero disciplinado** | n60+ | Marca visual personal de aliado designado en rango normal de party; no atraviesa ocultación. | counter/alcance: n/a.
- **G16 Escucha del bosque** | n65+ | Mejor distinción de animales/ambiente frente a pasos, sin amplificar sonidos rivales. | counter/alcance: n/a.

### Catálogo validación
Recuento: 48 mono-stat, 16 híbridas, 16 generales => 80. No hay nombres, scripts, assets ni buffs de Deepwoken copiados.

## 8. Árboles, prerequisitos y exclusiones: RFC
Arquetipo Defensa reactiva: S13 Defensa medida (Res 25) -> [H10 Respuesta firme Res 65 Tai 50] o [H12 Retirada del duelista Vel 65 Buk 50], EXCLUSIVE_CHAIN_BRANCH; la rama alternativa exige otro prerrequisito de parry y no se considera realmente elegible sin él. Culminación candidata 'Dominio defensivo' queda FUERA del catálogo de 80 hasta pasar análisis stacking; ejemplo de dirección, no carta concedible.
Arquetipo Kenjutsu: rasgo PDF 'Kenjutsu elemental' (Buk 40 + Nin 40) -> H03 Filo conductor -> H04 Contraflujo (requiere parry), exclusión si el arma no soporta canalización. Arquetipo Ilusionista: rasgo PDF 'Jutsu fantasma' (Gen 40 + Nin 40) -> H05 -> H06.
Regla de implementación: NO inferir prerequisitos del texto mostrado: deben codificarse en registry, ser auditables y prueba unitaria obligatoria. H04 requiere H03; H06 requiere H05; H02 requiere H01 + Estilo del remolino; H10 requiere S13; H12 requiere parry + S13; H16 requiere H15. Registrar exclusividad sólo tras decisión de diseño; por ahora se muestran como requerimientos propuestos.

## 9. Respec, clan, cambio de equipamiento y permadeath
Respec stats vigente: una vez gratis y luego objeto raro/Robux; esta RFC NO cambia esa regla. Propuesta de política para talentos: snapshot de atributos al aprender, el talento PERMANECE registrado pero queda INACTIVE al no cumplir sus requisitos actuales; reactivar al recuperarlos; no borrar talento ni entregar carta nueva. Evita dupear elecciones y ofrece transparencia. Si se decide futuro respec de cartas, debe ser limitado a una sustitución fuera de combate y sólo antes de adoptar maestría; REQUIERE DECISIÓN.
Al equipar/retirar variantes de dash/sustitución: reevaluar requisitos contextuales, nunca conceder talento nuevo. Al cambiar clan no hay caso normal (clan fijo por slot). La carta no debe activar efectos para otro ClanId ni al transferir slot.
Cuando la vida termina, perks por vida se borran SOLO cuando el Character Life service confirma WIPE definitivo; revive preserva exactamente talentos del mismo CharacterId/LifeId conforme a reglas del lifecycle aprobadas. No mutar datos de account permanent sin diseño independiente. Meta-progresión Echo-like fuera de alcance: únicamente cosméticos/diario/quality-of-life si se aprueba, no daño extra intervidas.

## 10. Arquitectura objetivo compatible; no duplicar runtime
Design-only nuevos componentes candidatos: ReplicatedStorage/Shared/TalentDefinitions (solo metadatos y descripciones replicables), ServerScriptService/Services/TalentOfferService (sampling y validación), TalentStateService (persistencia por vida), TalentEffectRegistry (handlers server authoritative), StarterPlayerScripts/TalentSelectionHUD (presentación). No añadir instancias a Roblox ahora.
Integraciones a evaluar sobre archivo canónico real: CharacterProgressionService al subir nivel; CharacterDataService y/o AccountProfileService para persistencia por lifeId; CharacterRequirementService como parser de MinPlayerAttributes y trait prereq; Combat/DamageService para eventos aceptados; ChakraConfig/StaminaConfig/Health para recursos; DashController/SubstitutionServer para variantes; TechniqueLoadoutService como lectura de equipamiento únicamente; TAB/menú shinobi según UX aprobado sin alterar Inventory. No crear un segundo sistema de niveles, jutsus, salud o reemplazar CombatBalance.
Contrato sugerido: AwardMilestone(CharacterId,LifeId,level,revision) idempotente -> PendingOffer{offerId,level,seed,choices,createdAt,version}; ChooseTalent(offerId,selectedId,nonce) atómico -> OwnedTalent{cardId,acquiredLevel,version,active}; EventGateway normalizado OnBlockSuccess/OnDodgeConfirmed/OnJutsuAccepted/OnParryConfirmed/OnLifeWiped. Verificar eventos reales en fuentes canónicas: son interfaz PROPOSED, no nombres confirmados.
Persistencia schemaCandidate v1: talentSchemaVersion, rollRevision, ownedTalentIds, pendingMilestones, pendingOffer, rerollsUsed, reservedTalentId, bannedIds, eventCounters; todos dentro del mismo Character Life record; validar límites y tamaño de DataStore. Nunca guardar stack de buffs efímeros. Backup/migración en snapshot antes de integrar.
Transacciones: server-only claim; single-flight por LifeId; monotonía de nivel y oferta; compare-and-swap/retry compatible con el servicio persistente real; doble click, disconnect, retries, multi-server, teleport y server migration tienen que ser idempotentes. Reconciliar con sesión locks y rollback cross-place existente.

## 11. UX/UI accesible
Mano de tres cartas como pergaminos/papel washi discretos, tinta y pincel sobrios, nombre/ícono, requisitos, efecto corto, tooltip de cooldown/counter, indicador 'puedes elegir 1', confirmación reversible hasta Submit. Evitar metales, glow genérico y ornamentación exagerada. Solo mostrar al subir nivel en lugar seguro o luego de combate (no congelar inputs durante duelo). Mobile: tarjetas apiladas; gamepad focus; mouse/tablet; screenreader equivalente textual donde plataforma lo permita.
TAB muestra progreso y todas cartas adquiridas con filtro de familias; sin abrir más hotbars. Mando NPC maestros vincula enseñanza y soft-bias de futuras manos, no venta de probabilidades. Estado 'inactive due to respec' y futuro aspiracional de prerequisitos visibles sin revelar secretos ocultos. No obligar a elegir inmediatamente: pendiente persistente.

## 12. Economía y adquisición
Las cartas por nivel no cuestan Ryo ni Robux. Entrenamiento especial y maestro pueden desbloquear elegibilidad sin saltarse límites; quests de conocimiento pueden otorgar entradas de codex o abrir cartas futuras, no conceder 21ª carta sin un tipo claramente separado de recompensa. Rechazar boosters pagados de rareza, reroll ilimitado o cajas aleatorias de PvP. Transparencia de probabilidad para cualquier aleatoriedad implementada y revisión de políticas Roblox al momento de ship.

## 13. Plan QA, amenazas y telemetría
Tests estáticos: no 2 ids iguales; 80 cards exactas; 8 stats permitidas; nombres/localización; minLevel reachable; thresholds <=100; graph no cycles; cada advanced con fallback; exclusiones simétricas. Tests property-based: simular 1–100 por ≥1000 repartos aleatorios y las seis builds del PDF; todos los hitos generan tres cartas o fallback explícito; ningún camino viola 297 puntos.
Combate: PvP 1v1 espejo por vida/clan/equipo igual; target duel 45–90 s con percentiles p25/p50/p75; promedio por match, no solo ganadores; alerta inicial por win-rate >55% para arquetipos con N suficiente; revisar pick rate, proc uptime, stamina/chakra economy, guardbreak loops, time-to-kill, source win bias y cantidad de efectos concurrentes. Simular de forma especial Sharingan/Byakugan, Henge, substitutions, elemental reaction, parry, air combo, knockdown, respawn.
Seguridad: forged remotes, ID no ofrecido, replay offerId, spoof CharacterId, packet spam, forced respec mid-selection, disconnected mid-write, multi-server double-write; nonces y rate-limit con auditoría. Performance: 2 jugadores, 20 jugadores, mobile lowest-tier; sin partículas permanentes o polling por frame; profiler EventGateway; memory leak tras respawn, wipe y teleport.
Señales principales: offer_created, offer_reopened, offer_selected, offer_invalid, talent_triggered, talent_proc_suppressed, card_inactive_after_respec, life_wiped, duel_finish; version, character anonymizado, level, build bucket, card family, match context. Retención, anonimización y consentimiento a alinear con ANALYTICS_PLAN; sin guardar datos de identidad sin necesidad.

## 14. Secuencia recomendada de implementación si se aprueba algún día
Gate 0: due diligence canónica (CURRENT_STATUS, FILE_MANIFEST, KNOWN_ISSUES, DECISIONS_LOG + fuentes actuales GitHub/Studio) y confirmación de versión de Stats & Builds. Gate 1: owner aprueba/edita esta RFC y comité decide economía/poder/permadeath. Gate 2: registry data-only + validador offline y simulador 1–100; no runtime. Gate 3: XP milestone service + persistencia idempotente detrás de flag desactivado. Gate 4: selection UI dummy de tres cartas sin buffs. Gate 5: 15–20 cartas de vertical slice, server events existentes auditados, VFX cuando proceda. Gate 6: PvP/PvE/móvil/exploit QA; Gate 7: iterar balance y aprobar per build; Gate 8: integrar en release bajo rollback verificable.
Nada se considera CANONICAL sin owner explicit QA y actualización del control plane, release/rollback y git main por PR aprobado. Ruta de GitHub RFC en rama proposal, no runtime, no PR ni merge automático.

## 15. Matriz de riesgos y mitigación
R1 [HIGH]: stack inflación combat -> proc budgets, nonstacking y QA. R2 [HIGH]: DataStore/character loss -> lifeId isolation/atomic transactions, replica testing. R3 [HIGH]: 100 levels con 20 milestones triviales -> variety chains y choices; probar retention y decision load. R4 [HIGH]: pay-to-win vía reroll -> no pago. R5 [MED]: pools elegibles demasiado chicos -> general fallback + detector. R6 [MED]: tutorial/UI overload -> contextual, opción posponer. R7 [MED]: variación RNG arruina build -> bias, reroll limitado y no must-have meta. R8 [MED]: deuda técnica por mezclar Jutsu/Combat → respetar estado de QA, no scripts paralelos. R9 [MED]: rendimiento mobile -> no continuous client effects. R10 [HIGH]: contenido inspirado demasiado similar a Deepwoken/Bloodlines -> originales en nombres, ilustración y mecánicas específicas.

## 16. Criterios de aceptación para DISEÑO (no QA de código)
✓ cada una de 80 cartas tiene definición, requisito y contra/alcance. ✓ seis builds ejemplo de PDF pueden alcanzar manos de 3. ✓ catálogo clasificado por disciplina/híbrido/general. ✓ 32 rasgos del PDF y 8 híbridos no duplicados ni consumidos como cartas. ✓ documentación de persistencia, respec, wipe/revive, counters, UI, QA, telemetría y monetización. ✓ plan de QA y gating explícito. ✓ archivo íntegro en Drive + GitHub sin tocar main.

## 17. Cuestiones abiertas — NO aprobadas
D1 ¿Mano cada 5 niveles (20 cartas) o manos más espaciadas? D2 ¿Permitir reserva/ban/reroll? D3 ¿Fijar límites de proc en lugar de 20 cartas sin slot? D4 ¿Respec de cartas independiente o talentos quedarán inactivos? D5 ¿Quest talents otorgan carta adicional o modifican pool? D6 ¿Telemetría privacy model? D7 ¿Revisar stacking con maestrías y rasgos del PDF? D8 ¿Nivel 100 elige carta y maestría en dos momentos separados? D9 ¿Talent selection popup automatic o pospuesto en TAB? D10 ¿Cuáles perks se desactivan durante world safezones/eventos? Todas requieren aprobación posterior.

## 18. Referencias y provenance
Fuente WAYLESS: adjunto PDF 13pp 'Wayless · Stats y Builds', 24 Oct 2026, enviado por el usuario en este hilo, prioridad absoluta de contenido. Registros consultados: Google Drive 00_PROJECT_CONTROL/CURRENT_STATUS, FILE_MANIFEST, KNOWN_ISSUES, DECISIONS_LOG, MASTER_CONTEXT, ROADMAP. No alterar estos archivos por una propuesta no aprobada.
Inspiración externa no canónica: https://deepwoken.fandom.com/wiki/Deepwoken_Wiki ; https://trello.com/b/6qTU0St2/bloodlines-trello . El acceso exhaustivo a todas las entradas externas no está demostrado, por lo que los rasgos aquí catalogados son creación específica para WAYLESS y NO implican verificación completa de esas wikis.

## 19. Control de cambios
v1.0 2026-10-25 — RFC con 80 talentos, reglas, riesgos, arquitectura, QA y gating; PROPOSAL ONLY.