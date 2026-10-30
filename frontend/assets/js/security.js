/* Launch hardening layer. Loaded before app.js so it owns sensitive submits. */
(() => {
  'use strict';

  const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
  const SAFE_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
  const safeText = value => String(value ?? '').replace(/[<>]/g, '').trim();
  const safeUrl = (value, { image = false } = {}) => {
    const raw = String(value ?? '').trim();
    if (!raw) return '';
    if (image && raw.startsWith('data:image/')) return raw;
    try {
      const url = new URL(raw, window.location.origin);
      if (!['https:', 'http:'].includes(url.protocol)) return '';
      return raw;
    } catch {
      return raw.startsWith('assets/images/catalog/') || raw.startsWith('logo.') || raw.startsWith('videos/') ? raw : '';
    }
  };
  const notify = message => window.toast ? window.toast(message) : window.alert(message);
  const checkoutKeyStorage = 'sazCheckoutIdempotencyKey';
  let checkoutIdempotencyKey = sessionStorage.getItem(checkoutKeyStorage) || '';
  const nextCheckoutKey = () => {
    if (!checkoutIdempotencyKey) {
      const random = new Uint8Array(16);
      crypto.getRandomValues(random);
      checkoutIdempotencyKey = (crypto.randomUUID ? crypto.randomUUID() : [...random].map(byte => byte.toString(16).padStart(2, '0')).join('')).replace(/-/g, '');
      sessionStorage.setItem(checkoutKeyStorage, checkoutIdempotencyKey);
    }
    return checkoutIdempotencyKey;
  };
  const installHoneypot = root => {
    for (const form of root.querySelectorAll?.('#checkout-form, #contact-form') || []) {
      if (form.elements.website) continue;
      const field = document.createElement('input');
      field.name = 'website'; field.type = 'text'; field.tabIndex = -1;
      field.autocomplete = 'off'; field.setAttribute('aria-hidden', 'true');
      field.style.cssText = 'position:absolute;left:-10000px;width:1px;height:1px;overflow:hidden';
      form.append(field);
    }
  };

  new MutationObserver(records => records.forEach(record => record.addedNodes.forEach(node => {
    if (node.nodeType === Node.ELEMENT_NODE) {
      installHoneypot(node);
      node.querySelectorAll?.('.facebook-qr img').forEach(image => {
        image.src = 'assets/images/social/facebook-qr.png';
      });
    }
  }))).observe(document.documentElement, { childList: true, subtree: true });

  document.addEventListener('change', event => {
    const input = event.target;
    if (!(input instanceof HTMLInputElement) || input.type !== 'file') return;
    for (const file of input.files || []) {
      if (!SAFE_IMAGE_TYPES.has(file.type) || file.size > MAX_IMAGE_BYTES) {
        input.value = '';
        notify('Use a JPG, PNG, or WebP image smaller than 5 MB.');
        event.stopImmediatePropagation();
        return;
      }
    }
  }, true);

  document.addEventListener('change', async event => {
    const input = event.target;
    if (!(input instanceof HTMLInputElement) || input.type !== 'file' || !input.files?.length) return;
    const isProductGallery = input.id === 'product-image-file';
    const isColourGallery = input.matches('[data-colour-image-upload]');
    const isCarousel = input.matches('[data-carousel-upload]');
    const isSlide = input.matches('[data-slide-upload]');
    const isCategory = input.matches('[data-category-upload]');
    if (!isProductGallery && !isColourGallery && !isCarousel && !isSlide && !isCategory) return;
    event.stopImmediatePropagation();
    if (!window.SAZ_API?.uploadImages) return notify('Secure upload is temporarily unavailable.');
    try {
      const contentUpload = isCarousel || isSlide || isCategory;
      const urls = await window.SAZ_API.uploadImages(input.files, contentUpload ? 'content' : 'products');
      const row = input.closest('.carousel-slide-editor, .home-slide-editor, .home-category-editor');
      const field = isProductGallery ? document.querySelector('#product-form [name="imageUrls"]')
        : isColourGallery ? document.querySelector(`[data-colour-image-urls][data-colour="${CSS.escape(input.dataset.colour || '')}"]`)
        : isCarousel ? row?.querySelector('[data-field="image"]')
        : row?.querySelector('[name="image"]');
      if (!(field instanceof HTMLInputElement) && !(field instanceof HTMLTextAreaElement)) throw new Error('Upload destination is unavailable.');
      field.value = isProductGallery || isColourGallery ? [field.value.trim(), ...urls].filter(Boolean).join('\n') : urls[0] || '';
      field.dispatchEvent(new Event('input', { bubbles: true }));
      input.value = '';
      notify(`${urls.length} image${urls.length === 1 ? '' : 's'} uploaded. Save the changes to publish them.`);
    } catch (error) {
      input.value = '';
      notify(error.message || 'Could not upload the selected image.');
    }
  }, true);

  document.addEventListener('click', event => {
    const link = event.target.closest?.('a[href]');
    if (link && !safeUrl(link.getAttribute('href'))) {
      event.preventDefault();
      notify('Blocked an unsafe link.');
    }
  }, true);

  document.addEventListener('error', event => {
    const image = event.target;
    if (!(image instanceof HTMLImageElement) || image.dataset.fallbackApplied) return;
    image.dataset.fallbackApplied = 'true';
    image.src = 'assets/images/brand/logo.png';
    image.alt = image.alt || 'SAZ House';
  }, true);

  document.addEventListener('submit', async event => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;

    if (form.id === 'admin-login-form') {
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!window.SAZ_API) return notify('Secure sign-in is temporarily unavailable.');
      const data = new FormData(form);
      const result = await window.SAZ_API.signIn(data.get('email'), data.get('password'));
      if (result.error || !window.SAZ_API.isAdmin()) {
        await window.SAZ_API.signOut();
        return notify('Invalid administrator credentials.');
      }
      localStorage.setItem('sazAdmin', 'true');
      location.reload();
      return;
    }

    if (form.id === 'login-form') {
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!window.SAZ_API) return notify('Secure sign-in is temporarily unavailable.');
      const data = new FormData(form);
      const result = await window.SAZ_API.signIn(data.get('email'), data.get('password'));
      if (result.error) return notify('Email or password is incorrect.');
      localStorage.setItem('sazUser', JSON.stringify({ email: safeText(data.get('email')) }));
      location.reload();
      return;
    }

    if (form.id === 'checkout-form' || form.id === 'contact-form') {
      event.preventDefault();
      event.stopImmediatePropagation();
      const data = new FormData(form);
      const action = form.id === 'checkout-form' ? 'checkout' : 'contact';
      const submit = form.querySelector('[type="submit"]');
      if (submit?.disabled) return;
      const payload = action === 'checkout'
        ? {
            action,
            cart: JSON.parse(localStorage.getItem('sazCart') || '[]'),
            customer: Object.fromEntries(['name', 'phone', 'email', 'address', 'district', 'division'].map(key => [key, safeText(data.get(key))])),
            deliveryArea: safeText(data.get('deliveryArea') || data.get('city')),
            payment: safeText(data.get('payment')),
            coupon: safeText(localStorage.getItem('sazCouponCode')),
            idempotencyKey: nextCheckoutKey(),
            website: safeText(data.get('website'))
          }
        : {
            action,
            name: safeText(data.get('name')),
            email: safeText(data.get('email')),
            subject: safeText(data.get('subject')),
            message: safeText(data.get('message')),
            website: safeText(data.get('website'))
          };
      if (submit) submit.disabled = true;
      try {
        const csrf = window.SAZ_API?.getCsrfToken?.();
        if (!csrf) throw new Error('Security session is unavailable. Please refresh and try again.');
        const response = await fetch(`api/index.php?route=${action === 'checkout' ? 'checkout' : 'contact'}`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrf
          },
          body: JSON.stringify(payload)
        });
        let result = {};
        try { result = await response.json(); } catch { /* A proxy error can be non-JSON. */ }
        if (!response.ok) {
          const responseError = typeof result?.error === 'string' ? result.error : 'Request could not be completed.';
          const reference = typeof result?.requestId === 'string' ? ` Reference: ${result.requestId}.` : '';
          throw new Error(`${responseError}${reference}`);
        }
        if (action === 'contact') {
          form.reset();
          document.getElementById('contact-notice')?.style && (document.getElementById('contact-notice').style.display = 'block');
          return;
        }
        localStorage.setItem('sazLastOrder', JSON.stringify({ ...result.order, payment: payload.payment, placedAt: Date.now() }));
        localStorage.removeItem('sazCart');
        localStorage.removeItem('sazCouponCode');
        checkoutIdempotencyKey = '';
        sessionStorage.removeItem(checkoutKeyStorage);
        location.href = 'success.html';
      } catch (error) {
        notify(error.message || 'Could not submit your request. Please try again.');
        if (submit) submit.disabled = false;
      }
    }
  }, true);

  // Normalize old browser data before legacy templates render it.
  for (const key of ['sazUser', 'sazMessages']) {
    try {
      const value = JSON.parse(localStorage.getItem(key));
      if (key === 'sazUser' && value?.email) localStorage.setItem(key, JSON.stringify({ email: safeText(value.email) }));
      if (key === 'sazMessages' && Array.isArray(value)) {
        localStorage.setItem(key, JSON.stringify(value.map(message => Object.fromEntries(
          Object.entries(message).map(([name, text]) => [name, typeof text === 'string' ? safeText(text) : text])
        ))));
      }
    } catch { localStorage.removeItem(key); }
  }
})();
