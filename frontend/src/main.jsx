import React from 'react';
import { createRoot } from 'react-dom/client';
import '@fontsource-variable/bricolage-grotesque';
import '@fontsource/instrument-serif/400-italic.css';
import '@/shared/cinema/cinema.css';
import '@/shared/styles/tokens.css';
import '@/shared/styles/base.css';
import { App } from '@/app/App';
import { startSmoothScroll } from '@/shared/cinema/index.js';

startSmoothScroll();
createRoot(document.getElementById('root')).render(<React.StrictMode><App /></React.StrictMode>);
