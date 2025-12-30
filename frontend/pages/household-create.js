/**
 * Household Creation Page
 * 
 * Form to create a new household
 * - Optional step after registration or from profile
 * - Can skip for now
 * - Redirects to household page after creation
 */

import { API_URL } from '../config.js';
import router from '../router.js';
import * as Navbar from '../components/navbar.js';

let currentUser = null;
let isSubmitting = false;

/**
 * Render household creation page
 */
export function render(user, fromRegistration = false) {
  currentUser = user;
  
  return `
    <main class="card">
      <header class="header">
        <div class="header-row">
          <h1>Crear hogar</h1>
          ${Navbar.render(user, '/hogar/crear')}
        </div>
        <p class="subtitle">Crea tu hogar para compartir gastos con tu familia.</p>
      </header>

      <form id="household-form" class="grid">
        <div class="field">
          <label for="household-name">
            <span>Nombre del hogar</span>
            <input 
              type="text" 
              id="household-name" 
              name="name"
              placeholder="Ej: Casa de Jose y Caro"
              required
              maxlength="100"
              autofocus
            />
          </label>
          <span class="field-hint">El nombre que identificará a tu hogar</span>
        </div>

        <div id="error-message" class="error" style="display: none;"></div>

        <div class="form-actions">
          <button type="submit" id="create-btn" class="btn-primary">
            Crear hogar
          </button>
          ${fromRegistration ? `
            <button type="button" id="skip-btn" class="btn-secondary">
              Omitir por ahora
            </button>
          ` : `
            <button type="button" id="cancel-btn" class="btn-secondary">
              Cancelar
            </button>
          `}
        </div>
      </form>
    </main>
  `;
}

/**
 * Setup household creation page
 */
export function setup(fromRegistration = false) {
  Navbar.setup();
  
  const form = document.getElementById('household-form');
  const nameInput = document.getElementById('household-name');
  const createBtn = document.getElementById('create-btn');
  const skipBtn = document.getElementById('skip-btn');
  const cancelBtn = document.getElementById('cancel-btn');
  const errorMsg = document.getElementById('error-message');

  // Handle form submission
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    await handleCreateHousehold(nameInput.value.trim(), createBtn, errorMsg);
  });

  // Handle skip button
  if (skipBtn) {
    skipBtn.addEventListener('click', () => {
      router.navigate('/registrar-movimiento');
    });
  }

  // Handle cancel button
  if (cancelBtn) {
    cancelBtn.addEventListener('click', () => {
      router.navigate('/perfil');
    });
  }

  // Clear error on input
  nameInput.addEventListener('input', () => {
    errorMsg.style.display = 'none';
  });
}

/**
 * Handle household creation
 */
async function handleCreateHousehold(name, button, errorMsg) {
  if (isSubmitting) return;

  // Validate
  if (!name) {
    showError(errorMsg, 'Por favor ingresa un nombre para el hogar');
    return;
  }

  if (name.length > 100) {
    showError(errorMsg, 'El nombre es demasiado largo (máximo 100 caracteres)');
    return;
  }

  isSubmitting = true;
  button.disabled = true;
  button.classList.add('loading');
  errorMsg.style.display = 'none';

  try {
    const response = await fetch(`${API_URL}/households`, {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ name }),
    });

    const data = await response.json();

    if (response.ok) {
      // Success - navigate to household page
      router.navigate('/hogar');
    } else {
      showError(errorMsg, data.error || 'Error al crear el hogar');
    }
  } catch (error) {
    console.error('Error creating household:', error);
    showError(errorMsg, 'Error de conexión. Por favor, intenta de nuevo.');
  } finally {
    isSubmitting = false;
    button.disabled = false;
    button.classList.remove('loading');
  }
}

/**
 * Show error message
 */
function showError(errorEl, message) {
  errorEl.textContent = message;
  errorEl.style.display = 'block';
}
