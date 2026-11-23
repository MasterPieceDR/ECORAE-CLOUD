import { useState } from 'react';
import { aplicarTema } from '@/shared/styles/theme';
import './ThemeSelect.css';

export function ThemeSelect() {
  const [tema, setTema] = useState(document.documentElement.dataset.themePreference || 'system');

  return (
    <label className="theme-select">
      <span className="sr">Tema</span>
      <select value={tema} onChange={(e) => { setTema(e.target.value); aplicarTema(e.target.value); }}>
        <option value="light">Claro</option>
        <option value="dark">Oscuro</option>
        <option value="system">Sistema</option>
      </select>
    </label>
  );
}
