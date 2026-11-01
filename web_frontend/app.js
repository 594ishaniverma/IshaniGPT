/* ============================================================
   IshaniGPT – Web Frontend App
   ============================================================ */

// When served from FastAPI (http/https), use relative URLs so it works on any host.
// When opened directly as a local file (file://), fall back to localhost dev server.
const API_BASE_URL = window.location.protocol === 'file:'
  ? 'http://127.0.0.1:8000'
  : '';
const TOKEN_KEY    = 'ishanigpt_access_token';

/* ── App State ───────────────────────────────────────────── */
const state = {
  token:           null,
  user:            null,
  conversations:   [],
  activeThreadId:  null,
  messages:        [],
  streaming:       false,
};

/* ============================================================
   API HELPERS
   ============================================================ */

async function api(method, path, body = null, isFormData = false) {
  const headers = {};
  if (state.token) headers['Authorization'] = `Bearer ${state.token}`;
  if (body && !isFormData) headers['Content-Type'] = 'application/json';

  const options = { method, headers };
  if (body) options.body = isFormData ? body : JSON.stringify(body);

  let res;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, options);
  } catch {
    throw new Error('Could not reach IshaniGPT. Check your connection.');
  }

  if (res.status === 401) {
    clearToken();
    showAuthScreen();
    throw new Error('Session expired. Please sign in again.');
  }

  if (!res.ok) {
    let msg = 'Something went wrong. Please try again.';
    try {
      const err = await res.json();
      if (typeof err.detail === 'string') msg = err.detail;
      else if (Array.isArray(err.detail)) msg = err.detail.map(e => e.msg || e).join('\n');
    } catch { /* ignore */ }
    throw new Error(msg);
  }

  if (res.status === 204 || res.headers.get('content-length') === '0') return {};
  const text = await res.text();
  return text ? JSON.parse(text) : {};
}

/* SSE streaming via fetch + ReadableStream */
async function streamMessage(threadId, content, onDelta, onDone, onError) {
  const headers = {
    'Content-Type':  'application/json',
    'Authorization': `Bearer ${state.token}`,
  };

  let res;
  try {
    res = await fetch(`${API_BASE_URL}/conversations/${threadId}/messages/stream`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ content }),
    });
  } catch {
    onError('Could not reach IshaniGPT. Check your connection.');
    return;
  }

  if (!res.ok) {
    onError('IshaniGPT could not generate a response. Please try again.');
    return;
  }

  const reader  = res.body.getReader();
  const decoder = new TextDecoder();
  let   buffer  = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });

    let idx;
    while ((idx = buffer.indexOf('\n\n')) !== -1) {
      const event = buffer.slice(0, idx).trim();
      buffer = buffer.slice(idx + 2);

      if (!event.startsWith('data: ')) continue;
      const data = event.slice(6).trim();
      if (!data || data === '[DONE]') { onDone(); return; }

      try {
        const payload = JSON.parse(data);
        if (payload.error) { onError(payload.error); return; }
        if (payload.delta) onDelta(payload.delta);
      } catch { /* ignore malformed event */ }
    }
  }
  onDone();
}

/* ── Token helpers ───────────────────────────────────────── */
function saveToken(token) {
  state.token = token;
  localStorage.setItem(TOKEN_KEY, token);
}

function clearToken() {
  state.token = null;
  localStorage.removeItem(TOKEN_KEY);
}

/* ============================================================
   MARKDOWN RENDERER  (simple subset)
   ============================================================ */
function renderMarkdown(text) {
  if (!text) return '';

  // Escape HTML first
  let html = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  // Code blocks (``` ... ```)
  html = html.replace(/```[\w]*\n?([\s\S]*?)```/g, (_, code) => {
    return `<div class="code-block-wrapper"><pre><code>${code.trimEnd()}</code></pre><button class="copy-btn" onclick="copyCode(this)">Copy</button></div>`;
  });

  // Inline code
  html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

  // Bold
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

  // Italic
  html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');

  // Paragraphs (double newline)
  html = html.split(/\n{2,}/).map(para => {
    if (para.includes('<div class="code-block-wrapper">') || para.includes('<pre>')) return para;
    return `<p>${para.replace(/\n/g, '<br>')}</p>`;
  }).join('');

  return html;
}

