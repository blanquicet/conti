/**
 * Admin Audit Logs Page
 * 
 * Displays audit logs with filtering and pagination
 * Only accessible to blanquicet@gmail.com
 */

import { API_URL } from '../config.js';
import router from '../router.js';
import * as Navbar from '../components/navbar.js';
import { showError } from '../utils.js';

let currentUser = null;
let currentLogs = [];
let totalLogs = 0;
let usersMap = {}; // Map of user_id -> user object
let currentFilters = {
  limit: 50,
  offset: 0,
  action: '',
  start_time: '',
  end_time: '',
  user_id: '',
  success_only: false
};

/**
 * Load users for mapping IDs to names/emails
 */
async function loadUsers() {
  try {
    // Get current user's household
    const householdsResponse = await fetch(`${API_URL}/households`, {
      credentials: 'include'
    });

    if (householdsResponse.ok) {
      const householdsData = await householdsResponse.json();
      const households = householdsData.households || [];
      
      if (households.length > 0) {
        const householdId = households[0].id;
        
        // Get household details which includes members
        const householdResponse = await fetch(`${API_URL}/households/${householdId}`, {
          credentials: 'include'
        });
        
        if (householdResponse.ok) {
          const householdData = await householdResponse.json();
          const members = householdData.members || [];
          
          // Create a map of user_id -> user object
          members.forEach(member => {
            const name = member.user_name || member.name || member.userName || 'Usuario';
            const email = member.user_email || member.email || member.userEmail || '';
            
            usersMap[member.user_id] = {
              name: name,
              email: email
            };
          });
        }
      }
    }
  } catch (error) {
    console.error('Error loading users:', error);
  }
}

/**
 * Get user display name from user ID
 */
function getUserDisplay(userId) {
  if (!userId) return 'Sistema';
  
  const user = usersMap[userId];
  
  if (user && user.name && user.email) {
    return `${user.name} (${user.email})`;
  }
  
  // For users not in current household, show full ID
  return userId;
}

/**
 * Format date and time
 */
function formatDateTime(dateStr) {
  const date = new Date(dateStr);
  
  // Check if mobile
  const isMobile = window.innerWidth <= 768;
  
  if (isMobile) {
    // Compact format for mobile: "16 ene, 10:52"
    return new Intl.DateTimeFormat('es-CO', {
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit'
    }).format(date).replace(',', '\n'); // Add line break for time
  }
  
  // Full format for desktop
  return new Intl.DateTimeFormat('es-CO', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  }).format(date);
}

/**
 * Format action name for display
 */
