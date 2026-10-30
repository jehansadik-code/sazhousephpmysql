(() => {
  'use strict';

  const stateNames = { sazProducts: 'products', sazProductTypes: 'product_types', sazCoupons: 'coupons', sazSettings: 'settings', sazSiteContent: 'site_content', sazPageProducts: 'page_products', sazHomeCategories: 'home_categories' };
  const statePermissions = { sazProducts: 'products.manage', sazProductTypes: 'products.manage', sazCoupons: 'coupons.manage', sazSettings: 'settings.manage', sazSiteContent: 'content.manage', sazPageProducts: 'content.manage', sazHomeCategories: 'content.manage' };
  let currentUser = null;
  let csrfToken = '';
  let stateVersions = {};

  const writeLocal = (key, value) => localStorage.setItem(key, JSON.stringify(value));
  const allowed = permission => Boolean(currentUser && (currentUser.role.permissions.includes('*') || currentUser.role.permissions.includes(permission)));

  async function call(route, { method = 'GET', body, csrf = false, form = false } = {}) {
    const headers = {};
    if (csrf) headers['X-CSRF-Token'] = csrfToken;
    if (!form && body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`api/index.php?route=${encodeURIComponent(route)}`, { method, credentials: 'same-origin', headers, body: body === undefined ? undefined : form ? body : JSON.stringify(body) });
    let data = {};
    try { data = await response.json(); } catch { /* The server returned a non-JSON failure. */ }
    if (!response.ok) throw new Error(typeof data.error === 'string' ? data.error : 'Request failed.');
    return data;
  }

  async function bootstrap() {
    const data = await call('storefront');
    csrfToken = data.csrf || csrfToken;
    currentUser = data.user || null;
    stateVersions = data.versions || {};
    for (const [localKey, remoteKey] of Object.entries(stateNames)) {
      if (Object.hasOwn(data.state || {}, remoteKey)) writeLocal(localKey, data.state[remoteKey]);
    }
    if (!currentUser) {
      localStorage.removeItem('sazOrders');
      localStorage.removeItem('sazMessages');
    }
    return data;
  }

  async function hydrate() {
    await bootstrap();
    if (allowed('orders.view')) {
      const { orders } = await call('admin/orders');
      writeLocal('sazOrders', orders.map(order => {
        const lines = JSON.parse(order.line_items || '[]');
        return { ref: order.reference, date: new Date(order.created_at).toLocaleDateString(), createdAt: order.created_at, lines, items: lines.length, subtotal: Number(order.subtotal || 0), shipping: Number(order.shipping || 0), discount: Number(order.discount || 0), total: Number(order.total || 0), coupon: order.coupon || '', status: order.status, customer: order.customer_name || '', phone: order.phone || '', email: order.email || '', address: order.address || '', city: order.city || '', district: order.district || '', division: order.division || '', payment: order.payment_method || '' };
      }));
    }
    if (allowed('messages.view')) {
      const { messages } = await call('admin/messages');
      writeLocal('sazMessages', messages.map(message => ({ id: message.id, name: message.name, email: message.email, subject: message.subject || '', message: message.message, date: message.created_at })));
    }
  }

  window.SAZ_API = {
    hydrate,
    refreshRole: async () => { await bootstrap(); return allowed('admin.access'); },
    isAdmin: () => allowed('admin.access'),
    hasPermission: allowed,
    getRole: () => currentUser?.role || null,
    getUser: () => currentUser ? { id: currentUser.id, email: currentUser.email } : null,
    getCsrfToken: () => csrfToken,
    client: {
      rpc: async (name, args) => {
        try {
          if (name !== 'update_staff_order_status') return { error: { message: 'Unsupported API operation.' } };
          await call('admin/orders/status', { method: 'POST', csrf: true, body: { reference: args.p_reference, status: args.p_status } });
          return { error: null };
        } catch (error) { return { error: { message: error.message } }; }
      },
    },
    signIn: async (email, password) => {
      try {
        const data = await call('auth/login', { method: 'POST', csrf: true, body: { email, password } });
        csrfToken = data.csrf || '';
        currentUser = data.user || null;
        return { error: null };
      } catch (error) { return { error: { message: error.message } }; }
    },
    signOut: async () => {
      try { if (csrfToken) await call('auth/logout', { method: 'POST', csrf: true, body: {} }); } catch (_) { /* Clear local state regardless. */ }
      currentUser = null;
      csrfToken = '';
      return { error: null };
    },
    updateOwnPassword: async password => {
      try { await call('auth/password', { method: 'POST', csrf: true, body: { password } }); return { error: null }; }
      catch (error) { return { error: { message: error.message } }; }
    },
    requestPasswordReset: async email => {
      try { return { data: await call('auth/password-reset/request', { method: 'POST', csrf: true, body: { email } }), error: null }; }
      catch (error) { return { data: null, error: error.message }; }
    },
    confirmPasswordReset: async (selector, token, password) => {
      try { return { data: await call('auth/password-reset/confirm', { method: 'POST', csrf: true, body: { selector, token, password } }), error: null }; }
      catch (error) { return { data: null, error: error.message }; }
    },
    accessControl: async (action, payload = {}) => {
      try { const data = await call('admin/access', { method: 'POST', csrf: true, body: { action, ...payload } }); return { data: data.data, error: null }; }
      catch (error) { return { data: null, error: error.message }; }
    },
    uploadImages: async (files, scope = 'products') => {
      const permission = scope === 'content' ? 'content.manage' : 'products.manage';
      if (!allowed(permission)) throw new Error('You do not have permission to upload these images.');
      const uploads = await Promise.all([...files].map(async file => {
        const body = new FormData();
        body.append('file', file, file.name);
        body.append('scope', scope);
        const data = await call('admin/upload', { method: 'POST', csrf: true, body, form: true });
        return data.url;
      }));
      return uploads;
    },
    sync: async (key, value) => {
      if (key === 'sazOrders' || key === 'sazMessages') return { ok: true, skipped: true };
      if (!stateNames[key] || (!allowed('store.manage') && !allowed(statePermissions[key]))) return { ok: true, skipped: true };
      try {
        const remoteKey = stateNames[key];
        const data = await call('admin/state', { method: 'POST', csrf: true, body: { key, value, version: Number(stateVersions[remoteKey] ?? 0) } });
        stateVersions[remoteKey] = Number(data.version);
        return { ok: true };
      }
      catch (error) { return { ok: false, error: error.message }; }
    },
  };
})();
