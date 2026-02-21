/**
 * Chat Page — Financial Assistant
 * 
 * Modern chat UI that sends messages to POST /chat
 * and displays the assistant's responses.
 */

const API_URL = window.API_URL || '';

export function render() {
  return `
    <div class="chat-page">
      <header class="chat-header">
        <button class="back-btn" id="chat-back-btn">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="m12 19-7-7 7-7"/></svg>
        </button>
        <div class="chat-header-info">
          <div class="chat-avatar">✨</div>
          <div>
            <h1>Asistente Financiero</h1>
            <span class="chat-status" id="chat-status">En línea</span>
          </div>
        </div>
      </header>

      <div class="chat-messages" id="chat-messages">
        <div class="chat-welcome" id="chat-welcome">
          <div class="chat-welcome-icon">✨</div>
          <h2>¡Hola! Soy tu asistente financiero</h2>
          <p>Pregúntame sobre tus gastos, ingresos o presupuesto</p>
          <div class="chat-suggestions" id="chat-suggestions">
            <button class="chat-chip" data-msg="¿Cuánto gasté en mercado este mes?">🛒 Gastos en mercado</button>
            <button class="chat-chip" data-msg="¿Cuál es mi top 5 de gastos este mes?">📊 Top 5 gastos</button>
            <button class="chat-chip" data-msg="¿Cómo va mi presupuesto este mes?">💰 Mi presupuesto</button>
            <button class="chat-chip" data-msg="Compara enero y febrero 2026">📈 Comparar meses</button>
          </div>
        </div>
      </div>

      <form class="chat-input-area" id="chat-form">
        <input 
          type="text" 
          id="chat-input" 
          placeholder="Pregunta algo..." 
          autocomplete="off"
          autofocus
        />
        <button type="submit" id="chat-send-btn" aria-label="Enviar">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m22 2-7 20-4-9-9-4z"/><path d="m22 2-11 11"/></svg>
        </button>
      </form>
    </div>
  `;
}

export function setup() {
  const form = document.getElementById('chat-form');
  const input = document.getElementById('chat-input');
  const messagesEl = document.getElementById('chat-messages');
  const backBtn = document.getElementById('chat-back-btn');
  const welcome = document.getElementById('chat-welcome');
  const statusEl = document.getElementById('chat-status');

  backBtn.addEventListener('click', () => {
    window.history.back();
  });

  // Suggestion chips
  document.querySelectorAll('.chat-chip').forEach(btn => {
    btn.addEventListener('click', () => {
      input.value = btn.dataset.msg;
      form.dispatchEvent(new Event('submit', { cancelable: true }));
    });
  });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const message = input.value.trim();
    if (!message) return;

    // Hide welcome on first message
    if (welcome) welcome.style.display = 'none';

    // Add user message
    appendMessage('user', message);
    input.value = '';
    input.disabled = true;
    document.getElementById('chat-send-btn').disabled = true;

    // Show typing indicator
    statusEl.textContent = 'Escribiendo...';
    statusEl.classList.add('typing');
    const loadingId = showTypingIndicator();

    try {
      const response = await fetch(`${API_URL}/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ message }),
      });

      removeMessage(loadingId);

      if (!response.ok) {
        const err = await response.json().catch(() => ({}));
        appendMessage('assistant', `No pude procesar tu pregunta. ${err.error || 'Intenta de nuevo.'}`);
        return;
      }

      const data = await response.json();
      appendMessage('assistant', data.message);
    } catch (err) {
      removeMessage(loadingId);
      appendMessage('assistant', 'No se pudo conectar con el servidor. Verifica tu conexión.');
    } finally {
      input.disabled = false;
      document.getElementById('chat-send-btn').disabled = false;
      input.focus();
      statusEl.textContent = 'En línea';
      statusEl.classList.remove('typing');
    }
  });

  function appendMessage(role, content) {
    const id = 'msg-' + Date.now() + '-' + Math.random().toString(36).slice(2, 6);
    const div = document.createElement('div');
    div.className = `chat-message ${role}`;
    div.id = id;

    const formatted = role === 'assistant' ? formatAssistantMessage(content) : escapeHtml(content);
    div.innerHTML = `<div class="chat-bubble">${formatted}</div>`;

    messagesEl.appendChild(div);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return id;
  }

  function showTypingIndicator() {
    const id = 'typing-' + Date.now();
    const div = document.createElement('div');
    div.className = 'chat-message assistant';
    div.id = id;
    div.innerHTML = `<div class="chat-bubble typing-bubble"><span class="dot"></span><span class="dot"></span><span class="dot"></span></div>`;
    messagesEl.appendChild(div);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return id;
  }

  function removeMessage(id) {
    const el = document.getElementById(id);
    if (el) el.remove();
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function formatAssistantMessage(text) {
    // Escape HTML first
    let html = escapeHtml(text);
    // Bold: **text**
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    // Line breaks
    html = html.replace(/\n/g, '<br>');
    return html;
  }
}