function copyCode(btn) {
  const code = btn.previousElementSibling.querySelector('code').innerText;
  navigator.clipboard.writeText(code).then(() => {
    const orig = btn.textContent;
    btn.textContent = 'Copied!';
    setTimeout(() => { btn.textContent = orig; }, 1800);
    showToast('Code copied!', 'success');
  });
}

/* ============================================================
   TOAST NOTIFICATIONS
   ============================================================ */
function showToast(message, type = '') {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transition = 'opacity .3s';
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

/* ============================================================
   DOM HELPERS
   ============================================================ */
const $ = id => document.getElementById(id);

function show(id)   { $(id).classList.remove('hidden'); }
function hide(id)   { $(id).classList.add('hidden'); }
function setText(id, text) { $(id).textContent = text; }

/* ============================================================
   AUTH SCREEN
   ============================================================ */
function showAuthScreen() {
  hide('chat-screen');
  show('auth-screen');
  clearAuthError();
  switchTab('signin');
}

function showChatScreen() {
  hide('auth-screen');
  show('chat-screen');
}

function switchTab(tab) {
  const isSignIn = tab === 'signin';
  $('tab-signin').classList.toggle('active',  isSignIn);
  $('tab-signup').classList.toggle('active', !isSignIn);
  $('signin-form').classList.toggle('hidden',  !isSignIn);
  $('signup-form').classList.toggle('hidden',   isSignIn);
  clearAuthError();
}

function setAuthError(msg) {
  const el = $('auth-error');
  el.textContent = msg;
  el.classList.remove('hidden');
}

function clearAuthError() {
  const el = $('auth-error');
  el.textContent = '';
  el.classList.add('hidden');
}

function setAuthLoading(formId, loading) {
  const btnText = $(formId === 'signin-form' ? 'signin-btn-text' : 'signup-btn-text');
  const btn     = btnText.closest('button');
  if (loading) {
    btnText.innerHTML = '<span class="spinner"></span>';
    btn.disabled = true;
  } else {
    btnText.textContent = formId === 'signin-form' ? 'Sign In' : 'Create Account';
    btn.disabled = false;
  }
}

async function handleSignIn(e) {
  e.preventDefault();
  clearAuthError();
  const email    = $('signin-email').value.trim();
  const password = $('signin-password').value;
  setAuthLoading('signin-form', true);
  try {
    const data = await api('POST', '/auth/login', { email, password }, false);
    saveToken(data.access_token);
    state.user = data.user;
    await enterChatScreen();
  } catch (err) {
    setAuthError(err.message);
  } finally {
    setAuthLoading('signin-form', false);
  }
}

async function handleSignUp(e) {
  e.preventDefault();
  clearAuthError();
  const name     = $('signup-name').value.trim();
  const email    = $('signup-email').value.trim();
  const password = $('signup-password').value;
  setAuthLoading('signup-form', true);
  try {
    const data = await api('POST', '/auth/signup', { name, email, password }, false);
    saveToken(data.access_token);
    state.user = data.user;
    await enterChatScreen();
  } catch (err) {
    setAuthError(err.message);
  } finally {
    setAuthLoading('signup-form', false);
  }
}

async function handleSignOut() {
  try { await api('POST', '/auth/logout'); } catch { /* ignore */ }
  clearToken();
  state.user = null;
  state.conversations = [];
  state.activeThreadId = null;
  state.messages = [];
  showAuthScreen();
}

/* ============================================================
   ENTERING CHAT
   ============================================================ */
async function enterChatScreen() {
  // Update user info in sidebar
  const u = state.user;
  setText('user-name', u.name);
  setText('user-email', u.email);
  $('user-avatar').textContent = getInitials(u.name);

  showChatScreen();
  await loadConversations();

  if (state.conversations.length > 0) {
    await selectConversation(state.conversations[0].thread_id);
  } else {
    showEmptyState();
  }
}

function getInitials(name) {
  return name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0].toUpperCase()).join('') || '?';
}

