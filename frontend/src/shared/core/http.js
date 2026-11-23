// Cliente de la API de EcoRAEE (FastAPI detrás de CloudFront /api → ALB → ECS/EC2).
// El token vive en sessionStorage: se borra al cerrar la pestaña.
const BASE = import.meta.env.VITE_API_URL ?? '/api/v1';
const CLAVE_TOKEN = 'ecoraee:token';

export class ApiError extends Error {
  constructor(message, status = 0, codigo = '', requestId = null) {
    super(message);
    this.status = status;
    this.codigo = codigo;
    this.requestId = requestId;
  }
}

export const token = {
  get: () => { try { return sessionStorage.getItem(CLAVE_TOKEN); } catch { return null; } },
  set: (v) => { try { if (v) sessionStorage.setItem(CLAVE_TOKEN, v); else sessionStorage.removeItem(CLAVE_TOKEN); } catch { /* modo privado */ } },
};

let alExpirar = () => {};
export const onSesionExpirada = (fn) => { alExpirar = fn; };

async function request(ruta, { method = 'GET', body, query } = {}) {
  const headers = { Accept: 'application/json' };
  const t = token.get();
  if (t) headers.Authorization = `Bearer ${t}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const qs = query ? `?${new URLSearchParams(Object.entries(query).filter(([, v]) => v !== undefined && v !== null && v !== '')).toString()}` : '';
  let res;
  try {
    res = await fetch(`${BASE}${ruta}${qs === '?' ? '' : qs}`, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
  } catch {
    throw new ApiError('Sin conexión con el servidor. Revisa tu red e inténtalo de nuevo.', 0, 'RED');
  }
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    if (res.status === 401 && t) alExpirar();
    throw new ApiError(typeof data.detail === 'string' ? data.detail : 'No se pudo completar la operación.', res.status, data.codigo, data.request_id);
  }
  return data;
}

export const http = {
  get: (ruta, query) => request(ruta, { query }),
  post: (ruta, body = {}) => request(ruta, { method: 'POST', body }),
  put: (ruta, body = {}) => request(ruta, { method: 'PUT', body }),
  del: (ruta, body) => request(ruta, { method: 'DELETE', body }),
};

// ---------------------------------------------------------------------------
// Archivos: el navegador sube directo al almacén (S3 con URL prefirmada; la API no recibe el binario)
// ---------------------------------------------------------------------------
async function sha256(blob) {
  const hash = await crypto.subtle.digest('SHA-256', await blob.arrayBuffer());
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// RNF-10: re-dibujar la imagen en un canvas elimina EXIF y GPS. También la reduce para conexiones lentas (RNF-07).
async function limpiarImagen(file, mime, maximo = 1800) {
  const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' });
  const escala = Math.min(1, maximo / Math.max(bmp.width, bmp.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bmp.width * escala);
  canvas.height = Math.round(bmp.height * escala);
  canvas.getContext('2d').drawImage(bmp, 0, 0, canvas.width, canvas.height);
  return new Promise((ok, mal) => canvas.toBlob((b) => (b ? ok(b) : mal(new ApiError('No se pudo procesar la imagen.'))), mime, 0.88));
}

function put(url, blob, cabeceras = {}, onProgress = () => {}) {
  return new Promise((ok, mal) => {
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', url);
    Object.entries(cabeceras).forEach(([k, v]) => xhr.setRequestHeader(k, v));
    xhr.upload.onprogress = (e) => e.lengthComputable && onProgress(Math.round((e.loaded / e.total) * 100));
    xhr.onload = () => (xhr.status < 300 ? ok() : mal(new ApiError('El almacén rechazó el archivo.', xhr.status, 'ALMACEN')));
    xhr.onerror = () => mal(new ApiError('Se cortó la conexión durante la subida.', 0, 'RED'));
    xhr.send(blob);
  });
}

const MIME_IMAGEN = ['image/jpeg', 'image/png', 'image/webp'];

/** Sube una evidencia y la registra en la base. Devuelve su uid. */
export async function subirEvidencia({ tipo, file, objeto }, onProgress) {
  const mime = file.type || 'application/octet-stream';
  const blob = MIME_IMAGEN.includes(mime) ? await limpiarImagen(file, mime) : file;
  const firma = await http.post('/evidencias/subida', { tipo, mime, tamano: blob.size });
  await put(firma.url, blob, firma.cabeceras, onProgress);
  const r = await http.post('/evidencias', { tipo, clave: firma.clave, sha256: await sha256(blob), mime, tamano: blob.size, objeto });
  return r.uid;
}

/** Sube un video de capacitación. Devuelve los datos del archivo para publicarlo. */
export async function subirVideo(file, onProgress) {
  const firma = await http.post('/capacitacion/subida', { mime: file.type, tamano: file.size });
  await put(firma.url, file, firma.cabeceras, onProgress);
  return { clave: firma.clave, mime: file.type, tamano: file.size };
}

export async function subirImagenModelo(uid, file, onProgress) {
  if (!MIME_IMAGEN.includes(file.type)) throw new ApiError('Selecciona una imagen JPEG, PNG o WEBP.');
  const blob = await limpiarImagen(file, file.type);
  const firma = await http.post(`/catalogo/modelos/${uid}/imagen/subida`, { mime: file.type, tamano: blob.size });
  await put(firma.url, blob, firma.cabeceras, onProgress);
  return http.put(`/catalogo/modelos/${uid}/imagen`, { clave: firma.clave, sha256: await sha256(blob), mime: file.type, tamano: blob.size });
}
