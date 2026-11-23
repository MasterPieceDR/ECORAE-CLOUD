// La elección se conserva incluso si el almacenamiento está bloqueado.

let tema = 'light';

try { tema = localStorage.getItem('eco-theme') || 'light'; } catch { /* almacenamiento no disponible */ }

const mediaTema = window.matchMedia('(prefers-color-scheme: dark)');

export function aplicarTema(preferencia) {

  const valor = ['light', 'dark', 'system'].includes(preferencia) ? preferencia : 'system';

  document.documentElement.dataset.theme = valor === 'system' ? (mediaTema.matches ? 'dark' : 'light') : valor;

  document.documentElement.dataset.themePreference = valor;

  try { localStorage.setItem('eco-theme', valor); } catch { /* almacenamiento no disponible */ }

}

mediaTema.addEventListener('change', () => { if (document.documentElement.dataset.themePreference === 'system') aplicarTema('system'); });

aplicarTema(tema);