function formatAction(action) {
  return action.replace(/_/g, ' ').toLowerCase()
    .split(' ')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

/**
 * Get action badge color class
 */
function getActionColor(action) {
  if (action.startsWith('AUTH_')) return 'badge-auth';
  if (action.startsWith('USER_')) return 'badge-user';
  if (action.startsWith('HOUSEHOLD_')) return 'badge-household';
  if (action.startsWith('MOVEMENT_')) return 'badge-movement';
  if (action.startsWith('BUDGET_')) return 'badge-budget';
  if (action.startsWith('CATEGORY_')) return 'badge-category';
  return 'badge-default';
}

/**
 * Render main page
 */
export function render(user) {
  currentUser = user;
  
  return `
    <main class="card">
      <header class="header">
        <div class="header-row">
          <h1>Audit Logs (Admin)</h1>
          ${Navbar.render(user, '/admin/audit-logs')}
        </div>
      </header>

      <div class="audit-logs-container">
          <!-- Filters -->
          <div class="audit-filters">
            <h2>Filtros</h2>
            <div class="filter-grid">
              <!-- Quick date filters -->
              <div class="filter-group">
                <label>Período Rápido</label>
                <div class="filter-buttons">
                  <button class="btn-filter" data-period="24h">Últimas 24h</button>
                  <button class="btn-filter" data-period="7d">Últimos 7 días</button>
                  <button class="btn-filter" data-period="30d">Últimos 30 días</button>
                  <button class="btn-filter active" data-period="all">Todos</button>
                </div>
              </div>

              <!-- Action filter -->
              <div class="filter-group">
                <label for="action-filter">Acción</label>
                <select id="action-filter">
                  <option value="">Todas</option>
                  <optgroup label="Autenticación">
                    <option value="AUTH_LOGIN">Login</option>
                    <option value="AUTH_LOGOUT">Logout</option>
                    <option value="AUTH_PASSWORD_RESET_REQUEST">Reset Password Request</option>
                    <option value="AUTH_PASSWORD_RESET_COMPLETE">Reset Password Complete</option>
                  </optgroup>
                  <optgroup label="Usuarios">
                    <option value="USER_CREATED">Usuario Creado</option>
                    <option value="USER_UPDATED">Usuario Actualizado</option>
                    <option value="USER_DELETED">Usuario Eliminado</option>
                  </optgroup>
                  <optgroup label="Hogar">
                    <option value="HOUSEHOLD_CREATED">Hogar Creado</option>
                    <option value="HOUSEHOLD_UPDATED">Hogar Actualizado</option>
                    <option value="HOUSEHOLD_MEMBER_ADDED">Miembro Agregado</option>
                    <option value="HOUSEHOLD_MEMBER_REMOVED">Miembro Eliminado</option>
                  </optgroup>
                  <optgroup label="Movimientos">
                    <option value="MOVEMENT_CREATED">Movimiento Creado</option>
                    <option value="MOVEMENT_UPDATED">Movimiento Actualizado</option>
                    <option value="MOVEMENT_DELETED">Movimiento Eliminado</option>
                  </optgroup>
                  <optgroup label="Presupuesto">
                    <option value="BUDGET_CREATED">Presupuesto Creado</option>
                    <option value="BUDGET_UPDATED">Presupuesto Actualizado</option>
                    <option value="BUDGET_DELETED">Presupuesto Eliminado</option>
                  </optgroup>
                </select>
              </div>

              <!-- Success only filter -->
              <div class="filter-group">
                <label>
                  <input type="checkbox" id="success-filter">
                  Solo exitosos
                </label>
              </div>

              <!-- Apply filters button -->
              <div class="filter-group">
                <button id="apply-filters-btn" class="btn-apply">Aplicar Filtros</button>
              </div>
            </div>
          </div>

          <!-- Logs table -->
          <div class="audit-logs-table-container">
            <div class="audit-logs-header">
              <h2>Registros (${totalLogs} total)</h2>
              <div class="pagination-info" id="pagination-info"></div>
            </div>
            
            <div id="logs-table-wrapper">
              <!-- Will be populated by renderLogsTable() -->
            </div>

            <!-- Pagination controls -->
            <div class="pagination-controls" id="pagination-controls">
              <!-- Will be populated by renderPagination() -->
            </div>
          </div>
        </div>
    </main>

    <style>
      .audit-logs-container {
        padding: 1rem;
        max-width: 1400px;
        margin: 0 auto;
      }

      .audit-filters {
        background: white;
        border-radius: 8px;
        padding: 1.5rem;
        margin-bottom: 1.5rem;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      }

      .audit-filters h2 {
        margin-top: 0;
        margin-bottom: 1rem;
        font-size: 1.2rem;
      }

      .filter-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
        gap: 1rem;
        align-items: end;
      }

      .filter-group {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      .filter-group label {
        font-weight: 500;
        font-size: 0.9rem;
      }

      .filter-buttons {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
      }

      .btn-filter {
        padding: 0.5rem 1rem;
        border: 1px solid #d0d7de;
        background: #eef2ff;
        color: #111827;
        border-radius: 6px;
        cursor: pointer;
        font-size: 0.9rem;
        transition: all 0.2s;
      }

      .btn-filter:hover {
        background: #f9fafb;
        border-color: #9ca3af;
      }

      .btn-filter.active {
        background: #111827;
        color: white;
        border-color: #111827;
      }

      .audit-logs-table-container {
        background: white;
        border-radius: 8px;
        padding: 1.5rem;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      }

      #logs-table-wrapper {
        overflow-x: auto;
        -webkit-overflow-scrolling: touch;
      }

      .audit-logs-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 1rem;
      }

      .audit-logs-header h2 {
        margin: 0;
        font-size: 1.2rem;
      }

      .pagination-info {
        font-size: 0.9rem;
        color: #666;
      }

      .audit-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 0.9rem;
        table-layout: auto;
      }

      .audit-table th {
        background: #f8f9fa;
        padding: 0.75rem;
        text-align: left;
        font-weight: 600;
        border-bottom: 2px solid #dee2e6;
        white-space: nowrap;
      }

      .audit-table td {
        padding: 0.75rem;
        border-bottom: 1px solid #dee2e6;
        vertical-align: top;
      }

      /* Make Usuario column wider and allow wrapping */
      .audit-table th:nth-child(3),
      .audit-table td:nth-child(3) {
        min-width: 200px;
        max-width: 300px;
        white-space: normal;
        word-wrap: break-word;
      }

      .audit-table tr:hover {
        background: #f8f9fa;
      }

      .audit-table tr.expandable {
        cursor: pointer;
      }

      .log-badge {
        display: inline-block;
        padding: 0.25rem 0.5rem;
        border-radius: 4px;
        font-size: 0.85rem;
        font-weight: 500;
      }

      .badge-auth { background: #e3f2fd; color: #1976d2; }
      .badge-user { background: #f3e5f5; color: #7b1fa2; }
      .badge-household { background: #fff3e0; color: #f57c00; }
      .badge-movement { background: #e8f5e9; color: #388e3c; }
      .badge-budget { background: #fce4ec; color: #c2185b; }
      .badge-category { background: #e0f2f1; color: #00897b; }
      .badge-default { background: #f5f5f5; color: #616161; }

      .status-badge {
        display: inline-block;
        padding: 0.25rem 0.5rem;
        border-radius: 4px;
        font-size: 0.85rem;
        font-weight: 500;
      }

      .status-success { background: #d4edda; color: #155724; }
      .status-failure { background: #f8d7da; color: #721c24; }

      .log-details {
        margin-top: 0.5rem;
        padding: 1rem;
        background: #f8f9fa;
        border-radius: 4px;
        font-family: monospace;
        font-size: 0.85rem;
        max-height: 300px;
        overflow-y: auto;
      }

      .log-details pre {
        margin: 0;
        white-space: pre-wrap;
        word-wrap: break-word;
      }

      .pagination-controls {
        display: flex;
        justify-content: center;
        align-items: center;
        gap: 1rem;
        margin-top: 1.5rem;
      }

      .btn-apply {
        background: #111827;
        color: white;
        border: none;
        padding: 0.75rem 1.5rem;
        border-radius: 10px;
        cursor: pointer;
        font-size: 0.9rem;
        font-weight: 500;
        transition: all 0.2s;
      }

      .btn-apply:hover {
        opacity: 0.9;
      }

      .pagination-controls button {
        padding: 0.5rem 1rem;
        border: 1px solid #d0d7de;
        background: #eef2ff;
        color: #111827;
        border-radius: 6px;
        cursor: pointer;
        font-size: 0.9rem;
        transition: all 0.2s;
      }

      .pagination-controls button:hover:not(:disabled) {
        background: #f9fafb;
        border-color: #9ca3af;
      }

      .pagination-controls button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }

      .loading-spinner {
        text-align: center;
        padding: 2rem;
        color: #666;
      }

      .error-message {
        padding: 1rem;
        background: #f8d7da;
        color: #721c24;
        border-radius: 4px;
        margin-bottom: 1rem;
      }

      @media (max-width: 768px) {
        .filter-grid {
          grid-template-columns: 1fr;
        }

        .audit-logs-table-container {
          padding: 1rem;
        }

        .audit-table {
          font-size: 0.75rem;
          min-width: 900px;
        }

        .audit-table th,
        .audit-table td {
          padding: 0.5rem 0.25rem;
        }

        .audit-table th:first-child,
        .audit-table td:first-child {
          position: sticky;
          left: 0;
          background: white;
          z-index: 1;
          max-width: 90px;
          white-space: pre-line;
          font-size: 0.7rem;
        }

        .audit-table th:first-child {
          background: #f8f9fa;
        }

        /* Usuario column on mobile */
        .audit-table th:nth-child(3),
        .audit-table td:nth-child(3) {
          min-width: 180px;
          max-width: none !important;
          font-size: 0.7rem;
          white-space: normal !important;
          word-wrap: break-word;
          overflow-wrap: break-word;
          text-overflow: clip !important;
        }

        .log-details {
          font-size: 0.75rem;
        }
      }
    </style>
  `;
}

/**
 * Render logs table
 */
function renderLogsTable() {
  const wrapper = document.getElementById('logs-table-wrapper');
  
  if (!currentLogs || currentLogs.length === 0) {
    wrapper.innerHTML = '<p style="text-align: center; color: #666; padding: 2rem;">No se encontraron registros</p>';
    return;
  }

  const html = `
    <table class="audit-table">
      <thead>
        <tr>
          <th>Fecha/Hora</th>
          <th>Acción</th>
          <th>Usuario</th>
          <th>IP</th>
          <th>Estado</th>
          <th>Detalles</th>
        </tr>
      </thead>
      <tbody>
        ${currentLogs.map((log, index) => `
          <tr class="expandable" data-index="${index}">
            <td>${formatDateTime(log.created_at)}</td>
            <td>
              <span class="log-badge ${getActionColor(log.action)}">
                ${formatAction(log.action)}
              </span>
            </td>
            <td title="${log.user_id || 'Sistema'}">${getUserDisplay(log.user_id)}</td>
            <td>${log.ip_address || '-'}</td>
            <td>
              <span class="status-badge ${log.success ? 'status-success' : 'status-failure'}">
                ${log.success ? '✓ Éxito' : '✗ Fallo'}
              </span>
            </td>
            <td>
              <button class="btn-filter" onclick="window.toggleLogDetails(${index})">
                Ver más
              </button>
            </td>
          </tr>
          <tr id="details-${index}" style="display: none;">
            <td colspan="6">
              <div class="log-details">
                <pre>${JSON.stringify({
                  id: log.id,
                  resource_type: log.resource_type,
                  resource_id: log.resource_id,
                  household_id: log.household_id,
                  user_agent: log.user_agent,
                  old_values: log.old_values,
                  new_values: log.new_values,
                  metadata: log.metadata,
                  error_message: log.error_message
                }, null, 2)}</pre>
              </div>
            </td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `;

  wrapper.innerHTML = html;
}

/**
 * Toggle log details visibility
 */
window.toggleLogDetails = function(index) {
  const detailsRow = document.getElementById(`details-${index}`);
  if (detailsRow) {
    detailsRow.style.display = detailsRow.style.display === 'none' ? 'table-row' : 'none';
  }
};

/**
 * Render pagination controls
 */
function renderPagination() {
  const paginationInfo = document.getElementById('pagination-info');
  const paginationControls = document.getElementById('pagination-controls');
  
  const currentPage = Math.floor(currentFilters.offset / currentFilters.limit) + 1;
  const totalPages = Math.ceil(totalLogs / currentFilters.limit);
  const start = currentFilters.offset + 1;
  const end = Math.min(currentFilters.offset + currentFilters.limit, totalLogs);

  paginationInfo.textContent = `Mostrando ${start}-${end} de ${totalLogs}`;

  paginationControls.innerHTML = `
    <button id="prev-page-btn" ${currentFilters.offset === 0 ? 'disabled' : ''}>
      ← Anterior
    </button>
    <span>Página ${currentPage} de ${totalPages}</span>
    <button id="next-page-btn" ${currentFilters.offset + currentFilters.limit >= totalLogs ? 'disabled' : ''}>
      Siguiente →
    </button>
  `;

  // Attach pagination event listeners
  const prevBtn = document.getElementById('prev-page-btn');
  const nextBtn = document.getElementById('next-page-btn');

  prevBtn?.addEventListener('click', () => {
    if (currentFilters.offset > 0) {
      currentFilters.offset -= currentFilters.limit;
      loadAuditLogs();
    }
  });

  nextBtn?.addEventListener('click', () => {
    if (currentFilters.offset + currentFilters.limit < totalLogs) {
      currentFilters.offset += currentFilters.limit;
      loadAuditLogs();
    }
  });
}

/**
 * Load audit logs from API
 */
async function loadAuditLogs() {
  const wrapper = document.getElementById('logs-table-wrapper');
  wrapper.innerHTML = '<div class="loading-spinner">Cargando registros...</div>';

  try {
    // Build query params
    const params = new URLSearchParams({
      limit: currentFilters.limit.toString(),
      offset: currentFilters.offset.toString()
    });

    if (currentFilters.action) params.append('action', currentFilters.action);
    if (currentFilters.start_time) params.append('start_time', currentFilters.start_time);
    if (currentFilters.end_time) params.append('end_time', currentFilters.end_time);
    if (currentFilters.user_id) params.append('user_id', currentFilters.user_id);
    if (currentFilters.success_only) params.append('success_only', 'true');

    const response = await fetch(`${API_URL}/admin/audit-logs?${params}`, {
      credentials: 'include'
    });

    if (!response.ok) {
      throw new Error('Failed to fetch audit logs');
    }

    const data = await response.json();
    currentLogs = data.logs || [];
    totalLogs = data.total || 0;

    renderLogsTable();
    renderPagination();

  } catch (error) {
    console.error('Error loading audit logs:', error);
    wrapper.innerHTML = '<div class="error-message">Error al cargar los registros. Por favor, intenta de nuevo.</div>';
  }
}

/**
 * Apply filters
 */
function applyFilters() {
  const actionFilter = document.getElementById('action-filter');
  const successFilter = document.getElementById('success-filter');

  currentFilters.action = actionFilter.value;
  currentFilters.success_only = successFilter.checked;
  currentFilters.offset = 0; // Reset to first page

  loadAuditLogs();
}

/**
 * Set quick date filter
 */
function setQuickDateFilter(period) {
  const now = new Date();
  
  switch (period) {
    case '24h':
      currentFilters.start_time = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
      currentFilters.end_time = now.toISOString();
      break;
    case '7d':
      currentFilters.start_time = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
      currentFilters.end_time = now.toISOString();
      break;
    case '30d':
      currentFilters.start_time = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();
      currentFilters.end_time = now.toISOString();
      break;
    case 'all':
    default:
      currentFilters.start_time = '';
      currentFilters.end_time = '';
      break;
  }

  currentFilters.offset = 0; // Reset to first page
  loadAuditLogs();

  // Update active button
  document.querySelectorAll('.btn-filter[data-period]').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.period === period);
  });
}

/**
 * Setup page - called after render
 */
export async function setup() {
  Navbar.setup();

  // Load users for display mapping
  await loadUsers();

  // Setup filter event listeners
  const applyFiltersBtn = document.getElementById('apply-filters-btn');
  applyFiltersBtn?.addEventListener('click', applyFilters);

  // Setup quick date filter buttons
  document.querySelectorAll('.btn-filter[data-period]').forEach(btn => {
    btn.addEventListener('click', () => {
      setQuickDateFilter(btn.dataset.period);
    });
  });

  // Initial load
  await loadAuditLogs();
}
