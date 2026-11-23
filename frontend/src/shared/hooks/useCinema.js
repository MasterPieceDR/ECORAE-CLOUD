import { useEffect, useRef } from 'react';
import { scan } from '@/shared/cinema/index.js';

// Activa los efectos data-* dentro del elemento y los limpia al desmontar.
export function useCinema(ready = true) {
  const ref = useRef(null);
  useEffect(() => {
    if (!ready || !ref.current) return undefined;
    const media = matchMedia('(prefers-reduced-motion: reduce)');
    let limpiar = scan(ref.current);
    const actualizar = () => { limpiar(); limpiar = scan(ref.current); };
    media.addEventListener('change', actualizar);
    return () => { media.removeEventListener('change', actualizar); limpiar(); };
  }, [ready]);
  return ref;
}
