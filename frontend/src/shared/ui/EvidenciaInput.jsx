import { useCatalogos } from '@/features/auth';

// Selector de evidencia: tipo (según lo que permite la acción) + archivo. La subida ocurre al confirmar.
export function EvidenciaInput({ tipos, value, onChange, required = true, label = 'Evidencia' }) {
  const { tipoEvidencia } = useCatalogos();
  const tipo = value?.tipo ?? tipos[0];
  const t = tipoEvidencia(tipo);
  const accept = (t?.mime ?? []).join(',');
  return (
    <fieldset className="evid">
      <legend>{label}{required ? ' *' : ' (opcional)'}</legend>
      {tipos.length > 1 && (
        <label className="field">Tipo
          <select value={tipo} onChange={(e) => onChange({ tipo: e.target.value, file: null })}>
            {tipos.map((x) => <option key={x} value={x}>{tipoEvidencia(x)?.nombre ?? x}</option>)}
          </select>
        </label>
      )}
      <label className="field">{tipos.length === 1 ? (t?.nombre ?? tipo) : 'Archivo'}
        <input type="file" accept={accept} required={required} onChange={(e) => onChange({ tipo, file: e.target.files[0] ?? null })} />
      </label>
      <small className="evid__hint">
        Formatos: {(t?.mime ?? []).map((m) => m.split('/')[1].toUpperCase()).join(', ')} · máx. 25 MB.
        {(t?.mime ?? []).some((m) => m.startsWith('image/')) && ' Las fotos se limpian de GPS y metadatos antes de subir (RNF-10).'}
      </small>
    </fieldset>
  );
}
