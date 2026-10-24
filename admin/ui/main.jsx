import React from 'react';
import { createRoot } from 'react-dom/client';
import { icons } from 'lucide';
import '@derekurban/design-system/styles.css';
import './app.css';
import { App } from './App.jsx';

// The design system's <Icon> reads Lucide from window.
window.lucide = { icons };

createRoot(document.getElementById('root')).render(<App />);
