// Guion común de la portada: cifras de fuentes del proyecto y fotos ya descargadas en img/.
export const photo = (name) => `./img/${name}.webp`;

export const STATS = [
  { value: 62, suffix: ' Mt', label: 'de residuos electrónicos generados en el mundo en 2022' },
  { value: 22.3, decimals: 1, suffix: ' %', label: 'se recolectó y recicló de forma documentada' },
  { value: 200, suffix: '', label: 'equipos por semana procesa hoy la red de ejemplo' },
  { value: 13, suffix: '', label: 'estados de trazabilidad, del registro al cierre' },
];

export const MANIFESTO = 'Detrás de cada equipo que se desecha hay materiales, datos y una historia que nadie sigue. EcoRAEE Cloud conecta a quienes generan, recogen, evalúan y recuperan, para que ningún dispositivo se pierda en el camino.';

export const STEPS = [
  { n: '01', title: 'Registra', text: 'El equipo recibe un código único. Su historia empieza aquí y no vuelve a perderse en una hoja de cálculo.', who: 'Generador', photo: 'residuos' },
  { n: '02', title: 'Recolecta', text: 'Un centro de acopio confirma la recepción con evidencia, origen y responsable.', who: 'Operador de centro', photo: 'tecnico' },
  { n: '03', title: 'Evalúa', text: 'Un técnico autorizado decide si se reutiliza, se repara, se recicla o se dispone de forma controlada.', who: 'Técnico evaluador', photo: 'reparar-celular' },
  { n: '04', title: 'Recupera', text: 'La red analiza su capacidad real, autoriza el traslado y lleva cada equipo a su mejor destino.', who: 'Coordinador logístico', photo: 'laptop-interior' },
  { n: '05', title: 'Cierra', text: 'Una escuela lo recibe o un gestor recupera sus materiales. Queda constancia del destino final.', who: 'Entidad beneficiaria', photo: 'estudiantes' },
];

export const DESTINIES = [
  { title: 'Reutilizable', text: 'Funciona como está y vuelve a usarse en una escuela.', photo: 'aula' },
  { title: 'Reparable', text: 'Una reparación le devuelve años de vida útil.', photo: 'pinzas' },
  { title: 'Reciclable', text: 'Sus materiales se recuperan con un gestor autorizado.', photo: 'placas-pila' },
  { title: 'No recuperable', text: 'Se dispone de forma controlada y con evidencia.', photo: 'monitores' },
];

export const PLATFORM = [
  { icon: 'box', title: 'Inventario vivo', text: 'Cada equipo y lote con su historial completo.' },
  { icon: 'network', title: 'Flujo máximo', text: 'Cuánto procesa la red y dónde se atasca.' },
  { icon: 'user', title: '11 roles', text: 'Cada persona ve y hace solo lo que le corresponde, con alcance por centro.' },
  { icon: 'file', title: 'Evidencias', text: 'Fotos sin GPS y actas protegidas, descargables solo con un propósito.' },
];

export const GALLERY = ['placa-verde', 'celulares', 'servidores', 'laptop-abierta', 'placa-azul', 'chatarra', 'rack', 'placa-chips', 'cables'];
// Foto de portada por tema de capacitación
const FOTO_TEMA = { CONCEPTOS: 'residuos', RECICLAJE: 'monitores', REPARACION: 'reparar-celular', COMUNIDAD: 'aula', SEGURIDAD_DATOS: 'servidores' };
export const fotoTema = (tema, i = 0) => photo(FOTO_TEMA[tema] ?? ['bosque', 'pinzas', 'placa-verde'][i % 3]);

// La portada es pública (no consulta la API): copia de los 13 estados del diccionario maestro (cat.estado_trazabilidad)
export const ESTADOS_PUBLICOS = ['Registrado', 'Recolección solicitada', 'En recolección', 'Recibido', 'En evaluación', 'Clasificado',
  'En transferencia', 'En tratamiento', 'Tratado', 'Asignado a beneficiario', 'Cerrado'];

export const CAPACITACION_PUBLICA = [
  { titulo: '¿Qué son los RAEE?', tema: 'CONCEPTOS', texto: 'Qué se considera residuo electrónico y cómo empezar en casa.' },
  { titulo: 'Borra tus datos antes de donar', tema: 'SEGURIDAD_DATOS', texto: 'Por qué la red exige un certificado de borrado (RN-09).' },
  { titulo: 'Computadoras para escuelas', tema: 'COMUNIDAD', texto: 'Cómo un equipo reacondicionado llega a una escuela.' },
];

// Foto de portada de cada sección interna.
const COVERS = [['/app/objetos', 'residuos'], ['/app/tareas', 'tecnico'], ['/app/documentos', 'placa-verde'], ['/app/red', 'servidores'],
  ['/app/capacitacion', 'aula'], ['/app/auditoria', 'rack'], ['/app/usuarios', 'cables'], ['/app/perfil', 'placa-azul'], ['/app', 'bosque']];
export const coverFor = (path) => (COVERS.find(([p]) => path.startsWith(p)) ?? COVERS[COVERS.length - 1])[1];
