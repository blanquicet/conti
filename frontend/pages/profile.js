/**
 * Profile Page
 * 
 * Read-only display of:
 * - User information (name, email)
 * - Household status (none or household name)
 * - Link to household details if household exists
 */

import { API_URL } from '../config.js';
import router from '../router.js';
import * as Navbar from '../components/navbar.js';

let currentUser = null;
let currentHousehold = null;

/**
 * Render profile page
 */
export function render(user) {
  currentUser = user;
  
  return `
    <main class="card">
      <header class="header">
        <div class="header-row">
          <h1>Mi perfil</h1>
          ${Navbar.render(user, '/perfil')}
        </div>
        <p class="subtitle">Información de tu cuenta y hogar.</p>
      </header>

      <div id="profile-content">
        <div class="loading-section">
          <div class="spinner-small"></div>
          <p>Cargando información...</p>
        </div>
      </div>
    </main>
  `;
}

/**
 * Setup profile page
 */
export async function setup() {
  Navbar.setup();
  await loadProfile();
}

/**
 * Load profile data from API
 */
async function loadProfile() {
  const contentEl = document.getElementById('profile-content');
  
  try {
    // Fetch user's households
    const response = await fetch(`${API_URL}/households`, {
      credentials: 'include'
    });

    if (!response.ok) {
      throw new Error('Error al cargar información del hogar');
    }

    const data = await response.json();
    const households = data.households || [];
    currentHousehold = households.length > 0 ? households[0] : null;

    // Render profile content
    contentEl.innerHTML = renderProfileContent();
    setupEventListeners();

  } catch (error) {
    console.error('Error loading profile:', error);
    contentEl.innerHTML = `
      <div class="error-box">
        <p>Error al cargar tu perfil. Por favor, intenta de nuevo.</p>
        <button id="retry-btn" class="btn-secondary">Reintentar</button>
      </div>
    `;
    
    document.getElementById('retry-btn')?.addEventListener('click', loadProfile);
  }
}

/**
 * Render profile content
 */
function renderProfileContent() {
  return `
    <div class="profile-section">
      <h2 class="section-title">Información personal</h2>
      <div class="info-grid">
        <div class="info-item">
          <span class="info-label">Nombre</span>
          <span class="info-value">${currentUser.name}</span>
        </div>
        <div class="info-item">
          <span class="info-label">Email</span>
          <span class="info-value">${currentUser.email}</span>
        </div>
      </div>
    </div>

    <div class="profile-section">
      <h2 class="section-title">Mi hogar</h2>
      ${renderHouseholdSection()}
    </div>
  `;
}

/**
 * Render household section
 */
function renderHouseholdSection() {
  if (!currentHousehold) {
    return `
      <div class="no-household">
        <div class="no-household-icon">🏠</div>
        <p class="no-household-text">Aún no tienes un hogar configurado</p>
        <p class="no-household-hint">Crea un hogar para compartir gastos con tu familia</p>
        <button id="create-household-btn" class="btn-primary">Crear hogar</button>
      </div>
    `;
  }

  return `
    <div class="household-card">
      <div class="household-header">
        <div class="household-icon">🏠</div>
        <div class="household-info">
          <h3 class="household-name">${currentHousehold.name}</h3>
          <p class="household-meta">Creado el ${formatDate(currentHousehold.created_at)}</p>
        </div>
      </div>
      <div class="household-actions">
        <button id="view-household-btn" class="btn-secondary">Ver detalles</button>
      </div>
    </div>
  `;
}

/**
 * Setup event listeners
 */
function setupEventListeners() {
  const createBtn = document.getElementById('create-household-btn');
  const viewBtn = document.getElementById('view-household-btn');

  if (createBtn) {
    createBtn.addEventListener('click', () => {
      router.navigate('/hogar/crear');
    });
  }

  if (viewBtn) {
    viewBtn.addEventListener('click', () => {
      router.navigate('/hogar');
    });
  }
}

/**
 * Format date to readable format
 */
function formatDate(dateString) {
  const date = new Date(dateString);
  return date.toLocaleDateString('es-CO', { 
    year: 'numeric', 
    month: 'long', 
    day: 'numeric' 
  });
}
