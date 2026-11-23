import { useCallback, useEffect, useState } from 'react';

export function useAsync(fn, deps = []) {
  const [state, setState] = useState({ data: null, loading: true, error: null });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const run = useCallback(fn, deps);
  const reload = useCallback(() => {
    let live = true;
    setState((s) => ({ ...s, loading: true, error: null }));
    run().then(
      (data) => live && setState({ data, loading: false, error: null }),
      (error) => live && setState({ data: null, loading: false, error }),
    );
    return () => { live = false; };
  }, [run]);
  useEffect(() => reload(), [reload]);
  const setData = (data) => setState((s) => ({ ...s, data: typeof data === 'function' ? data(s.data) : data }));
  return { ...state, reload, setData };
}
