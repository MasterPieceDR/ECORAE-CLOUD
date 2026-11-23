import { useEffect, useRef } from 'react';
import { scan } from '@/shared/cinema/index.js';

// Activa los efectos data-* dentro del elemento y los limpia al desmontar.
export function useCinema(ready = true) {
  const ref = useRef(null);
  useEffect(() => {
    if (!ready || !ref.current) return undefined;
    return scan(ref.current);
  }, [ready]);
  return ref;
}