/* ============================================================
   CONVERSATIONS
   ============================================================ */
async function loadConversations() {
  try {
    const convs = await api('GET', '/conversations');
    state.conversations = convs;
    renderConversationList();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function renderConversationList() {
  const list  = $('conv-list');
  const empty = $('conv-empty');

  // Remove existing items (keep the empty placeholder)
  list.querySelectorAll('.conv-item').forEach(el => el.remove());

  if (!state.conversations.length) {
    empty.classList.remove('hidden');
    return;
  }

  empty.classList.add('hidden');

  state.conversations.forEach(conv => {
    const item = document.createElement('div');
    item.className = 'conv-item' + (conv.thread_id === state.activeThreadId ? ' active' : '');
    item.dataset.threadId = conv.thread_id;
    item.innerHTML = `
      <span class="conv-title" title="${escHtml(conv.title)}">${escHtml(conv.title)}</span>
      <button class="conv-delete" title="Delete" onclick="deleteConversation(event, '${conv.thread_id}')">✕</button>
    `;
    item.addEventListener('click', () => selectConversation(conv.thread_id));
    list.appendChild(item);
  });
}

async function selectConversation(threadId) {
  state.activeThreadId = threadId;
  const conv = state.conversations.find(c => c.thread_id === threadId);
  setText('chat-title', conv ? conv.title : 'Chat');

  // Update active class
  document.querySelectorAll('.conv-item').forEach(el => {
    el.classList.toggle('active', el.dataset.threadId === threadId);
  });

  closeSidebar();
  await loadMessages(threadId);
}

async function newConversation() {
  try {
    const conv = await api('POST', '/conversations');
    state.conversations.unshift(conv);
    renderConversationList();
    await selectConversation(conv.thread_id);
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function deleteConversation(e, threadId) {
  e.stopPropagation();
  if (!confirm('Delete this conversation?')) return;
  try {
    await api('DELETE', `/conversations/${threadId}`);
    state.conversations = state.conversations.filter(c => c.thread_id !== threadId);
    renderConversationList();
    if (state.activeThreadId === threadId) {
      state.activeThreadId = null;
      state.messages = [];
      if (state.conversations.length > 0) {
        await selectConversation(state.conversations[0].thread_id);
      } else {
        setText('chat-title', 'Select a conversation');
        showEmptyState();
      }
    }
  } catch (err) {
    showToast(err.message, 'error');
  }
}

/* ============================================================
   MESSAGES
   ============================================================ */
async function loadMessages(threadId) {
  clearMessages();
  try {
    const msgs = await api('GET', `/conversations/${threadId}/messages`);
    state.messages = msgs;
    if (msgs.length === 0) {
      showEmptyState();
    } else {
      msgs.forEach(msg => appendMessage(msg.role, msg.content));
      scrollToBottom();
    }
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function clearMessages() {
  const inner = $('messages-inner');
  inner.querySelectorAll('.msg, .typing-indicator').forEach(el => el.remove());
  showEmptyState();
}

function showEmptyState() {
  show('empty-state');
}

function hideEmptyState() {
  hide('empty-state');
}

function appendMessage(role, content) {
  hideEmptyState();
  const inner = $('messages-inner');

  const wrapper = document.createElement('div');
  wrapper.className = `msg ${role}`;

  const isUser = role === 'user';
  const avatarHtml = isUser
    ? `<div class="msg-avatar">${getInitials(state.user?.name || '?')}</div>`
    : `<div class="msg-ai-icon">✦</div>`;

  const senderHtml = isUser ? '' : `<div class="msg-sender">IshaniGPT</div>`;
  const bubbleContent = isUser ? escHtml(content).replace(/\n/g, '<br>') : renderMarkdown(content);

  wrapper.innerHTML = `
    ${avatarHtml}
    <div class="msg-body">
      ${senderHtml}
      <div class="msg-bubble">${bubbleContent}</div>
    </div>
  `;

  inner.appendChild(wrapper);
  return wrapper;
}

function showTypingIndicator() {
  hideEmptyState();
  const inner = $('messages-inner');
  const el = document.createElement('div');
  el.className = 'typing-indicator';
  el.id = 'typing-indicator';
  el.innerHTML = `
    <div class="msg-ai-icon">✦</div>
    <div class="typing-dots">
      <span></span><span></span><span></span>
    </div>
    <span class="typing-label">Thinking…</span>
  `;
  inner.appendChild(el);
  scrollToBottom();
  return el;
}

function removeTypingIndicator() {
  const el = $('typing-indicator');
  if (el) el.remove();
}

function scrollToBottom() {
  const area = $('messages-area');
  area.scrollTop = area.scrollHeight;
}

/* ============================================================
   SENDING A MESSAGE
   ============================================================ */
async function sendMessage() {
  if (!state.activeThreadId) {
    // Auto-create a conversation
    try {
      const conv = await api('POST', '/conversations');
      state.conversations.unshift(conv);
      renderConversationList();
      state.activeThreadId = conv.thread_id;
      setText('chat-title', conv.title);
    } catch (err) {
      showToast(err.message, 'error');
      return;
    }
  }

  const input   = $('msg-input');
  const content = input.value.trim();
  if (!content || state.streaming) return;

  input.value = '';
  autoResize(input);
  setSendDisabled(true);

  appendMessage('user', content);
  scrollToBottom();

  const typingEl = showTypingIndicator();
  state.streaming = true;

  // Streaming assistant message
  let assistantWrapper = null;
  let assistantBubble  = null;
  let accumulated      = '';

  await streamMessage(
    state.activeThreadId,
    content,

    // onDelta
    (delta) => {
      removeTypingIndicator();
      if (!assistantWrapper) {
        assistantWrapper = appendMessage('assistant', '');
        assistantBubble  = assistantWrapper.querySelector('.msg-bubble');
      }
      accumulated += delta;
      assistantBubble.innerHTML = renderMarkdown(accumulated);
      scrollToBottom();
    },

    // onDone
    () => {
      state.streaming = false;
      setSendDisabled(false);
      removeTypingIndicator();
      scrollToBottom();
    },

    // onError
    (errMsg) => {
      state.streaming = false;
      setSendDisabled(false);
      removeTypingIndicator();
      showToast(errMsg, 'error');
    }
  );
}

function setSendDisabled(disabled) {
  $('btn-send').disabled = disabled;
}

/* ============================================================
   FILE UPLOAD
   ============================================================ */
async function handleFileUpload(e) {
  const file = e.target.files[0];
  if (!file) return;

  if (!state.activeThreadId) {
    showToast('Please select or start a conversation first.', 'error');
    e.target.value = '';
    return;
  }

  const formData = new FormData();
  formData.append('file', file);

  showToast(`Uploading ${file.name}…`);
  try {
    await api('POST', `/conversations/${state.activeThreadId}/upload`, formData, true);
    showToast(`${file.name} uploaded successfully!`, 'success');
  } catch (err) {
    showToast(err.message, 'error');
  } finally {
    e.target.value = '';
  }
}

/* ============================================================
   INPUT HELPERS
   ============================================================ */
function autoResize(el) {
  el.style.height = 'auto';
  el.style.height = Math.min(el.scrollHeight, 112) + 'px';
  // Enable/disable send button
  $('btn-send').disabled = !el.value.trim() || state.streaming;
}

function handleInputKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    if (!$('btn-send').disabled) sendMessage();
  }
}

/* ============================================================
   SIDEBAR (mobile toggle)
   ============================================================ */
function openSidebar() {
  $('sidebar').classList.add('open');
  $('sidebar-overlay').classList.add('open');
}

function closeSidebar() {
  $('sidebar').classList.remove('open');
  $('sidebar-overlay').classList.remove('open');
}

/* ============================================================
   UTILITY
   ============================================================ */
function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/* ============================================================
   INIT — Restore session on page load
   ============================================================ */
async function init() {
  const savedToken = localStorage.getItem(TOKEN_KEY);

  if (savedToken) {
    state.token = savedToken;
    try {
      const user = await api('GET', '/auth/me');
      state.user = user;
      await enterChatScreen();
      return;
    } catch {
      clearToken();
    }
  }

  showAuthScreen();
}

// Kick off
init();
